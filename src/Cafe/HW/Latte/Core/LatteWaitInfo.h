#pragma once

#include <atomic>
#include <chrono>
#include <cstdint>

// Lightweight breadcrumbs the GPU thread leaves behind so a stall can be explained after the fact.
// Everything here is a relaxed atomic: it is written from the GPU thread and read by the
// render-stall watchdog in the bridge, and it must never be able to slow the GPU thread down.
namespace LatteWait
{
	// Who the GPU thread is waiting for. The stall watchdog tells "the game is not sending GPU work" (a
	// loading screen, a game-side hang: not a video freeze) from "the GPU is not finishing work" with this.
	enum class Kind : uint8_t
	{
		None = 0,
		GuestIdle = 1, // the command ring is empty
		GuestWait = 2, // a semaphore or flip only the game can release
		Gpu = 3,       // a command buffer, query or readback (the default for a wait)
		Display = 4,   // a screen drawable
	};

	struct State
	{
		// what the GPU thread is blocked on right now (string literal), or nullptr when it is running
		std::atomic<const char*> reason{nullptr};
		std::atomic<int64_t> reasonSinceMs{0};
		std::atomic<uint8_t> reasonKind{0}; // Kind of `reason`

		// waits that gave up (see WaitForCommandBuffer and the force-finish loops)
		std::atomic<uint32_t> timeouts{0};
		std::atomic<const char*> lastTimeoutReason{nullptr};
		std::atomic<bool> gpuPresumedLost{false};

		// command processor
		std::atomic<uint32_t> lastPM4Opcode{0};
		std::atomic<uint32_t> pm4Count{0}; // packets processed; only ever written by the GPU thread

		// pending asynchronous work
		std::atomic<uint32_t> queriesInFlight{0};
		std::atomic<uint32_t> readbacksPending{0};
		std::atomic<uint32_t> executingCommandBuffers{0};
		std::atomic<uint32_t> erroredCommandBuffers{0};
		// GPU progress, for the stall watchdog: command buffers handed to the GPU, finished without error, and the
		// current run of failed ones (reset by a success) with the last failure's MTLCommandBufferError code.
		std::atomic<uint32_t> cbSubmitted{0};
		std::atomic<uint32_t> cbRetired{0};
		std::atomic<uint32_t> cbErrorStreak{0};
		std::atomic<int32_t> cbLastErrorCode{0};

		// A command buffer ended in an error that stops the GPU doing this process's work
		// (page fault, ignored submissions, timeout...). Latched until the title stops.
		std::atomic<bool> gpuError{false};
		std::atomic<int32_t> gpuErrorCode{0};

		// GPU memory breakdown in MB, refreshed by the GPU thread about twice a second so the
		// memory watchdog can put it in every MEM line without touching GPU-thread data.
		std::atomic<uint32_t> memDeviceMB{0};
		std::atomic<uint32_t> memHostMappedMB{0};
		std::atomic<uint32_t> memTextureCount{0};
		std::atomic<uint32_t> memTextureMB{0};
		std::atomic<uint32_t> memStagingMB{0};
		std::atomic<uint32_t> memIndexMB{0};
		std::atomic<uint32_t> memSnapshotMB{0};
		std::atomic<uint32_t> memBufferCacheMB{0};
		std::atomic<uint32_t> memXfbMB{0};
		std::atomic<uint32_t> memReadbackMB{0};
		std::atomic<uint32_t> texturesEvicted{0};
		// Another thread (a guest thread that could not get a stack) asks the GPU thread to evict textures now;
		// the GPU thread bumps evictionPasses when it has done so.
		std::atomic<bool> evictionRequested{false};
		std::atomic<uint32_t> evictionPasses{0};
		std::atomic<bool> memStatsValid{false};

		// presentation
		std::atomic<uint32_t> presentedFrames{0};
		std::atomic<uint32_t> drawableFailures{0};
		std::atomic<uint32_t> drawableFailuresInARow{0};
		std::atomic<bool> tvDrawableHeld{false};
		std::atomic<uint32_t> tvDrawableWidth{0};
		std::atomic<uint32_t> tvDrawableHeight{0};
		std::atomic<bool> tvLayerAttached{false};
		std::atomic<bool> tvLayerHasDevice{false};
	};

	inline State& Get()
	{
		static State s_state;
		return s_state;
	}

	inline int64_t NowMs()
	{
		return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
	}

	// only restarts the clock when the reason changes, so a spin loop can call this every iteration
	inline void Set(const char* reason, Kind kind = Kind::Gpu)
	{
		auto& s = Get();
		if (s.reason.load(std::memory_order_relaxed) != reason)
		{
			s.reasonSinceMs.store(NowMs(), std::memory_order_relaxed);
			s.reasonKind.store((uint8_t)kind, std::memory_order_relaxed);
			s.reason.store(reason, std::memory_order_relaxed);
		}
	}

	inline void Clear()
	{
		auto& s = Get();
		if (s.reason.load(std::memory_order_relaxed) != nullptr)
		{
			s.reason.store(nullptr, std::memory_order_relaxed);
			s.reasonKind.store((uint8_t)Kind::None, std::memory_order_relaxed);
		}
	}

	inline void NotePM4(uint32_t opcode)
	{
		auto& s = Get();
		s.lastPM4Opcode.store(opcode, std::memory_order_relaxed);
		// single writer (the GPU thread), so a plain load and store instead of a locked increment
		s.pm4Count.store(s.pm4Count.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
	}

	// RAII form for a single blocking call; restores whatever was set before it
	struct Scope
	{
		explicit Scope(const char* reason, Kind kind = Kind::Gpu)
			: m_previous(Get().reason.load(std::memory_order_relaxed)), m_previousKind((Kind)Get().reasonKind.load(std::memory_order_relaxed))
		{
			Set(reason, kind);
		}
		~Scope()
		{
			if (m_previous)
				Set(m_previous, m_previousKind);
			else
				Clear();
		}
		Scope(const Scope&) = delete;
		Scope& operator=(const Scope&) = delete;
	private:
		const char* m_previous;
		Kind m_previousKind;
	};
}
