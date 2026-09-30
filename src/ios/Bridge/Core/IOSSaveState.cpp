// Save states: freeze a running title's guest RAM to a slot file, and restore it later.
//
// Captures every currently-mapped guest RAM region (MMU.h's MMURange table) and nothing
// else. CPU registers are not serialised separately: each thread's OSThread_t.context
// lives in guest memory and is flushed there whenever the thread leaves a core, so once
// every core is idle a RAM dump already contains complete register state.
//
// GPU state (textures, shaders, buffers) is not captured or flushed. A load can therefore
// show stale textures or shaders for a few frames until the game's next GX2 call refreshes
// them; this is a visual glitch, not a memory-safety problem.
//
// Pause() suspends guest threads but does not stop one that is mid-timeslice, and the GPU
// command processor also writes guest memory. WaitForCoresIdle() and WaitForGPUDrain()
// below wait for both before anything is read or written.
//
// A save can only be loaded into the same still-running title instance it was taken from.
// Thread and memory-range layout are checked against the live session before any memory is
// touched, and a mismatch refuses the load.
#include "Cafe/CafeSystem.h"
#include "Cafe/HW/MMU/MMU.h"
#include "Cafe/HW/Espresso/Recompiler/PPCRecompiler.h"
#include "Cafe/OS/libs/coreinit/coreinit_Thread.h"
#include "Cafe/OS/libs/gx2/GX2_Command.h"
#include "Cemu/Logging/CemuLogging.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include <unistd.h>

bool IOSTitlePause_Pause();
bool IOSTitlePause_Resume();
bool IOSTitlePause_IsPaused();
extern "C" bool cemu_bridge_video_stalled(void); // CemuBridge.h

namespace
{
	constexpr char kSaveStateMagic[8] = {'M', 'F', 'N', 'S', 'T', 'A', 'T', '1'};
	constexpr uint32 kSaveStateFormatVersion = 1;

	// Bounded waits: this must never hang the UI forever on a title stuck in a long HLE
	// call. Timing out means "refuse the operation", never "proceed anyway".
	constexpr int kCoreIdleTimeoutMs = 2000;
	constexpr int kGpuDrainTimeoutMs = 5000;

	bool WaitForCoresIdle(int timeoutMs)
	{
		const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);
		while (!coreinit::__OSAllCoresIdle())
		{
			if (std::chrono::steady_clock::now() > deadline)
				return false;
			std::this_thread::sleep_for(std::chrono::milliseconds(1));
		}
		return true;
	}

	bool WaitForGPUDrain(int timeoutMs)
	{
		const uint64 target = GX2::GX2GetLastSubmittedTimeStamp();
		const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);
		while (GX2::GX2GetRetiredTimeStamp() < target)
		{
			if (std::chrono::steady_clock::now() > deadline)
				return false;
			std::this_thread::sleep_for(std::chrono::milliseconds(1));
		}
		return true;
	}

	// True while the title is genuinely quiescent: no core mid-timeslice, no GPU command
	// still in flight. Everything IOSSaveState touches assumes this already holds.
	//
	// skipGpuDrain: a save may go ahead without waiting for the GPU when the bridge's watchdog
	// had flagged the picture as stopped (sampled before pausing: pausing clears the flag). The GPU thread is not going to drain, so waiting would
	// only turn "the picture froze" into "and saving failed too"; the guest CPU state, which is
	// what a save captures, is still complete. Never used for a load.
	bool WaitForQuiescence(bool skipGpuDrain = false)
	{
		if (!WaitForCoresIdle(kCoreIdleTimeoutMs))
		{
			cemuLog_log(LogType::Force, "IOSSaveState: timed out waiting for all cores to idle; refusing (a guest thread is stuck in a long call)");
			return false;
		}
		if (skipGpuDrain)
		{
			cemuLog_log(LogType::Force, "IOSSaveState: the picture has stalled, saving without waiting for the GPU command queue to drain");
			return true;
		}
		if (!WaitForGPUDrain(kGpuDrainTimeoutMs))
		{
			cemuLog_log(LogType::Force, "IOSSaveState: timed out waiting for the GPU command queue to drain; refusing");
			return false;
		}
		return true;
	}

	struct SavedRange
	{
		uint32 base;
		uint32 size;
		uint32 areaId;
	};

	bool WriteAll(FILE* f, const void* data, size_t size)
	{
		return size == 0 || fwrite(data, 1, size, f) == size;
	}

	bool ReadAll(FILE* f, void* data, size_t size)
	{
		return size == 0 || fread(data, 1, size, f) == size;
	}

	// Chunked so one enormous fwrite/fread (a fully-mapped MEM2 region can be up to 1GiB)
	// never has to succeed atomically; on a short read/write we bail immediately.
	constexpr size_t kIoChunkSize = 4 * 1024 * 1024;

	bool WriteMemoryRange(FILE* f, const uint8* src, uint32 size)
	{
		uint32 written = 0;
		while (written < size)
		{
			const size_t n = std::min<size_t>(kIoChunkSize, size - written);
			if (fwrite(src + written, 1, n, f) != n)
				return false;
			written += (uint32)n;
		}
		return true;
	}

	bool ReadMemoryRange(FILE* f, uint8* dst, uint32 size)
	{
		uint32 read = 0;
		while (read < size)
		{
			const size_t n = std::min<size_t>(kIoChunkSize, size - read);
			if (fread(dst + read, 1, n, f) != n)
				return false;
			read += (uint32)n;
		}
		return true;
	}

	// Writes to "<path>.tmp" and renames it over the slot only after every byte was
	// written, flushed and closed successfully, so a failed save (for example a full
	// disk) leaves the slot's previous save untouched.
	bool WriteSaveFile(const char* path)
	{
		const std::string tmpPath = std::string(path) + ".tmp";
		FILE* f = fopen(tmpPath.c_str(), "wb");
		if (!f)
		{
			cemuLog_log(LogType::Force, "IOSSaveState: could not open '{}' for writing", tmpPath);
			return false;
		}

		const uint64 titleId = CafeSystem::GetForegroundTitleId();
		const uint32 threadCount = (uint32)activeThreadCount;

		std::vector<MMURange*> mapped;
		for (auto* r : memory_getMMURanges())
		{
			if (r->isMapped())
				mapped.push_back(r);
		}
		const uint32 rangeCount = (uint32)mapped.size();

		bool ok = WriteAll(f, kSaveStateMagic, sizeof(kSaveStateMagic)) &&
			WriteAll(f, &kSaveStateFormatVersion, sizeof(kSaveStateFormatVersion)) &&
			WriteAll(f, &titleId, sizeof(titleId)) &&
			WriteAll(f, &threadCount, sizeof(threadCount)) &&
			WriteAll(f, activeThread, sizeof(MPTR) * threadCount) &&
			WriteAll(f, &rangeCount, sizeof(rangeCount));

		if (ok)
		{
			for (auto* r : mapped)
			{
				SavedRange sr{r->getBase(), r->getSize(), (uint32)r->areaId};
				if (!WriteAll(f, &sr, sizeof(sr)))
				{
					ok = false;
					break;
				}
			}
		}

		if (ok)
		{
			for (auto* r : mapped)
			{
				if (!WriteMemoryRange(f, r->getPtr(), r->getSize()))
				{
					ok = false;
					break;
				}
			}
		}

		if (ok && fflush(f) != 0)
			ok = false;
		if (ok && fsync(fileno(f)) != 0)
			ok = false;
		if (fclose(f) != 0)
			ok = false;
		if (ok && std::rename(tmpPath.c_str(), path) != 0)
			ok = false;
		if (!ok)
		{
			cemuLog_log(LogType::Force, "IOSSaveState: write failed, removing partial file '{}' (previous save kept)", tmpPath);
			std::remove(tmpPath.c_str());
		}
		return ok;
	}

	// Every check here runs BEFORE a single byte of guest memory is touched. Once restore
	// starts, a truncated/corrupt file can no longer be refused cleanly - see the comment
	// at that call site.
	bool ReadSaveFile(const char* path)
	{
		FILE* f = fopen(path, "rb");
		if (!f)
		{
			cemuLog_log(LogType::Force, "IOSSaveState: could not open '{}' for reading", path);
			return false;
		}

		auto refuse = [&](const char* why)
		{
			cemuLog_log(LogType::Force, "IOSSaveState: load refused - {}", why);
			fclose(f);
			return false;
		};

		char magic[8];
		uint32 formatVersion;
		uint64 titleId;
		uint32 threadCount;
		if (!ReadAll(f, magic, sizeof(magic)) || memcmp(magic, kSaveStateMagic, sizeof(magic)) != 0)
			return refuse("not a MuffinEMU save state file");
		if (!ReadAll(f, &formatVersion, sizeof(formatVersion)) || formatVersion != kSaveStateFormatVersion)
			return refuse("unsupported save state format version");
		if (!ReadAll(f, &titleId, sizeof(titleId)))
			return refuse("truncated header");
		if (!CafeSystem::IsTitleRunning() || CafeSystem::GetForegroundTitleId() != titleId)
			return refuse("save state belongs to a different title than the one currently running");
		if (!ReadAll(f, &threadCount, sizeof(threadCount)))
			return refuse("truncated header");
		if (threadCount > 256) // coreinit's own activeThread[] ceiling - anything above is a corrupt/hostile file, not a real save
			return refuse("thread count in file is not plausible");

		std::vector<MPTR> savedThreads(threadCount);
		if (!ReadAll(f, savedThreads.data(), sizeof(MPTR) * threadCount))
			return refuse("truncated thread list");

		// The set of active guest threads must match exactly - this can only be trusted
		// because the caller has already forced quiescence (WaitForQuiescence()) before
		// calling this, so activeThread[]/activeThreadCount cannot be mid-change.
		if ((sint32)threadCount != activeThreadCount)
			return refuse("active guest thread count no longer matches the save (title state has diverged)");
		for (MPTR t : savedThreads)
		{
			bool found = false;
			for (sint32 i = 0; i < activeThreadCount; i++)
			{
				if (activeThread[i] == t)
				{
					found = true;
					break;
				}
			}
			if (!found)
				return refuse("a saved guest thread no longer exists (title state has diverged)");
		}

		uint32 rangeCount;
		if (!ReadAll(f, &rangeCount, sizeof(rangeCount)))
			return refuse("truncated range table");
		if (rangeCount > 64) // generous ceiling above the real MMU range table - guards against a corrupt/hostile file forcing a huge allocation
			return refuse("range count in file is not plausible");
		std::vector<SavedRange> savedRanges(rangeCount);
		for (auto& sr : savedRanges)
		{
			if (!ReadAll(f, &sr, sizeof(sr)))
				return refuse("truncated range table");
		}

		// Every saved range must currently be mapped at the same base with the same size.
		// A mismatch (different overlay/tiling-aperture allocation state, a range that
		// isn't mapped right now, etc.) means the live memory layout no longer lines up
		// with the save, and there is no safe way to reconcile that here.
		const std::vector<MMURange*> liveRanges = memory_getMMURanges();
		std::vector<MMURange*> targets;
		targets.reserve(savedRanges.size());
		for (const auto& sr : savedRanges)
		{
			MMURange* match = nullptr;
			for (auto* lr : liveRanges)
			{
				if (lr->getBase() == sr.base)
				{
					match = lr;
					break;
				}
			}
			if (!match || !match->isMapped() || match->getSize() != sr.size)
				return refuse("guest memory layout no longer matches the save");
			targets.push_back(match);
		}

		// The file must be exactly as long as the header says. Checking now, before any
		// memory is touched, means a truncated or damaged slot is refused cleanly.
		{
			const off_t dataStart = ftello(f);
			uint64 expectedData = 0;
			for (const auto& sr : savedRanges)
				expectedData += sr.size;
			if (dataStart < 0 || fseeko(f, 0, SEEK_END) != 0)
				return refuse("could not determine file size");
			const off_t fileEnd = ftello(f);
			if (fileEnd < 0 || (uint64)fileEnd != (uint64)dataStart + expectedData)
				return refuse("file size does not match its header (truncated or damaged)");
			if (fseeko(f, dataStart, SEEK_SET) != 0)
				return refuse("could not seek within file");
		}

		// Past this point every header check has passed. A short read from here on means
		// the file changed under us or an I/O error occurred, and guest memory may already
		// be partially overwritten with no way back to a consistent pre-load state - the
		// title must be treated as no longer trustworthy if that happens.
		for (size_t i = 0; i < targets.size(); i++)
		{
			if (!ReadMemoryRange(f, targets[i]->getPtr(), savedRanges[i].size))
			{
				fclose(f);
				cemuLog_log(LogType::Force, "IOSSaveState: save file truncated mid-restore - guest memory is now inconsistent, the title should be restarted");
				return false;
			}
		}
		fclose(f);

		// The code at any address may now be entirely different from what was JIT-compiled
		// for the pre-load state. Safe under both the interpreter and the recompiler:
		// PPCRecompiler_invalidateRange() is a no-op when the recompiler isn't active.
		PPCRecompiler_invalidateRange(PPC_REC_CODE_AREA_START, PPC_REC_CODE_AREA_END);
		return true;
	}
}

// See the file-level comment for exactly what this does and does not capture.
bool IOSSaveState_Save(const char* path)
{
	if (!path || !*path)
		return false;
	if (!CafeSystem::IsTitleRunning())
		return false;

	const bool videoStalled = cemu_bridge_video_stalled();
	const bool wasAlreadyPaused = IOSTitlePause_IsPaused();
	if (!wasAlreadyPaused && !IOSTitlePause_Pause())
		return false;

	bool ok = WaitForQuiescence(videoStalled) && WriteSaveFile(path);

	if (!wasAlreadyPaused)
		IOSTitlePause_Resume();

	cemuLog_log(LogType::Force, "IOSSaveState: save to '{}' {}", path, ok ? "succeeded" : "failed");
	return ok;
}

// See the file-level comment, especially the GPU-cache-staleness tradeoff and the
// same-running-instance requirement, before changing what this accepts.
bool IOSSaveState_Load(const char* path)
{
	if (!path || !*path)
		return false;
	if (!CafeSystem::IsTitleRunning())
		return false;

	const bool wasAlreadyPaused = IOSTitlePause_IsPaused();
	if (!wasAlreadyPaused && !IOSTitlePause_Pause())
		return false;

	bool ok = WaitForQuiescence() && ReadSaveFile(path);

	if (!wasAlreadyPaused)
		IOSTitlePause_Resume();

	cemuLog_log(LogType::Force, "IOSSaveState: load from '{}' {}", path, ok ? "succeeded" : "failed");
	return ok;
}
