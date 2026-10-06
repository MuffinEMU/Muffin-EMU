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
#include "Cafe/HW/Espresso/PPCState.h"
#include "Cafe/HW/Latte/Core/LatteBufferCache.h"
#include "Cafe/HW/Latte/Core/LatteWaitInfo.h"
#include "Cafe/OS/libs/coreinit/coreinit_Thread.h"
#include "Cafe/OS/libs/coreinit/coreinit_Scheduler.h"
#include "Cafe/OS/libs/gx2/GX2_Command.h"
#include "Cafe/OS/libs/gx2/GX2_Event.h"
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

#include <fmt/format.h>

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
	// 3: adds tagged chunks of host-side state between the range table and the memory data (GPU command buffer
	// positions, the guest clock; see the chunk tags below). A load needs every chunk its build knows about.
	constexpr uint32 kSaveStateFormatVersion = 3;

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

	// ---- diagnostics ------------------------------------------------------------------------------------------------
	//
	// Nothing here can be tested away from a device, so a save or load narrates itself: every step of an operation is one
	// numbered log line with the time since the operation began, and the guest thread table is dumped before and after, so
	// a log sent back shows what the game was doing and exactly which step went wrong.

	std::atomic<int> sStepNumber{0};
	std::atomic<int64_t> sOpStartMs{0};

	int64_t SteadyNowMs()
	{
		return std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now().time_since_epoch()).count();
	}

	void BeginOperationLog()
	{
		sStepNumber.store(0);
		sOpStartMs.store(SteadyNowMs());
	}

	void LogStep(const char* op, const std::string& text)
	{
		const int n = sStepNumber.fetch_add(1) + 1;
		cemuLog_log(LogType::Force, "IOSSaveState: {} step {} (+{} ms): {}", op, n, (long long)(SteadyNowMs() - sOpStartMs.load()), text);
	}

	// Guest strings can be anything, so this copies at most `maxLen` printable bytes and never reads outside mapped memory.
	std::string SafeGuestString(MPTR address, size_t maxLen = 40)
	{
		std::string out;
		if (address == 0)
			return out;
		for (size_t i = 0; i < maxLen; i++)
		{
			if (!memory_isAddressRangeAccessible(address + (uint32)i, 1))
				break;
			const char c = (char)*memory_getPointerFromVirtualOffset(address + (uint32)i);
			if (c == 0)
				break;
			out.push_back(c >= 32 && c < 127 ? c : '?');
		}
		return out;
	}

	const char* ThreadStateName(OSThread_t::THREAD_STATE state)
	{
		switch (state)
		{
		case OSThread_t::THREAD_STATE::STATE_NONE: return "none";
		case OSThread_t::THREAD_STATE::STATE_READY: return "ready";
		case OSThread_t::THREAD_STATE::STATE_RUNNING: return "running";
		case OSThread_t::THREAD_STATE::STATE_WAITING: return "waiting";
		case OSThread_t::THREAD_STATE::STATE_MORIBUND: return "moribund";
		}
		return "?";
	}

	// One line per active guest thread. `tag` says when (for example "save: before writing").
	void LogThreadTable(const char* tag)
	{
		__OSLockScheduler();
		cemuLog_log(LogType::Force, "IOSSaveState: {}: {} active guest threads", tag, (int)activeThreadCount);
		for (sint32 i = 0; i < activeThreadCount; i++)
		{
			const MPTR threadAddress = activeThread[i];
			if (!memory_isAddressRangeAccessible(threadAddress, sizeof(OSThread_t)))
			{
				cemuLog_log(LogType::Force, "IOSSaveState:   [{}] {:08x} is not readable guest memory", i, threadAddress);
				continue;
			}
			const OSThread_t* t = (const OSThread_t*)memory_getPointerFromVirtualOffset(threadAddress);
			const OSThread_t::THREAD_STATE state = t->state;
			const sint32 suspend = t->suspendCounter;
			const sint32 priority = t->effectivePriority;
			const uint32 ip = t->context.srr0;
			const uint32 lr = _swapEndianU32(t->context.lr); // stored big-endian, unlike srr0
			const MPTR waitQueue = t->currentWaitQueue.GetMPTR();
			cemuLog_log(LogType::Force, "IOSSaveState:   [{}] {:08x} '{}' {} suspend={} prio={} affinity={:x} ip={:08x} lr={:08x} waitQueue={:08x}",
				i, threadAddress, SafeGuestString(t->threadName.GetMPTR()), ThreadStateName(state), suspend, priority, t->context.getAffinity(), ip, lr, waitQueue);
		}
		__OSUnlockScheduler();
	}

	void LogMemoryRanges(const char* tag)
	{
		std::string line;
		for (auto* r : memory_getMMURanges())
		{
			if (r->isMapped())
				line += fmt::format(" {}@{:08x}+{:x}", r->getName(), r->getBase(), r->getSize());
		}
		cemuLog_log(LogType::Force, "IOSSaveState: {}: mapped ranges:{}", tag, line);
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

	// How long the GPU thread must have been parked on something the paused guest or the display decides before a load stops
	// waiting for it.
	constexpr int kGpuParkedGivesUpMs = 700;

	// The GPU thread can be parked on a flip (vsync) or a semaphore only a running guest can release, or on a screen that has no
	// drawable to give. While the guest is paused none of those end, and a command buffer that is half-processed cannot drain.
	// True once that has lasted long enough and no Metal work is still in flight.
	bool GpuIsParkedOnPacing(std::string& why)
	{
		auto& w = LatteWait::Get();
		const char* reason = w.reason.load();
		if (!reason)
			return false;
		const auto kind = (LatteWait::Kind)w.reasonKind.load();
		if (kind != LatteWait::Kind::GuestWait && kind != LatteWait::Kind::Display)
			return false;
		const int64_t since = w.reasonSinceMs.load();
		const int64_t parkedMs = since ? LatteWait::NowMs() - since : 0;
		if (parkedMs < kGpuParkedGivesUpMs || w.executingCommandBuffers.load() != 0)
			return false;
		why = fmt::format("GPU thread parked on '{}' (kind {}) for {} ms with no Metal work in flight", reason, (int)kind, (long long)parkedMs);
		return true;
	}

	// True while the title is genuinely quiescent: no core mid-timeslice, no GPU command
	// still in flight. Everything IOSSaveState touches assumes this already holds. The caller has paused the title.
	//
	// skipGpuDrain: a save may go ahead without waiting for the GPU when the bridge's watchdog
	// had flagged the picture as stopped (sampled before pausing: pausing clears the flag), or when the GPU is known
	// to be dead. The GPU thread is not going to drain, so waiting would only turn "the picture froze" into "and
	// saving failed too"; the guest CPU state, which is what a save captures, is still complete. Never used for a load,
	// except through the parked-on-pacing rule below.
	//
	// A load gives up on the drain the same way when the GPU thread has sat on a flip or semaphore for a long time with no GPU
	// work in flight (a save would have been taken in that state too). Anything the GPU had not read yet is then dropped after
	// the restore, because the memory it points into is about to change.
	//
	// gpuDrainedOut is false when the GPU was NOT confirmed idle.
	bool Quiesce(const char* op, bool skipGpuDrain, bool& gpuDrainedOut)
	{
		gpuDrainedOut = true;
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
				gpuDrainedOut = false;
				return true;
			}
			if (std::string(op) == "save" && (LatteWait::Get().gpuPresumedLost.load() || LatteWait::Get().gpuError.load()))
			{
				cemuLog_log(LogType::Force, "IOSSaveState: {}: the GPU is lost or errored, not waiting for it to drain ({})", op, DescribeGpu());
				gpuDrainedOut = false;
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

			std::string parkedWhy;
			if (std::string(op) == "load" && attempt >= 2 && GpuIsParkedOnPacing(parkedWhy))
			{
				cemuLog_log(LogType::Force, "IOSSaveState: {}: treating the GPU as drained: {}. Commands it has not read will be dropped after the restore.", op, parkedWhy);
				gpuDrainedOut = false;
				return true;
			}
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
		uint64 total = 4096 + 64 * 1024; // header, thread list, range table, chunks
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

	// ---- host-side state that travels with the memory dump -------------------------------------------------------------
	//
	// A chunk is {tag, size, bytes}. Everything that lives on the host rather than in guest memory, and that a restore has to put back
	// in step with the memory it restores, is carried in one. All fields are host-endian: a file never leaves the device it was made
	// on, and never outlives the launch that made it.

	constexpr uint32 MakeTag(char a, char b, char c, char d)
	{
		return (uint32)(uint8)a | ((uint32)(uint8)b << 8) | ((uint32)(uint8)c << 16) | ((uint32)(uint8)d << 24);
	}

	constexpr uint32 kTagMeta = MakeTag('M', 'E', 'T', 'A');	// flags and the guest clock at the moment of the save
	constexpr uint32 kTagGx2 = MakeTag('G', 'X', '2', 'S');		// where each core was in its GX2 command buffer

	constexpr uint32 kMaxChunks = 32;
	constexpr uint32 kMaxChunkBytes = 4u * 1024 * 1024;
	constexpr uint32 kMetaFlagGpuDrained = 1u << 0;

	struct Chunk
	{
		uint32 tag = 0;
		std::vector<uint8> data;
	};

	struct ByteWriter
	{
		std::vector<uint8>& out;
		void U32(uint32 v) { const uint8* p = (const uint8*)&v; out.insert(out.end(), p, p + sizeof(v)); }
		void U64(uint64 v) { const uint8* p = (const uint8*)&v; out.insert(out.end(), p, p + sizeof(v)); }
	};

	struct ByteReader
	{
		const std::vector<uint8>& in;
		size_t pos = 0;
		bool ok = true;
		uint32 U32()
		{
			uint32 v = 0;
			if (pos + sizeof(v) > in.size()) { ok = false; return 0; }
			memcpy(&v, in.data() + pos, sizeof(v));
			pos += sizeof(v);
			return v;
		}
		uint64 U64()
		{
			uint64 v = 0;
			if (pos + sizeof(v) > in.size()) { ok = false; return 0; }
			memcpy(&v, in.data() + pos, sizeof(v));
			pos += sizeof(v);
			return v;
		}
		bool Finished() const { return ok && pos == in.size(); }
	};

	std::string TagName(uint32 tag)
	{
		std::string s;
		for (int i = 0; i < 4; i++)
		{
			const char c = (char)((tag >> (8 * i)) & 0xFF);
			s.push_back(c >= 32 && c < 127 ? c : '?');
		}
		return s;
	}

	// ---- what a save collects ---------------------------------------------------------------------------------------

	Chunk MakeMetaChunk(bool gpuDrained)
	{
		Chunk c;
		c.tag = kTagMeta;
		ByteWriter w{c.data};
		w.U32(gpuDrained ? kMetaFlagGpuDrained : 0);
		w.U32(0); // reserved
		w.U64(PPCInterpreter_getMainCoreCycleCounter());
		return c;
	}

	Chunk MakeGx2Chunk()
	{
		GX2::GX2CommandStateSnapshot snap{};
		GX2::GX2CaptureCommandState(snap);
		Chunk c;
		c.tag = kTagGx2;
		ByteWriter w{c.data};
		w.U32((uint32)Espresso::CORE_COUNT);
		for (uint32 i = 0; i < Espresso::CORE_COUNT; i++)
		{
			w.U32(snap.core[i].bufferPtr);
			w.U32(snap.core[i].bufferSizeInU32s);
			w.U32(snap.core[i].currentWritePtr);
			w.U32(snap.core[i].isDisplayList);
		}
		return c;
	}

	// Called with the title paused and quiescent, right before the file is written.
	std::vector<Chunk> CollectExtras(bool gpuDrained)
	{
		std::vector<Chunk> chunks;
		chunks.push_back(MakeMetaChunk(gpuDrained));
		chunks.push_back(MakeGx2Chunk());
		for (const auto& c : chunks)
			cemuLog_log(LogType::Force, "IOSSaveState: save: chunk {} is {} bytes", TagName(c.tag), c.data.size());
		return chunks;
	}

	// Writes to "<path>.tmp" and renames it over the slot only after every byte was
	// written, flushed and closed successfully, so a failed save (for example a full
	// disk) leaves the slot's previous save untouched.
	bool WriteSaveFile(const char* path, uint64 sessionToken, const std::vector<Chunk>& chunks)
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
		const uint32 chunkCount = (uint32)chunks.size();

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

		if (ok && !WriteAll(f, &chunkCount, sizeof(chunkCount)))
		{
			ok = false;
			noteFail();
		}
		if (ok)
		{
			for (const auto& c : chunks)
			{
				const uint32 size = (uint32)c.data.size();
				if (!WriteAll(f, &c.tag, sizeof(c.tag)) || !WriteAll(f, &size, sizeof(size)) || !WriteAll(f, c.data.data(), c.data.size()))
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

	// ---- a save file, parsed ----------------------------------------------------------------------------------------

	// Everything in a file up to the memory data. Parsing reads and checks the whole of it and changes nothing in the game.
	struct SaveImage
	{
		HeaderPrefix header;
		std::vector<MPTR> threads;
		std::vector<SavedRange> ranges;
		std::vector<Chunk> chunks;
		uint64 totalBytes = 0; // memory data that follows
		const Chunk* Find(uint32 tag) const
		{
			for (const auto& c : chunks)
			{
				if (c.tag == tag)
					return &c;
			}
			return nullptr;
		}
	};

	// Opens the file, parses its header, thread list, range table and chunks, and checks that the file is exactly as long as they say.
	// Returns the file positioned on the first byte of memory data, or nullptr with the error set.
	FILE* OpenAndParse(const char* path, SaveImage& img)
	{
		FILE* f = fopen(path, "rb");
		if (!f)
		{
			const int e = errno;
			Fail(SSE_FileMissing, std::string("Couldn't open the save file (") + strerror(e) + ").", std::string("fopen('") + path + "') errno " + std::to_string(e));
			return nullptr;
		}
		auto refuse = [&](IOSSaveStateError code, const char* message, const char* detail) -> FILE*
		{
			fclose(f);
			Fail(code, message, detail);
			return nullptr;
		};

		switch (ReadHeaderPrefix(f, img.header))
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

		uint32 threadCount;
		if (!ReadAll(f, &threadCount, sizeof(threadCount)))
			return refuse(SSE_FileDamaged, "The save file is damaged or incomplete.", "truncated header");
		if (threadCount > 256) // coreinit's own activeThread[] ceiling - anything above is a corrupt/hostile file, not a real save
			return refuse(SSE_FileDamaged, "The save file is damaged.", "thread count in file is not plausible");
		img.threads.resize(threadCount);
		if (!ReadAll(f, img.threads.data(), sizeof(MPTR) * threadCount))
			return refuse(SSE_FileDamaged, "The save file is damaged or incomplete.", "truncated thread list");

		uint32 rangeCount;
		if (!ReadAll(f, &rangeCount, sizeof(rangeCount)))
			return refuse(SSE_FileDamaged, "The save file is damaged or incomplete.", "truncated range table");
		if (rangeCount > 64) // generous ceiling above the real MMU range table - guards against a corrupt/hostile file forcing a huge allocation
			return refuse(SSE_FileDamaged, "The save file is damaged.", "range count in file is not plausible");
		img.ranges.resize(rangeCount);
		for (auto& sr : img.ranges)
		{
			if (!ReadAll(f, &sr, sizeof(sr)))
				return refuse(SSE_FileDamaged, "The save file is damaged or incomplete.", "truncated range table");
		}

		uint32 chunkCount;
		if (!ReadAll(f, &chunkCount, sizeof(chunkCount)))
			return refuse(SSE_FileDamaged, "The save file is damaged or incomplete.", "truncated chunk table");
		if (chunkCount > kMaxChunks)
			return refuse(SSE_FileDamaged, "The save file is damaged.", "chunk count in file is not plausible");
		uint64 chunkBytes = 0;
		for (uint32 i = 0; i < chunkCount; i++)
		{
			Chunk c;
			uint32 size = 0;
			if (!ReadAll(f, &c.tag, sizeof(c.tag)) || !ReadAll(f, &size, sizeof(size)))
				return refuse(SSE_FileDamaged, "The save file is damaged or incomplete.", "truncated chunk header");
			chunkBytes += size;
			if (size > kMaxChunkBytes || chunkBytes > 4ull * kMaxChunkBytes)
				return refuse(SSE_FileDamaged, "The save file is damaged.", "chunk size in file is not plausible");
			c.data.resize(size);
			if (!ReadAll(f, c.data.data(), size))
				return refuse(SSE_FileDamaged, "The save file is damaged or incomplete.", "truncated chunk");
			img.chunks.push_back(std::move(c));
		}

		// The file must be exactly as long as the header says. Checking now, before any
		// memory is touched, means a truncated or damaged slot is refused cleanly.
		for (const auto& sr : img.ranges)
			img.totalBytes += sr.size;
		const off_t dataStart = ftello(f);
		if (dataStart < 0 || fseeko(f, 0, SEEK_END) != 0)
			return refuse(SSE_FileDamaged, "The save file couldn't be read.", "could not determine file size");
		const off_t fileEnd = ftello(f);
		if (fileEnd < 0 || (uint64)fileEnd != (uint64)dataStart + img.totalBytes)
			return refuse(SSE_FileDamaged, "The save file is damaged or incomplete.", "file size does not match its header (truncated or damaged)");
		if (fseeko(f, dataStart, SEEK_SET) != 0)
			return refuse(SSE_FileDamaged, "The save file couldn't be read.", "could not seek within file");
		return f;
	}

	// ---- load: the thread set --------------------------------------------------------------------------------------

	// Compares the threads the save had with the ones that are alive now. True when they are the same set. Until the host side
	// of a thread can be rebuilt from the file, a different set is refused; the difference is logged either way.
	bool CompareThreadSets(const std::vector<MPTR>& saved, std::string& difference)
	{
		std::string added, gone;
		int addedCount = 0, goneCount = 0;
		for (sint32 i = 0; i < activeThreadCount; i++)
		{
			if (std::find(saved.begin(), saved.end(), (MPTR)activeThread[i]) == saved.end())
			{
				addedCount++;
				const OSThread_t* t = (const OSThread_t*)memory_getPointerFromVirtualOffset(activeThread[i]);
				added += fmt::format(" {:08x}('{}')", (uint32)activeThread[i], SafeGuestString(t->threadName.GetMPTR()));
			}
		}
		for (MPTR t : saved)
		{
			bool alive = false;
			for (sint32 i = 0; i < activeThreadCount; i++)
			{
				if (activeThread[i] == t)
				{
					alive = true;
					break;
				}
			}
			if (!alive)
			{
				goneCount++;
				gone += fmt::format(" {:08x}", (uint32)t);
			}
		}
		difference = fmt::format("{} thread(s) started since the save:{}; {} thread(s) from the save are gone:{}", addedCount, added, goneCount, gone);
		return addedCount == 0 && goneCount == 0;
	}

	// ---- load: the memory layout -----------------------------------------------------------------------------------

	// Every saved range has to exist live with the same base and size. A range that is optional (the overlay area, which a game
	// asks for) and not mapped right now is mapped to match, since the restore then has somewhere to put it. A range that is mapped
	// live but absent from the save is left alone. Anything else cannot be reconciled and is refused, naming the range.
	// Nothing is mapped unless every range checks out.
	bool PrepareMemoryLayout(const SaveImage& img, std::vector<MMURange*>& targets, std::string& problem)
	{
		const std::vector<MMURange*> liveRanges = memory_getMMURanges();
		std::vector<MMURange*> toMap;
		targets.clear();
		for (const auto& sr : img.ranges)
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
			if (!match)
			{
				problem = fmt::format("the save has memory at {:08x} (+{:x}) that this game does not have", sr.base, sr.size);
				return false;
			}
			if (match->isMapped())
			{
				if (match->getSize() != sr.size)
				{
					problem = fmt::format("{} is {:x} bytes now and {:x} in the save", match->getName(), match->getSize(), sr.size);
					return false;
				}
			}
			else if (match->isOptional() && match->getSize() == sr.size)
			{
				toMap.push_back(match);
			}
			else
			{
				problem = fmt::format("{} is not mapped now and the save has it ({:x} bytes)", match->getName(), sr.size);
				return false;
			}
			targets.push_back(match);
		}
		for (auto* lr : liveRanges)
		{
			if (!lr->isMapped())
				continue;
			bool inSave = false;
			for (const auto& sr : img.ranges)
				inSave = inSave || sr.base == lr->getBase();
			if (!inSave)
				cemuLog_log(LogType::Force, "IOSSaveState: load: {} is mapped now but is not in the save; left as it is", lr->getName());
		}
		for (auto* r : toMap)
		{
			cemuLog_log(LogType::Force, "IOSSaveState: load: mapping optional range {} ({}) to match the save", r->getName(), Megabytes(r->getSize()));
			r->mapMem();
		}
		return true;
	}

	// ---- load: putting the memory back ------------------------------------------------------------------------------

	constexpr uint32 kGpuCachePageSize = 0x400; // the buffer cache's page size; a restore compares and invalidates in pages of this size

	bool IsGpuVisibleRange(const MMURange* r)
	{
		return r->areaId == MMU_MEM_AREA_ID::MEM2_DATA || r->areaId == MMU_MEM_AREA_ID::MEM1 || r->areaId == MMU_MEM_AREA_ID::OVERLAY;
	}

	struct RestoreStats
	{
		uint64 pagesCompared = 0;
		uint64 pagesChanged = 0;
	};

	// Reads `size` bytes from the file over the live range. For a range the GPU reads, the incoming data is compared with what is
	// there page by page and every page that differs is queued through the same notification the guest's own cache flushes use,
	// so cached buffers and textures built from the old contents are refreshed. Only pages that really change are queued: a
	// restore of a gigabyte that differs in a few megabytes does not make the GPU thread walk a million pages.
	bool RestoreMemoryRange(FILE* f, MMURange* range, uint32 size, std::vector<uint8>& scratch, RestoreStats& stats)
	{
		uint8* dst = range->getPtr();
		if (!IsGpuVisibleRange(range))
			return ReadMemoryRange(f, dst, size);

		scratch.resize(kIoChunkSize);
		const uint32 base = range->getBase();
		uint32 done = 0;
		bool inRun = false;
		uint32 runStart = 0;
		auto closeRun = [&](uint32 runEnd)
		{
			LatteBufferCache_notifyDCFlush(memory_virtualToPhysical(base + runStart), runEnd - runStart);
			inRun = false;
		};
		while (done < size)
		{
			const uint32 n = (uint32)std::min<size_t>(kIoChunkSize, size - done);
			if (fread(scratch.data(), 1, n, f) != n)
				return false;
			for (uint32 off = 0; off < n; off += kGpuCachePageSize)
			{
				const uint32 len = std::min<uint32>(kGpuCachePageSize, n - off);
				stats.pagesCompared++;
				if (memcmp(dst + done + off, scratch.data() + off, len) != 0)
				{
					stats.pagesChanged++;
					if (!inRun)
					{
						inRun = true;
						runStart = done + off;
					}
				}
				else if (inRun)
				{
					closeRun(done + off);
				}
			}
			memcpy(dst + done, scratch.data(), n);
			done += n;
		}
		if (inRun)
			closeRun(size);
		return true;
	}

	// Every check here runs BEFORE a single byte of guest memory is touched. Once restore
	// starts, a truncated/corrupt file can no longer be refused cleanly - see the comment
	// at that call site.
	bool ReadSaveFile(const char* path, bool& gpuDrained)
	{
		const auto start = Clock::now();
		SaveImage img;
		FILE* f = OpenAndParse(path, img);
		if (!f)
			return false;

		auto refuse = [&](IOSSaveStateError code, const char* message, const std::string& detail)
		{
			fclose(f);
			return Fail(code, message, detail);
		};

		if (!CafeSystem::IsTitleRunning() || CafeSystem::GetForegroundTitleId() != img.header.titleId)
			return refuse(SSE_OtherTitle, "This save belongs to a different game.", "title id differs from the running title");
		if (img.header.sessionToken != EnsureSessionToken())
			return refuse(SSE_EarlierSession, "This save is from an earlier session of the game and can't be loaded.", "session token differs");

		// the host-side state this build knows how to put back
		const Chunk* metaChunk = img.Find(kTagMeta);
		const Chunk* gx2Chunk = img.Find(kTagGx2);
		if (!metaChunk || !gx2Chunk)
			return refuse(SSE_UnsupportedFormat, "This save was made by an older version of MuffinEMU and can't be loaded.", fmt::format("missing chunk (META {}, GX2S {})", metaChunk != nullptr, gx2Chunk != nullptr));

		uint32 metaFlags = 0;
		uint64 savedGuestCycles = 0;
		{
			ByteReader r{metaChunk->data};
			metaFlags = r.U32();
			r.U32();
			savedGuestCycles = r.U64();
			if (!r.Finished())
				return refuse(SSE_FileDamaged, "The save file is damaged.", "META chunk has the wrong size");
		}
		GX2::GX2CommandStateSnapshot gx2Snapshot{};
		{
			ByteReader r{gx2Chunk->data};
			if (r.U32() != (uint32)Espresso::CORE_COUNT)
				return refuse(SSE_FileDamaged, "The save file is damaged.", "GX2S chunk has the wrong core count");
			for (uint32 i = 0; i < Espresso::CORE_COUNT; i++)
			{
				gx2Snapshot.core[i].bufferPtr = r.U32();
				gx2Snapshot.core[i].bufferSizeInU32s = r.U32();
				gx2Snapshot.core[i].currentWritePtr = r.U32();
				gx2Snapshot.core[i].isDisplayList = r.U32();
			}
			if (!r.Finished())
				return refuse(SSE_FileDamaged, "The save file is damaged.", "GX2S chunk has the wrong size");
		}
		LogStep("load", fmt::format("file parsed: {} guest threads, {} memory ranges, {} chunks, {} of memory; GPU idle when saved: {}, guest clock {}",
			img.threads.size(), img.ranges.size(), img.chunks.size(), Megabytes(img.totalBytes), (metaFlags & kMetaFlagGpuDrained) != 0, savedGuestCycles));

		// The set of active guest threads: this can only be trusted because the caller has already forced quiescence (Quiesce()).
		std::string threadDifference;
		const bool sameThreads = CompareThreadSets(img.threads, threadDifference);
		cemuLog_log(LogType::Force, "IOSSaveState: load: guest threads in the save {} the live ones{}", sameThreads ? "match" : "DIFFER from", sameThreads ? "" : " - " + threadDifference);
		if (!sameThreads)
		{
			return refuse(SSE_ThreadsChanged,
				"The game has started or stopped background tasks since this save was taken, so it can't be put back safely. Saves load best soon after they're made, in the same part of the game.",
				threadDifference);
		}

		std::vector<MMURange*> targets;
		std::string layoutProblem;
		if (!PrepareMemoryLayout(img, targets, layoutProblem))
		{
			return refuse(SSE_MemoryLayoutChanged,
				"The game's memory layout has changed since this save was taken (an area was loaded or unloaded), so it can't be put back safely.", layoutProblem);
		}
		LogStep("load", "memory layout matches the save");

		std::string gx2Problem;
		if (!GX2::GX2RestoreCommandState(gx2Snapshot, gx2Problem))
			return refuse(SSE_FileDamaged, "The save file is damaged.", "GX2S chunk: " + gx2Problem);
		LogStep("load", "GX2 command buffer positions restored");
		cemuLog_log(LogType::Force, "IOSSaveState: load checks passed in {} ms ({} to restore)", ElapsedMs(start), Megabytes(img.totalBytes));

		// Past this point every header check has passed. A short read from here on means
		// the file changed under us or an I/O error occurred, and guest memory may already
		// be partially overwritten with no way back to a consistent pre-load state - the
		// title must be treated as no longer trustworthy if that happens.
		const auto restoreStart = Clock::now();
		RestoreStats stats;
		std::vector<uint8> scratch;
		for (size_t i = 0; i < targets.size(); i++)
		{
			const auto rangeStart = Clock::now();
			const uint64 changedBefore = stats.pagesChanged;
			if (!RestoreMemoryRange(f, targets[i], img.ranges[i].size, scratch, stats))
			{
				fclose(f);
				return Fail(SSE_DamagedMidRestore, "The save file couldn't be read all the way through and the game's memory is now half-restored. Quit and restart the game.",
					"save file truncated mid-restore - guest memory is inconsistent");
			}
			cemuLog_log(LogType::Force, "IOSSaveState: restored range {:08x} ({}) in {} ms{}", img.ranges[i].base, Megabytes(img.ranges[i].size), ElapsedMs(rangeStart),
				IsGpuVisibleRange(targets[i]) ? fmt::format(", {} pages changed", stats.pagesChanged - changedBefore) : std::string());
		}
		fclose(f);

		// The code at any address may now be entirely different from what was JIT-compiled
		// for the pre-load state. Safe under both the interpreter and the recompiler:
		// PPCRecompiler_invalidateRange() is a no-op when the recompiler isn't active.
		PPCRecompiler_invalidateRange(PPC_REC_CODE_AREA_START, PPC_REC_CODE_AREA_END);
		cemuLog_log(LogType::Force, "IOSSaveState: restored {} in {} ms", Megabytes(img.totalBytes), ElapsedMs(restoreStart));
		LogStep("load", fmt::format("guest memory restored ({}), recompiled code dropped, {} of {} GPU-visible pages differed and were queued for the GPU caches",
			Megabytes(img.totalBytes), stats.pagesChanged, stats.pagesCompared));

		// Guest memory now says what the GPU had been given when the state was saved; the GPU itself did not move.
		std::string gx2Report;
		GX2::GX2ResyncAfterStateLoad(!gpuDrained, gx2Report);
		LogStep("load", "GX2 resynced with the live GPU: " + gx2Report);
		const size_t droppedEvents = GX2::GX2ClearEventCallbackQueue();
		LogStep("load", fmt::format("GX2 event callback queue emptied ({} stale entries dropped)", droppedEvents));
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
	BeginOperationLog();
	const auto total = Clock::now();
	if (!path || !*path)
		return Fail(SSE_InvalidPath, "No save location was given.");
	if (!CafeSystem::IsTitleRunning())
		return Fail(SSE_NoTitle, "The game isn't running.");
	LogStep("save", fmt::format("starting, file '{}'", path));

	// Cheap failures first, before the game is paused: nothing to undo.
	EnsureParentDirectory(path);
	if (!CheckDiskSpace(path, EstimateSaveBytes()))
		return false;
	LogStep("save", "disk space is enough");

	const bool videoStalled = cemu_bridge_video_stalled();
	bool pausedByUs = false;
	if (!PauseForOperation("save", pausedByUs))
		return false;
	LogStep("save", fmt::format("paused (by this save: {}, picture stalled: {})", pausedByUs, videoStalled));

	const auto quiesceStart = Clock::now();
	bool gpuDrained = true;
	bool ok = Quiesce("save", videoStalled, gpuDrained);
	if (ok)
	{
		cemuLog_log(LogType::Force, "IOSSaveState: save: quiescent after {} ms", ElapsedMs(quiesceStart));
		LogStep("save", "cores idle and GPU settled");
		LogMemoryRanges("save");
		LogThreadTable("save: guest threads at the moment of the save");
	}
	ok = ok && WriteSaveFile(path, EnsureSessionToken(), CollectExtras(gpuDrained));
	if (ok)
		LogStep("save", "file written");

	RestorePauseState("save", pausedByUs);
	LogStep("save", "pause state put back");

	cemuLog_log(LogType::Force, "IOSSaveState: save to '{}' {} (total {} ms)", path, ok ? "succeeded" : "failed", ElapsedMs(total));
	return ok;
}

// See the file-level comment, especially the GPU-cache-staleness tradeoff and the
// same-running-instance requirement, before changing what this accepts.
bool IOSSaveState_Load(const char* path)
{
	ClearError();
	BeginOperationLog();
	const auto total = Clock::now();
	if (!path || !*path)
		return Fail(SSE_InvalidPath, "No save location was given.");
	if (!CafeSystem::IsTitleRunning())
		return Fail(SSE_NoTitle, "The game isn't running.");
	LogStep("load", fmt::format("starting, file '{}'", path));

	if (!PrecheckLoad(path))
		return false;
	LogStep("load", "file header is a loadable save from this launch of this game");

	bool pausedByUs = false;
	if (!PauseForOperation("load", pausedByUs))
		return false;
	LogStep("load", fmt::format("paused (by this load: {})", pausedByUs));

	const auto quiesceStart = Clock::now();
	bool gpuDrained = true;
	bool ok = Quiesce("load", false, gpuDrained);
	if (ok)
	{
		cemuLog_log(LogType::Force, "IOSSaveState: load: quiescent after {} ms", ElapsedMs(quiesceStart));
		LogStep("load", "cores idle and GPU settled");
		LogMemoryRanges("load: live memory before the restore");
		LogThreadTable("load: live guest threads before the restore");
	}
	ok = ok && ReadSaveFile(path, gpuDrained);
	if (ok)
		LogThreadTable("load: guest threads after the restore");

	RestorePauseState("load", pausedByUs);
	LogStep("load", fmt::format("pause state put back, result: {}", ok ? "loaded" : "failed"));

	cemuLog_log(LogType::Force, "IOSSaveState: load from '{}' {} (total {} ms)", path, ok ? "succeeded" : "failed", ElapsedMs(total));
	return ok;
}
