#pragma once

#include <atomic>
#include <chrono>
#include <cstdint>

// Lightweight breadcrumbs the GPU thread leaves behind so a stall can be explained after the fact.
// Everything here is a relaxed atomic: it is written from the GPU thread and read by the
// render-stall watchdog in the bridge, and it must never be able to slow the GPU thread down.
namespace LatteWait
{
	struct State
	{
		// what the GPU thread is blocked on right now (string literal), or nullptr when it is running
		std::atomic<const char*> reason{nullptr};
		std::atomic<int64_t> reasonSinceMs{0};

		// waits that gave up (see WaitForCommandBuffer and the force-finish loops)
		std::atomic<uint32_t> timeouts{0};
		std::atomic<const char*> lastTimeoutReason{nullptr};
		std::atomic<bool> gpuPresumedLost{false};

		// command processor
		std::atomic<uint32_t> lastPM4Opcode{0};

		// pending asynchronous work
		std::atomic<uint32_t> queriesInFlight{0};
		std::atomic<uint32_t> readbacksPending{0};
		std::atomic<uint32_t> executingCommandBuffers{0};
		std::atomic<uint32_t> erroredCommandBuffers{0};

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
	inline void Set(const char* reason)
	{
		auto& s = Get();
		if (s.reason.load(std::memory_order_relaxed) != reason)
		{
			s.reasonSinceMs.store(NowMs(), std::memory_order_relaxed);
			s.reason.store(reason, std::memory_order_relaxed);
		}
	}

	inline void Clear()
	{
		auto& s = Get();
		if (s.reason.load(std::memory_order_relaxed) != nullptr)
			s.reason.store(nullptr, std::memory_order_relaxed);
	}

	inline void NotePM4(uint32_t opcode)
	{
		Get().lastPM4Opcode.store(opcode, std::memory_order_relaxed);
	}

	// RAII form for a single blocking call; restores whatever was set before it
	struct Scope
	{
		explicit Scope(const char* reason) : m_previous(Get().reason.load(std::memory_order_relaxed))
		{
			Set(reason);
		}
		~Scope()
		{
			if (m_previous)
				Set(m_previous);
			else
				Clear();
		}
		Scope(const Scope&) = delete;
		Scope& operator=(const Scope&) = delete;
	private:
		const char* m_previous;
	};
}
