// Save states: freeze a running title's guest RAM + CPU register state to a slot file,
// and restore it later.
//
// SCOPE - read this before touching this file. This is deliberately NOT a full,
// arbitrary-point save state. It captures:
//   - every currently-mapped guest RAM region (MMU.h's MMURange table), raw bytes
//   - nothing else, explicitly - no GPU/Latte renderer state, no texture/shader/buffer
//     caches, no PPCInterpreter_t register blobs
//
// It does NOT separately serialize CPU registers, and that is not an oversight. Cafe OS's
// own OSThread_t.context (coreinit_Thread.h) already lives in guest memory and is kept
// authoritative for every thread that is not the one actually mid-timeslice on a core
// right now - see __OSThreadStoreContext()/__OSStoreThread() in coreinit_Thread.cpp,
// which unconditionally flushes a thread's full register file into its OSThread_t.context
// every single time it is switched off a core, independent of suspension. So once every
// core is confirmed to have reached its idle fiber (nothing "mid-timeslice" anywhere), a
// plain guest-RAM dump already contains complete, correct register state for every guest
// thread, running or not. Restoring RAM restores registers along with it, for free,
// through the exact same (unmodified) __OSLoadThread()/__OSThreadLoadContext() path a
// normal thread dispatch already uses.
//
// WHY GPU STATE IS DELIBERATELY LEFT ALONE: Latte/GX2 already treats VRAM-side objects
// (textures, shaders, vertex/uniform buffers) as caches derived from guest memory + GX2
// calls, invalidated by explicit signals (GX2Invalidate, ICBI-style range invalidation),
// not by continuous re-derivation every frame - see LatteCommandProcessor.cpp's
// IT_SURFACE_SYNC handling and GX2_Misc.cpp's GX2Invalidate(). A RAM-only load bypasses
// those signals, so any texture/shader Cemu already has cached host-side could go stale
// relative to the just-restored memory. The only "invalidate everything" primitives that
// exist (LatteBufferCache_UnloadAll/LatteTC_UnloadAllTextures/LatteSHRC_UnloadAll) are
// exercised exactly once in this codebase, from LatteThread_Exit(), as the last thing the
// GPU thread does before the renderer is destroyed - never as a standalone "flush caches,
// keep rendering" operation, and never from a different thread than the GPU thread itself.
// Calling them here, live, from the bridge thread, while the GPU thread stays up, is an
// untested cross-thread path this investigation could not certify as safe, so it is not
// done. The accepted consequence: for a handful of frames after a load, a texture or
// shader that changed between save and load MAY still show old contents on screen until
// the game's own next GX2 call naturally refreshes it. This is a visual glitch, not a
// memory-safety problem, and it is the one deliberate compromise in this design - see
// notes at the top of IOSSaveState_Load() below for the exact tradeoff.
//
// WHY THIS NEEDED MORE THAN "CALL IOSTitlePause_Pause()": that function suspends every
// guest thread (coreinit's own suspend-count mechanism) but does not interrupt one that
// is already mid-timeslice on a core - see its own "todo - if thread is still running
// find a way to cancel it's timeslice immediately" comment in
// __OSSuspendThreadInternal() (coreinit_Thread.cpp). In multicore mode that is up to 3
// real host OS threads that can keep executing PPC instructions - and keep writing to
// guest memory - for up to a full quantum (default ~45000 cycles, longer if blocked in an
// HLE call) after Pause() returns. A save/load taken right after Pause() returns would
// race with that. coreinit_Thread.h's __OSAllCoresIdle() (backed by a small per-core busy
// flag added for this feature) answers "has every core actually reached its idle fiber",
// and WaitForCoresIdle() below polls it before touching anything.
//
// A second, separate host thread also writes into guest memory independently of the CPU
// scheduler entirely: the Latte/GX2 command processor (LatteCommandProcessor.cpp writes
// PM4 event/timestamp results with memory_writeU32/memory_writeU64; LatteQuery.cpp writes
// occlusion query results the same way). Suspending CPU threads does not pause it - it
// keeps draining whatever was already queued. WaitForGPUDrain() below closes this the same
// way GX2DrawDone() itself does on the guest side: compare GX2's last-submitted command
// timestamp against the GPU's last-retired one (both are supported by plain atomics -
// GX2GetLastSubmittedTimeStamp()/GX2GetRetiredTimeStamp() - with no dependency on a live
// guest thread context, unlike GX2WaitTimeStamp()'s guest-blocking OSWaitEvent() path,
// which is why this polls the atomics directly instead of calling that).
//
// LOADING ACROSS A FRESH BOOT: a save is only valid to load into the SAME still-running
// title instance it was taken from - not "the same game relaunched". OSThread_t
// structures, thread MPTRs and the set of mapped MMU ranges are compared against the live
// session's coreinit::activeThread[] list and memory_getMMURanges() before a single byte
// of memory is touched; any mismatch refuses the load outright rather than guessing. This
// is deliberately conservative: a real cross-boot "load this save on a freshly launched
// copy of the same game" feature would need to prove Cafe OS's own allocators are
// deterministic enough for thread/heap layout to line up, which this investigation did not
// attempt to establish.
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
#include <thread>
#include <vector>

bool IOSTitlePause_Pause();
bool IOSTitlePause_Resume();
bool IOSTitlePause_IsPaused();

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
	bool WaitForQuiescence()
	{
		if (!WaitForCoresIdle(kCoreIdleTimeoutMs))
		{
			cemuLog_log(LogType::Force, "IOSSaveState: timed out waiting for all cores to idle; refusing (a guest thread is stuck in a long call)");
			return false;
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

	bool WriteSaveFile(const char* path)
	{
		FILE* f = fopen(path, "wb");
		if (!f)
		{
			cemuLog_log(LogType::Force, "IOSSaveState: could not open '{}' for writing", path);
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

		fclose(f);
		if (!ok)
		{
			cemuLog_log(LogType::Force, "IOSSaveState: write failed, removing partial file '{}'", path);
			std::remove(path);
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

		// Past this point every check has passed. A short read from here on means the
		// file itself was truncated/corrupt in a way none of the header checks could
		// catch, and guest memory may already be partially overwritten with no way back
		// to a consistent pre-load state - the title must be treated as no longer
		// trustworthy if that happens (see the comment on IOSSaveState_Load() below).
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

	const bool wasAlreadyPaused = IOSTitlePause_IsPaused();
	if (!wasAlreadyPaused && !IOSTitlePause_Pause())
		return false;

	bool ok = WaitForQuiescence() && WriteSaveFile(path);

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
