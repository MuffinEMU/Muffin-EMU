#pragma once

#include <atomic>
#include <chrono>
#include <cstdint>

// Cumulative counters for the performance line the iOS bridge logs every few seconds and for the
// in-game overlay. Everything is a relaxed atomic bumped from the thread that does the work and
// read (as deltas between two samples) by one sampler thread, so a counter costs a few
// nanoseconds at most and none of them can block or reorder anything. Timers only ever wrap
// waits and whole units of work (a timeslice hand-off, a command buffer, a compile), never
// individual instructions or draws.
namespace PerfTelemetry
{
	struct Counters
	{
		// PPC scheduler: nanoseconds the scheduler's idle fiber ran (nothing runnable, or
		// the hand-off between two guest threads), summed over the host threads
		std::atomic<uint64_t> ppcIdleNs{0};
		std::atomic<uint32_t> ppcHostThreads{1};

		// Latte (GPU) thread: waiting for the guest to send commands, and blocked on
		// something else (flip/vsync, fences, semaphores, the drawable, a command buffer)
		std::atomic<uint64_t> gpuIdleNs{0};
		std::atomic<uint64_t> gpuSyncNs{0};
		std::atomic<uint64_t> drawableWaitNs{0};

		// Metal: what the GPU itself reports for completed command buffers
		std::atomic<uint64_t> mtlGpuNs{0};
		std::atomic<uint32_t> mtlCommandBuffers{0};
		std::atomic<uint32_t> tvPresents{0};
		std::atomic<uint32_t> padPresents{0};

		// compiles; the ns counters are wall time on the compiling thread
		std::atomic<uint32_t> shaderCompiles{0};
		std::atomic<uint64_t> shaderCompileNs{0};
		std::atomic<uint32_t> pipelineCompiles{0};
		std::atomic<uint64_t> pipelineCompileNs{0};
		// pipelines the GPU thread had to compile itself instead of handing to a compile thread
		std::atomic<uint32_t> pipelineSyncCompiles{0};

		// Latte thread: guest texture data turned into host texture contents (untile, decode, and the
		// BC to ASTC re-encode on a GPU without BC). Wall time on the calling thread, per slice.
		std::atomic<uint32_t> textureDecodes{0};
		std::atomic<uint64_t> textureDecodeNs{0};

		// PPC recompiler
		std::atomic<uint32_t> jitBlocks{0};
		std::atomic<uint64_t> jitCompileNs{0};
		std::atomic<uint32_t> jitInvalidations{0}; // functions dropped because guest code changed
		std::atomic<uint32_t> jitArenaReleases{0}; // ranges handed back to the arena
		std::atomic<uint32_t> jitArenaAllocFails{0}; // a block could not get arena space
	};

	inline Counters& Get()
	{
		static Counters s_counters;
		return s_counters;
	}

	// Published by the sampler once per window so the overlay can show the same numbers the log
	// line does. All zero (and valid == false) until the first window has been measured, and on
	// platforms that have no sampler.
	struct Summary
	{
		std::atomic<bool> valid{false};
		std::atomic<float> hostFps{0};
		std::atomic<float> guestFps{0};
		std::atomic<float> vsyncRate{0};
		std::atomic<float> ppcExecPct{0};
		std::atomic<float> gpuThreadBusyPct{0};
		std::atomic<float> mtlGpuMsPerFrame{0};
		std::atomic<float> mtlGpuBusyPct{0};
		std::atomic<int> bottleneck{0}; // see BottleneckName()
	};

	inline Summary& GetSummary()
	{
		static Summary s_summary;
		return s_summary;
	}

	// The per-draw breadcrumb ring in MetalRenderer is forensic data for a GPU fault; this lets the
	// bridge turn the recording off. On by default.
	inline std::atomic<bool>& DrawBreadcrumbsEnabled()
	{
		static std::atomic<bool> s_enabled{true};
		return s_enabled;
	}

	inline const char* BottleneckName(int code)
	{
		switch (code)
		{
		case 1: return "at frame cap";
		case 2: return "GPU";
		case 3: return "CPU (PPC)";
		case 4: return "CPU (GPU thread)";
		case 5: return "sync";
		case 6: return "compiling";
		case 7: return "no frames";
		default: return "unknown";
		}
	}

	inline uint64_t NowNs()
	{
		return (uint64_t)std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
	}

	// Adds the time between construction and destruction to a counter.
	class ScopedTimer
	{
	public:
		explicit ScopedTimer(std::atomic<uint64_t>& sink) : m_sink(sink), m_start(NowNs()) {}
		~ScopedTimer() { m_sink.fetch_add(NowNs() - m_start, std::memory_order_relaxed); }
		ScopedTimer(const ScopedTimer&) = delete;
		ScopedTimer& operator=(const ScopedTimer&) = delete;
	private:
		std::atomic<uint64_t>& m_sink;
		uint64_t m_start;
	};
}
