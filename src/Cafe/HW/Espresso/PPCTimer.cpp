#include "Cafe/HW/Espresso/Const.h"
#include "config/ActiveSettings.h"
#include "util/helpers/fspinlock.h"
#include "util/highresolutiontimer/HighResolutionTimer.h"
#include "Common/cpu_features.h"

#if defined(ARCH_X86_64)
#include <immintrin.h>
#pragma intrinsic(__rdtsc)
#endif

uint64 _rdtscLastMeasure = 0;
std::atomic<uint64> _rdtscFrequency = 0;

struct uint128_t
{
	uint64 low;
	uint64 high;
};

static_assert(sizeof(uint128_t) == 16);

uint128_t _rdtscAcc{};

uint64 muldiv64(uint64 a, uint64 b, uint64 d);

#if defined(__aarch64__)
// The emulated clock is baseSummary + scale(raw - baseRaw, shift). The three base values are replaced together when the
// timebase speed changes, and readers on other cores must never combine the old set with the new one: the new summary
// with the old raw base counts the whole run a second time, so the guest clock jumps forward by however long the game
// has been running and then back again on the next read. s_armTimerBaseSeq is a sequence lock around the set: odd
// while a writer is replacing it, bumped again when done. Writers also hold sArmTimerRebaseLock.
std::atomic<uint32> s_armTimerBaseSeq = 0;
std::atomic<uint64> s_armTimerBaseRaw = 0;
std::atomic<uint64> s_armTimerBaseSummary = 0;
std::atomic<uint32> s_armTimerBaseShift = 3;
FSpinlock sArmTimerRebaseLock;

static FORCE_INLINE uint64 PPCTimer_readArmCounterFrequency()
{
	uint64 freq = 0;
	asm volatile("mrs %0, cntfrq_el0" : "=r" (freq));
	return freq;
}

static FORCE_INLINE uint64 PPCTimer_scaleArmCounterDelta(uint64 rawDelta, uint8 shiftFactor, uint64 counterFrequency)
{
	uint64 elapsedTick = muldiv64(rawDelta, Espresso::CORE_CLOCK, counterFrequency);
    
	elapsedTick <<= 3ULL;
	elapsedTick >>= shiftFactor;
	return elapsedTick;
}

static FORCE_INLINE uint64 PPCTimer_getArmSummary(uint64 rawCounter, uint64 baseRawCounter, uint64 baseSummary, uint8 shiftFactor, uint64 counterFrequency)
{
	uint64 rawDelta = rawCounter - baseRawCounter;
	rawDelta = rawDelta & ~(uint64)((sint64)rawDelta >> 63);
    
	return baseSummary + PPCTimer_scaleArmCounterDelta(rawDelta, shiftFactor, counterFrequency);
}

// caller holds sArmTimerRebaseLock
static void PPCTimer_publishArmBase(uint64 rawCounter, uint64 summary, uint8 shiftFactor)
{
    const uint32 seq = s_armTimerBaseSeq.load(std::memory_order_relaxed);
    s_armTimerBaseSeq.store(seq + 1, std::memory_order_relaxed);
    std::atomic_thread_fence(std::memory_order_release);
    s_armTimerBaseRaw.store(rawCounter, std::memory_order_relaxed);
    s_armTimerBaseSummary.store(summary, std::memory_order_relaxed);
    s_armTimerBaseShift.store(shiftFactor, std::memory_order_relaxed);
    s_armTimerBaseSeq.store(seq + 2, std::memory_order_release);
}

// reads one consistent set of base values (see s_armTimerBaseSeq)
static FORCE_INLINE void PPCTimer_readArmBase(uint64& baseRawCounter, uint64& baseSummary, uint8& shiftFactor)
{
    for (;;)
    {
        const uint32 seq = s_armTimerBaseSeq.load(std::memory_order_acquire);
        if (seq & 1) [[unlikely]]
        {
            _mm_pause();
            continue;
        }
        baseRawCounter = s_armTimerBaseRaw.load(std::memory_order_relaxed);
        baseSummary = s_armTimerBaseSummary.load(std::memory_order_relaxed);
        shiftFactor = (uint8)s_armTimerBaseShift.load(std::memory_order_relaxed);
        std::atomic_thread_fence(std::memory_order_acquire);
        if (s_armTimerBaseSeq.load(std::memory_order_relaxed) == seq) [[likely]]
            return;
    }
}

static void PPCTimer_resetArmBase(uint64 rawCounter)
{
    sArmTimerRebaseLock.lock();
    PPCTimer_publishArmBase(rawCounter, 0, ActiveSettings::GetTimerShiftFactor());
    sArmTimerRebaseLock.unlock();
}

static void PPCTimer_rebaseArmTimerIfNeeded(uint8 requestedShiftFactor)
{
    if ((uint8)s_armTimerBaseShift.load(std::memory_order_relaxed) == requestedShiftFactor)
        return;
    
    sArmTimerRebaseLock.lock();
    
    const uint8 currentShiftFactor = ActiveSettings::GetTimerShiftFactor();
    const uint8 baseShiftFactor = (uint8)s_armTimerBaseShift.load(std::memory_order_relaxed);
    if (baseShiftFactor != currentShiftFactor)
    {
        // Read the counter under the lock: a value read before it could be older than a base another thread just
        // published, which would move the base backwards and count that stretch twice.
        const uint64 rawCounter = __rdtsc();
        const uint64 counterFrequency = _rdtscFrequency.load(std::memory_order_relaxed);
        const uint64 baseRawCounter = s_armTimerBaseRaw.load(std::memory_order_relaxed);
        const uint64 baseSummary = s_armTimerBaseSummary.load(std::memory_order_relaxed);
        const uint64 rebasedSummary = PPCTimer_getArmSummary(rawCounter, baseRawCounter, baseSummary, baseShiftFactor, counterFrequency);
        
        PPCTimer_publishArmBase(rawCounter, rebasedSummary, currentShiftFactor);
    }
    
    sArmTimerRebaseLock.unlock();
}
#endif

uint64 muldiv64(uint64 a, uint64 b, uint64 d)
{
	uint64 diva = a / d;
	uint64 moda = a % d;
	uint64 divb = b / d;
	uint64 modb = b % d;
	return diva * b + moda * divb + moda * modb / d;
}

uint64 PPCTimer_estimateRDTSCFrequency()
{
#if defined(__aarch64__)
	return PPCTimer_readArmCounterFrequency();
#else
	if (!g_CPUFeatures.x86.invariant_tsc)
		cemuLog_log(LogType::Force, "Invariant TSC not supported");

	_mm_mfence();
	uint64 tscStart = __rdtsc();
	unsigned int startTime = GetTickCount();
	HRTick startTick = HighResolutionTimer::now().getTick();
	// wait roughly 3 seconds
	while (true)
	{
		if ((GetTickCount() - startTime) >= 3000)
			break;
		std::this_thread::sleep_for(std::chrono::milliseconds(10));
	}
	_mm_mfence();
	HRTick stopTick = HighResolutionTimer::now().getTick();
	uint64 tscEnd = __rdtsc();
	// derive frequency approximation from measured time difference
	uint64 tsc_diff = tscEnd - tscStart;
	uint64 hrtFreq = 0;
	uint64 hrtDiff = HighResolutionTimer::getTimeDiffEx(startTick, stopTick, hrtFreq);
	uint64 tsc_freq = muldiv64(tsc_diff, hrtFreq, hrtDiff);

	// uint64 freqMultiplier = tsc_freq / hrtFreq;
	//cemuLog_log(LogType::Force, "RDTSC measurement test:");
	//cemuLog_log(LogType::Force, "TSC-diff:   0x{:016x}", tsc_diff);
	//cemuLog_log(LogType::Force, "TSC-freq:   0x{:016x}", tsc_freq);
	//cemuLog_log(LogType::Force, "HPC-diff:   0x{:016x}", qpc_diff);
	//cemuLog_log(LogType::Force, "HPC-freq:   0x{:016x}", (uint64)qpc_freq.QuadPart);
	//cemuLog_log(LogType::Force, "Multiplier: 0x{:016x}", freqMultiplier);

	return tsc_freq;
#endif
}

int PPCTimer_initThread()
{
	_rdtscFrequency.store(PPCTimer_estimateRDTSCFrequency(), std::memory_order_release);
	return 0;
}

void PPCTimer_init()
{
#if defined(__aarch64__)
	const uint64 rawCounter = __rdtsc();
    
	_rdtscFrequency.store(PPCTimer_estimateRDTSCFrequency(), std::memory_order_release);
	_rdtscLastMeasure = rawCounter;
    
	PPCTimer_resetArmBase(rawCounter);
#else
	std::thread t(PPCTimer_initThread);
	t.detach();
	_rdtscLastMeasure = __rdtsc();
#endif
}

uint64 _tickSummary = 0;

void PPCTimer_start()
{
	const uint64 rawCounter = __rdtsc();
	_rdtscLastMeasure = rawCounter;
	_tickSummary = 0;
#if defined(__aarch64__)
	PPCTimer_resetArmBase(rawCounter);
#endif
}

uint64 PPCTimer_getRawTsc()
{
	return __rdtsc();
}

uint64 PPCTimer_microsecondsToTsc(uint64 us)
{
	return (us * _rdtscFrequency.load(std::memory_order_relaxed)) / 1000000ULL;
}

uint64 PPCTimer_tscToMicroseconds(uint64 us)
{
	uint128_t r{};
	r.low = _umul128(us, 1000000ULL, &r.high);

	uint64 remainder;
	const uint64 microseconds = _udiv128(r.high, r.low, _rdtscFrequency.load(std::memory_order_relaxed), &remainder);

	return microseconds;
}

bool PPCTimer_isReady()
{
	return _rdtscFrequency.load(std::memory_order_acquire) != 0;
}

void PPCTimer_waitForInit()
{
	while (!PPCTimer_isReady()) std::this_thread::sleep_for(std::chrono::milliseconds(10));
}

FSpinlock sTimerSpinlock;

// thread safe
uint64 PPCTimer_getFromRDTSC()
{
#if defined(__aarch64__)
	const uint64 counterFrequency = _rdtscFrequency.load(std::memory_order_acquire);
	cemu_assert_debug(counterFrequency != 0);
    
	PPCTimer_rebaseArmTimerIfNeeded(ActiveSettings::GetTimerShiftFactor());
    
	uint64 baseRawCounter, baseSummary;
	uint8 shiftFactor;
	PPCTimer_readArmBase(baseRawCounter, baseSummary, shiftFactor);
	// read after the base: a counter value older than the base clamps to a zero delta in PPCTimer_getArmSummary
	const uint64 rawCounter = __rdtsc();
    
	return PPCTimer_getArmSummary(rawCounter, baseRawCounter, baseSummary, shiftFactor, counterFrequency);
#else
	sTimerSpinlock.lock();
	_mm_mfence();
	uint64 rdtscCurrentMeasure = __rdtsc();
	uint64 rdtscDif = rdtscCurrentMeasure - _rdtscLastMeasure;
	// optimized max(rdtscDif, 0) without conditionals
	rdtscDif = rdtscDif & ~(uint64)((sint64)rdtscDif >> 63);

	uint128_t diff{};
	diff.low = _umul128(rdtscDif, Espresso::CORE_CLOCK, &diff.high);

	if(rdtscCurrentMeasure > _rdtscLastMeasure)
		_rdtscLastMeasure = rdtscCurrentMeasure; // only travel forward in time

	uint8 c = 0;
	#if BOOST_OS_WINDOWS
	c = _addcarry_u64(c, _rdtscAcc.low, diff.low, &_rdtscAcc.low);
	_addcarry_u64(c, _rdtscAcc.high, diff.high, &_rdtscAcc.high);
	#else
	// requires casting because of long / long long nonesense
	c = _addcarry_u64(c, _rdtscAcc.low, diff.low, (unsigned long long*)&_rdtscAcc.low);
	_addcarry_u64(c, _rdtscAcc.high, diff.high, (unsigned long long*)&_rdtscAcc.high);
	#endif

	uint64 remainder;
	uint64 elapsedTick = _udiv128(_rdtscAcc.high, _rdtscAcc.low, _rdtscFrequency.load(std::memory_order_relaxed), &remainder);

	_rdtscAcc.low = remainder;
	_rdtscAcc.high = 0;

	// timer scaling
	elapsedTick <<= 3ull; // *8
	uint8 timerShiftFactor = ActiveSettings::GetTimerShiftFactor();
	elapsedTick >>= timerShiftFactor;

	_tickSummary += elapsedTick;

	sTimerSpinlock.unlock();
	return _tickSummary;
#endif
}
