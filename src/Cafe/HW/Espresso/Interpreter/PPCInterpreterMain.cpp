#include "PPCInterpreterInternal.h"
#include "Cafe/OS/RPL/rpl.h"
#include "Cafe/GameProfile/GameProfile.h"
#include "Cafe/HW/Espresso/Debugger/Debugger.h"

thread_local PPCInterpreter_t* ppcInterpreterCurrentInstance;

// main thread instruction counter and timing
uint64 ppcMainThreadDECCycleValue = 0; // value that was set to dec register
uint64 ppcMainThreadDECCycleStart = 0; // at which cycle the dec register was set, if == 0 -> dec is 0
uint64 ppcCyclesSince2000 = 0;
uint64 ppcCyclesSince2000TimerClock = 0;
uint64 ppcCyclesSince2000_UTC = 0;

// Allocates a standalone interpreter instance.
//
// Worth knowing before reading it: nothing in the tree calls this. The two instances that
// actually execute guest code are members of larger objects - OSHostThread::ppcInstance for
// the Cafe OS HLE path that retail titles run on, and PPCInterpreterLLEContext_t::cores[3]
// for the LLE scheduler - and each of those supplies its own prefix area as a plain member
// array (128 KiB, considerably more than the 0x6000 here). This function is kept because it
// is the declared way to make an instance, but it is not on any hot path and has not been
// exercised, so it is fixed rather than trusted.
//
// WHAT THE PREFIX AREA IS FOR: it is an x64-backend requirement, not a general one.
// BackendX64 keeps the hCPU pointer in RSP (REG_RESV_HCPU == X86_REG_RSP), so anything that
// pushes - a call out of recompiled code, the exception handler - writes to memory BELOW the
// struct. The slack in front of it is what stops those writes landing in another
// allocation. The aarch64 backend uses x29 for hCPU and has no such need, but the area is
// allocated unconditionally because the struct layout must not differ between backends.
PPCInterpreter_t* PPCInterpreter_createInstance(unsigned int Entrypoint)
{
	constexpr size_t prefixAreaSize = 0x6000;
	constexpr size_t instanceAlignment = alignof(PPCInterpreter_t);
	// The old body was malloc(...) + prefixAreaSize. That is no longer a correct allocator
	// for this type: PPCInterpreter_t is now alignas(64) (see the layout comment in
	// PPCState.h for why the alignment is load-bearing rather than cosmetic), and malloc
	// only promises 16. An instance starting 16 or 32 bytes into a cache line makes every
	// "these fields share one line" claim in that comment false, and reaching an
	// over-aligned type through an under-aligned pointer is undefined behaviour besides.
	static_assert(prefixAreaSize % instanceAlignment == 0, "offsetting past the prefix area must preserve the instance's alignment, or aligning the base buys nothing");
	// Rounded up so that, if this ever allocates an array, element 1 is still line-aligned -
	// the same property that stops two emulated cores sharing a line in the LLE context.
	const size_t instanceSize = (sizeof(PPCInterpreter_t) + instanceAlignment - 1) & ~(instanceAlignment - 1);
	uint8* baseAllocation;
#if defined(_MSC_VER)
	baseAllocation = (uint8*)_aligned_malloc(prefixAreaSize + instanceSize, instanceAlignment);
#else
	void* alignedAllocation = nullptr;
	if (posix_memalign(&alignedAllocation, instanceAlignment, prefixAreaSize + instanceSize) != 0)
		alignedAllocation = nullptr;
	baseAllocation = (uint8*)alignedAllocation;
#endif
	// Previously a failed malloc was dereferenced immediately. Reporting the failure is the
	// only honest option here, since the caller is the only code that knows whether running
	// without a CPU instance is survivable.
	if (!baseAllocation)
		return nullptr;
	PPCInterpreter_t* pData = (PPCInterpreter_t*)(baseAllocation + prefixAreaSize);
	memset((void*)pData, 0x00, sizeof(PPCInterpreter_t));
	// set instruction pointer to entrypoint
	pData->instructionPointer = (uint32)Entrypoint;
	// set initial register values
	pData->gpr[GPR_SP] = 0x00000000;
	pData->spr.LR = 0;
	// return instance
	return pData;
}

TLS_WORKAROUND_NOINLINE PPCInterpreter_t* PPCInterpreter_getCurrentInstance()
{
	return ppcInterpreterCurrentInstance;
}

TLS_WORKAROUND_NOINLINE void PPCInterpreter_setCurrentInstance(PPCInterpreter_t* hCPU)
{
	ppcInterpreterCurrentInstance = hCPU;
}

uint64 PPCInterpreter_getMainCoreCycleCounter()
{
	return PPCTimer_getFromRDTSC();
}

// PPCInterpreter_nextInstruction and PPCInterpreter_jumpToInstruction are now inline in
// PPCState.h - see the comment there for why.

void PPCInterpreter_setDEC(PPCInterpreter_t* hCPU, uint32 newValue)
{
	hCPU->sprExtended.DEC = newValue;
	ppcMainThreadDECCycleStart = PPCInterpreter_getMainCoreCycleCounter();
	ppcMainThreadDECCycleValue = newValue;
}

uint32 PPCInterpreter_getXER(PPCInterpreter_t* hCPU)
{
	uint32 xerValue = hCPU->spr.XER;
	xerValue &= ~(1 << XER_BIT_CA);
	xerValue &= ~(1 << XER_BIT_SO);
	xerValue &= ~(1 << XER_BIT_OV);
	if (hCPU->xer_ca)
		xerValue |= (1 << XER_BIT_CA);
	if (hCPU->xer_so)
		xerValue |= (1 << XER_BIT_SO);
	if (hCPU->xer_ov)
		xerValue |= (1 << XER_BIT_OV);
	return xerValue;
}

void PPCInterpreter_setXER(PPCInterpreter_t* hCPU, uint32 v)
{
	const uint32 XER_MASK = 0xE0FFFFFF; // some bits are masked out. Figure out which ones exactly
	hCPU->spr.XER = v & XER_MASK;
	hCPU->xer_ca = (v >> XER_BIT_CA) & 1;
	hCPU->xer_so = (v >> XER_BIT_SO) & 1;
	hCPU->xer_ov = (v >> XER_BIT_OV) & 1;
}

uint32 PPCInterpreter_getCoreIndex(PPCInterpreter_t* hCPU)
{
	return hCPU->spr.UPIR;
};

uint32 PPCInterpreter_getCurrentCoreIndex()
{
	return PPCInterpreter_getCurrentInstance()->spr.UPIR;
};

uint8* PPCInterpreterGetStackPointer()
{
	return memory_getPointerFromVirtualOffset(PPCInterpreter_getCurrentInstance()->gpr[1]);
}

uint8* PPCInterpreter_PushAndReturnStackPointer(sint32 offset)
{
	PPCInterpreter_t* hCPU = PPCInterpreter_getCurrentInstance();
	uint8* result = memory_getPointerFromVirtualOffset(hCPU->gpr[1] - offset);
	hCPU->gpr[1] -= offset;
	return result;
}

void PPCInterpreterModifyStackPointer(sint32 offset)
{
	PPCInterpreter_getCurrentInstance()->gpr[1] -= offset;
}

uint32 RPLLoader_MakePPCCallable(void(*ppcCallableExport)(PPCInterpreter_t* hCPU));

// deprecated wrapper, use RPLLoader_MakePPCCallable directly
uint32 PPCInterpreter_makeCallableExportDepr(void (*ppcCallableExport)(PPCInterpreter_t* hCPU))
{
	return RPLLoader_MakePPCCallable(ppcCallableExport);
}
