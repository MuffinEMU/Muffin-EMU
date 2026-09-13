#pragma once
#include "Cafe/HW/MMU/MMU.h"

enum
{
	CPUException_NOTHING,
	CPUException_FPUUNAVAILABLE,
	CPUException_EXTERNAL,
	CPUException_SYSTEMCALL
};

#define PPC_LWARX_RESERVATION_MAX	(4)

union FPR_t
{
	double fpr;
	struct
	{
		double fp0;
		double fp1;
	};
	struct
	{
		uint64 guint; 
	};
	struct
	{
		uint64 fp0int;
		uint64 fp1int;
	};
};

typedef struct  
{
	struct  
	{
		uint32 scr;
		uint32 car;
		//uint32 bcr;
	}sprGlobal;
	uint64 tb;
}PPCInterpreterGlobal_t;

// Field order below is chosen for the cache, and the alignas(64) is what makes that choice
// mean anything. Both engines - interpreter and recompiler - touch this struct on nearly
// every instruction, so it is worth spelling out the reasoning at length.
//
// WHY THE ALIGNMENT COMES FIRST
//
// Every claim of the form "these fields share a cache line" is a claim about offsetof()
// PLUS the alignment of the instance. Until this alignas, the instance had alignment 8.
// The two live instantiations are OSHostThread::ppcInstance - a member sitting behind an
// OSThread_t*, a Fiber and 128 KiB of recompiler stack padding - and the three-element
// cores[] array inside PPCInterpreterLLEContext_t. Neither was forced to begin on a line
// boundary, so which fields shared a line was an accident of the surrounding struct and
// would silently change when an unrelated member of it did. alignas(64) turns the grouping
// below from a coincidence into a property that holds.
//
// It also removes the only real false-sharing hazard between the three emulated cores.
// PPCInterpreterLLEContext_t holds `PPCInterpreter_t cores[3]` back to back. At the old
// size of 1192 bytes - not a multiple of any line size - cores[1] started 1192 bytes in,
// i.e. 40 bytes into a line whose first 24 bytes still belonged to cores[0]. Two cores'
// hottest fields therefore shared a line, and every write by one invalidated it for the
// other. alignas(64) both starts each instance on a line and rounds sizeof() up to a
// multiple of one, which makes that arrangement impossible. The HLE path - the one retail
// titles actually run on - never had this problem: each guest thread gets its own
// OSHostThread allocation and the 128 KiB padding array keeps instances far apart.
//
// 64 rather than 128: the A-series parts this port targets (A9X, A12Z) have a 64-byte L1
// data line. On a 128-byte-line host - an M-series Mac running the desktop build - the
// first two 64-byte groups below pair into one line, and that is the right pairing to get:
// the per-instruction control block together with the first half of the GPR file.
//
// THE GROUPS, ordered by how often the interpreter touches them
//
//   0..63     everything touched by (nearly) every instruction: the instruction pointer,
//             the timeslice counter that the execution loop decrements once per
//             instruction, the condition register, the XER carry/overflow bytes, FPSCR,
//             and the lwarx/stwcx reservation. One line, exactly full. These used to live
//             at offsets 648..703 - at the far end of the FPR file - so an integer-only
//             instruction touched a line 600 bytes away from the one holding its own
//             instruction pointer.
//   64..191   gpr[32]: two lines, exactly, both aligned. gpr used to start at offset 4
//             because instructionPointer came first, so 128 bytes of registers straddled
//             THREE lines and gpr[31] - r31, which compiled PowerPC code uses constantly -
//             sat by itself in a third line it shared with fpr[0..3].
//   192..255  the user-visible SPRs (LR, CTR, XER, UPIR, the eight UGQRs) plus the
//             recompiler's GPR temporaries. One line. LR and CTR are the hottest things
//             here: bl/blr and bdnz.
//   256..767  fpr[32]: eight lines, exactly, line-aligned, so paired-single code walks
//             whole lines instead of straddling.
//   768+      recompiler scratch, then the supervisor-only SPRs that Cafe OS usermode
//             never reads at all.
//
// WHY MOVING FIELDS IS SAFE HERE
//
// Both backends address this struct only through offsetof() - verified across
// BackendX64/*, BackendAArch64.cpp and the IML layer; there is not one hardcoded numeric
// offset and no hand-written assembly that touches it - so generated code cannot
// desynchronise from the interpreter when a field moves. The one way a move here COULD
// break the JIT is by pushing a field out of range of the backend's addressing immediate,
// and BackendAArch64.cpp already static_asserts every offset it emits against the AdrUimm
// range, so that failure is a build error rather than a mis-assembled load. The asserts
// after this struct pin the grouping above, so a later edit that quietly undoes it also
// fails the build instead of just getting slower.
struct alignas(64) PPCInterpreter_t
{
	// ---- bytes 0..63: touched by (nearly) every instruction ----
	uint32 instructionPointer;	// 0
	sint32 remainingCycles;		// 4  - if this value goes below zero, the next thread is scheduled. The execution loop decrements it once per instruction.
	sint32 skippedCycles;		// 8  - number of skipped cycles
	uint32 fpscr;			// 12
	uint8 xer_ca;			// 16 - carry from xer
	uint8 xer_so;			// 17 - STICKY overflow. Copied into CR0, never recomputed.
	uint8 xer_ov;			// 18
	uint8 LSQE;			// 19
	uint8 PSE;			// 20
	bool memoryException;		// 21 - interpreter control
	uint8 reservedPad0[2];		// 22..23 - explicit rather than compiler-inserted, so the line budget above stays readable
	uint8 cr[32];			// 24..55 - 0 -> bit not set, 1 -> bit set (upper 7 bits of each byte must always be zero) (cr0 starts at index 0, cr1 at index 4 ..)
	uint32 reservedMemAddr;		// 56 - LWARX and STWCX
	uint32 reservedMemValue;	// 60
	// ---- bytes 64..191: the general purpose register file, exactly two aligned lines ----
	uint32 gpr[32];
	// ---- bytes 192..255: user-visible SPRs and the recompiler's GPR temporaries ----
	struct
	{
		uint32 LR;
		uint32 CTR;
		uint32 XER;
		uint32 UPIR;
		uint32 UGQR[8];
	}spr;				// 192..239
	uint32 temporaryGPR_reg[4];	// 240..255
	// ---- bytes 256..767: the floating point register file, eight aligned lines ----
	FPR_t fpr[32];
	// ---- cold from here on ----
	// temporary storage for recompiler
	FPR_t temporaryFPR[8];		// 768..895 - BackendAArch64 loads these with ldr q, whose immediate must be a multiple of 16, so this offset is asserted below
	uint32 temporaryGPR[4];		// 896..911 - deprecated, refactor backend dependency on this away
	// core context (starts at 0xFFFFFF00?)
	/* 0xFFFFFFE4 */ uint32 coreInterruptMask;	// 912
	uint32 reservedPad1;		// 916 - keeps the two pointers below 8-byte aligned without the compiler guessing
	// global CPU values
	PPCInterpreterGlobal_t* global;	// 920
	// extra variables for recompiler
	void* rspTemp;			// 928
	// values below this are not used by Cafe OS usermode
	struct
	{
		uint32 fpecr; // is this the same register as fpscr ?
		uint32 DEC;
		uint32 srr0;
		uint32 srr1;
		uint32 PVR;
		uint32 msr;
		uint32 sprg[4];
		// DSI/ISI
		uint32 dar;
		uint32 dsisr;
		// DMA
		uint32 dmaU;
		uint32 dmaL;
		// MMU
		uint32 dbatU[8];
		uint32 dbatL[8];
		uint32 ibatU[8];
		uint32 ibatL[8];
		uint32 sr[16];
		uint32 sdr1;
	}sprExtended;			// 936..1187
};

// The layout contract described above, pinned. These are not decoration: the whole point
// of the ordering is that the hot fields sit in a known, small set of lines, and that is
// exactly the kind of property a later unrelated edit undoes without anyone noticing.
static_assert(alignof(PPCInterpreter_t) == 64, "the cache-line grouping above is only true if the instance itself starts on a line");
static_assert(sizeof(PPCInterpreter_t) % 64 == 0, "a size that is not a whole number of lines lets two instances in an array share one - which is the false sharing between emulated cores this alignment exists to prevent");
static_assert(offsetof(PPCInterpreter_t, instructionPointer) == 0, "");
static_assert(offsetof(PPCInterpreter_t, reservedMemValue) + sizeof(uint32) == 64, "the per-instruction control block must fit in exactly one cache line");
static_assert(offsetof(PPCInterpreter_t, gpr) == 64 && sizeof(PPCInterpreter_t::gpr) == 128, "gpr must cover exactly two aligned cache lines and no third");
static_assert(offsetof(PPCInterpreter_t, fpr) % 64 == 0, "the FPR file should start on a line, not straddle one");
static_assert(offsetof(PPCInterpreter_t, temporaryFPR) % 16 == 0, "BackendAArch64 addresses temporaryFPR with ldr/str q, whose scaled immediate must be a multiple of 16");

// parameter access (legacy C style)

static uint32 PPCInterpreter_getCallParamU32(PPCInterpreter_t* hCPU, uint32 index)
{
	if (index >= 8)
		return memory_readU32(hCPU->gpr[1] + 8 + (index - 8) * 4);
	return hCPU->gpr[3 + index];
}

static uint64 PPCInterpreter_getCallParamU64(PPCInterpreter_t* hCPU, uint32 index)
{
	uint64 v = ((uint64)PPCInterpreter_getCallParamU32(hCPU, index)) << 32ULL;
	v |= ((uint64)PPCInterpreter_getCallParamU32(hCPU, index+1));
	return v;
}

#define ppcGetCallParamU32(__index) PPCInterpreter_getCallParamU32(hCPU, __index)
#define ppcGetCallParamU16(__index) ((uint16)(PPCInterpreter_getCallParamU32(hCPU, __index)&0xFFFF))
#define ppcGetCallParamU8(__index) ((uint8)(PPCInterpreter_getCallParamU32(hCPU, __index)&0xFF))
#define ppcGetCallParamStruct(__index, __type) ((__type*)memory_getPointerFromVirtualOffsetAllowNull(PPCInterpreter_getCallParamU32(hCPU, __index)))

// legacy way of accessing parameters
#define ppcDefineParamU32(__name, __index) uint32 __name = PPCInterpreter_getCallParamU32(hCPU, __index)
#define ppcDefineParamU16(__name, __index) uint16 __name = (uint16)PPCInterpreter_getCallParamU32(hCPU, __index)
#define ppcDefineParamU32BEPtr(__name, __index) uint32be* __name = (uint32be*)((uint8*)memory_getPointerFromVirtualOffsetAllowNull(PPCInterpreter_getCallParamU32(hCPU, __index)))
#define ppcDefineParamS32(__name, __index) sint32 __name = (sint32)PPCInterpreter_getCallParamU32(hCPU, __index)
#define ppcDefineParamU64(__name, __index) uint64 __name = PPCInterpreter_getCallParamU64(hCPU, __index)
#define ppcDefineParamMPTR(__name, __index) MPTR __name = (MPTR)PPCInterpreter_getCallParamU32(hCPU, __index)
#define ppcDefineParamMEMPTR(__name, __type, __index) MEMPTR<__type> __name{PPCInterpreter_getCallParamU32(hCPU, __index)}
#define ppcDefineParamU8(__name, __index) uint8 __name = (PPCInterpreter_getCallParamU32(hCPU, __index)&0xFF)
#define ppcDefineParamStructPtr(__name, __type, __index) __type* __name = ((__type*)memory_getPointerFromVirtualOffsetAllowNull(PPCInterpreter_getCallParamU32(hCPU, __index)))
#define ppcDefineParamTypePtr(__name, __type, __index) __type* __name = ((__type*)memory_getPointerFromVirtualOffsetAllowNull(PPCInterpreter_getCallParamU32(hCPU, __index)))
#define ppcDefineParamPtr(__name, __type, __index) __type* __name = ((__type*)memory_getPointerFromVirtualOffsetAllowNull(PPCInterpreter_getCallParamU32(hCPU, __index)))
#define ppcDefineParamStr(__name, __index) char* __name = ((char*)memory_getPointerFromVirtualOffsetAllowNull(PPCInterpreter_getCallParamU32(hCPU, __index)))
#define ppcDefineParamUStr(__name, __index) uint8* __name = ((uint8*)memory_getPointerFromVirtualOffsetAllowNull(PPCInterpreter_getCallParamU32(hCPU, __index)))
#define ppcDefineParamWStr(__name, __index) wchar_t* __name = ((wchar_t*)memory_getPointerFromVirtualOffsetAllowNull(PPCInterpreter_getCallParamU32(hCPU, __index)))
#define ppcDefineParamWStrBE(__name, __index) uint16be* __name = ((uint16be*)memory_getPointerFromVirtualOffsetAllowNull(PPCInterpreter_getCallParamU32(hCPU, __index)))

// GPR constants

#define GPR_SP 1

// interpreter functions

PPCInterpreter_t* PPCInterpreter_createInstance(unsigned int Entrypoint);
PPCInterpreter_t* PPCInterpreter_getCurrentInstance();
void PPCInterpreter_setCurrentInstance(PPCInterpreter_t* hCPU);

uint64 PPCInterpreter_getMainCoreCycleCounter();

// Defined here rather than in PPCInterpreterMain.cpp, which is what they used to be.
//
// There are ~230 calls to PPCInterpreter_nextInstruction and essentially every interpreter
// handler ends in one - it is reached once per guest instruction executed. Out of line in
// another translation unit, that is a cross-TU function call whose entire body is
// `ip += 4`, and the call, the spill and the return dominate the work by a wide margin.
//
// Whether this was already being folded depends on link-time optimisation, which the
// release build does enable - so on a build where LTO fires this changes nothing, and on
// one where it does not it removes a call per instruction. It costs ten lines either way,
// and the interpreter is the only CPU path available when JIT is unavailable, which is the
// case this port has to be good at.
inline void PPCInterpreter_nextInstruction(PPCInterpreter_t* cpuInterpreter)
{
	cpuInterpreter->instructionPointer += 4;
}

inline void PPCInterpreter_jumpToInstruction(PPCInterpreter_t* cpuInterpreter, uint32 newIP)
{
	cpuInterpreter->instructionPointer = (uint32)newIP;
}

void PPCInterpreterSlim_executeInstruction(PPCInterpreter_t* hCPU);
void PPCInterpreterFull_executeInstruction(PPCInterpreter_t* hCPU);

// misc

uint32 PPCInterpreter_getXER(PPCInterpreter_t* hCPU);
void PPCInterpreter_setXER(PPCInterpreter_t* hCPU, uint32 v);

// Wii U clocks (deprecated. Moved to Espresso/Const.h)
#define ESPRESSO_CORE_CLOCK       1243125000
#define ESPRESSO_BUS_CLOCK        248625000
#define ESPRESSO_TIMER_CLOCK      (ESPRESSO_BUS_CLOCK/4) // 62156250

#define ESPRESSO_CORE_CLOCK_TO_TIMER_CLOCK(__cc) ((__cc)/20ULL)

// interrupt vectors
#define CPU_EXCEPTION_DSI			0x00000300
#define CPU_EXCEPTION_INTERRUPT		0x00000500 // todo: validate
#define CPU_EXCEPTION_FPUUNAVAIL	0x00000800 // todo: validate
#define CPU_EXCEPTION_SYSTEMCALL	0x00000C00 // todo: validate
#define CPU_EXCEPTION_DECREMENTER	0x00000900 // todo: validate

// FPU available check
//#define FPUCheckAvailable() if ((hCPU->msr & MSR_FP) == 0) { IPTException(hCPU, CPU_EXCEPTION_FPUUNAVAIL); return; }
#define FPUCheckAvailable() // since the emulated code always runs in usermode we can assume that MSR_FP is always set

// spr
void PPCSpr_set(PPCInterpreter_t* hCPU, uint32 spr, uint32 newValue);
uint32 PPCSpr_get(PPCInterpreter_t* hCPU, uint32 spr);

uint32 PPCInterpreter_getCoreIndex(PPCInterpreter_t* hCPU);
uint32 PPCInterpreter_getCurrentCoreIndex();

// decrement register
void PPCInterpreter_setDEC(PPCInterpreter_t* hCPU, uint32 newValue);

// timing for main processor
extern uint64 ppcCyclesSince2000; // on init this is set to the cycles that passed since 1.1.2000
extern uint64 ppcCyclesSince2000TimerClock; // on init this is set to the cycles that passed since 1.1.2000 / 20
extern uint64 ppcCyclesSince2000_UTC;
extern uint64 ppcMainThreadDECCycleValue; // value that was set to dec register
extern uint64 ppcMainThreadDECCycleStart; // at which cycle the dec register was set

// PPC timer
void PPCTimer_init();
void PPCTimer_waitForInit();
uint64 PPCTimer_getFromRDTSC();

// Told when the emulated clock rate changes, so the timebase can carry its current value
// into a new anchor instead of jumping. No-op where the timebase is not anchor-based.
//
// Calling it is now an optimisation, not a requirement: it had zero callers in the whole
// tree, which meant every timer-shift change was silently discarded on the anchor-based
// (arm64) path, so PPCTimer_getFromRDTSC_fast() detects a changed shift on the read path
// itself. Calling this makes the change take effect at once instead of on the next timebase
// read, which is the difference between a guest seeing the new rate immediately and seeing
// it a few microseconds later. Nothing breaks if it is never called.
void PPCTimer_onTimerShiftFactorChanged();
// Falls back to the original spinlock timebase. Only meaningful on ARM, where the
// lock-free rewrite is the default; it exists so that a wrong clock can be ruled in or
// out on the device instead of by rebuilding.
void PPCTimer_setUseLegacyTimebase(bool useLegacy);
bool PPCTimer_usingLegacyTimebase();

uint64 PPCTimer_microsecondsToTsc(uint64 us);
uint64 PPCTimer_tscToMicroseconds(uint64 us);
uint64 PPCTimer_getRawTsc();

void PPCTimer_start();

// core info and control
extern uint32 ppcThreadQuantum;

// Guest CPU liveness
//
// Whether the emulated Espresso is retiring instructions at all. Nothing else in the
// emulator reports this, which is why every stalled-boot log from the iOS port has so far
// been unreadable: the GPU-side counters (GX2 frames, OSScreen scanouts, guest flip
// requests) all sit downstream of the guest reaching GX2Init, so before that point they
// read zero whether the guest is grinding along or wedged solid. Those two cases need
// opposite fixes - one is "the interpreter is ~100x slower than a recompiler and needs
// CS_DEBUGGED", the other is a bug in here - and nothing in the log told them apart.
//
// Read the three counters together:
//   cyclesRetired climbing                   -> the guest is alive; a stall before
//                                               GX2Init is speed, not a hang
//   cyclesRetired flat, coreIdleSpins rising -> the scheduler is alive but no guest
//                                               thread is runnable: everything is
//                                               blocked, i.e. a guest-side deadlock
//   both flat                                -> the core threads themselves are not
//                                               running: wedged in host code, or
//                                               OSSchedulerBegin never got as far as
//                                               starting them
//
// cyclesRetired is accumulated per timeslice from __OSStoreThread()'s own executed-cycle
// figure rather than counted per instruction, so it costs one relaxed add per ~45000
// instructions instead of one per instruction. It is therefore a liveness signal, not a
// performance counter: it lands in bursts of a whole quantum, and a core that is
// mid-timeslice has not contributed its current work yet.
struct PPCGuestLiveness
{
	uint64 cyclesRetired;   // guest instructions retired, summed over all cores
	uint64 timeslices;      // completed thread timeslices
	uint64 coreIdleSpins;   // idle-loop iterations, i.e. a core looking for work and finding none
	uint32 coreInstructionPointer[3]; // 0 when that core is not currently running a guest thread
	// Raw counter ticks spent inside the interpreter loop, and instructions executed
	// there, summed over all cores. Unlike cyclesRetired these are measured AT the loop,
	// so instructions/tsc is real interpreter throughput and tsc/wallclock is the
	// fraction of the run that any interpreter optimisation could possibly affect.
	uint64 interpreterTsc;
	uint64 interpreterInstructions;
};

void PPCCore_getLiveness(PPCGuestLiveness& out);
void PPCCore_noteRetiredCycles(uint64 cycles);
void PPCCore_noteCoreIdleSpin();
// Called once per interpreter burst - a whole timeslice's worth of instructions - not
// once per instruction, so it cannot distort what it measures.
void PPCCore_noteInterpreterBurst(uint64 tscElapsed, uint64 instructions);
// Called with the interpreter instance a core is running, and with nullptr when it stops
// running one. The core index is passed explicitly rather than derived from thread-local
// state on purpose: guest threads are fibers and migrate between host threads, so a
// thread_local here would be read on the wrong host thread after a fiber switch - the
// same hazard TLS_WORKAROUND_NOINLINE exists to prevent in PPCInterpreterMain.cpp.
void PPCCore_setCoreInstance(uint32 coreIndex, PPCInterpreter_t* hCPU);

uint8* PPCInterpreter_PushAndReturnStackPointer(sint32 offset);
uint8* PPCInterpreterGetStackPointer();
void PPCInterpreterModifyStackPointer(sint32 offset);

uint32 PPCInterpreter_makeCallableExportDepr(void (*ppcCallableExport)(PPCInterpreter_t* hCPU));

static inline float flushDenormalToZero(float f)
{
	uint32 v = *(uint32*)&f;
	return *(float*)&v;
}

// HLE interface

using HLECALL = void(*)(PPCInterpreter_t*);
using HLEIDX = sint32;

HLEIDX PPCInterpreter_registerHLECall(HLECALL hleCall, std::string hleName);
HLECALL PPCInterpreter_getHLECall(HLEIDX funcIndex);

// HLE scheduler

void PPCInterpreter_relinquishTimeslice();

void PPCCore_boostQuantum(sint32 numCycles);
void PPCCore_deboostQuantum(sint32 numCycles);

void PPCCore_switchToScheduler();
void PPCCore_switchToSchedulerWithLock();

PPCInterpreter_t* PPCCore_executeCallbackInternal(uint32 functionMPTR);
void PPCCore_init();

// LLE scheduler

void PPCCoreLLE_startSingleCoreScheduler(uint32 entrypoint);
