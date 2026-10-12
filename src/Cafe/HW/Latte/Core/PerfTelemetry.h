#pragma once

#include <atomic>
#include <chrono>
#include <cstdint>
#include <type_traits>

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
		// Of that work, the BC to ASTC re-encode (decode the BC blocks, then ASTC-encode them). Counted where the
		// encode runs, so it also includes the re-encode of copied raw blocks, which textureDecodes does not.
		std::atomic<uint32_t> textureTranscodes{0};
		std::atomic<uint64_t> textureTranscodeNs{0};

		// Latte (GPU) thread breakdown, wall nanoseconds on that thread. The first three are disjoint
		// slices of a draw; the rest are parts of those slices (see ios_perf_log_window for the layout).
		std::atomic<uint32_t> gpuDraws{0};          // draw calls handled
		std::atomic<uint64_t> gpuBeginNs{0};        // draw_beginSequence: shaders, render target, textures
		std::atomic<uint64_t> gpuTexUpdateNs{0};    //   of it: LatteTexture_updateTextures
		std::atomic<uint64_t> gpuTexHashNs{0};      //     of that: texture change hashing
		std::atomic<uint32_t> gpuTexHashes{0};      //     textures hashed
		std::atomic<uint64_t> gpuTexHashBytes{0};   //     guest bytes covered by those textures
		std::atomic<uint64_t> gpuExecNs{0};         // draw_execute, everything
		std::atomic<uint64_t> gpuIndexNs{0};        //   index decode / conversion
		std::atomic<uint64_t> gpuFlushNs{0};        //   guest cache-flush queue processing
		std::atomic<uint64_t> gpuBufferNs{0};       //   vertex + uniform buffer binding and snapshots
		std::atomic<uint64_t> gpuSnapshotCompareBytes{0}; // bytes memcmp'd against a snapshot
		std::atomic<uint64_t> gpuSnapshotCopyBytes{0};    // bytes copied into a new snapshot
		std::atomic<uint64_t> gpuPassNs{0};         //   render encoder / pass setup
		std::atomic<uint64_t> gpuPipelineNs{0};     //   pipeline state lookup
		std::atomic<uint64_t> gpuBindNs{0};         //   per-stage uniform, texture and sampler binding
		std::atomic<uint32_t> gpuUseResourceCalls{0}; //     of it: useResource() calls made on the encoder
		std::atomic<uint32_t> gpuUseResourceSkips{0}; //     useResource() calls skipped, already declared on this encoder
		std::atomic<uint64_t> gpuUseResourceNs{0};
		std::atomic<uint32_t> gpuArgEncodes{0};     //     argument buffers encoded
		std::atomic<uint64_t> gpuArgEncodeNs{0};
		std::atomic<uint32_t> gpuArgReuses{0};      //     argument buffers found in the cache
		std::atomic<uint64_t> gpuArgReuseNs{0};
		std::atomic<uint32_t> gpuArgMissNoBase{0};  //     argument buffer misses with no earlier entry for the layout
		std::atomic<uint32_t> gpuArgMissSupport{0}; //     misses (this and the next five are not exclusive) where the support buffer differs from the latest entry,
		std::atomic<uint32_t> gpuArgMissSupportOnly{0}; //   where only it does,
		std::atomic<uint32_t> gpuArgMissUniform{0}; //     uniform buffers,
		std::atomic<uint32_t> gpuArgMissTexture{0}; //     textures,
		std::atomic<uint32_t> gpuArgMissSampler{0}; //     samplers,
		std::atomic<uint32_t> gpuArgMissVertexIndex{0}; //  vertex / index / streamout buffers,
		std::atomic<uint32_t> gpuArgMissConstant{0};    //  vertex / index sizes and index type
		std::atomic<uint32_t> gpuArgDeltaEncodes{0};    //  misses encoded by copying the latest entry and writing only the differing slots
		std::atomic<uint64_t> gpuArgDeltaSlots{0};      //    slots written by those
		// Parts of per-stage binding time (disjoint unless noted), to account for what the counters above do not cover
		std::atomic<uint64_t> gpuBindTextureLoopNs{0};  //     texture + sampler loop (includes the lookups above and breadcrumb texture writes)
		std::atomic<uint64_t> gpuBindResidencyNs{0};    //     residency table lookups that decide whether useResource() is needed (nested in the others)
		std::atomic<uint64_t> gpuBindSupportPrepNs{0};  //     support buffer contents: rescale, alpha ref, registers, viewport (not the next two)
		std::atomic<uint64_t> gpuBindRemappedNs{0};     //     remapped uniform loading
		std::atomic<uint64_t> gpuBindSnapshotNs{0};     //     support buffer snapshot compare / upload
		std::atomic<uint64_t> gpuBindUniformLoopNs{0};  //     uniform buffer loop, everything
		std::atomic<uint64_t> gpuBindTrackNs{0};        //       of it: shared buffer cache tracking
		std::atomic<uint64_t> gpuBindCrumbNs{0};        //       of it: breadcrumb writes
		std::atomic<uint64_t> gpuBindVertexNs{0};       //     vertex / index buffer recording for the argument buffer
		std::atomic<uint64_t> gpuBindFinalNs{0};        //     argument buffer lookup and binding to the encoder (includes the encode and reuse time above)
		std::atomic<uint32_t> gpuSamplerLookups{0};
		std::atomic<uint64_t> gpuSamplerLookupNs{0};
		std::atomic<uint32_t> gpuTexViewLookups{0};
		std::atomic<uint64_t> gpuTexViewLookupNs{0};
		std::atomic<uint64_t> gpuEndNs{0};          // draw_endSequence: readback checks, command buffer commit

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

	// True while the app is in the background. iOS refuses GPU work from a backgrounded app (the command
	// buffer fails with "not permitted") and a layer that is not on screen hands out no drawables, so the
	// renderer neither waits on a drawable nor adds presents while this is set.
	inline std::atomic<bool>& AppInBackground()
	{
		static std::atomic<bool> s_background{false};
		return s_background;
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

	// Sampling for the fine-grained GPU-thread timers. Timing every useResource(), lookup and encode
	// costs more than a few percent of a heavy frame, so those only run on one frame in kSampleEvery
	// (chosen once per frame by BeginFrameSampling on the GPU thread, read as a plain bool) and what they
	// add is multiplied by kSampleEvery, so the totals keep the meaning of an every-frame measurement.
	// The flag is only touched by the GPU thread.
	inline constexpr uint32_t kSampleEvery = 8;
	inline bool g_sampleFrame = false;
	inline bool IsSampling() { return g_sampleFrame; }
	inline void BeginFrameSampling()
	{
		static uint32_t s_frame = 0;
		g_sampleFrame = (s_frame++ % kSampleEvery) == 0;
	}
	// 0 when this frame is not sampled (NowNs is never 0)
	inline uint64_t SampleStart() { return g_sampleFrame ? NowNs() : 0; }
	inline void SampleEnd(std::atomic<uint64_t>& sink, uint64_t start)
	{
		if (start)
			sink.fetch_add((NowNs() - start) * kSampleEvery, std::memory_order_relaxed);
	}
	template <typename T>
	inline void SampleCount(std::atomic<T>& sink, typename std::common_type<T>::type n = 1)
	{
		if (g_sampleFrame)
			sink.fetch_add(n * kSampleEvery, std::memory_order_relaxed);
	}
	class SampledTimer
	{
	public:
		explicit SampledTimer(std::atomic<uint64_t>& sink) : m_sink(sink), m_start(SampleStart()) {}
		~SampledTimer() { SampleEnd(m_sink, m_start); }
		SampledTimer(const SampledTimer&) = delete;
		SampledTimer& operator=(const SampledTimer&) = delete;
	private:
		std::atomic<uint64_t>& m_sink;
		uint64_t m_start;
	};

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
