#pragma once

// What this device is and what it can afford, asked once and read everywhere.
//
// MuffinEMU runs on everything from a 2 GB iPhone to a 16 GB M-series iPad. Nothing in the
// engine or the app should carry a number that was measured on one of them: each budget below
// is derived from the capabilities the OS reports at launch, and every consumer reads it from
// here. The numbers for the middle tier are the ones that shipped before this existed (and were
// proven on 6 GB devices), so a device in that tier behaves exactly as it always did.
//
// Header only, so the Metal renderer, the recompiler and the bridge can all use it without a
// link dependency on each other. The bridge publishes the full picture (GPU, screen) once at
// launch through Publish(); until then, or in a binary that has no bridge, Get() falls back to
// what sysctl alone can answer and the GPU fields read as unknown.
//
// On anything that is not iOS every budget is the long-standing upstream value.

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#include <sys/sysctl.h>
#endif

#if defined(__APPLE__) && TARGET_OS_IPHONE
#define CEMU_DEVICECAPS_IOS 1
#else
#define CEMU_DEVICECAPS_IOS 0
#endif

namespace DeviceCaps
{
	// Low: under 4.5 GiB of RAM (2, 3 and 4 GB devices; hw.memsize reads about 10% under the
	// marketing number). Standard: 4.5 to 7 GiB (6 GB iPads and iPhone 14 to 16).
	// High: 7 GiB and up (8 and 16 GB M-series iPads, 8 GB iPhones).
	enum class Tier : uint8_t { Low = 0, Standard = 1, High = 2 };

	enum class ScreenClass : uint8_t
	{
		Unknown = 0,
		PhoneCompact = 1, // 4.7 to 5.4 inch: SE, 8, mini. Short side 375 pt or less.
		Phone = 2,        // every other iPhone
		Pad = 3,          // iPad mini through iPad Pro 11 inch
		PadLarge = 4,     // iPad Pro 12.9 and 13 inch, iPad Air 13 inch (short side 1024 pt or more)
	};

	struct Info
	{
		char machine[32] = {};     // hw.machine, e.g. "iPad8,11"
		char chipFamily[24] = {};  // from the GPU name, e.g. "A12Z", "A17 Pro", "M2"; empty if unknown
		char chipSeries = 0;       // 'A' or 'M', 0 if unknown
		int chipNumber = 0;        // 17 for A17 Pro, 2 for M2

		bool gpuKnown = false;
		int appleGpuFamily = 0;    // highest MTLGPUFamilyAppleN supported (1 to 9), 0 if none or unknown
		bool metal3 = false;
		bool meshShaders = false;  // Apple7 (A14, M1) and later with Metal 3
		bool bcTextures = false;   // native BC1-7; false means the renderer transcodes to ASTC
		bool astcHdr = false;      // Apple6 (A13) and later
		uint64_t maxBufferLength = 0;
		uint64_t recommendedMaxWorkingSet = 0;

		uint64_t physicalMemory = 0;
		uint64_t availableAtLaunch = 0; // os_proc_available_memory() when the snapshot was taken
		uint32_t logicalCores = 0;
		uint32_t perfCores = 0;
		uint32_t effCores = 0;

		ScreenClass screen = ScreenClass::Unknown;
		uint32_t screenShortPoints = 0;
		uint32_t screenLongPoints = 0;
		uint32_t screenScale = 0; // native scale, rounded
		bool isPad = false;

		Tier tier() const
		{
			constexpr uint64_t GiB = 1024ull * 1024ull * 1024ull;
			if (physicalMemory == 0)
				return Tier::Standard; // unknown: behave as the shipped defaults do
			if (physicalMemory < (9 * GiB) / 2)
				return Tier::Low;
			if (physicalMemory < 7 * GiB)
				return Tier::Standard;
			return Tier::High;
		}

		// A17 Pro and later, or any M-series: the parts with the GPU and thermal headroom to
		// start at a higher render scale.
		bool isHighEndSoc() const
		{
			if (chipSeries == 'M')
				return true;
			return chipSeries == 'A' && chipNumber >= 17;
		}
	};

	inline const char* TierName(Tier t)
	{
		return t == Tier::Low ? "low" : (t == Tier::High ? "high" : "standard");
	}

	inline const char* ScreenClassName(ScreenClass s)
	{
		switch (s)
		{
		case ScreenClass::PhoneCompact: return "phone-compact";
		case ScreenClass::Phone: return "phone";
		case ScreenClass::Pad: return "pad";
		case ScreenClass::PadLarge: return "pad-large";
		default: return "unknown";
		}
	}

	// What the tier means in bytes. Standard is what shipped, and is what a non-iOS build uses.
	struct Budgets
	{
		uint64_t bufferCacheBytes = 164ull * 1024 * 1024;     // the GPU-visible mirror of guest buffers
		uint64_t stagingChunkBytes = 32ull * 1024 * 1024;     // one host-to-GPU upload chunk
		uint64_t textureReadbackBytes = 32ull * 1024 * 1024;  // GPU-to-CPU readback ring
		uint32_t jitArenaStartMB = 512;                       // first rung of the JIT arena ladder
		uint64_t evictLowFloorBytes = 600ull * 1024 * 1024;   // start evicting cheap textures below this...
		uint64_t evictCriticalFloorBytes = 400ull * 1024 * 1024; // ...and unused GPU-written ones below this
		uint64_t minBootHeadroomBytes = 0;                    // refuse to start a game with less room than this
		bool multicoreViable = true;                          // three host threads for the emulated cores
	};

	// How far a tier's budgets may grow from the memory the process really has. The tier's own
	// values are the floor (scale 1, nothing ever drops below them); the scale rises as the
	// process's free memory at launch (os_proc_available_memory) passes the amount the tier's
	// values were sized for, up to a ceiling per tier. Returned in 1/100ths. Low does not grow:
	// a small device has no spare memory to hand out.
	inline uint32_t BudgetScalePercent(Tier tier, uint64_t availableAtLaunch)
	{
		constexpr uint64_t MB = 1024ull * 1024ull;
		uint64_t referenceMB = 0; // free memory the tier's base values were sized for
		uint32_t maxPercent = 100;
		switch (tier)
		{
		case Tier::Low: return 100;
		case Tier::Standard: referenceMB = 4608; maxPercent = 150; break;
		case Tier::High: referenceMB = 4096; maxPercent = 200; break;
		}
		if (availableAtLaunch == 0)
			return 100; // unreadable: keep the tier's values
		const uint64_t percent = availableAtLaunch / MB * 100 / referenceMB;
		return (uint32_t)std::min<uint64_t>(maxPercent, std::max<uint64_t>(100, percent));
	}

	inline Budgets ComputeBudgets(const Info& info)
	{
		Budgets b;
#if CEMU_DEVICECAPS_IOS
		constexpr uint64_t MB = 1024ull * 1024ull;
		switch (info.tier())
		{
		case Tier::Low:
			b.bufferCacheBytes = 128 * MB;
			b.stagingChunkBytes = 16 * MB;
			b.jitArenaStartMB = 256;
			b.multicoreViable = false; // two or three host threads on 2 to 4 GB parts heat and starve the GPU
			break;
		case Tier::Standard:
			break;
		case Tier::High:
			b.bufferCacheBytes = 256 * MB;
			b.stagingChunkBytes = 64 * MB;
			b.textureReadbackBytes = 64 * MB;
			break;
		}
		// The tier's values above are the floor. Scale them from the memory this process really has
		// free, so a device with more room than its tier assumes gets more of it.
		const uint64_t floorCache = b.bufferCacheBytes;
		const uint64_t floorStaging = b.stagingChunkBytes;
		const uint32_t pct = BudgetScalePercent(info.tier(), info.availableAtLaunch);
		if (pct > 100)
		{
			auto scaled = [&](uint64_t v, uint64_t quantum) { return std::max<uint64_t>(v, v * pct / 100 / quantum * quantum); };
			uint64_t cache = scaled(b.bufferCacheBytes, 16 * MB);
			// The cache is one MTLBuffer: it may grow only to an eighth of the device's maximum buffer.
			if (info.maxBufferLength != 0)
				cache = std::min<uint64_t>(cache, std::max<uint64_t>(floorCache, info.maxBufferLength / 8));
			b.bufferCacheBytes = cache;
			b.stagingChunkBytes = scaled(b.stagingChunkBytes, 8 * MB);
			b.textureReadbackBytes = scaled(b.textureReadbackBytes, 8 * MB);
			b.jitArenaStartMB = (uint32_t)scaled((uint64_t)b.jitArenaStartMB, 128);
			b.evictLowFloorBytes = scaled(b.evictLowFloorBytes, 50 * MB);
			b.evictCriticalFloorBytes = scaled(b.evictCriticalFloorBytes, 50 * MB);
		}
		// The cache is one MTLBuffer, so it cannot be larger than the device's maximum buffer.
		if (info.maxBufferLength != 0)
			b.bufferCacheBytes = std::min<uint64_t>(b.bufferCacheBytes, std::max<uint64_t>(64 * MB, info.maxBufferLength));
		// The emulated console has three cores; fewer host cores than that cannot run them in parallel.
		if (info.logicalCores != 0 && info.logicalCores < 3)
			b.multicoreViable = false;
		// The cache, the first staging chunk and room for the guest's own working set. Sized from the
		// floor values, so scaling up never makes a game refuse to start where it started before.
		b.minBootHeadroomBytes = std::min<uint64_t>(b.bufferCacheBytes, floorCache) + floorStaging + 192 * MB;
#endif
		return b;
	}

	// Eviction marks for the Metal texture cache, from what the process had free when the first
	// frame was presented. Below 1.5 GB of headroom the device is small: it keeps a larger share in
	// reserve (45% and 25% instead of the shipped 35% and 20%), because a texture dropped early only
	// costs a re-upload while a process killed for memory costs the whole session. The absolute
	// floors were measured on a device with about 4.5 GB free, so they are capped to a share of the
	// headroom the device really has (50% and 30%) instead of evicting from the first frame.
	// Returns true for the small-headroom class. An unreadable headroom (0) gives marks of 0: no
	// eviction is requested from a number that means nothing.
	inline bool EvictionMarks(const Budgets& b, uint64_t startAvailable, uint64_t& lowMark, uint64_t& criticalMark)
	{
		constexpr uint64_t MB = 1024ull * 1024ull;
		const bool small = startAvailable < 1536 * MB;
		const uint64_t lowPercent = small ? 45 : 35;
		const uint64_t criticalPercent = small ? 25 : 20;
		lowMark = std::max<uint64_t>(startAvailable * lowPercent / 100, std::min<uint64_t>(b.evictLowFloorBytes, startAvailable / 2));
		criticalMark = std::max<uint64_t>(startAvailable * criticalPercent / 100, std::min<uint64_t>(b.evictCriticalFloorBytes, startAvailable * 30 / 100));
		return small;
	}

	// There is deliberately no low-memory card threshold here. The video-stall watchdog
	// (ios/Bridge/StallDetector.h, unit-tested in ci/stall-detector-test.cpp) owns it, as fractions of
	// the process's own memory limit (warn below 4%, clear above 7%, 32 MB floor), so it already scales
	// with the device without a tier.

	namespace detail
	{
		inline Info& Storage()
		{
			static Info s_info;
			return s_info;
		}
		inline bool& Published()
		{
			static bool s_published = false;
			return s_published;
		}

#if defined(__APPLE__)
		inline uint64_t SysctlU64(const char* name)
		{
			uint64_t v = 0;
			size_t len = sizeof(v);
			if (sysctlbyname(name, &v, &len, nullptr, 0) == 0 && len == sizeof(v))
				return v;
			uint32_t v32 = 0;
			len = sizeof(v32);
			if (sysctlbyname(name, &v32, &len, nullptr, 0) == 0)
				return v32;
			return 0;
		}
		inline void SysctlString(const char* name, char* out, size_t outSize)
		{
			size_t len = outSize;
			out[0] = 0;
			if (sysctlbyname(name, out, &len, nullptr, 0) != 0)
				out[0] = 0;
			out[outSize - 1] = 0;
		}
#endif
	}

	// What sysctl alone can say. Used by the bridge as the first half of the snapshot, and by
	// Get() when nothing was published.
	inline Info FromSysctl()
	{
		Info info;
#if defined(__APPLE__)
		detail::SysctlString("hw.machine", info.machine, sizeof(info.machine));
		info.physicalMemory = detail::SysctlU64("hw.memsize");
		info.logicalCores = (uint32_t)detail::SysctlU64("hw.ncpu");
		info.perfCores = (uint32_t)detail::SysctlU64("hw.perflevel0.logicalcpu");
		info.effCores = (uint32_t)detail::SysctlU64("hw.perflevel1.logicalcpu");
		info.isPad = std::strncmp(info.machine, "iPad", 4) == 0;
#endif
		return info;
	}

	// Called once by the bridge at launch, before the renderer or the recompiler start.
	inline void Publish(const Info& info)
	{
		detail::Storage() = info;
		detail::Published() = true;
	}

	inline bool IsPublished() { return detail::Published(); }

	inline const Info& Get()
	{
		if (!detail::Published())
		{
			// Not published (no bridge in this binary): answer from sysctl, once.
			static const Info s_fallback = FromSysctl();
			return s_fallback;
		}
		return detail::Storage();
	}

	inline const Budgets& GetBudgets()
	{
		static const Budgets s_budgets = ComputeBudgets(Get());
		return s_budgets;
	}

	// The one line every device log starts with, so reports from different devices compare.
	inline std::string Line(const Info& info)
	{
		char buf[640];
		std::snprintf(buf, sizeof(buf),
			"DEVICE %s | chip %s | tier %s | RAM %llu MB, %llu MB free at launch | cores %u (%u perf + %u eff) | "
			"GPU apple%d%s, max buffer %llu MB, working set %llu MB, BC %s, ASTC-HDR %s, mesh shaders %s | screen %s %ux%u pt @%ux",
			info.machine[0] ? info.machine : "unknown",
			info.chipFamily[0] ? info.chipFamily : "unknown",
			TierName(info.tier()),
			(unsigned long long)(info.physicalMemory / (1024 * 1024)),
			(unsigned long long)(info.availableAtLaunch / (1024 * 1024)),
			info.logicalCores, info.perfCores, info.effCores,
			info.appleGpuFamily, info.metal3 ? "+metal3" : "",
			(unsigned long long)(info.maxBufferLength / (1024 * 1024)),
			(unsigned long long)(info.recommendedMaxWorkingSet / (1024 * 1024)),
			info.gpuKnown ? (info.bcTextures ? "native" : "via ASTC") : "unknown",
			info.gpuKnown ? (info.astcHdr ? "yes" : "no") : "unknown",
			info.gpuKnown ? (info.meshShaders ? "yes" : "no") : "unknown",
			ScreenClassName(info.screen), info.screenLongPoints, info.screenShortPoints, info.screenScale);
		return std::string(buf);
	}
}
