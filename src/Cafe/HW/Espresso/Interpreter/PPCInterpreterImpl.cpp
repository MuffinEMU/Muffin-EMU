#include "PPCInterpreterInternal.h"
#include "PPCInterpreterHelper.h"
#include "Cafe/HW/Espresso/Debugger/Debugger.h"
#include "Cafe/HW/Espresso/Debugger/GDBStub.h"

#include <atomic>
#include <mutex>
#include <type_traits>
#include <unordered_map>

class PPCItpCafeOSUsermode
{
public:
	static const bool allowSupervisorMode = false;
	static const bool allowDSI = false;

	inline static uint32 memory_readCodeU32(PPCInterpreter_t* hCPU, uint32 address)
	{
		return _swapEndianU32(*(uint32*)(memory_base + address));
	}

	inline static void ppcMem_writeDataDouble(PPCInterpreter_t* hCPU, uint32 address, double vf)
	{
		uint64 v = *(uint64*)&vf;
		uint32 v1 = v & 0xFFFFFFFF;
		uint32 v2 = v >> 32;
		uint8* ptr = memory_getPointerFromVirtualOffset(address);
		*(uint32*)(ptr + 4) = CPU_swapEndianU32(v1);
		*(uint32*)(ptr + 0) = CPU_swapEndianU32(v2);
	}

	inline static void ppcMem_writeDataU64(PPCInterpreter_t* hCPU, uint32 address, uint64 v)
	{
		*(uint64*)(memory_getPointerFromVirtualOffset(address)) = CPU_swapEndianU64(v);
	}

	inline static void ppcMem_writeDataU32(PPCInterpreter_t* hCPU, uint32 address, uint32 v)
	{
		*(uint32*)(memory_getPointerFromVirtualOffset(address)) = CPU_swapEndianU32(v);
	}

	inline static void ppcMem_writeDataU16(PPCInterpreter_t* hCPU, uint32 address, uint16 v)
	{
		*(uint16*)(memory_getPointerFromVirtualOffset(address)) = CPU_swapEndianU16(v);
	}

	inline static void ppcMem_writeDataU8(PPCInterpreter_t* hCPU, uint32 address, uint8 v)
	{
		*(uint8*)(memory_getPointerFromVirtualOffset(address)) = v;
	}
	
	inline static double ppcMem_readDataDouble(PPCInterpreter_t* hCPU, uint32 address)
	{
		uint32 v[2];
		v[1] = *(uint32*)(memory_getPointerFromVirtualOffset(address));
		v[0] = *(uint32*)(memory_getPointerFromVirtualOffset(address) + 4);
		v[0] = CPU_swapEndianU32(v[0]);
		v[1] = CPU_swapEndianU32(v[1]);
		return *(double*)v;
	}

	inline static float ppcMem_readDataFloat(PPCInterpreter_t* hCPU, uint32 address)
	{
		uint32 v = *(uint32*)(memory_getPointerFromVirtualOffset(address));
		v = CPU_swapEndianU32(v);
		return *(float*)&v;
	}

	inline static uint64 ppcMem_readDataU64(PPCInterpreter_t* hCPU, uint32 address)
	{
		uint64 v = *(uint64*)(memory_getPointerFromVirtualOffset(address));
		return CPU_swapEndianU64(v);
	}

	inline static uint32 ppcMem_readDataU32(PPCInterpreter_t* hCPU, uint32 address)
	{
		uint32 v = *(uint32*)(memory_getPointerFromVirtualOffset(address));
		return CPU_swapEndianU32(v);
	}

	inline static uint16 ppcMem_readDataU16(PPCInterpreter_t* hCPU, uint32 address)
	{
		uint16 v = *(uint16*)(memory_getPointerFromVirtualOffset(address));
		return CPU_swapEndianU16(v);
	}

	inline static uint8 ppcMem_readDataU8(PPCInterpreter_t* hCPU, uint32 address)
	{
		return *(uint8*)(memory_getPointerFromVirtualOffset(address));
	}

	inline static uint64 ppcMem_readDataFloatEx(PPCInterpreter_t* hCPU, uint32 addr)
	{
		return ConvertToDoubleNoFTZ(_swapEndianU32(*(uint32*)(memory_base + addr)));
	}

	inline static void ppcMem_writeDataFloatEx(PPCInterpreter_t* hCPU, uint32 addr, uint64 value)
	{
		*(uint32*)(memory_base + addr) = _swapEndianU32(ConvertToSingleNoFTZ(value));
	}

	inline static uint64 getTB(PPCInterpreter_t* hCPU)
	{
		return PPCInterpreter_getMainCoreCycleCounter();
	}
};

uint32 debug_lastTranslatedHit;

void generateDSIException(PPCInterpreter_t* hCPU, uint32 dataAddress)
{
	// todo - check if we are already inside an interrupt handler (in which case the DSI exception is queued and not executed immediately?)

	// set flag to cancel current instruction
	hCPU->memoryException = true;

	hCPU->sprExtended.srr0 = hCPU->instructionPointer;
	hCPU->sprExtended.srr1 = hCPU->sprExtended.msr & 0x87C0FFFF;

	hCPU->sprExtended.dar = dataAddress;

	hCPU->sprExtended.msr &= ~0x04EF36;

	hCPU->instructionPointer = 0xFFF00300;


	uint32 dsisr = 0;
	dsisr |= (1<<(31-1)); // set if no TLB/BAT match found

	hCPU->sprExtended.dsisr = dsisr;

}

class PPCItpSupervisorWithMMU
{
public:
	static const bool allowSupervisorMode = true;
	static const bool allowDSI = true;

	inline static uint32 ppcMem_translateVirtualDataToPhysicalAddr(PPCInterpreter_t* hCPU, uint32 vAddr)
	{
		// check if address translation is disabled for data accesses
		if (GET_MSR_BIT(MSR_DR) == 0)
		{
			return vAddr;
		}

#ifdef CEMU_DEBUG_ASSERT
		if (hCPU->memoryException)
			assert_dbg(); // should not be set anymore
#endif

		// how to determine if BAT is valid:
		// BAT_entry_valid = (Vs & ~MSR[PR]) | (Vp & MSR[PR]) (The entry has separate enable flags for usermode and supervisor mode)
		for (sint32 i = 0; i < 8; i++)
		{
			// upper
			uint32 batU = hCPU->sprExtended.dbatU[i];
			uint32 BEPI = ((batU >> 17) & 0x7FFF) << 17;
			uint32 Vp = (batU >> 0) & 1;
			uint32 Vs = (batU >> 1) & 1;
			uint32 BL = (((batU >> 2) & 0x7FF) ^ 0x7FF) << 17;
			BL |= 0xF0000000;
			if (Vs == 0)
				continue; // todo - check if in supervisor/usermode
			// lower
			uint32 batL = hCPU->sprExtended.dbatL[i];
			uint32 PP = (batL >> 0) & 3;
			uint32 WIMG = (batL >> 3) & 0xF;
			uint32 BRPN = ((batL >> 17) & 0x7FFF) << 17;

			// check for match
			if ((vAddr&BL) == BEPI)
			{
				// match
				vAddr = (vAddr&~BL) | (BRPN&BL);
				debug_lastTranslatedHit = vAddr;
				return vAddr;
			}
		}

		// no match
		debug_lastTranslatedHit = 0xFFFFFFFF;

		// find segment
		uint32 segmentIndex = (vAddr>>28);
		//uint32 pageIndex = (vAddr >> 12) & 0xFFFF; // for 4KB pages
		// uint32 byteOffset = vAddr & 0xFFF; // for 4KB pages
		uint32 pageIndex = (vAddr >> 17) & 0x7FF; // for 128KB pages 
		uint32 byteOffset = vAddr & 0x1FFFF;
		uint32 srValue = hCPU->sprExtended.sr[segmentIndex];
		
		uint8 sr_ks = (srValue >> 30) & 1; // supervisor
		uint8 sr_kp = (srValue >> 29) & 1; // user mode
		uint8 sr_n = (srValue >> 28) & 1; // no-execute
		uint32 sr_vsid = (srValue & 0xFFFFFF);
		//uint32 vpn = pageIndex | (sr_vsid << 16); // 40bit virtual page number


		// look up in page table
		//uint32 lookupHash = (sr_vsid ^ pageIndex) & 0x7FFFF; // not correct for 4KB pages? sr_vsid must be shifted?
		//uint32 lookupHash = (sr_vsid ^ pageIndex) & 0x7FFFF;
		//uint32 lookupHash = ((sr_vsid>>8) ^ pageIndex) & 0x7FFFF;
		uint32 lookupHash = ((sr_vsid >> 0) ^ pageIndex) & 0x7FFFF;

		//lookupHash ^= 0x7FFFF;

		uint32 pageTableAddr = hCPU->sprExtended.sdr1&0xFFFF0000;
		uint32 pageTableMask = hCPU->sprExtended.sdr1&0x1FF;

		for (uint32 ch = 0; ch < 2; ch++)
		{
			uint32 ptegSelectLow = (lookupHash & 0x3FF);
			uint32 maskOR = (lookupHash >> 10) & pageTableMask;

			uint32* pteg = (uint32*)(memory_base + (pageTableAddr | (maskOR << 16)) + ptegSelectLow * 64);
			for (sint32 t = 0; t < 8; t++)
			{
				uint32 w0 = _swapEndianU32(pteg[0]);
				uint32 w1 = _swapEndianU32(pteg[1]);
				pteg += 2;
				if ((w0 & 0x80000000) == 0)
					continue; // entry not valid

				uint32 abPageIndex = (w0 >> 0) & 0x3F;
				uint8 h = (w0 >> 6) & 1;
				uint32 ptegVSID = (w0 >> 7) & 0xFFFFFF;

				if (abPageIndex == (pageIndex >> 5) && ptegVSID == sr_vsid && h == ch)
				{
					if (ch == 1)
						assert_dbg();
					// match
					uint32 ptegPhysicalPage = (w1 >> 12) & 0xFFFFF;
					// replace page (128KB)
					vAddr = (vAddr & ~0xFFFE0000) | (ptegPhysicalPage << 12);
					return vAddr;

				}
			}
			// calculate hash 2
			lookupHash = ~lookupHash;
		}

		cemuLog_logDebug(LogType::Force, "DSI exception at 0x{:08x} DataAddress {:08x}", hCPU->instructionPointer, vAddr);

		generateDSIException(hCPU, vAddr);

		// todo: Check hash func 1
		// todo: Check protection bits
		// todo: Check supervisor/usermode bits


		// also use this function in all the mem stuff below

		// note: bat has higher priority than TLB

		// since iterating the bats and page table is too slow, we need to pre-process the data somehow.

		return vAddr;
	}

	inline static uint32 ppcMem_translateVirtualCodeToPhysicalAddr(PPCInterpreter_t* hCPU, uint32 vAddr)
	{
		// check if address translation is disabled for instruction accesses
		if (GET_MSR_BIT(MSR_IR) == 0)
		{
			return vAddr;
		}

		// how to determine if BAT is valid:
		// BAT_entry_valid = (Vs & ~MSR[PR]) | (Vp & MSR[PR]) (The entry has separate enable flags for usermode and supervisor mode)
		for (sint32 i = 0; i < 8; i++)
		{
			// upper
			uint32 batU = hCPU->sprExtended.ibatU[i];
			uint32 BEPI = ((batU >> 17) & 0x7FFF) << 17;
			uint32 Vp = (batU >> 0) & 1;
			uint32 Vs = (batU >> 1) & 1;
			uint32 BL = (((batU >> 2) & 0x7FF) ^ 0x7FF) << 17;
			BL |= 0xF0000000;
			if (Vs == 0)
				continue; // todo - check if in supervisor/usermode
			// lower
			uint32 batL = hCPU->sprExtended.ibatL[i];
			uint32 PP = (batL >> 0) & 3;
			uint32 WIMG = (batL >> 3) & 0xF;
			uint32 BRPN = ((batL >> 17) & 0x7FFF) << 17;

			// check for match
			if ((vAddr&BL) == BEPI)
			{
				// match
				vAddr = (vAddr&~BL) | (BRPN&BL);
				debug_lastTranslatedHit = vAddr;
				return vAddr;
			}
		}
		assert_dbg();

		// no match
		// todo - throw exception if translation is enabled?
		return vAddr;
	}

	static uint32 memory_readCodeU32(PPCInterpreter_t* hCPU, uint32 address)
	{
		return _swapEndianU32(*(uint32*)(memory_base + ppcMem_translateVirtualCodeToPhysicalAddr(hCPU, address)));
	}

	inline static uint8* ppcMem_getDataPtr(PPCInterpreter_t* hCPU, uint32 vAddr)
	{
		return memory_base + ppcMem_translateVirtualDataToPhysicalAddr(hCPU, vAddr);
	}

	inline static void ppcMem_writeDataDouble(PPCInterpreter_t* hCPU, uint32 address, double vf)
	{
		uint64 v = *(uint64*)&vf;
		uint32 v1 = v & 0xFFFFFFFF;
		uint32 v2 = v >> 32;
		uint8* ptr = ppcMem_getDataPtr(hCPU, address);
		*(uint32*)(ptr + 4) = CPU_swapEndianU32(v1);
		*(uint32*)(ptr + 0) = CPU_swapEndianU32(v2);
	}

	inline static void ppcMem_writeDataU64(PPCInterpreter_t* hCPU, uint32 address, uint64 v)
	{
		*(uint64*)(ppcMem_getDataPtr(hCPU, address)) = CPU_swapEndianU64(v);
	}

	inline static void ppcMem_writeDataU32(PPCInterpreter_t* hCPU, uint32 address, uint32 v)
	{
		uint32 pAddr = ppcMem_translateVirtualDataToPhysicalAddr(hCPU, address); 
		if (hCPU->memoryException)
			return;

		if (pAddr >= 0x0c000000 && pAddr < 0x0d100000)
		{
			cemu_assert_unimplemented();
			return;
		}
		*(uint32*)(memory_base + pAddr) = CPU_swapEndianU32(v);
	}

	inline static void ppcMem_writeDataU16(PPCInterpreter_t* hCPU, uint32 address, uint16 v)
	{
		*(uint16*)(ppcMem_getDataPtr(hCPU, address)) = CPU_swapEndianU16(v);
	}

	inline static void ppcMem_writeDataU8(PPCInterpreter_t* hCPU, uint32 address, uint8 v)
	{
		*(uint8*)(ppcMem_getDataPtr(hCPU, address)) = v;
	}

	inline static double ppcMem_readDataDouble(PPCInterpreter_t* hCPU, uint32 address)
	{
		uint32 v[2];
		v[1] = *(uint32*)(ppcMem_getDataPtr(hCPU, address));
		v[0] = *(uint32*)(ppcMem_getDataPtr(hCPU, address) + 4);
		v[0] = CPU_swapEndianU32(v[0]);
		v[1] = CPU_swapEndianU32(v[1]);
		return *(double*)v;
	}

	inline static float ppcMem_readDataFloat(PPCInterpreter_t* hCPU, uint32 address)
	{
		uint32 v = *(uint32*)(ppcMem_getDataPtr(hCPU, address));
		v = CPU_swapEndianU32(v);
		return *(float*)&v;
	}

	inline static uint64 ppcMem_readDataU64(PPCInterpreter_t* hCPU, uint32 address)
	{
		uint64 v = *(uint64*)(ppcMem_getDataPtr(hCPU, address));
		return CPU_swapEndianU64(v);
	}

	inline static uint32 ppcMem_readDataU32(PPCInterpreter_t* hCPU, uint32 address)
	{
		uint32 pAddr = ppcMem_translateVirtualDataToPhysicalAddr(hCPU, address);
		if (hCPU->memoryException)
			return 0;
		if (pAddr >= 0x01FFF000 && pAddr < 0x02000000)
		{
			debug_printf("Access u32 boot param block 0x%08x IP %08x LR %08x\n", pAddr, hCPU->instructionPointer, hCPU->spr.LR);
			cemuLog_logDebug(LogType::Force, "Access u32 boot param block 0x{:08x} (org {:08x}) IP {:08x}", pAddr, address, hCPU->instructionPointer);
		}
		if (pAddr >= 0xFFEB73B0 && pAddr < (0xFFEB73B0+0x40C))
		{
			debug_printf("Access cached u32 boot param block 0x%08x IP %08x LR %08x\n", pAddr, hCPU->instructionPointer, hCPU->spr.LR);
			cemuLog_logDebug(LogType::Force, "Access cached u32 boot param block 0x{:08x} (org {:08x}) IP {:08x}", pAddr, address, hCPU->instructionPointer);
		}

		if (pAddr >= 0x0c000000 && pAddr < 0x0d100000)
		{
			cemu_assert_unimplemented();
			return 0;
		}
		uint32 v = *(uint32*)(memory_base + pAddr);
		return CPU_swapEndianU32(v);
	}

	inline static uint16 ppcMem_readDataU16(PPCInterpreter_t* hCPU, uint32 address)
	{
		uint16 v = *(uint16*)(ppcMem_getDataPtr(hCPU, address));
		return CPU_swapEndianU16(v);
	}

	inline static uint8 ppcMem_readDataU8(PPCInterpreter_t* hCPU, uint32 address)
	{
		uint32 pAddr = ppcMem_translateVirtualDataToPhysicalAddr(hCPU, address);
		if (pAddr >= 0x0c000000 && pAddr < 0x0d100000)
		{
			cemu_assert_unimplemented();
			return 0;
		}
		return *(uint8*)(memory_base + pAddr);
	}

	inline static uint64 ppcMem_readDataFloatEx(PPCInterpreter_t* hCPU, uint32 addr)
	{
		return ConvertToDoubleNoFTZ(_swapEndianU32(*(uint32*)(memory_base + addr)));
	}

	inline static void ppcMem_writeDataFloatEx(PPCInterpreter_t* hCPU, uint32 addr, uint64 value)
	{
		*(uint32*)(memory_base + addr) = _swapEndianU32(ConvertToSingleNoFTZ(value));
	}

	inline static uint64 getTB(PPCInterpreter_t* hCPU)
	{
		return hCPU->global->tb / 20ULL;
	}
};

// ================================================================================================
// Predecoded instruction cache
//
// WHY THIS EXISTS
//
// executeInstruction() used to re-derive the handler for an instruction from the raw opcode bits
// on every single execution: a switch on the primary opcode, then for the dense categories (4,
// 19, 31, 59, 63) a second switch on the extended opcode, and for the paired-single compare and
// merge groups a third. A hot loop walked that entire decision tree again on every iteration, to
// arrive at the same answer it arrived at the previous time. Decode is a pure function of the
// 32-bit opcode word, so every walk after the first is waste - and on this port the interpreter
// is not a fallback, it is the only CPU engine, because the JIT capability probe asks for
// PROT_EXEC at mmap time and iOS arm64 never grants that on an APRR core.
//
// So: decode once per guest instruction address, remember the answer, and afterwards dispatch
// straight through a function pointer.
//
// HOW CORRECTNESS IS GUARANTEED - this is the important part
//
// The cache is SELF-VALIDATING. Every entry stores the opcode word it was decoded from next to
// the handler, and an entry is only used when that stored word still equals the word currently
// in guest memory at that address. The handler is by construction decodeInstruction(storedWord),
// so a match means the cached handler is bit-for-bit what a fresh decode would have produced.
// A stale entry cannot be used, because "stale" is exactly the case the comparison rejects.
//
// That is why there is deliberately NO invalidation hook here. The recompiler's invalidation path
// is PPCRecompiler_invalidateRange() in Recompiler/PPCRecompiler.cpp, reached from
// coreinit_CodeGen (the guest's own icbi/flush path), RPL load and unload, graphic pack patching
// and the debugger. Subscribing a second listener to that signal would create two schemes that
// can disagree about what is live, and a disagreement there is a corruption bug nobody can
// diagnose from a screenshot. Worse, on this port that signal is not even live:
// PPCRecompiler_invalidateRange() returns immediately when ppcRecompilerEnabled is false, which
// on iOS it always is, so a cache that trusted it would never be invalidated at all. Comparing
// the opcode word cannot disagree with anything, because it asks guest memory directly, every
// time, and it costs one compare against a word the interpreter had to load anyway.
//
// Cases that are handled correctly for free, none of which have to know this cache exists:
//   - self-modifying guest code, and icbi
//   - an RPL's text being unloaded and another module being mapped over the same addresses
//   - graphic pack code patches
//   - debugger execution breakpoints, which work by writing a trap opcode over the instruction
//     and restoring the original word afterwards
//   - guest code executed through an address that is not 4-byte aligned: two such addresses can
//     share a slot, and they then simply keep evicting each other's entry, still correct
//
// MEMORY
//
// One 8-byte entry per 4-byte guest instruction, i.e. twice the size of the code it describes,
// and only for 4 KB pages the title actually executes. Entries are carved from a single fixed
// 32 MB arena, which is what bounds the whole feature: 16 MB of distinct guest code, far more
// than any title's hot set, and once it is exhausted the pages that missed out keep decoding the
// old way instead of anything failing. The device log this work is aimed at showed 2416 MB in
// use with 2191 MB of headroom before iOS kills the process, so a table keyed on every possible
// guest address (256 MB of code space -> 512 MB of entries) was never an option. The arena is
// calloc'd once, so at first it is only address space; it becomes resident a host page at a time
// as blocks are actually written.
//
// THREADING
//
// Three emulated cores run this concurrently on three host threads and share one cache per
// interpreter flavour. An entry is a single naturally aligned uint64 holding {opcode word,
// handler index}, published with one atomic store and read with one atomic load, so it can never
// be seen half-updated. That matters: a torn entry could pair the opcode word one core wrote
// with the handler index another core wrote, which is the one way this design could dispatch a
// wrong handler. Everything else is arranged so the hot path needs no barrier at all - the arena
// is zeroed before any core thread exists, blocks are never freed or reused, and a handler table
// slot is filled before the index naming it is ever published and never changes afterwards. A
// reader that somehow ran ahead of a handler table write sees a null slot, which is simply
// treated as a miss.
// ================================================================================================

#if defined(_MSC_VER) && !defined(__clang__)
#define PPCITP_NOINLINE __declspec(noinline)
#else
#define PPCITP_NOINLINE __attribute__((noinline))
#endif

// Internal linkage for the cache tables and for the interpreter template that owns them. Not
// cosmetic: with external linkage the dispatch path has to reach s_blockTable and s_handlerTable
// through the GOT, which is an extra dependent load each, on every guest instruction. Internal,
// clang addresses them with adrp+add and the two loads disappear. Nothing outside this file has
// ever referred to PPCInterpreterContainer - the two exported entry points at the bottom are the
// whole interface - so this costs nothing.
namespace
{

namespace PPCPredecode
{
	// Guest code only ever lives below 0x10000000: CODELOW0 at 0x00010000, the RPL trampoline and
	// import area at 0x00E00000, the code cave at 0x01800000 and the 224 MB code area at
	// 0x02000000. This is the same bound the recompiler works to (PPC_REC_CODE_AREA_END), and it
	// is checked rather than assumed - an instruction pointer outside it is not cached and falls
	// through to a plain decode, which is always correct, just not faster.
	static constexpr uint32 kCodeAreaEnd = 0x10000000u;

	static constexpr uint32 kBlockShift = 12;                              // 4 KB of guest code per block
	static constexpr uint32 kBlockSize = 1u << kBlockShift;
	static constexpr uint32 kEntriesPerBlock = kBlockSize / 4u;             // 1024 instructions
	static constexpr uint32 kBlockTableSize = kCodeAreaEnd >> kBlockShift;  // 65536 possible pages

	// 4096 blocks * 8 KB = 32 MB of entries, describing 16 MB of distinct guest code.
	static constexpr uint32 kArenaBlocks = 4096;
	static constexpr size_t kArenaEntries = (size_t)kArenaBlocks * kEntriesPerBlock;

	// Constructed during static initialisation, i.e. before any core thread exists. That is not
	// incidental: it is what lets the dispatch path load a block pointer with relaxed ordering
	// and read the block's contents with no acquire barrier, because the zeroing of every block
	// happens-before the creation of every thread that can observe it.
	struct Arena
	{
		uint64* base;
		std::atomic<uint32> nextBlock;

		Arena() : base(nullptr), nextBlock(0)
		{
			// calloc rather than new[]: for a request this size every allocator hands back fresh
			// zero pages from the kernel, so nothing is touched here and the 32 MB costs address
			// space only. new[] with value-initialisation would write all 32 MB up front and make
			// the whole arena resident on a device that measures its headroom in hundreds of MB.
			base = (uint64*)calloc(kArenaEntries, sizeof(uint64));
			// A failed allocation is not fatal. base stays null, no block is ever handed out, and
			// every instruction decodes the way it did before this cache existed.
		}
	};

	inline Arena g_arena;
	inline std::atomic<bool> g_reportedArenaFull{false};

	// Hands out one zeroed block, or nullptr once the arena is full. Blocks are never returned,
	// so there is no reuse policy to get wrong and no pointer that can be freed underneath a
	// core that is still dispatching through it.
	inline uint64* allocBlock()
	{
		if (!g_arena.base)
			return nullptr;
		// Checked before the fetch_add so that an exhausted arena does not turn every subsequent
		// cache miss into a contended atomic increment across three cores forever.
		if (g_arena.nextBlock.load(std::memory_order_relaxed) >= kArenaBlocks)
		{
			// Said once, and worth saying. Every page that fails to get a block from here keeps
			// re-decoding on every execution, so a title whose code footprint outgrows the arena
			// would just look slower than the others for no visible reason. This line turns that
			// into "raise kArenaBlocks", which is a one-word fix.
			if (!g_reportedArenaFull.exchange(true, std::memory_order_relaxed))
				cemuLog_log(LogType::Force, "Interpreter predecode cache: arena full after {} pages ({} MB of guest code). Pages claimed from here on will decode on every execution.", kArenaBlocks, (kArenaBlocks * kBlockSize) / (1024u * 1024u));
			return nullptr;
		}
		uint32 idx = g_arena.nextBlock.fetch_add(1, std::memory_order_relaxed);
		if (idx >= kArenaBlocks)
			return nullptr;
		return g_arena.base + (size_t)idx * kEntriesPerBlock;
	}
}

template <typename ppcItpCtrl>
class PPCInterpreterContainer
{
public:
#include "PPCInterpreterSPR.hpp"
#include "PPCInterpreterOPC.hpp"
#include "PPCInterpreterLoadStore.hpp"
#include "PPCInterpreterALU.hpp"

	// ---- handlers that used to be written inline in the decode switch ---------------------------
	//
	// decodeInstruction() below has to be a pure opcode -> handler function with no side effects,
	// because that purity is the entire basis on which a cached handler can be trusted. The cases
	// the old switch handled inline - the invalid primary opcodes, TWI, and every "unknown
	// extended opcode" default - therefore become ordinary handlers. Their bodies are unchanged,
	// including which of them advance the instruction pointer and which deliberately do not, and
	// they still run at EXECUTION time, so the diagnostics they log appear exactly as often as
	// they did before.

	static void PPCInterpreter_opcodeZero(PPCInterpreter_t* hCPU, uint32 opcode)
	{
		debug_printf("ZERO[NOP] | 0x%08X\n", (unsigned int)hCPU->instructionPointer);
#ifdef CEMU_DEBUG_ASSERT
		assert_dbg();
		while (true) std::this_thread::sleep_for(std::chrono::seconds(1));
#endif
		hCPU->instructionPointer += 4;
	}

	static void PPCInterpreter_unsupportedTWI(PPCInterpreter_t* hCPU, uint32 opcode)
	{
		cemuLog_logDebug(LogType::Force, "Unsupported TWI instruction executed at {:08x}", hCPU->instructionPointer);
		PPCInterpreter_nextInstruction(hCPU);
	}

	static void PPCInterpreter_unsupported17(PPCInterpreter_t* hCPU, uint32 opcode)
	{
		cemuLog_logDebug(LogType::Force, "Unsupported Opcode [0x17 --> 0x0]");
		cemu_assert_unimplemented();
		hCPU->instructionPointer += 4;
	}

	static void PPCInterpreter_unknown_4_0(PPCInterpreter_t* hCPU, uint32 opcode)
	{
		cemuLog_logDebug(LogType::Force, "Unknown execute {:04x} as [4->0] at {:08x}", PPC_getBits(opcode, 25, 5), hCPU->instructionPointer);
		cemu_assert_unimplemented();
		hCPU->instructionPointer += 4;
	}

	static void PPCInterpreter_unknown_4_8(PPCInterpreter_t* hCPU, uint32 opcode)
	{
		cemuLog_logDebug(LogType::Force, "Unknown execute {:04x} as [4->8] at {:08x}", PPC_getBits(opcode, 25, 5), hCPU->instructionPointer);
		cemu_assert_unimplemented();
		hCPU->instructionPointer += 4;
	}

	static void PPCInterpreter_unknown_4_16(PPCInterpreter_t* hCPU, uint32 opcode)
	{
		cemuLog_logDebug(LogType::Force, "Unknown execute {:04x} as [4->16] at {:08x}", PPC_getBits(opcode, 25, 5), hCPU->instructionPointer);
		cemu_assert_unimplemented();
		hCPU->instructionPointer += 4;
	}

	static void PPCInterpreter_unknown_4(PPCInterpreter_t* hCPU, uint32 opcode)
	{
		cemuLog_logDebug(LogType::Force, "Unknown execute {:04x} as [4] at {:08x}", PPC_getBits(opcode, 30, 5), hCPU->instructionPointer);
		cemu_assert_unimplemented();
		hCPU->instructionPointer += 4;
	}

	static void PPCInterpreter_unknown_19(PPCInterpreter_t* hCPU, uint32 opcode)
	{
		cemuLog_logDebug(LogType::Force, "Unknown execute {:04x} as [19] at {:08x}\n", PPC_getBits(opcode, 30, 10), hCPU->instructionPointer);
		cemu_assert_unimplemented();
		hCPU->instructionPointer += 4;
	}

	static void PPCInterpreter_unknown_31(PPCInterpreter_t* hCPU, uint32 opcode)
	{
		cemuLog_logDebug(LogType::Force, "Unknown execute {:04x} as [31] at {:08x}\n", PPC_getBits(opcode, 30, 10), hCPU->instructionPointer);
		cemu_assert_unimplemented();
		hCPU->instructionPointer += 4;
	}

	static void PPCInterpreter_unknown_59(PPCInterpreter_t* hCPU, uint32 opcode)
	{
		cemuLog_logDebug(LogType::Force, "Unknown execute {:04x} as [59] at {:08x}\n", PPC_getBits(opcode, 30, 10), hCPU->instructionPointer);
		cemu_assert_unimplemented();
		hCPU->instructionPointer += 4;
	}

	static void PPCInterpreter_unknown_63(PPCInterpreter_t* hCPU, uint32 opcode)
	{
		cemuLog_logDebug(LogType::Force, "Unknown execute {:04x} as [63] at {:08x}\n", PPC_getBits(opcode, 30, 10), hCPU->instructionPointer);
		cemu_assert_unimplemented();
		PPCInterpreter_nextInstruction(hCPU);
	}

	// Note the absence of an instruction pointer advance. The old top-level default did not have
	// one either, so an unknown primary opcode re-executes forever in a release build. That is
	// preserved on purpose: this is a decode change, and turning a hang into a silent skip would
	// change what the emulator does with bad code, which is not this change's business.
	static void PPCInterpreter_unknownPrimary(PPCInterpreter_t* hCPU, uint32 opcode)
	{
		cemuLog_logDebug(LogType::Force, "Unknown execute {:04x} at {:08x}\n", PPC_getBits(opcode, 5, 6), (unsigned int)hCPU->instructionPointer);
		cemu_assert_unimplemented();
	}

	// Pure. The same opcode word always maps to the same handler, and nothing in here may read
	// hCPU or guest memory - that is what lets the cache below be correct on nothing more than an
	// opcode word comparison. Kept out of line so that the dispatch path stays a handful of
	// instructions instead of inlining the whole decision tree it exists to avoid.
	PPCITP_NOINLINE static PPCInstructionHandler decodeInstruction(uint32 opcode)
	{
		switch ((opcode >> 26))
		{
		case 0:
			return &PPCInterpreter_opcodeZero;
		case 1: // virtual HLE
			return &PPCInterpreter_virtualHLE;
		case 3:
			return &PPCInterpreter_unsupportedTWI;
		case 4:
			switch (PPC_getBits(opcode, 30, 5))
			{
			case 0: // subcategory compare
				switch (PPC_getBits(opcode, 25, 5))
				{
				case 0: // Sonic All Stars Racing
					return &PPCInterpreter_PS_CMPU0;
				case 1:
					return &PPCInterpreter_PS_CMPO0;
				case 2: // Assassin's Creed 3, Sonic All Stars Racing
					return &PPCInterpreter_PS_CMPU1;
				default:
					return &PPCInterpreter_unknown_4_0;
				}
				break;
			case 6:
				return &PPCInterpreter_PSQ_LX;
			case 7:
				return &PPCInterpreter_PSQ_STX;
			case 8:
				switch (PPC_getBits(opcode, 25, 5))
				{
				case 1:
					return &PPCInterpreter_PS_NEG;
				case 2:
					return &PPCInterpreter_PS_MR;
				case 4:
					return &PPCInterpreter_PS_NABS;
				case 8:
					return &PPCInterpreter_PS_ABS;
				default:
					return &PPCInterpreter_unknown_4_8;
				}
				break;
			case 10:
				return &PPCInterpreter_PS_SUM0;
			case 11:
				return &PPCInterpreter_PS_SUM1;
			case 12:
				return &PPCInterpreter_PS_MULS0;
			case 13:
				return &PPCInterpreter_PS_MULS1;
			case 14:
				return &PPCInterpreter_PS_MADDS0;
			case 15:
				return &PPCInterpreter_PS_MADDS1;
			case 16: // sub category - merge
				switch (PPC_getBits(opcode, 25, 5))
				{
				case 16:
					return &PPCInterpreter_PS_MERGE00;
				case 17:
					return &PPCInterpreter_PS_MERGE01;
				case 18:
					return &PPCInterpreter_PS_MERGE10;
				case 19:
					return &PPCInterpreter_PS_MERGE11;
				default:
					return &PPCInterpreter_unknown_4_16;
				}
				break;
			case 18:
				return &PPCInterpreter_PS_DIV;
			case 20:
				return &PPCInterpreter_PS_SUB;
			case 21:
				return &PPCInterpreter_PS_ADD;
			case 22:
				return &PPCInterpreter_DCBZL;
			case 23:
				return &PPCInterpreter_PS_SEL;
			case 24:
				return &PPCInterpreter_PS_RES;
			case 25:
				return &PPCInterpreter_PS_MUL;
			case 26: // sub category with only one entry - RSQRTE
				return &PPCInterpreter_PS_RSQRTE;
			case 28:
				return &PPCInterpreter_PS_MSUB;
			case 29:
				return &PPCInterpreter_PS_MADD;
			case 30:
				return &PPCInterpreter_PS_NMSUB;
			case 31:
				return &PPCInterpreter_PS_NMADD;
			default:
				return &PPCInterpreter_unknown_4;
			}
			break;
		case 7:
			return &PPCInterpreter_MULLI;
		case 8:
			return &PPCInterpreter_SUBFIC;
		case 10:
			return &PPCInterpreter_CMPLI;
		case 11:
			return &PPCInterpreter_CMPI;
		case 12:
			return &PPCInterpreter_ADDIC;
		case 13:
			return &PPCInterpreter_ADDIC_;
		case 14:
			return &PPCInterpreter_ADDI;
		case 15:
			return &PPCInterpreter_ADDIS;
		case 16:
			return &PPCInterpreter_BCX;
		case 17:
			if (PPC_getBits(opcode, 30, 1) == 1)
				return &PPCInterpreter_SC;
			return &PPCInterpreter_unsupported17;
		case 18:
			return &PPCInterpreter_BX;
		case 19: // opcode category
			switch (PPC_getBits(opcode, 30, 10))
			{
			case 0:
				return &PPCInterpreter_MCRF;
			case 16:
				return &PPCInterpreter_BCLRX;
			case 33:
				return &PPCInterpreter_CRNOR;
			case 50:
				return &PPCInterpreter_RFI;
			case 129:
				return &PPCInterpreter_CRANDC;
			case 150:
				return &PPCInterpreter_ISYNC;
			case 193:
				return &PPCInterpreter_CRXOR;
			case 225:
				return &PPCInterpreter_CRNAND;
			case 257:
				return &PPCInterpreter_CRAND;
			case 289:
				return &PPCInterpreter_CREQV;
			case 417:
				return &PPCInterpreter_CRORC;
			case 449:
				return &PPCInterpreter_CROR;
			case 528:
				return &PPCInterpreter_BCCTR;
			default:
				return &PPCInterpreter_unknown_19;
			}
			break;
		case 20:
			return &PPCInterpreter_RLWIMI;
		case 21:
			return &PPCInterpreter_RLWINM;
		case 23:
			return &PPCInterpreter_RLWNM;
		case 24:
			return &PPCInterpreter_ORI;
		case 25:
			return &PPCInterpreter_ORIS;
		case 26:
			return &PPCInterpreter_XORI;
		case 27:
			return &PPCInterpreter_XORIS;
		case 28:
			return &PPCInterpreter_ANDI_;
		case 29:
			return &PPCInterpreter_ANDIS_;
		case 31: // opcode category
			switch (PPC_getBits(opcode, 30, 10))
			{
			case 0:
				return &PPCInterpreter_CMP;
			case 4:
				return &PPCInterpreter_TW;
			case 8:
				return &PPCInterpreter_SUBFC;
			case 10:
				return &PPCInterpreter_ADDC;
			case 11:
				return &PPCInterpreter_MULHWU_;
			case 19:
				return &PPCInterpreter_MFCR;
			case 20:
				return &PPCInterpreter_LWARX;
			case 23:
				return &PPCInterpreter_LWZX;
			case 24:
				return &PPCInterpreter_SLWX;
			case 26:
				return &PPCInterpreter_CNTLZW;
			case 28:
				return &PPCInterpreter_ANDX;
			case 32:
				return &PPCInterpreter_CMPL;
			case 40:
				return &PPCInterpreter_SUBF;
			case 54:
				return &PPCInterpreter_DCBST;
			case 55:
				return &PPCInterpreter_LWZXU;
			case 60:
				return &PPCInterpreter_ANDCX;
			case 75:
				return &PPCInterpreter_MULHW_;
			case 83:
				return &PPCInterpreter_MFMSR;
			case 86:
				return &PPCInterpreter_DCBF;
			case 87:
				return &PPCInterpreter_LBZX;
			case 104:
				return &PPCInterpreter_NEG;
			case 119: // Sonic Lost World
				return &PPCInterpreter_LBZXU;
			case 124:
				return &PPCInterpreter_NORX;
			case 136:
				return &PPCInterpreter_SUBFE;
			case 138:
				return &PPCInterpreter_ADDE;
			case 144:
				return &PPCInterpreter_MTCRF;
			case 146:
				return &PPCInterpreter_MTMSR;
			case 150:
				return &PPCInterpreter_STWCX;
			case 151:
				return &PPCInterpreter_STWX;
			case 183:
				return &PPCInterpreter_STWUX;
			case 200:
				return &PPCInterpreter_SUBFZE;
			case 202:
				return &PPCInterpreter_ADDZE;
			case 210:
				return &PPCInterpreter_MTSR;
			case 215:
				return &PPCInterpreter_STBX;
			case 232: // Trine 2
				return &PPCInterpreter_SUBFME;
			case 234:
				return &PPCInterpreter_ADDME;
			case 235:
				return &PPCInterpreter_MULLW;
			case 247:
				return &PPCInterpreter_STBUX;
			case 266:
				return &PPCInterpreter_ADD;
			case 278:
				return &PPCInterpreter_DCBT;
			case 279:
				return &PPCInterpreter_LHZX;
			case 284:
				return &PPCInterpreter_EQV;
			case 306:
				return &PPCInterpreter_TLBIE;
			case 311: // Wii U Menu v177 (US)
				return &PPCInterpreter_LHZUX;
			case 316:
				return &PPCInterpreter_XOR;
			case 339:
				return &PPCInterpreter_MFSPR;
			case 343:
				return &PPCInterpreter_LHAX;
			case 371:
				return &PPCInterpreter_MFTB;
			case 375: // Wii U Menu v177 (US)
				return &PPCInterpreter_LHAUX;
			case 407:
				return &PPCInterpreter_STHX;
			case 412:
				return &PPCInterpreter_ORC;
			case 439:
				return &PPCInterpreter_STHUX;
			case 444:
				return &PPCInterpreter_OR;
			case 459:
				return &PPCInterpreter_DIVWU;
			case 467:
				return &PPCInterpreter_MTSPR;
			case 470:
				return &PPCInterpreter_DCBI;
			case 476:
				return &PPCInterpreter_NANDX;
			case 491:
				return &PPCInterpreter_DIVW;
			case 512:
				return &PPCInterpreter_MCRXR;
			case 520: // Affordable Space Adventures + other Unity games
				return &PPCInterpreter_SUBFCO;
			case 522:
				return &PPCInterpreter_ADDCO;
			case 523: // 11 | OE
				return &PPCInterpreter_MULHWU_; // OE is ignored
			case 533:
				return &PPCInterpreter_LSWX;
			case 534:
				return &PPCInterpreter_LWBRX;
			case 535:
				return &PPCInterpreter_LFSX;
			case 536:
				return &PPCInterpreter_SRWX;
			case 552:
				return &PPCInterpreter_SUBFO;
			case 566:
				return &PPCInterpreter_TLBSYNC;
			case 567:
				return &PPCInterpreter_LFSUX;
			case 587: // 75 | OE
				return &PPCInterpreter_MULHW_; // OE is ignored for MULHW
			case 595:
				return &PPCInterpreter_MFSR;
			case 597:
				return &PPCInterpreter_LSWI;
			case 598:
				return &PPCInterpreter_SYNC;
			case 599:
				return &PPCInterpreter_LFDX;
			case 616:
				return &PPCInterpreter_NEGO;
			case 631:
				return &PPCInterpreter_LFDUX;
			case 648: // 136 | OE
				return &PPCInterpreter_SUBFEO;
			case 650: // 138 | OE
				return &PPCInterpreter_ADDEO;
			case 662:
				return &PPCInterpreter_STWBRX;
			case 663:
				return &PPCInterpreter_STFSX;
			case 661:
				return &PPCInterpreter_STSWX;
			case 695:
				return &PPCInterpreter_STFSUX;
			case 712: // 200 | OE
				return &PPCInterpreter_SUBFZEO;
			case 714: // 202 | OE
				return &PPCInterpreter_ADDZEO;
			case 725:
				return &PPCInterpreter_STSWI;
			case 727:
				return &PPCInterpreter_STFDX;
			case 744: // 232 | OE
				return &PPCInterpreter_SUBFMEO;
			case 746: // 234 | OE
				return &PPCInterpreter_ADDMEO;
			case 747:
				return &PPCInterpreter_MULLWO;
			case 759:
				return &PPCInterpreter_STFDUX;
			case 778:
				return &PPCInterpreter_ADDO;
			case 790:
				return &PPCInterpreter_LHBRX;
			case 792:
				return &PPCInterpreter_SRAW;
			case 824:
				return &PPCInterpreter_SRAWI;
			case 854:
				return &PPCInterpreter_EIEIO;
			case 918:
				return &PPCInterpreter_STHBRX;
			case 922:
				return &PPCInterpreter_EXTSH;
			case 954:
				return &PPCInterpreter_EXTSB;
			case 971:
				return &PPCInterpreter_DIVWUO;
			case 982:
				return &PPCInterpreter_ICBI;
			case 983:
				return &PPCInterpreter_STFIWX;
			case 1003:
				return &PPCInterpreter_DIVWO;
			case 1014:
				return &PPCInterpreter_DCBZ;
			default:
				return &PPCInterpreter_unknown_31;
			}
			break;
		case 32:
			return &PPCInterpreter_LWZ;
		case 33:
			return &PPCInterpreter_LWZU;
		case 34:
			return &PPCInterpreter_LBZ;
		case 35:
			return &PPCInterpreter_LBZU;
		case 36:
			return &PPCInterpreter_STW;
		case 37:
			return &PPCInterpreter_STWU;
		case 38:
			return &PPCInterpreter_STB;
		case 39:
			return &PPCInterpreter_STBU;
		case 40:
			return &PPCInterpreter_LHZ;
		case 41:
			return &PPCInterpreter_LHZU;
		case 42:
			return &PPCInterpreter_LHA;
		case 43:
			return &PPCInterpreter_LHAU;
		case 44:
			return &PPCInterpreter_STH;
		case 45:
			return &PPCInterpreter_STHU;
		case 46:
			return &PPCInterpreter_LMW;
		case 47:
			return &PPCInterpreter_STMW;
		case 48:
			return &PPCInterpreter_LFS;
		case 49:
			return &PPCInterpreter_LFSU;
		case 50:
			return &PPCInterpreter_LFD;
		case 51:
			return &PPCInterpreter_LFDU;
		case 52:
			return &PPCInterpreter_STFS;
		case 53:
			return &PPCInterpreter_STFSU;
		case 54:
			return &PPCInterpreter_STFD;
		case 55:
			return &PPCInterpreter_STFDU;
		case 56:
			return &PPCInterpreter_PSQ_L;
		case 57:
			return &PPCInterpreter_PSQ_LU;
		case 59: // opcode category
			switch (PPC_getBits(opcode, 30, 5))
			{
			case 18:
				return &PPCInterpreter_FDIVS;
			case 20:
				return &PPCInterpreter_FSUBS;
			case 21:
				return &PPCInterpreter_FADDS;
			case 24:
				return &PPCInterpreter_FRES;
			case 25:
				return &PPCInterpreter_FMULS;
			case 28:
				return &PPCInterpreter_FMSUBS;
			case 29:
				return &PPCInterpreter_FMADDS;
			case 30:
				return &PPCInterpreter_FNMSUBS;
			case 31:
				return &PPCInterpreter_FNMADDS;
			default:
				return &PPCInterpreter_unknown_59;
			}
			break;
		case 60:
			return &PPCInterpreter_PSQ_ST;
		case 61:
			return &PPCInterpreter_PSQ_STU;
		case 63: // opcode category
			switch (PPC_getBits(opcode, 30, 5))
			{
			case 0:
				return &PPCInterpreter_FCMPU;
			case 12:
				return &PPCInterpreter_FRSP;
			case 15:
				return &PPCInterpreter_FCTIWZ;
			case 18:
				return &PPCInterpreter_FDIV;
			case 20:
				return &PPCInterpreter_FSUB;
			case 21:
				return &PPCInterpreter_FADD;
			case 23:
				return &PPCInterpreter_FSEL;
			case 25:
				return &PPCInterpreter_FMUL;
			case 26:
				return &PPCInterpreter_FRSQRTE;
			case 28:
				return &PPCInterpreter_FMSUB;
			case 29:
				return &PPCInterpreter_FMADD;
			case 30:
				return &PPCInterpreter_FNMSUB;
			case 31:
				return &PPCInterpreter_FNMADD;
			default:
				switch (PPC_getBits(opcode, 30, 10))
				{
				case 14:
					return &PPCInterpreter_FCTIW;
				case 32:
					return &PPCInterpreter_FCMPO;
				case 38:
					return &PPCInterpreter_MTFSB1X;
				case 40:
					return &PPCInterpreter_FNEG;
				case 72:
					return &PPCInterpreter_FMR;
				case 136: // Darksiders 2
					return &PPCInterpreter_FNABS;
				case 264:
					return &PPCInterpreter_FABS;
				case 583:
					return &PPCInterpreter_MFFS;
				case 711:
					return &PPCInterpreter_MTFSF;
				default:
					return &PPCInterpreter_unknown_63;
				}
			}
			break;
		default:
			return &PPCInterpreter_unknownPrimary;
		}
		// Not reachable: every path of the switch above returns, including its default. Present so
		// the function has a defined return value if a later edit ever adds a path that does not.
		return &PPCInterpreter_unknownPrimary;
	}

	// ---- the predecoded instruction cache, one per interpreter flavour --------------------------
	//
	// Slim (CafeOS usermode) and Full (LLE, with MMU translation) resolve the same opcode word to
	// DIFFERENT handler functions, because the handlers are members of this template and reach
	// memory through ppcItpCtrl. So the tables have to be per instantiation: one shared table
	// would eventually hand an LLE instruction to Slim's linear-memory accessors, or the reverse,
	// and that is a silent wrong-memory bug rather than a crash. Being per instantiation costs
	// nothing for a flavour that never runs - the block table is zero-initialised BSS whose pages
	// are never faulted in, and no arena block is claimed until an instruction actually executes.

	static constexpr uint32 kMaxHandlers = 512; // power of two, so the index mask below is exact
	static inline std::atomic<PPCInstructionHandler> s_handlerTable[kMaxHandlers]{};
	static inline std::atomic<uint64*> s_blockTable[PPCPredecode::kBlockTableSize]{};
	// Index 0 is permanently null. That is what makes a zeroed cache entry - the state every
	// freshly claimed block is in - unable to dispatch: it names handler 0, which is null, which
	// is read as a miss. Without that reservation an all-zero entry would be indistinguishable
	// from a legitimately cached opcode 0x00000000.
	static inline uint32 s_handlerCount = 1;
	static inline bool s_reportedHandlerTableFull = false;
	static inline std::mutex s_handlerMutex;
	static inline std::unordered_map<PPCInstructionHandler, uint32> s_handlerIds;

	// Cold path only - once per distinct handler for the life of the process. Returns 0, the
	// never-dispatchable index, if the table is full, which just means that opcode keeps decoding
	// the slow way rather than anything going wrong.
	PPCITP_NOINLINE static uint32 internHandler(PPCInstructionHandler h)
	{
		std::lock_guard<std::mutex> lock(s_handlerMutex);
		auto it = s_handlerIds.find(h);
		if (it != s_handlerIds.end())
			return it->second;
		if (s_handlerCount >= kMaxHandlers)
		{
			// There are 237 distinct handlers today against a table of 512, so this is headroom
			// rather than a limit - but a future wave that adds a lot of opcodes should be told
			// rather than silently losing the cache for whatever it added. Said once; this runs
			// under the lock, so a plain bool is enough.
			if (!s_reportedHandlerTableFull)
			{
				s_reportedHandlerTableFull = true;
				cemuLog_log(LogType::Force, "Interpreter predecode cache: handler table full at {} entries. Opcodes beyond it will decode on every execution - raise kMaxHandlers.", kMaxHandlers);
			}
			return 0;
		}
		uint32 idx = s_handlerCount;
		// Release, and the slot is filled before the index naming it can appear in any cache
		// entry. A core that reads the index therefore either sees the handler or sees null and
		// treats it as a miss; it can never see a different handler.
		s_handlerTable[idx].store(h, std::memory_order_release);
		s_handlerCount = idx + 1;
		s_handlerIds[h] = idx;
		return idx;
	}

	// Cold: the first time any instruction inside this 4 KB guest page executes. Returns the block
	// that ends up published for the page, or nullptr when the arena is exhausted - in which case
	// this page is simply never cached.
	PPCITP_NOINLINE static uint64* claimBlockForPage(std::atomic<uint64*>& tableSlot)
	{
		uint64* block = PPCPredecode::allocBlock();
		if (!block)
			return nullptr;
		uint64* expected = nullptr;
		if (!tableSlot.compare_exchange_strong(expected, block, std::memory_order_relaxed, std::memory_order_relaxed))
		{
			// Another core published a block for this page first. Ours is left unused for the rest
			// of the run; that wastes at most one block per page and needs no cleanup path, which
			// is worth more here than reclaiming 8 KB.
			return expected;
		}
		return block;
	}

	// Returns the cache slot for a guest address, or nullptr if the address cannot be cached.
	// Cold path only - reached from executeUncached, never from the hit path.
	static uint64* predecodeSlot(uint32 ip)
	{
		if (ip >= PPCPredecode::kCodeAreaEnd) [[unlikely]]
			return nullptr;
		std::atomic<uint64*>& tableSlot = s_blockTable[ip >> PPCPredecode::kBlockShift];
		// Relaxed, and this is the one load where it is worth saying why no acquire is needed.
		// The block this pointer names was zeroed by calloc during static initialisation, before
		// any core thread existed, and the only writes to it afterwards are the single-uint64
		// entry publications below, each carrying its own opcode tag. So there is no "initialised"
		// state a reader can arrive too early for: it either sees a zero entry, which is a miss,
		// or a whole published entry, which is self-checking.
		uint64* block = tableSlot.load(std::memory_order_relaxed);
		if (!block) [[unlikely]]
		{
			block = claimBlockForPage(tableSlot);
			if (!block)
				return nullptr;
		}
		return block + ((ip & (PPCPredecode::kBlockSize - 1u)) >> 2);
	}

	// Every reason a dispatch can fail to be a hit, in one place: first execution of this address,
	// the instruction word changed underneath the entry, this page has no block yet, the arena is
	// full, or the address is outside the guest code area. Decode, remember it if there is
	// somewhere to remember it, and run it.
	//
	// One function, and noinline, for a reason that is visible in the generated code rather than
	// aesthetic. With the cold work inlined, executeInstruction needed four callee-saved registers
	// and a 64-byte frame to carry hCPU across the cold calls, and paid the prologue and epilogue
	// for that frame on every HIT as well. Outlined, the hit path touches no callee-saved register
	// and needs no frame, so clang finishes it with a tail branch straight to the handler - which
	// means the handler's own `ret` returns directly to the execution loop, with no stack growth
	// and no second return hop. That is the shape a threaded interpreter wants, obtained from the
	// ordinary optimiser instead of from musttail.
	PPCITP_NOINLINE static void executeUncached(PPCInterpreter_t* hCPU, uint32 ip, uint32 opcode)
	{
		const PPCInstructionHandler h = decodeInstruction(opcode);
		uint64* slot = predecodeSlot(ip);
		if (slot)
		{
			const uint32 idx = internHandler(h);
			if (idx != 0)
				std::atomic_ref<uint64>(*slot).store(((uint64)idx << 32) | (uint64)opcode, std::memory_order_release);
		}
		// Not cacheable, or not cached yet - either way the instruction still executes exactly as
		// it did before this cache existed. Nothing here is a degraded fallback.
		h(hCPU, opcode);
	}

	static void executeInstruction(PPCInterpreter_t* hCPU)
	{
		if constexpr(ppcItpCtrl::allowSupervisorMode)
		{
			hCPU->global->tb++;
		}

#ifdef __DEBUG_OUTPUT_INSTRUCTION
		debug_printf("%08x: ", hCPU->instructionPointer);
#endif

		const uint32 ip = hCPU->instructionPointer;
		const uint32 opcode = ppcItpCtrl::memory_readCodeU32(hCPU, ip);

		// This is the whole hot path: bounds check, block pointer, entry, handler, tail call.
		// Anything that is not a hit leaves via executeUncached below, so that none of the cold
		// work costs the hit path a register or a stack frame.
		if (ip < PPCPredecode::kCodeAreaEnd) [[likely]]
		{
			uint64* block = s_blockTable[ip >> PPCPredecode::kBlockShift].load(std::memory_order_relaxed);
			if (block) [[likely]]
			{
				const uint64 entry = std::atomic_ref<uint64>(block[(ip & (PPCPredecode::kBlockSize - 1u)) >> 2]).load(std::memory_order_relaxed);
				// The entire validity check: the word this entry was decoded from is still the
				// word sitting in guest memory. If the title rewrote this instruction, a patch or
				// a breakpoint replaced it, or a different module was mapped over the address,
				// the comparison fails and it is decoded again.
				if ((uint32)entry == opcode) [[likely]]
				{
					// Masked rather than bounds-checked. Every index written here came from
					// internHandler and is already in range, so the mask is not what makes it
					// valid - it is there so that no value a 64-bit word in shared memory could
					// possibly hold can index outside the table, whatever goes wrong elsewhere.
					// kMaxHandlers is a power of two, so it costs one AND.
					const PPCInstructionHandler h = s_handlerTable[(uint32)(entry >> 32) & (kMaxHandlers - 1u)].load(std::memory_order_relaxed);
					if (h) [[likely]]
					{
						h(hCPU, opcode);
						return;
					}
				}
			}
		}
		executeUncached(hCPU, ip, opcode);
	}
};

} // anonymous namespace

// Slim interpreter, trades some features for extra performance
// Used when emulator runs in CafeOS HLE mode
// Assumes the following:
// - No MMU (linear memory with 1:1 mapping of physical to virtual)
// - No interrupts
// - Always runs in user mode
// - Paired single mode is always enabled
void PPCInterpreterSlim_executeInstruction(PPCInterpreter_t* hCPU)
{
	PPCInterpreterContainer<PPCItpCafeOSUsermode>::executeInstruction(hCPU);
}

// Full interpreter, supports most PowerPC features
// Used when emulator runs in LLE mode
void PPCInterpreterFull_executeInstruction(PPCInterpreter_t* hCPU)
{
	PPCInterpreterContainer<PPCItpSupervisorWithMMU>::executeInstruction(hCPU);
}
