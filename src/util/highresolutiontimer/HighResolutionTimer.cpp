#include "util/highresolutiontimer/HighResolutionTimer.h"
#include "Common/precompiled.h"

HighResolutionTimer HighResolutionTimer::now()
{
#if BOOST_OS_WINDOWS
	LARGE_INTEGER pc;
	QueryPerformanceCounter(&pc);
	return HighResolutionTimer(pc.QuadPart);
#elif BOOST_OS_LINUX
    timespec pc;
    clock_gettime(CLOCK_MONOTONIC_RAW, &pc);
    uint64 nsec = (uint64)pc.tv_sec * (uint64)1000000000 + (uint64)pc.tv_nsec;
    return HighResolutionTimer(nsec);
#elif BOOST_OS_MACOS || defined(CEMU_PLATFORM_IOS)
	return HighResolutionTimer(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW));
#elif BOOST_OS_BSD
    timespec pc;
    clock_gettime(CLOCK_MONOTONIC, &pc);
    uint64 nsec = (uint64)pc.tv_sec * (uint64)1000000000 + (uint64)pc.tv_nsec;
    return HighResolutionTimer(nsec);
#endif
}

HRTick HighResolutionTimer::getFrequency()
{
	return m_freq;
}

uint64 HighResolutionTimer::m_freq = []() -> uint64 {
#if BOOST_OS_WINDOWS
	LARGE_INTEGER freq;
	QueryPerformanceFrequency(&freq);
	return (uint64)(freq.QuadPart);
#elif BOOST_OS_MACOS || defined(CEMU_PLATFORM_IOS)
	// The CEMU_PLATFORM_IOS term is load-bearing, for the reason documented in
	// CafeSystem.cpp: Boost.Predef zeroes BOOST_OS_MACOS on an iOS target. Without it
	// iOS fell past every branch here into the generic #else, which derives the
	// frequency from clock_getres(CLOCK_MONOTONIC_RAW). On Darwin that reports the
	// mach timebase period - measured 42ns on Apple silicon, not the 1ns Linux
	// reports - so m_freq came out 23809523 while now() above kept returning
	// nanoseconds. Every conversion in the header was then wrong by ~42x, silently
	// and with no diagnostic: LatteTime_CalculateTimeBetweenVSync() asked for a vsync
	// every 0.4ms instead of 16.7ms, and microsecondsToTicks() made the IOSU timer
	// thread fire 42x early. now() is nanoseconds on both Apple platforms, so the
	// frequency is 1e9 on both.
	return 1000000000;
#elif BOOST_OS_BSD
	timespec pc;
	clock_getres(CLOCK_MONOTONIC, &pc);
	return (uint64)1000000000 / (uint64)pc.tv_nsec;
#else
    timespec pc;
    clock_getres(CLOCK_MONOTONIC_RAW, &pc);
    return (uint64)1000000000 / (uint64)pc.tv_nsec;
#endif
}();
