#include "Cafe/OS/libs/gx2/GX2.h"
#include "Cafe/HW/Latte/Core/Latte.h"
#include "Cafe/OS/libs/coreinit/coreinit_Alarm.h"
#include "Cafe/OS/libs/coreinit/coreinit_Thread.h"
#include "Cafe/HW/Latte/Core/LattePerformanceMonitor.h"

#include "Cafe/HW/Espresso/Recompiler/PPCRecompiler.h"
#include "Cafe/CafeSystem.h"

uint32 ppcThreadQuantum = 45000; // execute 45000 instructions before thread reschedule happens, this value can be overwritten by game profiles

// Guest CPU liveness counters. See PPCGuestLiveness in PPCState.h for what the three of
// them mean when read together, and why nothing else in the emulator answers the question
// they answer.
//
// Relaxed ordering throughout: these are read by a reporting thread that only cares
// whether a number is larger than it was three seconds ago. Ordering them against other
// memory would put a barrier on the scheduler's hot path to protect a log line.
static std::atomic<uint64> s_ppcCyclesRetired{0};
static std::atomic<uint64> s_ppcTimeslices{0};
static std::atomic<uint64> s_ppcCoreIdleSpins{0};

// Written on thread load/store, read by the reporting thread while the core is running,
// so the instruction pointer it publishes is deliberately a live racing read of a
// naturally-aligned uint32. That race is the point: a value that keeps changing means the
// core is executing, and a value frozen across several reports names the address it is
// stuck on. Taking a lock to read it would serialise the scheduler against a diagnostic.
static std::atomic<PPCInterpreter_t*> s_ppcCoreInstance[3] = {};

void PPCCore_noteRetiredCycles(uint64 cycles)
{
	s_ppcCyclesRetired.fetch_add(cycles, std::memory_order_relaxed);
	s_ppcTimeslices.fetch_add(1, std::memory_order_relaxed);
}

void PPCCore_noteCoreIdleSpin()
{
	s_ppcCoreIdleSpins.fetch_add(1, std::memory_order_relaxed);
}

void PPCCore_setCoreInstance(uint32 coreIndex, PPCInterpreter_t* hCPU)
{
	if (coreIndex >= 3)
		return;
	s_ppcCoreInstance[coreIndex].store(hCPU, std::memory_order_relaxed);
}

void PPCCore_getLiveness(PPCGuestLiveness& out)
{
	out.cyclesRetired = s_ppcCyclesRetired.load(std::memory_order_relaxed);
	out.timeslices = s_ppcTimeslices.load(std::memory_order_relaxed);
	out.coreIdleSpins = s_ppcCoreIdleSpins.load(std::memory_order_relaxed);
	for (uint32 i = 0; i < 3; i++)
	{
		PPCInterpreter_t* hCPU = s_ppcCoreInstance[i].load(std::memory_order_relaxed);
		out.coreInstructionPointer[i] = hCPU ? hCPU->instructionPointer : 0;
	}
}

void PPCInterpreter_relinquishTimeslice()
{
	PPCInterpreter_t* hCPU = PPCInterpreter_getCurrentInstance();
	if( hCPU->remainingCycles >= 0 )
	{
		hCPU->skippedCycles = hCPU->remainingCycles + 1;
		hCPU->remainingCycles = -1;
	}
}

void PPCCore_boostQuantum(sint32 numCycles)
{
	PPCInterpreter_t* hCPU = PPCInterpreter_getCurrentInstance();
	hCPU->remainingCycles += numCycles;
}

void PPCCore_deboostQuantum(sint32 numCycles)
{
	PPCInterpreter_t* hCPU = PPCInterpreter_getCurrentInstance();
	hCPU->remainingCycles -= numCycles;
}

namespace coreinit
{
	void __OSThreadSwitchToNext();
}

void PPCCore_switchToScheduler()
{
	cemu_assert_debug(__OSHasSchedulerLock() == false); // scheduler lock must not be hold past thread time slice
	cemu_assert_debug(PPCInterpreter_getCurrentInstance()->coreInterruptMask != 0 || CafeSystem::GetForegroundTitleId() == 0x000500001019e600);
	__OSLockScheduler();
	coreinit::__OSThreadSwitchToNext();
	__OSUnlockScheduler();
}

void PPCCore_switchToSchedulerWithLock()
{
	cemu_assert_debug(__OSHasSchedulerLock() == true); // scheduler lock must be hold
	cemu_assert_debug(PPCInterpreter_getCurrentInstance()->coreInterruptMask != 0 || CafeSystem::GetForegroundTitleId() == 0x000500001019e600);
	coreinit::__OSThreadSwitchToNext();
}

void _PPCCore_callbackExit(PPCInterpreter_t* hCPU)
{
	PPCInterpreter_relinquishTimeslice();
	hCPU->instructionPointer = 0;
}

PPCInterpreter_t* PPCCore_executeCallbackInternal(uint32 functionMPTR)
{
	cemu_assert_debug(functionMPTR != 0);
	PPCInterpreter_t* hCPU = PPCInterpreter_getCurrentInstance();
	// remember LR and instruction pointer
	uint32 lr = hCPU->spr.LR;
	uint32 ip = hCPU->instructionPointer;
	// save area
	hCPU->gpr[1] -= 16 * 4;
	// set LR
	hCPU->spr.LR = PPCInterpreter_makeCallableExportDepr(_PPCCore_callbackExit);
	// set instruction pointer
	hCPU->instructionPointer = functionMPTR;
	// execute code until we return from the function
	while (true)
	{
		hCPU->remainingCycles = ppcThreadQuantum;
		hCPU->skippedCycles = 0;
		if (hCPU->remainingCycles > 0)
		{
			// try to enter recompiler immediately
			PPCRecompiler_attemptEnter(hCPU, hCPU->instructionPointer);
			// execute any remaining instructions in interpreter
			while ((--hCPU->remainingCycles) >= 0)
			{
				PPCInterpreterSlim_executeInstruction(hCPU);
			};
		}
		if (hCPU->instructionPointer == 0)
		{
			// restore remaining cycles
			hCPU->remainingCycles += hCPU->skippedCycles;
			hCPU->skippedCycles = 0;
			break;
		}
		coreinit::OSYieldThread();
	}
	// save area
	hCPU->gpr[1] += 16 * 4;
	// restore LR and instruction pointer
	hCPU->spr.LR = lr;
	hCPU->instructionPointer = ip;
	return hCPU;
}

void PPCCore_init()
{
}
