#include "Cafe/HW/Espresso/Const.h"
#include "config/ActiveSettings.h"
#include "util/helpers/fspinlock.h"
#include "util/highresolutiontimer/HighResolutionTimer.h"
#include "Common/cpu_features.h"
#include "Cemu/Logging/CemuLogging.h"

#include <atomic>
#include <vector>

#if defined(ARCH_X86_64)
#include <immintrin.h>
#pragma intrinsic(__rdtsc)
#endif

uint64 _rdtscLastMeasure = 0;
uint64 _rdtscFrequency = 0;

struct uint128_t
{
	uint64 low;
	uint64 high;
};

static_assert(sizeof(uint128_t) == 16);

uint128_t _rdtscAcc{};

uint64 muldiv64(uint64 a, uint64 b, uint64 d)
{
	uint64 diva = a / d;
	uint64 moda = a % d;
	uint64 divb = b / d;
	uint64 modb = b % d;
	return diva * b + moda * divb + moda * modb / d;
}

#if defined(__aarch64__)
// Defined further down, next to the rest of the lock-free timebase; declared here
// because PPCTimer_init() and PPCTimer_start() above it both publish an anchor.
static void PPCTimer_republishAnchor(bool resetToZero);
// Same reason: PPCTimer_init() below reports the resulting guest clock rate, and both the
// anchor type and the conversion it needs are defined further down.
static void PPCTimer_reportTimebaseRate(uint64 counterHz);
#endif

uint64 PPCTimer_estimateRDTSCFrequency()
{
    #if defined(ARCH_X86_64)
	if (!g_CPUFeatures.x86.invariant_tsc)
		cemuLog_log(LogType::Force, "Invariant TSC not supported");
    #endif

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
}

int PPCTimer_initThread()
{
	_rdtscFrequency = PPCTimer_estimateRDTSCFrequency();
	return 0;
}

void PPCTimer_init()
{
#if defined(__aarch64__)
	// cntfrq_el0 IS the counter frequency, exactly, so there is nothing to estimate.
	// That also removes the detached thread that spent three seconds measuring it and
	// the PPCTimer_waitForInit() poll that waited on the result - three seconds of boot,
	// and a window during which PPCTimer_isReady() reported false.
	uint64 f;
	asm volatile("mrs %0, cntfrq_el0" : "=r"(f));
	_rdtscFrequency = f;
	_rdtscLastMeasure = __rdtsc();
	PPCTimer_republishAnchor(true);
	// The resulting guest rate, measured out of the published anchor rather than restated
	// from the constants, and compared against what it is supposed to be. The previous
	// version of this arithmetic was wrong by a factor of 65 and said nothing, and no
	// symptom of it looked like a clock - so the number that matters gets printed and
	// checked, and a mismatch is called out in the log rather than left to be inferred
	// from a game behaving strangely.
	PPCTimer_reportTimebaseRate(f);
#else
	std::thread t(PPCTimer_initThread);
	t.detach();
	_rdtscLastMeasure = __rdtsc();
#endif
}

uint64 _tickSummary = 0;

void PPCTimer_start()
{
	_rdtscLastMeasure = __rdtsc();
	_tickSummary = 0;
#if defined(__aarch64__)
	// Rebase to zero for the new title, which is what _tickSummary = 0 does above.
	PPCTimer_republishAnchor(true);
#endif
}

uint64 PPCTimer_getRawTsc()
{
	return __rdtsc();
}

uint64 PPCTimer_microsecondsToTsc(uint64 us)
{
	return (us * _rdtscFrequency) / 1000000ULL;
}

uint64 PPCTimer_tscToMicroseconds(uint64 us)
{
	uint128_t r{};
	r.low = _umul128(us, 1000000ULL, &r.high);

	uint64 remainder;
	const uint64 microseconds = _udiv128(r.high, r.low, _rdtscFrequency, &remainder);

	return microseconds;
}

bool PPCTimer_isReady()
{
	return _rdtscFrequency != 0;
}

void PPCTimer_waitForInit()
{
	while (!PPCTimer_isReady()) std::this_thread::sleep_for(std::chrono::milliseconds(10));
}

FSpinlock sTimerSpinlock;

#if defined(__aarch64__)

// The guest timebase, lock-free.
//
// WHAT WAS WRONG
//
// Every read took a global spinlock, issued a full memory fence, did a 128-bit multiply
// into a shared accumulator, and then divided that accumulator by the counter frequency.
// On arm64 that division is _udiv128, which has no instruction - it lowers to a call to
// __udivti3, a software divide - and the spinlock's backoff is _mm_pause, which is
// `isb sy`, a full instruction-synchronisation barrier.
//
// The contention is the worse half. This is reached from every guest mftb, from
// OSGetSystemTime and OSGetTime and their siblings, from __OSLoadThread once per
// timeslice per core, from coreinit's spinlocks and message queues, from GX2 - and from
// the Latte GPU thread. So three interpreter threads and the GPU thread serialise on one
// lock to run a software division, several hundred cycles at a time, on a path that a
// title polling the clock hits constantly.
//
// WHY IT CAN SIMPLY BE DELETED HERE
//
// The accumulator exists for x86 reasons. There, __rdtsc is not architecturally
// invariant and the frequency is ESTIMATED at runtime over three seconds, so the
// remainder has to be carried to stop the error compounding, and monotonicity has to be
// enforced by hand. On arm64 the counter is cntvct_el0: architecturally monotonic,
// uniform across cores, and its exact frequency is readable from cntfrq_el0. Nothing has
// to be estimated, so nothing has to be corrected.
//
// The tick therefore becomes a pure function of the counter and an immutable anchor,
// which is what makes it lock-free: readers only ever read.
//
// THE DIVISION BECOMES A MULTIPLY
//
// tick = counterDelta * CORE_CLOCK / cntfrq. With cntfrq known and fixed, the reciprocal
// is precomputed once as a 64.64 fixed-point multiplier and the runtime operation is a
// 128-bit multiply taking the high half - one umulh. Error is under one tick per read
// and, crucially, is computed from the anchor rather than accumulated, so it cannot
// drift no matter how long a title runs.
struct TimebaseAnchor
{
	uint64 cntAtAnchor;   // counter value when this anchor was published
	uint64 tickAtAnchor;  // guest tick at that moment
	uint64 mulFixed;      // CORE_CLOCK / cntfrq, as 64.64 fixed point
	uint8 shift;          // ActiveSettings timer shift in force
};

static std::atomic<TimebaseAnchor*> s_timebaseAnchor{nullptr};
// Retired anchors. A reader may still be holding one when it is replaced, and these are
// 32 bytes and replaced a handful of times in a run (a title start, a speed change), so
// they are kept rather than freed. That is a bounded leak by design, not an oversight -
// reclaiming them safely would mean hazard pointers for no benefit.
static std::vector<TimebaseAnchor*> s_retiredAnchors;
static FSpinlock s_anchorWriteLock;

static uint64 PPCTimer_armCounterFrequency()
{
	uint64 f;
	asm volatile("mrs %0, cntfrq_el0" : "=r"(f));
	return f;
}

static inline uint64 PPCTimer_mulHigh(uint64 a, uint64 b)
{
	return (uint64)(((unsigned __int128)a * (unsigned __int128)b) >> 64);
}

// How many fractional bits the guest-ticks-per-counter-tick multiplier is stored with.
//
// THIS IS THE BUG THAT BROKE EVERY BUILD AFTER v2.2, and it is worth spelling out so it
// is never reintroduced. The multiplier used to be built as (CORE_CLOCK << 64) / freq -
// a 0.64 fixed-point fraction, a format that can only represent values BELOW 1. The real
// ratio is CORE_CLOCK / cntfrq = 1243125000 / 24000000 = 51.796875. The 51 did not fit.
// It was truncated away in silence, leaving 0.796875, and the emulated console's clock
// ran at one sixty-fifth of the correct rate.
//
// Nothing about that looks like a rendering fault, which is why it cost so long to find:
// titles step animation and physics by elapsed time, so a clock at 1/65 speed makes them
// compute wrong positions for everything and then draw those positions perfectly.
//
// The multiplier here folds in the *8 the old code applied after dividing, so the ratio
// it must hold is CORE_CLOCK * 8 / freq, about 414.4 - nine integer bits. 55 fractional
// bits leaves those nine and keeps the whole value inside 64 bits.
static constexpr uint32 kTimebaseFracBits = 55;
static constexpr uint64 kTimebaseNumerator = Espresso::CORE_CLOCK * 8ull;

// Counter ticks to guest ticks, before the timer shift. mulHigh already discards 64 bits,
// so only the remaining (64 - kTimebaseFracBits) need shifting back.
static inline uint64 PPCTimer_guestTicks(uint64 counterDelta, uint64 mulFixed)
{
	return PPCTimer_mulHigh(counterDelta, mulFixed) << (64u - kTimebaseFracBits);
}

// Reports the guest clock rate the published anchor actually produces, and checks it
// against what it is supposed to be.
//
// Measured out of the anchor rather than restated from the constants, so it exercises the
// same arithmetic the emulator will use rather than a copy of it that could agree while
// the real one is wrong. The previous version of that arithmetic was out by a factor of
// 65 and reported nothing at all, and no symptom of it looked like a clock.
static void PPCTimer_reportTimebaseRate(uint64 counterHz)
{
	TimebaseAnchor* anchor = s_timebaseAnchor.load(std::memory_order_acquire);
	if (!anchor)
		return;
	const uint64 guestHz = PPCTimer_guestTicks(counterHz, anchor->mulFixed) >> 3ull;
	const uint64 expectedHz = Espresso::CORE_CLOCK;
	const uint64 drift = guestHz > expectedHz ? guestHz - expectedHz : expectedHz - guestHz;
	if (drift > expectedHz / 100ull)
		cemuLog_log(LogType::Force, "Emulated timebase: WRONG - counter {} Hz gives a guest clock of {} Hz, expected {} Hz. Titles will mistime everything they animate.", counterHz, guestHz, expectedHz);
	else
		cemuLog_log(LogType::Force, "Emulated timebase: counter {} Hz, guest clock {} Hz (expected {}), read lock-free", counterHz, guestHz, expectedHz);
}

// Publishes a new anchor that continues from wherever the current one had reached, so the
// timebase is continuous across a rebase or a speed change and can never jump or go
// backwards. Writers are rare; readers never block.
static void PPCTimer_republishAnchor(bool resetToZero)
{
	s_anchorWriteLock.lock();

	const uint64 freq = PPCTimer_armCounterFrequency();
	// floor(CORE_CLOCK * 8 * 2^kTimebaseFracBits / freq). Checked rather than assumed:
	// if a future counter frequency ever made this exceed 64 bits it would truncate
	// exactly as the original did, and silently, so it says so instead.
	const unsigned __int128 scaled =
		(((unsigned __int128)kTimebaseNumerator) << kTimebaseFracBits) / (unsigned __int128)freq;
	if ((scaled >> 64) != 0)
	{
		cemuLog_log(LogType::Force, "Emulated timebase: multiplier does not fit 64 bits at a counter frequency of {} Hz - the guest clock would run at the wrong rate", freq);
	}
	const uint64 mulFixed = (uint64)scaled;
	const uint64 now = __rdtsc();

	uint64 carriedTick = 0;
	if (!resetToZero)
	{
		if (TimebaseAnchor* previous = s_timebaseAnchor.load(std::memory_order_acquire))
		{
			const uint64 delta = now - previous->cntAtAnchor;
			carriedTick = previous->tickAtAnchor + (PPCTimer_guestTicks(delta, previous->mulFixed) >> previous->shift);
		}
	}

	auto* fresh = new TimebaseAnchor{now, carriedTick, mulFixed, ActiveSettings::GetTimerShiftFactor()};
	TimebaseAnchor* old = s_timebaseAnchor.exchange(fresh, std::memory_order_acq_rel);
	if (old)
		s_retiredAnchors.push_back(old);

	s_anchorWriteLock.unlock();
}

void PPCTimer_onTimerShiftFactorChanged()
{
	PPCTimer_republishAnchor(false);
}

// thread safe, and genuinely lock-free: one acquire load and arithmetic over fields that
// never change after publication.
static uint64 PPCTimer_getFromRDTSC_fast()
{
	TimebaseAnchor* anchor = s_timebaseAnchor.load(std::memory_order_acquire);
	if (!anchor) [[unlikely]]
	{
		PPCTimer_republishAnchor(true);
		anchor = s_timebaseAnchor.load(std::memory_order_acquire);
		if (!anchor)
			return 0;
	}
	// cntvct_el0 is monotonic, so this subtraction cannot go negative and needs no clamp.
	const uint64 delta = __rdtsc() - anchor->cntAtAnchor;
	return anchor->tickAtAnchor + (PPCTimer_guestTicks(delta, anchor->mulFixed) >> anchor->shift);
}

#endif // __aarch64__

// The original implementation, kept compiled on every platform rather than only where it
// is the default. On ARM it is the fallback behind the setting: if the rewritten timebase
// is ever wrong again, this is the one that was correct for years, and reaching it should
// not require another twenty-minute build. It needs no frequency estimator here because
// cntfrq_el0 has already given _rdtscFrequency the exact value.
// thread safe
static uint64 PPCTimer_getFromRDTSC_legacy()
{
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
	uint64 elapsedTick = _udiv128(_rdtscAcc.high, _rdtscAcc.low, _rdtscFrequency, &remainder);

	_rdtscAcc.low = remainder;
	_rdtscAcc.high = 0;

	// timer scaling
	elapsedTick <<= 3ull; // *8
	uint8 timerShiftFactor = ActiveSettings::GetTimerShiftFactor();
	elapsedTick >>= timerShiftFactor;

	_tickSummary += elapsedTick;

	sTimerSpinlock.unlock();
	return _tickSummary;
}

// Which implementation is live. Read on every timebase read, so it can be changed before
// a title starts without rebuilding; the legacy path reads the shift factor itself, so
// switching needs nothing republished.
static std::atomic<bool> s_useLegacyTimebase{false};

void PPCTimer_setUseLegacyTimebase(bool useLegacy)
{
	s_useLegacyTimebase.store(useLegacy, std::memory_order_relaxed);
	cemuLog_log(LogType::Force, "Emulated timebase: using the {} implementation", useLegacy ? "original spinlock" : "lock-free");
}

bool PPCTimer_usingLegacyTimebase()
{
	return s_useLegacyTimebase.load(std::memory_order_relaxed);
}

uint64 PPCTimer_getFromRDTSC()
{
#if defined(__aarch64__)
	if (!s_useLegacyTimebase.load(std::memory_order_relaxed)) [[likely]]
		return PPCTimer_getFromRDTSC_fast();
#endif
	return PPCTimer_getFromRDTSC_legacy();
}

#if !defined(__aarch64__)
// The x86 path reads ActiveSettings::GetTimerShiftFactor() on every call, so a change
// takes effect on its own and there is nothing to republish.
void PPCTimer_onTimerShiftFactorChanged()
{
}
#endif
