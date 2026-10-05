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
// command processor also writes guest memory. Quiesce() below waits for both before
// anything is read or written. If the GPU does not drain (it can be parked on a semaphore or
// flip that only a running guest can release) the guest is let run for a moment and paused
// again, a few times, before the operation is given up with a specific reason.
//
// A save can only be loaded into the same still-running title instance it was taken from.
// Every title launch gets a session token (IOSSaveState_BeginSession); it is written into
// the file, and a file from any other launch is refused before anything is touched. Thread
// and memory-range layout are checked against the live session on top of that.
//
// Why a save cannot outlive its session (a relaunched game, or the app restarted): each guest
// thread that is blocked inside an HLE call (almost all of them, most of the time) is parked
// in the middle of that call on a HOST fiber stack. Guest RAM and the thread contexts in it
// can be rewritten, the host stacks cannot. Restoring RAM into a fresh process leaves every
// such thread resuming into a host frame that belongs to a different moment. Alarms, open
// file handles, the GPU command ring and AX voices are host-side as well.
//
// Failures are specific. Every false return sets a code and a player-facing sentence, read
// through IOSSaveState_LastErrorCode()/IOSSaveState_LastErrorMessage(), and every step logs its
// own duration so a device log shows where the time (or the failure) went.
#include "Cafe/CafeSystem.h"
#include "Cafe/HW/MMU/MMU.h"
#include "Cafe/HW/Espresso/Recompiler/PPCRecompiler.h"
#include "Cafe/HW/Latte/Core/LatteWaitInfo.h"
#include "Cafe/OS/libs/coreinit/coreinit_Thread.h"
#include "Cafe/OS/libs/gx2/GX2_Command.h"
#include "Cemu/Logging/CemuLogging.h"

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <random>
#include <string>
#include <thread>
#include <vector>

#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

bool IOSTitlePause_Pause();
bool IOSTitlePause_Resume();
bool IOSTitlePause_IsPaused();
extern "C" bool cemu_bridge_video_stalled(void); // CemuBridge.h

// Codes behind cemu_bridge_save_state_last_error_code(); keep in step with CemuBridge.h.
enum IOSSaveStateError : int
{
	SSE_None = 0,
	SSE_InvalidPath = 1,
	SSE_NoTitle = 2,
	SSE_PauseFailed = 3,
	SSE_CoresBusy = 4,
	SSE_GpuBusy = 5,
	SSE_DiskFull = 6,
	SSE_CannotCreateFile = 7,
	SSE_WriteFailed = 8,
	SSE_FileMissing = 9,
	SSE_NotASaveFile = 10,
	SSE_UnsupportedFormat = 11,
	SSE_OtherTitle = 12,
	SSE_EarlierSession = 13,
	SSE_ThreadsChanged = 14,
	SSE_MemoryLayoutChanged = 15,
	SSE_FileDamaged = 16,
	SSE_DamagedMidRestore = 17,
};

namespace
{
	using Clock = std::chrono::steady_clock;

	constexpr char kSaveStateMagic[8] = {'M', 'F', 'N', 'S', 'T', 'A', 'T', '1'};
	// 2: adds the session token after the title ID. Version 1 files (saving always failed on the device that
	// produced them, so there are almost none) are reported as "from an earlier session".
	constexpr uint32 kSaveStateFormatVersion = 2;

	// Bounded waits: this must never hang the UI forever on a title stuck in a long HLE
	// call. Timing out means "refuse the operation", never "proceed anyway".
	constexpr int kCoreIdleTimeoutMs = 2000;
	// A core must read idle for this long in a row, so a single lucky sample between two timeslices does not count.
	constexpr int kCoreIdleStableMs = 5;
	// The GPU gets this many tries. Between tries the guest runs for a moment (kNudgeBaseMs * try), in case the GPU
	// is parked on something only a running guest can release.
	constexpr int kGpuDrainAttempts = 3;
	constexpr int kGpuDrainTimeoutMs = 1500;
	constexpr int kNudgeBaseMs = 150;
	// Free space left over after the file, so a save never takes the last of the device's storage.
	constexpr uint64 kDiskHeadroomBytes = 64ull * 1024 * 1024;

	int ElapsedMs(Clock::time_point since)
	{
		return (int)std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - since).count();
	}

	// ---- last error -------------------------------------------------------------------------------------------------

	std::mutex sErrorMutex;
	int sErrorCode = SSE_None;
	std::string sErrorMessage;

	void ClearError()
	{
		std::lock_guard<std::mutex> lock(sErrorMutex);
		sErrorCode = SSE_None;
		sErrorMessage.clear();
	}

	// `message` is the player-facing sentence; `detail` goes to the log only. Always returns false.
	bool Fail(IOSSaveStateError code, const std::string& message, const std::string& detail = std::string())
	{
		cemuLog_log(LogType::Force, "IOSSaveState: FAILED code={} - {}{}{}", (int)code, message, detail.empty() ? "" : " | ", detail);
		std::lock_guard<std::mutex> lock(sErrorMutex);
		sErrorCode = code;
		sErrorMessage = message;
		return false;
	}

	std::string Megabytes(uint64 bytes)
	{
		return std::to_string((bytes + (1024 * 1024) - 1) / (1024 * 1024)) + " MB";
	}

	// ---- session ----------------------------------------------------------------------------------------------------

	std::atomic<uint64> sSessionToken{0};

	uint64 NewSessionToken()
	{
		std::random_device rd;
		uint64 token = ((uint64)rd() << 32) ^ (uint64)rd() ^ (uint64)Clock::now().time_since_epoch().count();
		return token ? token : 1;
	}

	uint64 EnsureSessionToken()
	{
		uint64 token = sSessionToken.load();
		if (token == 0)
		{
			// Only reached if a title started without IOSSaveState_BeginSession(); it still gets a token.
			const uint64 fresh = NewSessionToken();
			if (sSessionToken.compare_exchange_strong(token, fresh))
				token = fresh;
		}
		return token;
	}

	// ---- GPU/core quiescence ----------------------------------------------------------------------------------------

	// True once every core has read idle for kCoreIdleStableMs in a row. Returns the time waited through waitedMs.
	bool WaitForCoresIdle(int timeoutMs, int& waitedMs)
	{
		const auto start = Clock::now();
		Clock::time_point idleSince{};
		bool wasIdle = false;
		while (true)
		{
			const auto now = Clock::now();
			if (coreinit::__OSAllCoresIdle())
			{
				if (!wasIdle)
				{
					wasIdle = true;
					idleSince = now;
				}
				else if (now - idleSince >= std::chrono::milliseconds(kCoreIdleStableMs))
				{
					waitedMs = ElapsedMs(start);
					return true;
				}
			}
			else
			{
				wasIdle = false;
			}
			if (now - start > std::chrono::milliseconds(timeoutMs))
			{
				waitedMs = ElapsedMs(start);
				return false;
			}
			std::this_thread::sleep_for(std::chrono::milliseconds(1));
		}
	}

	std::string DescribeGpu()
	{
		auto& w = LatteWait::Get();
		const char* reason = w.reason.load();
		const int64_t since = w.reasonSinceMs.load();
		std::string s = "GPU thread: ";
		if (reason)
			s += std::string("waiting on '") + reason + "' (kind " + std::to_string((int)w.reasonKind.load()) + ") for " + std::to_string(since ? (long long)(LatteWait::NowMs() - since) : 0LL) + " ms";
		else
			s += "running";
		s += ", pm4 packets " + std::to_string(w.pm4Count.load());
		s += ", last opcode " + std::to_string(w.lastPM4Opcode.load());
		s += ", Metal command buffers in flight " + std::to_string(w.executingCommandBuffers.load());
		s += ", errored " + std::to_string(w.erroredCommandBuffers.load());
		s += w.gpuPresumedLost.load() ? ", GPU presumed lost" : "";
		s += w.gpuError.load() ? ", GPU error latched" : "";
		return s;
	}

	bool WaitForGPUDrain(int timeoutMs, int& waitedMs, uint64& retiredOut, uint64& targetOut)
	{
		const uint64 target = GX2::GX2GetLastSubmittedTimeStamp();
		targetOut = target;
		const auto start = Clock::now();
		while (true)
		{
			retiredOut = GX2::GX2GetRetiredTimeStamp();
			if (retiredOut >= target)
			{
				waitedMs = ElapsedMs(start);
				return true;
			}
			if (ElapsedMs(start) > timeoutMs)
			{
				waitedMs = ElapsedMs(start);
				return false;
			}
			std::this_thread::sleep_for(std::chrono::milliseconds(1));
		}
	}

	// True while the title is genuinely quiescent: no core mid-timeslice, no GPU command
	// still in flight. Everything IOSSaveState touches assumes this already holds. The caller has paused the title.
	//
	// skipGpuDrain: a save may go ahead without waiting for the GPU when the bridge's watchdog
	// had flagged the picture as stopped (sampled before pausing: pausing clears the flag), or when the GPU is known
	// to be dead. The GPU thread is not going to drain, so waiting would only turn "the picture froze" into "and
	// saving failed too"; the guest CPU state, which is what a save captures, is still complete. Never used for a load.
	bool Quiesce(const char* op, bool skipGpuDrain)
	{
		for (int attempt = 1; attempt <= kGpuDrainAttempts; attempt++)
		{
			int coreWaitMs = 0;
			if (!WaitForCoresIdle(kCoreIdleTimeoutMs, coreWaitMs))
			{
				return Fail(SSE_CoresBusy,
					"The game is in the middle of a long operation (usually loading) and didn't stop in time. Wait a few seconds and try again.",
					std::string(op) + ": cores not idle after " + std::to_string(coreWaitMs) + " ms (attempt " + std::to_string(attempt) + ")");
			}
			cemuLog_log(LogType::Force, "IOSSaveState: {}: cores idle after {} ms (attempt {})", op, coreWaitMs, attempt);

			if (skipGpuDrain)
			{
				cemuLog_log(LogType::Force, "IOSSaveState: {}: the picture has stalled, not waiting for the GPU command queue to drain", op);
				return true;
			}
			if (std::string(op) == "save" && (LatteWait::Get().gpuPresumedLost.load() || LatteWait::Get().gpuError.load()))
			{
				cemuLog_log(LogType::Force, "IOSSaveState: {}: the GPU is lost or errored, not waiting for it to drain ({})", op, DescribeGpu());
				return true;
			}

			int gpuWaitMs = 0;
			uint64 retired = 0, target = 0;
			if (WaitForGPUDrain(kGpuDrainTimeoutMs, gpuWaitMs, retired, target))
			{
				cemuLog_log(LogType::Force, "IOSSaveState: {}: GPU command queue drained after {} ms (retired {} / submitted {}, attempt {})", op, gpuWaitMs, retired, target, attempt);
				return true;
			}
			cemuLog_log(LogType::Force, "IOSSaveState: {}: GPU did not drain in {} ms (retired {} / submitted {}, attempt {}/{}) - {}", op, gpuWaitMs, retired, target, attempt, kGpuDrainAttempts, DescribeGpu());
			if (attempt == kGpuDrainAttempts)
			{
				return Fail(SSE_GpuBusy,
					"The game's graphics were still busy and didn't settle in time. Try again in a moment, ideally while nothing is loading.",
					std::string(op) + ": retired " + std::to_string(retired) + " / submitted " + std::to_string(target) + " - " + DescribeGpu());
			}

			// The GPU may be parked on a semaphore or flip that only a running guest can release, which a paused
			// guest never will. Let the guest run for a moment and pause it again.
			const int nudgeMs = kNudgeBaseMs * attempt;
			cemuLog_log(LogType::Force, "IOSSaveState: {}: letting the guest run for {} ms so the GPU can finish", op, nudgeMs);
			IOSTitlePause_Resume();
			std::this_thread::sleep_for(std::chrono::milliseconds(nudgeMs));
			if (!IOSTitlePause_Pause())
				return Fail(SSE_PauseFailed, "The game couldn't be paused again. Try once more.", std::string(op) + ": re-pause after nudge failed");
		}
		return Fail(SSE_GpuBusy, "The game's graphics didn't settle in time. Try again in a moment.");
	}

	// ---- disk -------------------------------------------------------------------------------------------------------

	struct SavedRange
	{
		uint32 base;
		uint32 size;
		uint32 areaId;
	};

	uint64 EstimateSaveBytes()
	{
		uint64 total = 4096; // header, thread list, range table
		for (auto* r : memory_getMMURanges())
		{
			if (r->isMapped())
				total += r->getSize();
		}
		return total;
	}

	std::string ParentDirectory(const std::string& path)
	{
		const size_t slash = path.find_last_of('/');
		if (slash == std::string::npos)
			return ".";
		return slash == 0 ? "/" : path.substr(0, slash);
	}

	// mkdir -p. A failure is not reported here: opening the file reports the real reason.
	void EnsureParentDirectory(const std::string& path)
	{
		const std::string dir = ParentDirectory(path);
		for (size_t i = 1; i <= dir.size(); i++)
		{
			if (i == dir.size() || dir[i] == '/')
				mkdir(dir.substr(0, i).c_str(), 0755);
		}
	}

	bool CheckDiskSpace(const std::string& path, uint64 needBytes)
	{
		struct statvfs vfs;
		if (statvfs(ParentDirectory(path).c_str(), &vfs) != 0)
			return true; // can't tell; let the write find out
		const uint64 freeBytes = (uint64)vfs.f_bavail * (uint64)vfs.f_frsize;
		cemuLog_log(LogType::Force, "IOSSaveState: save needs {} on disk, {} free", Megabytes(needBytes), Megabytes(freeBytes));
		if (freeBytes < needBytes + kDiskHeadroomBytes)
		{
			return Fail(SSE_DiskFull,
				"Not enough free storage. This save needs about " + Megabytes(needBytes) + " and the device has " + Megabytes(freeBytes) +
					" free. Delete a save slot or free up some space, then try again.");
		}
		return true;
	}

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
	bool WriteSaveFile(const char* path, uint64 sessionToken)
	{
		const auto start = Clock::now();
		const std::string tmpPath = std::string(path) + ".tmp";
		FILE* f = fopen(tmpPath.c_str(), "wb");
		if (!f)
		{
			const int e = errno;
			return Fail(SSE_CannotCreateFile, std::string("Couldn't create the save file (") + strerror(e) + ").", "fopen('" + tmpPath + "') errno " + std::to_string(e));
		}

		errno = 0;
		const uint64 titleId = CafeSystem::GetForegroundTitleId();
		const uint32 threadCount = (uint32)activeThreadCount;

		std::vector<MMURange*> mapped;
		uint64 dataBytes = 0;
		for (auto* r : memory_getMMURanges())
		{
			if (r->isMapped())
			{
				mapped.push_back(r);
				dataBytes += r->getSize();
			}
		}
		const uint32 rangeCount = (uint32)mapped.size();

		int failErrno = 0;
		auto noteFail = [&]() { if (failErrno == 0) failErrno = errno ? errno : EIO; };

		bool ok = WriteAll(f, kSaveStateMagic, sizeof(kSaveStateMagic)) &&
			WriteAll(f, &kSaveStateFormatVersion, sizeof(kSaveStateFormatVersion)) &&
			WriteAll(f, &titleId, sizeof(titleId)) &&
			WriteAll(f, &sessionToken, sizeof(sessionToken)) &&
			WriteAll(f, &threadCount, sizeof(threadCount)) &&
			WriteAll(f, activeThread, sizeof(MPTR) * threadCount) &&
			WriteAll(f, &rangeCount, sizeof(rangeCount));
		if (!ok)
			noteFail();

		if (ok)
		{
			for (auto* r : mapped)
			{
				SavedRange sr{r->getBase(), r->getSize(), (uint32)r->areaId};
				if (!WriteAll(f, &sr, sizeof(sr)))
				{
					ok = false;
					noteFail();
					break;
				}
			}
		}

		if (ok)
		{
			for (auto* r : mapped)
			{
				const auto rangeStart = Clock::now();
				if (!WriteMemoryRange(f, r->getPtr(), r->getSize()))
				{
					ok = false;
					noteFail();
					cemuLog_log(LogType::Force, "IOSSaveState: write of range {:08x} ({}) failed after {} ms", r->getBase(), Megabytes(r->getSize()), ElapsedMs(rangeStart));
					break;
				}
				cemuLog_log(LogType::Force, "IOSSaveState: wrote range {:08x} ({}) in {} ms", r->getBase(), Megabytes(r->getSize()), ElapsedMs(rangeStart));
			}
		}

		const auto syncStart = Clock::now();
		if (ok && fflush(f) != 0)
		{
			ok = false;
			noteFail();
		}
		if (ok && fsync(fileno(f)) != 0)
		{
			ok = false;
			noteFail();
		}
		const int syncMs = ElapsedMs(syncStart);
		if (fclose(f) != 0 && ok)
		{
			ok = false;
			noteFail();
		}
		if (ok && std::rename(tmpPath.c_str(), path) != 0)
		{
			ok = false;
			noteFail();
		}
		if (!ok)
		{
			std::remove(tmpPath.c_str());
			if (failErrno == ENOSPC || failErrno == EDQUOT)
				return Fail(SSE_DiskFull, "The device ran out of storage while saving. Free up some space and try again. The previous save in this slot was kept.", "write errno " + std::to_string(failErrno));
			return Fail(SSE_WriteFailed, std::string("Writing the save file failed (") + strerror(failErrno) + "). The previous save in this slot was kept.", "write errno " + std::to_string(failErrno));
		}

		const int totalMs = ElapsedMs(start);
		cemuLog_log(LogType::Force, "IOSSaveState: wrote {} to '{}' in {} ms (fsync {} ms, {} MB/s)", Megabytes(dataBytes), path, totalMs, syncMs,
			totalMs > 0 ? (unsigned long long)((dataBytes / (1024 * 1024)) * 1000ull / (uint64)totalMs) : 0ull);
		return true;
	}

	// ---- file header ------------------------------------------------------------------------------------------------

	struct HeaderPrefix
	{
		uint32 formatVersion = 0;
		uint64 titleId = 0;
		uint64 sessionToken = 0;
	};

	enum class PrefixResult
	{
		Ok,
		NotASave,
		OldFormat,
		Truncated,
	};

	// Reads magic, version, title ID and session token. Leaves the file positioned at the thread count.
	PrefixResult ReadHeaderPrefix(FILE* f, HeaderPrefix& h)
	{
		char magic[8];
		if (!ReadAll(f, magic, sizeof(magic)) || memcmp(magic, kSaveStateMagic, sizeof(magic)) != 0)
			return PrefixResult::NotASave;
		if (!ReadAll(f, &h.formatVersion, sizeof(h.formatVersion)))
			return PrefixResult::Truncated;
		if (h.formatVersion != kSaveStateFormatVersion)
			return PrefixResult::OldFormat;
		if (!ReadAll(f, &h.titleId, sizeof(h.titleId)) || !ReadAll(f, &h.sessionToken, sizeof(h.sessionToken)))
			return PrefixResult::Truncated;
		return PrefixResult::Ok;
	}

	// Cheap checks that need no pause: the file exists and is a current-format save from THIS launch of THIS title. Run
	// before the game is touched, so a save from an earlier session is turned away without even a flicker.
	bool PrecheckLoad(const char* path)
	{
		FILE* f = fopen(path, "rb");
		if (!f)
		{
			const int e = errno;
			if (e == ENOENT)
				return Fail(SSE_FileMissing, "That slot's save file is missing.", std::string("fopen('") + path + "') ENOENT");
			return Fail(SSE_FileMissing, std::string("Couldn't open the save file (") + strerror(e) + ").", std::string("fopen('") + path + "') errno " + std::to_string(e));
		}
		HeaderPrefix h;
		const PrefixResult r = ReadHeaderPrefix(f, h);
		fclose(f);
		switch (r)
		{
		case PrefixResult::NotASave:
			return Fail(SSE_NotASaveFile, "That file isn't a MuffinEMU save state.");
		case PrefixResult::Truncated:
			return Fail(SSE_FileDamaged, "The save file is damaged or incomplete.");
		case PrefixResult::OldFormat:
			return Fail(SSE_UnsupportedFormat, "This save was made by an older version of MuffinEMU and can't be loaded.", "format version " + std::to_string(h.formatVersion));
		case PrefixResult::Ok:
			break;
		}
		if (CafeSystem::GetForegroundTitleId() != h.titleId)
			return Fail(SSE_OtherTitle, "This save belongs to a different game.");
		if (h.sessionToken != EnsureSessionToken())
		{
			return Fail(SSE_EarlierSession,
				"This save is from an earlier session of the game. A save state can only be loaded while the game keeps running from the launch it was saved in.",
				"session token mismatch");
		}
		return true;
	}

	// Every check here runs BEFORE a single byte of guest memory is touched. Once restore
	// starts, a truncated/corrupt file can no longer be refused cleanly - see the comment
	// at that call site.
	bool ReadSaveFile(const char* path)
	{
		const auto start = Clock::now();
		FILE* f = fopen(path, "rb");
		if (!f)
		{
			const int e = errno;
			return Fail(SSE_FileMissing, std::string("Couldn't open the save file (") + strerror(e) + ").", std::string("fopen('") + path + "') errno " + std::to_string(e));
		}

		auto refuse = [&](IOSSaveStateError code, const char* message, const char* detail)
		{
			fclose(f);
			return Fail(code, message, detail);
		};

		HeaderPrefix header;
		switch (ReadHeaderPrefix(f, header))
		{
		case PrefixResult::NotASave:
			return refuse(SSE_NotASaveFile, "That file isn't a MuffinEMU save state.", "bad magic");
		case PrefixResult::OldFormat:
			return refuse(SSE_UnsupportedFormat, "This save was made by an older version of MuffinEMU and can't be loaded.", "unsupported format version");
		case PrefixResult::Truncated:
			return refuse(SSE_FileDamaged, "The save file is damaged or incomplete.", "truncated header");
		case PrefixResult::Ok:
			break;
		}
		if (!CafeSystem::IsTitleRunning() || CafeSystem::GetForegroundTitleId() != header.titleId)
			return refuse(SSE_OtherTitle, "This save belongs to a different game.", "title id differs from the running title");
		if (header.sessionToken != EnsureSessionToken())
			return refuse(SSE_EarlierSession, "This save is from an earlier session of the game and can't be loaded.", "session token differs");

		uint32 threadCount;
		if (!ReadAll(f, &threadCount, sizeof(threadCount)))
			return refuse(SSE_FileDamaged, "The save file is damaged or incomplete.", "truncated header");
		if (threadCount > 256) // coreinit's own activeThread[] ceiling - anything above is a corrupt/hostile file, not a real save
			return refuse(SSE_FileDamaged, "The save file is damaged.", "thread count in file is not plausible");

		std::vector<MPTR> savedThreads(threadCount);
		if (!ReadAll(f, savedThreads.data(), sizeof(MPTR) * threadCount))
			return refuse(SSE_FileDamaged, "The save file is damaged or incomplete.", "truncated thread list");

		// The set of active guest threads must match exactly - this can only be trusted
		// because the caller has already forced quiescence (Quiesce()) before
		// calling this, so activeThread[]/activeThreadCount cannot be mid-change.
		const char* kThreadsChanged = "The game has started or stopped background tasks since this save was taken, so it can't be put back safely. Saves load best soon after they're made, in the same part of the game.";
		if ((sint32)threadCount != activeThreadCount)
			return refuse(SSE_ThreadsChanged, kThreadsChanged, "active guest thread count differs from the save");
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
				return refuse(SSE_ThreadsChanged, kThreadsChanged, "a saved guest thread no longer exists");
		}

		uint32 rangeCount;
		if (!ReadAll(f, &rangeCount, sizeof(rangeCount)))
			return refuse(SSE_FileDamaged, "The save file is damaged or incomplete.", "truncated range table");
		if (rangeCount > 64) // generous ceiling above the real MMU range table - guards against a corrupt/hostile file forcing a huge allocation
			return refuse(SSE_FileDamaged, "The save file is damaged.", "range count in file is not plausible");
		std::vector<SavedRange> savedRanges(rangeCount);
		for (auto& sr : savedRanges)
		{
			if (!ReadAll(f, &sr, sizeof(sr)))
				return refuse(SSE_FileDamaged, "The save file is damaged or incomplete.", "truncated range table");
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
				return refuse(SSE_MemoryLayoutChanged, "The game's memory layout has changed since this save was taken (an area was loaded or unloaded), so it can't be put back safely.", "guest memory layout no longer matches the save");
			targets.push_back(match);
		}

		// The file must be exactly as long as the header says. Checking now, before any
		// memory is touched, means a truncated or damaged slot is refused cleanly.
		uint64 totalBytes = 0;
		{
			const off_t dataStart = ftello(f);
			for (const auto& sr : savedRanges)
				totalBytes += sr.size;
			if (dataStart < 0 || fseeko(f, 0, SEEK_END) != 0)
				return refuse(SSE_FileDamaged, "The save file couldn't be read.", "could not determine file size");
			const off_t fileEnd = ftello(f);
			if (fileEnd < 0 || (uint64)fileEnd != (uint64)dataStart + totalBytes)
				return refuse(SSE_FileDamaged, "The save file is damaged or incomplete.", "file size does not match its header (truncated or damaged)");
			if (fseeko(f, dataStart, SEEK_SET) != 0)
				return refuse(SSE_FileDamaged, "The save file couldn't be read.", "could not seek within file");
		}
		cemuLog_log(LogType::Force, "IOSSaveState: load checks passed in {} ms ({} to restore)", ElapsedMs(start), Megabytes(totalBytes));

		// Past this point every header check has passed. A short read from here on means
		// the file changed under us or an I/O error occurred, and guest memory may already
		// be partially overwritten with no way back to a consistent pre-load state - the
		// title must be treated as no longer trustworthy if that happens.
		const auto restoreStart = Clock::now();
		for (size_t i = 0; i < targets.size(); i++)
		{
			const auto rangeStart = Clock::now();
			if (!ReadMemoryRange(f, targets[i]->getPtr(), savedRanges[i].size))
			{
				fclose(f);
				return Fail(SSE_DamagedMidRestore, "The save file couldn't be read all the way through and the game's memory is now half-restored. Quit and restart the game.",
					"save file truncated mid-restore - guest memory is inconsistent");
			}
			cemuLog_log(LogType::Force, "IOSSaveState: restored range {:08x} ({}) in {} ms", savedRanges[i].base, Megabytes(savedRanges[i].size), ElapsedMs(rangeStart));
		}
		fclose(f);

		// The code at any address may now be entirely different from what was JIT-compiled
		// for the pre-load state. Safe under both the interpreter and the recompiler:
		// PPCRecompiler_invalidateRange() is a no-op when the recompiler isn't active.
		PPCRecompiler_invalidateRange(PPC_REC_CODE_AREA_START, PPC_REC_CODE_AREA_END);
		cemuLog_log(LogType::Force, "IOSSaveState: restored {} in {} ms", Megabytes(totalBytes), ElapsedMs(restoreStart));
		return true;
	}

	// Pauses the title unless it already is. Returns false (error set) if it can't be; `pausedByUs` says whether the
	// caller has to resume afterwards. A pause that raced with another caller's counts as already paused.
	bool PauseForOperation(const char* op, bool& pausedByUs)
	{
		const auto start = Clock::now();
		pausedByUs = false;
		if (IOSTitlePause_IsPaused())
		{
			cemuLog_log(LogType::Force, "IOSSaveState: {}: title was already paused", op);
			return true;
		}
		if (IOSTitlePause_Pause())
		{
			pausedByUs = true;
			cemuLog_log(LogType::Force, "IOSSaveState: {}: paused the title in {} ms", op, ElapsedMs(start));
			return true;
		}
		if (IOSTitlePause_IsPaused())
		{
			cemuLog_log(LogType::Force, "IOSSaveState: {}: another caller paused the title first", op);
			return true;
		}
		return Fail(SSE_PauseFailed, CafeSystem::IsTitleRunning() ? "The game couldn't be paused. Try again." : "The game has stopped.", std::string(op) + ": pause failed");
	}

	// Puts the title's pause state back the way the caller found it. Quiesce() may have let the guest run and paused it
	// again, and a failure part-way through can leave it either way.
	void RestorePauseState(const char* op, bool pausedByUs)
	{
		const auto start = Clock::now();
		if (pausedByUs)
		{
			IOSTitlePause_Resume();
			cemuLog_log(LogType::Force, "IOSSaveState: {}: resumed the title in {} ms", op, ElapsedMs(start));
		}
		else if (!IOSTitlePause_IsPaused())
		{
			// it was paused when we started (by the player) and a failed nudge left it running
			IOSTitlePause_Pause();
			cemuLog_log(LogType::Force, "IOSSaveState: {}: put the player's pause back", op);
		}
	}
}

// ---- public ---------------------------------------------------------------------------------------------------------

void IOSSaveState_BeginSession()
{
	sSessionToken.store(NewSessionToken());
}

int IOSSaveState_LastErrorCode()
{
	std::lock_guard<std::mutex> lock(sErrorMutex);
	return sErrorCode;
}

// Valid until the next call on the same thread.
const char* IOSSaveState_LastErrorMessage()
{
	static thread_local std::string copy;
	std::lock_guard<std::mutex> lock(sErrorMutex);
	copy = sErrorMessage;
	return copy.c_str();
}

// Reads only the header. 0 unreadable or not a save, 1 loadable now, 2 from an earlier session, 3 a different game,
// 4 an older format (treated as an earlier session by the UI).
int IOSSaveState_InspectFile(const char* path)
{
	if (!path || !*path)
		return 0;
	FILE* f = fopen(path, "rb");
	if (!f)
		return 0;
	HeaderPrefix h;
	const PrefixResult r = ReadHeaderPrefix(f, h);
	fclose(f);
	if (r == PrefixResult::NotASave || r == PrefixResult::Truncated)
		return 0;
	if (r == PrefixResult::OldFormat)
		return 4;
	if (!CafeSystem::IsTitleRunning())
		return 2;
	if (CafeSystem::GetForegroundTitleId() != h.titleId)
		return 3;
	return h.sessionToken == sSessionToken.load() && h.sessionToken != 0 ? 1 : 2;
}

// See the file-level comment for exactly what this does and does not capture.
bool IOSSaveState_Save(const char* path)
{
	ClearError();
	const auto total = Clock::now();
	if (!path || !*path)
		return Fail(SSE_InvalidPath, "No save location was given.");
	if (!CafeSystem::IsTitleRunning())
		return Fail(SSE_NoTitle, "The game isn't running.");
	cemuLog_log(LogType::Force, "IOSSaveState: save to '{}' starting", path);

	// Cheap failures first, before the game is paused: nothing to undo.
	EnsureParentDirectory(path);
	if (!CheckDiskSpace(path, EstimateSaveBytes()))
		return false;

	const bool videoStalled = cemu_bridge_video_stalled();
	bool pausedByUs = false;
	if (!PauseForOperation("save", pausedByUs))
		return false;

	const auto quiesceStart = Clock::now();
	bool ok = Quiesce("save", videoStalled);
	if (ok)
		cemuLog_log(LogType::Force, "IOSSaveState: save: quiescent after {} ms", ElapsedMs(quiesceStart));
	ok = ok && WriteSaveFile(path, EnsureSessionToken());

	RestorePauseState("save", pausedByUs);

	cemuLog_log(LogType::Force, "IOSSaveState: save to '{}' {} (total {} ms)", path, ok ? "succeeded" : "failed", ElapsedMs(total));
	return ok;
}

// See the file-level comment, especially the GPU-cache-staleness tradeoff and the
// same-running-instance requirement, before changing what this accepts.
bool IOSSaveState_Load(const char* path)
{
	ClearError();
	const auto total = Clock::now();
	if (!path || !*path)
		return Fail(SSE_InvalidPath, "No save location was given.");
	if (!CafeSystem::IsTitleRunning())
		return Fail(SSE_NoTitle, "The game isn't running.");
	cemuLog_log(LogType::Force, "IOSSaveState: load from '{}' starting", path);

	if (!PrecheckLoad(path))
		return false;

	bool pausedByUs = false;
	if (!PauseForOperation("load", pausedByUs))
		return false;

	const auto quiesceStart = Clock::now();
	bool ok = Quiesce("load", false);
	if (ok)
		cemuLog_log(LogType::Force, "IOSSaveState: load: quiescent after {} ms", ElapsedMs(quiesceStart));
	ok = ok && ReadSaveFile(path);

	RestorePauseState("load", pausedByUs);

	cemuLog_log(LogType::Force, "IOSSaveState: load from '{}' {} (total {} ms)", path, ok ? "succeeded" : "failed", ElapsedMs(total));
	return ok;
}
