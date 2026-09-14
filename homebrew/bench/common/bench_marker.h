// bench_marker.h - the MUFFINBENCH marker protocol shared by cpubench.rpx and
// gpubench.rpx.
//
// The host app does not trust any clock read inside the guest for results.
// An emulator is free to scale guest time arbitrarily (a slow interpreter and
// a fast recompiler can both report "10000 PPC cycles elapsed" to the guest
// OS while taking wildly different amounts of real wall-clock time), so a
// guest-side OSGetTime() delta would measure the emulator's cycle-to-time
// model instead of its actual speed. Instead the host tails each engine's
// OSReport log and times the gap between these lines with its own clock:
//
//   MUFFINBENCH BEGIN <test> <iterations>
//   MUFFINBENCH END <test> <checksum>
//   MUFFINBENCH DONE
//
// BEGIN must be the last thing printed before the timed work starts and END
// the first thing printed the instant it ends - nothing else may be printed
// (or otherwise done) inside that window, because every OSReport call is
// itself an HLE round-trip that costs real time under an interpreter and
// would inflate the measurement it is supposed to be outside of.
//
// The checksum is not a benchmark result. It is a correctness gate: every
// engine runs the identical PPC binary against identical inputs, so all three
// must produce the same checksum for a given test. If one doesn't, that
// engine has an emulation bug (wrong FPU rounding, a broken shader, whatever)
// and its "speed" for that test is meaningless and must not be counted -
// a wrong answer computed quickly is not a fast correct answer.
//
// DONE marks the end of the fixed test sequence. The process then stays
// alive so the host - not the guest - decides when the run is over.
#pragma once

#include <coreinit/debug.h>
#include <stdint.h>

static inline void MuffinBenchBegin(const char *test, uint32_t iterations)
{
   OSReport("MUFFINBENCH BEGIN %s %u\n", test, iterations);
}

static inline void MuffinBenchEnd(const char *test, uint32_t checksum)
{
   OSReport("MUFFINBENCH END %s %08x\n", test, checksum);
}

static inline void MuffinBenchDone(void)
{
   OSReport("MUFFINBENCH DONE\n");
}
