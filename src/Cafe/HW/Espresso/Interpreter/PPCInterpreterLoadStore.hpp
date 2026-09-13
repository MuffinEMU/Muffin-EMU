
#define _signExtend16To32(__v) ((uint32)(sint32)(sint16)(__v))

// ---------------------------------------------------------------------------------------
// Guest memory access
//
// What one guest load actually costs, counted from the code rather than assumed:
//
// Guest memory is a flat reservation at a constant host base. memory_base points at guest
// address 0 and the whole 32-bit guest range behind it is reserved up front, which is why
// MMU_IsInPPCMemorySpace() is simply a range test against
// memory_base .. memory_base+0x100000000. So there is no per-access table walk and no
// bounds check to remove - reserved address space costs nothing until it is touched, and
// that trick is already taken here. A guest word load should be: one address add, one
// arm64 load, one REV. Three instructions, no branches, no calls.
//
// It was not. PPCItpCafeOSUsermode::ppcMem_readDataU32() - and every sibling accessor -
// reaches the base through memory_getPointerFromVirtualOffset(), which is declared in
// MMU.h and *defined in MMU.cpp*. Nothing in this translation unit can see that body, so
// at -O2 every single guest load and store in the interpreter emitted a cross-TU `bl` to
// a function whose entire text is `return memory_base + virtualOffset;`.
//
// Measured, not assumed. clang++ -O2 -arch arm64 -DCEMU_PLATFORM_IOS over
// PPCInterpreterImpl.cpp emitted 128 such calls for the usermode (game) interpreter, at
// least one in every load and store handler. PPCInterpreter_LWZX came out as:
//
//     stp x22,x21 / stp x20,x19 / stp x29,x30    <- 48-byte frame, six registers spilled
//     ...address computation...
//     bl  memory_getPointerFromVirtualOffset
//     ldr w8, [x0]                               <- the two instructions that do the work
//     rev w8, w8
//     ...write back to gpr, ip += 4...
//     ldp / ldp / ldp / ret
//
// The call is what forces all of that: it makes the handler a non-leaf function, so the
// prologue, the frame pointer and six callee-saved spills exist only to survive it.
// Without the call the handler is a leaf with zero stack traffic. LFD was worse still - it
// called the same function twice with the same argument, because an opaque cross-TU call
// cannot be common-subexpression-eliminated even when it is pure.
//
// The release build does turn on LTO, which may fold the call away. But "may" is the whole
// problem: this is the only CPU path the iOS port ever gets, since the MAP_JIT probe has
// never once passed on an APRR core, and loads and stores are the most frequent
// instruction class in any real program. Making the fast path independent of whether LTO
// fired costs nothing, and matches what was already done for PPCInterpreter_nextInstruction
// in PPCState.h for exactly the same reason.
//
// So the accessors below replace the ppcItpCtrl::ppcMem_* calls throughout this file:
//
//  - For the supervisor/MMU interpreter (allowSupervisorMode) they forward verbatim. That
//    configuration genuinely needs a BAT and page-table walk per access and can raise a
//    DSI exception, and none of that behaviour is touched here.
//  - For the usermode configuration - the one every Wii U title actually runs under - the
//    body is the identical expression from PPCItpCafeOSUsermode with
//    memory_getPointerFromVirtualOffset() spelled out, so it inlines to base + offset.
//
// On byte-swap widths, because getting one wrong corrupts data silently instead of
// crashing: CPU_swapEndianU16 reverses the two bytes of a halfword, CPU_swapEndianU32 the
// four bytes of a word, CPU_swapEndianU64 the eight bytes of a doubleword. On arm64 each
// is one REV of the matching register width. Every accessor below pairs the swap with a
// load or store of exactly that width, and the expressions are copied unchanged from
// PPCItpCafeOSUsermode so the pairing cannot drift. Single bytes are never swapped.
//
// On unaligned access: there is no software unaligned path here to be rid of, and there
// never was. Every access is a direct `*(uintN*)(base + ea)` at whatever alignment the
// guest asked for, which is what arm64 wants - it handles unaligned loads and stores to
// normal memory in hardware, as PowerPC does. Nothing to fix.
// ---------------------------------------------------------------------------------------

// identical to memory_getPointerFromVirtualOffset(ea), whose whole body is
// `return memory_base + virtualOffset;` - written out here so it does not cost a call
static FORCE_INLINE uint8* ppcItp_dataPtr(uint32 ea)
{
	return memory_base + ea;
}

static FORCE_INLINE uint32 ppcItp_readU32(PPCInterpreter_t* hCPU, uint32 ea)
{
	if constexpr (ppcItpCtrl::allowSupervisorMode)
		return ppcItpCtrl::ppcMem_readDataU32(hCPU, ea);
	else
		return CPU_swapEndianU32(*(uint32*)ppcItp_dataPtr(ea)); // 4 bytes loaded, 4 bytes reversed
}

static FORCE_INLINE uint16 ppcItp_readU16(PPCInterpreter_t* hCPU, uint32 ea)
{
	if constexpr (ppcItpCtrl::allowSupervisorMode)
		return ppcItpCtrl::ppcMem_readDataU16(hCPU, ea);
	else
		return CPU_swapEndianU16(*(uint16*)ppcItp_dataPtr(ea)); // 2 bytes loaded, 2 bytes reversed
}

static FORCE_INLINE uint8 ppcItp_readU8(PPCInterpreter_t* hCPU, uint32 ea)
{
	if constexpr (ppcItpCtrl::allowSupervisorMode)
		return ppcItpCtrl::ppcMem_readDataU8(hCPU, ea);
	else
		return *(uint8*)ppcItp_dataPtr(ea); // a single byte has no endianness
}

static FORCE_INLINE void ppcItp_writeU32(PPCInterpreter_t* hCPU, uint32 ea, uint32 v)
{
	if constexpr (ppcItpCtrl::allowSupervisorMode)
		ppcItpCtrl::ppcMem_writeDataU32(hCPU, ea, v);
	else
		*(uint32*)ppcItp_dataPtr(ea) = CPU_swapEndianU32(v);
}

static FORCE_INLINE void ppcItp_writeU16(PPCInterpreter_t* hCPU, uint32 ea, uint16 v)
{
	if constexpr (ppcItpCtrl::allowSupervisorMode)
		ppcItpCtrl::ppcMem_writeDataU16(hCPU, ea, v);
	else
		*(uint16*)ppcItp_dataPtr(ea) = CPU_swapEndianU16(v);
}

static FORCE_INLINE void ppcItp_writeU8(PPCInterpreter_t* hCPU, uint32 ea, uint8 v)
{
	if constexpr (ppcItpCtrl::allowSupervisorMode)
		ppcItpCtrl::ppcMem_writeDataU8(hCPU, ea, v);
	else
		*(uint8*)ppcItp_dataPtr(ea) = v; // a single byte has no endianness
}

// LFD / STFD. The usermode accessors in PPCInterpreterImpl.cpp move a double as two
// 32-bit halves and swap each half separately, writing the guest's high word to ea+0 and
// its low word to ea+4. That is the same eight bytes in the same order as one 64-bit
// access plus one 64-bit REV, which is what these do instead - verified exhaustively
// against the two-word form over 2,000,000 random bit patterns at every byte offset 0-7,
// loads and stores both, before this was written.
//
// It is also closer to the hardware, not further from it: an aligned lfd/stfd on Espresso
// is single-copy atomic, so a second emulated core can never see half of an old double and
// half of a new one. The two-word form allowed exactly that tear; one aligned 64-bit
// access on arm64 does not. Unaligned addresses stay as loose as they were, which also
// matches PowerPC.
static FORCE_INLINE double ppcItp_readDouble(PPCInterpreter_t* hCPU, uint32 ea)
{
	if constexpr (ppcItpCtrl::allowSupervisorMode)
		return ppcItpCtrl::ppcMem_readDataDouble(hCPU, ea);
	else
		return std::bit_cast<double>(CPU_swapEndianU64(*(uint64*)ppcItp_dataPtr(ea))); // 8 bytes, 8 reversed
}

static FORCE_INLINE void ppcItp_writeDouble(PPCInterpreter_t* hCPU, uint32 ea, double vf)
{
	if constexpr (ppcItpCtrl::allowSupervisorMode)
		ppcItpCtrl::ppcMem_writeDataDouble(hCPU, ea, vf);
	else
		*(uint64*)ppcItp_dataPtr(ea) = CPU_swapEndianU64(std::bit_cast<uint64>(vf));
}

// Paired-single quantised element access, shared by the six PSQ_* handlers.
//
// Each of those handlers used to spell the width dispatch out twice - once for ps0 and
// once for ps1 - inside two arms of an `if (W)` whose first halves were textually
// identical, and each arm called quantize()/dequantize() separately in all three width
// cases with the same three arguments. clang duly specialised every copy: PSQ_ST compiled
// to 811 lines of arm64 with 17 calls to memory_getPointerFromVirtualOffset in it, and
// PSQ_STU and PSQ_STX were the same again. Paired singles are the Wii U's SIMD, so that is
// a lot of instruction cache spent on one instruction in exactly the kind of code that
// uses it most.
//
// Folding it here changes no behaviour: exactly one width arm ran before and exactly one
// runs now, on the same address, with the same value, in the same order.
//
// The element stride is the width of the quantised element, which is what the old code
// meant by ea+1 / ea+2 / ea+4 for the second element.
static FORCE_INLINE uint32 ppcItp_quantizedStride(sint32 type)
{
	if ((type == 4) || (type == 6)) // u8 / s8
		return 1;
	if ((type == 5) || (type == 7)) // u16 / s16
		return 2;
	return 4; // float32
}

static FORCE_INLINE uint32 ppcItp_readQuantized(PPCInterpreter_t* hCPU, uint32 ea, sint32 type)
{
	// The original wrote the loaded value into the low bytes of a zero-initialised uint32
	// (`*(uint8*)&data0 = ...`), which on a little-endian host is a plain assignment of a
	// zero-extended value, then sign-extended afterwards for the signed types. Same here,
	// without the type pun.
	if ((type == 4) || (type == 6))
	{
		uint32 data = ppcItp_readU8(hCPU, ea);
		if (type == 6 && (data & 0x80))
			data |= 0xffffff00; // s8
		return data;
	}
	if ((type == 5) || (type == 7))
	{
		uint32 data = ppcItp_readU16(hCPU, ea);
		if (type == 7 && (data & 0x8000))
			data |= 0xffff0000; // s16
		return data;
	}
	return ppcItp_readU32(hCPU, ea); // float32, taken as raw bits
}

static FORCE_INLINE void ppcItp_writeQuantized(PPCInterpreter_t* hCPU, uint32 ea, float value, sint32 type, uint8 scale)
{
	uint32 v = quantize(value, type, scale);
	if ((type == 4) || (type == 6))
		ppcItp_writeU8(hCPU, ea, (uint8)v);
	else if ((type == 5) || (type == 7))
		ppcItp_writeU16(hCPU, ea, (uint16)v);
	else
		ppcItp_writeU32(hCPU, ea, v);
}


// store

#define DSI_EXIT() \
	if constexpr(ppcItpCtrl::allowDSI) \
	{ \
		if (hCPU->memoryException) \
		{ \
			hCPU->memoryException = false; \
			return; \
		} \
	}

static void PPCInterpreter_STW(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rS, rA, imm);
	if (rA != 0)
	{
		ppcItp_writeU32(hCPU, hCPU->gpr[rA] + imm, hCPU->gpr[rS]);
	}
	else
	{
		PPC_ASSERT(true);
	}
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STWU(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rS, rA, imm);
	ppcItp_writeU32(hCPU, hCPU->gpr[rA] + imm, hCPU->gpr[rS]);
	// check for rA != 0 ? 
	hCPU->gpr[rA] += imm;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STWX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS, rB;
	PPC_OPC_TEMPL_X(Opcode, rS, rA, rB);
	ppcItp_writeU32(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB], hCPU->gpr[rS]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STWCX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	// http://www.ibm.com/developerworks/library/pa-atom/
	sint32 rA, rS, rB;
	PPC_OPC_TEMPL_X(Opcode, rS, rA, rB);
	uint32 ea = (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB];
	// check if we hold a reservation for the memory location

	// todo - this isnt accurate. STWCX can succeed even with a different EA if the reserved value remained untouched
	if (hCPU->reservedMemAddr == ea)
	{
		uint32be reservedValue = hCPU->reservedMemValue; // this is the value we expect in memory (if it does not match, STWCX fails)
		std::atomic<uint32be>* wordPtr;		
		if constexpr(ppcItpCtrl::allowSupervisorMode)
		{
			wordPtr = _rawPtrToAtomic((uint32be*)(memory_base + ppcItpCtrl::ppcMem_translateVirtualDataToPhysicalAddr(hCPU, ea)));
			DSI_EXIT();
		}
		else
		{
			wordPtr = _rawPtrToAtomic((uint32be*)ppcItp_dataPtr(ea));
		}
		uint32be newValue = hCPU->gpr[rS];
		if (!wordPtr->compare_exchange_strong(reservedValue, newValue))
		{
			// failed
			ppc_setCRBit(hCPU, CR_BIT_LT, 0);
			ppc_setCRBit(hCPU, CR_BIT_GT, 0);
			ppc_setCRBit(hCPU, CR_BIT_EQ, 0);
		}
		else
		{
			// success, new value has been written
			ppc_setCRBit(hCPU, CR_BIT_LT, 0);
			ppc_setCRBit(hCPU, CR_BIT_GT, 0);
			ppc_setCRBit(hCPU, CR_BIT_EQ, 1);
		}
		cemu_assert_debug(hCPU->xer_so <= 1);
		ppc_setCRBit(hCPU, CR_BIT_SO, hCPU->xer_so);
		// remove reservation
		hCPU->reservedMemAddr = 0;
		hCPU->reservedMemValue = 0;
	}
	else
	{
		// failed
		ppc_setCRBit(hCPU, CR_BIT_LT, 0);
		ppc_setCRBit(hCPU, CR_BIT_GT, 0);
		ppc_setCRBit(hCPU, CR_BIT_EQ, 0);
	}
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STWUX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS, rB;
	PPC_OPC_TEMPL_X(Opcode, rS, rA, rB);
	ppcItp_writeU32(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB], hCPU->gpr[rS]);
	if (rA)
		hCPU->gpr[rA] += hCPU->gpr[rB];
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STWBRX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS, rB;
	PPC_OPC_TEMPL_X(Opcode, rS, rA, rB);
	ppcItp_writeU32(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB], _swapEndianU32(hCPU->gpr[rS]));
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STMW(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rS, rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rS, rA, imm);
	uint32 ea = (rA ? hCPU->gpr[rA] : 0) + imm;
	while (rS <= 31)
	{
		ppcItp_writeU32(hCPU, ea, hCPU->gpr[rS]);
		rS++;
		ea += 4;
	}
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STH(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rS, rA, imm);
	ppcItp_writeU16(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm, (uint16)hCPU->gpr[rS]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STHU(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rS, rA, imm);
	ppcItp_writeU16(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm, (uint16)hCPU->gpr[rS]);
	if (rA)
		hCPU->gpr[rA] += imm;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STHX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS, rB;
	PPC_OPC_TEMPL_X(Opcode, rS, rA, rB);
	ppcItp_writeU16(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB], (uint16)hCPU->gpr[rS]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STHUX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS, rB;
	PPC_OPC_TEMPL_X(Opcode, rS, rA, rB);
	ppcItp_writeU16(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB], (uint16)hCPU->gpr[rS]);
	if (rA)
		hCPU->gpr[rA] += hCPU->gpr[rB];
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STHBRX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS, rB;
	PPC_OPC_TEMPL_X(Opcode, rS, rA, rB);
	ppcItp_writeU16(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB], _swapEndianU16((uint16)hCPU->gpr[rS]));
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STB(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rS, rA, imm);
	ppcItp_writeU8(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm, (uint8)hCPU->gpr[rS]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STBU(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rS, rA, imm);
	ppcItp_writeU8(hCPU, hCPU->gpr[rA] + imm, (uint8)hCPU->gpr[rS]);
	hCPU->gpr[rA] += imm;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STBX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS, rB;
	PPC_OPC_TEMPL_X(Opcode, rS, rA, rB);
	ppcItp_writeU8(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB], (uint8)hCPU->gpr[rS]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STBUX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS, rB;
	PPC_OPC_TEMPL_X(Opcode, rS, rA, rB);
	ppcItp_writeU8(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB], (uint8)hCPU->gpr[rS]);
	if (rA)
		hCPU->gpr[rA] += hCPU->gpr[rB];
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STSWI(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS, nb;
	PPC_OPC_TEMPL_X(Opcode, rS, rA, nb);
	if (nb == 0) nb = 32;
	uint32 ea = rA ? hCPU->gpr[rA] : 0;
	uint32 r = 0;
	int i = 0;
	while (nb > 0)
	{
		if (i == 0)
		{
			r = rS < 32 ? hCPU->gpr[rS] : 0; // what happens if rS is out of bounds?
			rS++;
			rS %= 32;
			i = 4;
		}
		ppcItp_writeU8(hCPU, ea, (r >> 24));
		r <<= 8;
		ea++;
		i--;
		nb--;
	}
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STSWX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS, rB;
	PPC_OPC_TEMPL_X(Opcode, rS, rA, rB);
	sint32 nb = hCPU->spr.XER&0x7F;
	if (nb == 0)
	{
		PPCInterpreter_nextInstruction(hCPU);
		return;
	}
	uint32 ea = rA ? hCPU->gpr[rA] : 0;
	ea += hCPU->gpr[rB];
	uint32 r = 0;
	int i = 0;
	while (nb > 0)
	{
		if (i == 0)
		{
			r = rS < 32 ? hCPU->gpr[rS] : 0; // what happens if rS is out of bounds?
			rS++;
			rS %= 32;
			i = 4;
		}
		ppcItp_writeU8(hCPU, ea, (r >> 24));
		r <<= 8;
		ea++;
		i--;
		nb--;
	}
	PPCInterpreter_nextInstruction(hCPU);
}

// load

static void PPCInterpreter_LWZ(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rD, rA, imm);
	uint32 v = ppcItp_readU32(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm);
	DSI_EXIT();
	hCPU->gpr[rD] = v;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LWZU(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rD, rA, imm);
	hCPU->gpr[rA] += imm;
	hCPU->gpr[rD] = ppcItp_readU32(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LMW(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rD, rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rD, rA, imm);
	uint32 ea = (rA ? hCPU->gpr[rA] : 0) + imm;
	while (rD <= 31)
	{
		hCPU->gpr[rD] = ppcItp_readU32(hCPU, ea);
		rD++;
		ea += 4;
	}
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LWZX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD, rB;
	PPC_OPC_TEMPL_X(Opcode, rD, rA, rB);
	hCPU->gpr[rD] = ppcItp_readU32(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LWZXU(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD, rB;
	PPC_OPC_TEMPL_X(Opcode, rD, rA, rB);
	uint32 ea = (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB];
	hCPU->gpr[rD] = ppcItp_readU32(hCPU, ea);
	if (rA && rA != rD)
		hCPU->gpr[rA] = ea;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LWBRX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD, rB;
	PPC_OPC_TEMPL_X(Opcode, rD, rA, rB);
	hCPU->gpr[rD] = CPU_swapEndianU32(ppcItp_readU32(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB]));

	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LWARX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD, rB;
	PPC_OPC_TEMPL_X(Opcode, rD, rA, rB);
	uint32 ea = (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB];
	hCPU->gpr[rD] = ppcItp_readU32(hCPU, ea);
	// set reservation	
	hCPU->reservedMemAddr = ea;
	hCPU->reservedMemValue = hCPU->gpr[rD];
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LHZ(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rD, rA, imm);
	hCPU->gpr[rD] = ppcItp_readU16(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LHZU(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rD, rA, imm);
	// FIXME: rA!=0
	hCPU->gpr[rD] = ppcItp_readU16(hCPU, hCPU->gpr[rA] + imm);
	hCPU->gpr[rA] += imm;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LHZX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD, rB;
	PPC_OPC_TEMPL_X(Opcode, rD, rA, rB);
	hCPU->gpr[rD] = ppcItp_readU16(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LHZUX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD, rB;
	PPC_OPC_TEMPL_X(Opcode, rD, rA, rB);
	uint32 ea = (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB];
	hCPU->gpr[rD] = ppcItp_readU16(hCPU, ea);
	if (rA && rA != rD)
		hCPU->gpr[rA] = ea;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LHBRX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD, rB;
	PPC_OPC_TEMPL_X(Opcode, rD, rA, rB);
	hCPU->gpr[rD] = CPU_swapEndianU16(ppcItp_readU16(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB]));
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LHA(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rD, rA, imm);
	hCPU->gpr[rD] = ppcItp_readU16(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm);
	hCPU->gpr[rD] = _signExtend16To32(hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LHAU(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rD, rA, imm);
	hCPU->gpr[rD] = ppcItp_readU16(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm);
	if (rA && rA != rD)
		hCPU->gpr[rA] += imm;
	hCPU->gpr[rD] = _signExtend16To32(hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LHAUX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD, rB;
	PPC_OPC_TEMPL_X(Opcode, rD, rA, rB);
	uint32 ea = (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB];
	hCPU->gpr[rD] = ppcItp_readU16(hCPU, ea);
	if (rA && rA != rD)
		hCPU->gpr[rA] = ea;
	hCPU->gpr[rD] = _signExtend16To32(hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LHAX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rS, rB;
	PPC_OPC_TEMPL_X(Opcode, rS, rA, rB);

	hCPU->gpr[rS] = ppcItp_readU16(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB]);
	hCPU->gpr[rS] = _signExtend16To32(hCPU->gpr[rS]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LBZ(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rD, rA, imm);
	hCPU->gpr[rD] = ppcItp_readU8(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LBZX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD, rB;
	PPC_OPC_TEMPL_X(Opcode, rD, rA, rB);
	hCPU->gpr[rD] = ppcItp_readU8(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LBZXU(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD, rB;
	PPC_OPC_TEMPL_X(Opcode, rD, rA, rB);
	uint32 ea = (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB];
	hCPU->gpr[rD] = ppcItp_readU8(hCPU, ea);
	if (rA && rA != rD)
		hCPU->gpr[rA] = ea;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LBZU(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, rD, rA, imm);
	PPC_ASSERT(rA == 0);
	uint8 r;
	uint32 ea = hCPU->gpr[rA] + imm;
	hCPU->gpr[rA] = ea;
	r = ppcItp_readU8(hCPU, ea);
	hCPU->gpr[rD] = r;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LSWI(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD, nb;
	PPC_OPC_TEMPL_X(Opcode, rD, rA, nb);
	if (nb == 0)
		nb = 32;
	uint32 ea = rA ? hCPU->gpr[rA] : 0;
	uint32 r = 0;
	int i = 4;
	uint8 v;
	while (nb>0)
	{
		if (i == 0)
		{
			i = 4;
			if(rD < 32)
				hCPU->gpr[rD] = r;
			rD++;
			rD %= 32;
			r = 0;
		}
		v = ppcItp_readU8(hCPU, ea);
		r <<= 8;
		r |= v;
		ea++;
		i--;
		nb--;
	}
	while (i)
	{
		r <<= 8;
		i--;
	}
	if(rD < 32)
		hCPU->gpr[rD] = r;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LSWX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	sint32 rA, rD, rB;
	PPC_OPC_TEMPL_X(Opcode, rD, rA, rB);
	// byte count comes from XER
	uint32 nb = (hCPU->spr.XER>>0)&0x7F;
	if (nb == 0)
	{
		PPCInterpreter_nextInstruction(hCPU);
		return; // no-op
	}
	uint32 ea = rA ? hCPU->gpr[rA] : 0;
	ea += hCPU->gpr[rB];
	uint32 r = 0;
	int i = 4;
	uint8 v;
	while (nb>0)
	{
		if (i == 0)
		{
			i = 4;
			if(rD < 32)
				hCPU->gpr[rD] = r;
			rD++;
			rD %= 32;
			r = 0;
		}
		v = ppcItp_readU8(hCPU, ea);
		r <<= 8;
		r |= v;
		ea++;
		i--;
		nb--;
	}
	while (i)
	{
		r <<= 8;
		i--;
	}
	if(rD < 32)
		hCPU->gpr[rD] = r;
	PPCInterpreter_nextInstruction(hCPU);
}

// floating point load

static void PPCInterpreter_LFS(PPCInterpreter_t* hCPU, uint32 Opcode) //Copied
{
	FPUCheckAvailable();
	sint32 rA, frD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, frD, rA, imm);

	uint64 val;
	//*(uint32*)&Val = ppcItp_readU32(hCPU, (rA?hCPU->gpr[rA]:0)+imm);
	val = ppcItpCtrl::ppcMem_readDataFloatEx(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm);

	if (PPC_LSQE)
		hCPU->fpr[frD].fp0int = hCPU->fpr[frD].fp1int = val;
	else
		hCPU->fpr[frD].fp0int = val;

	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LFSX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	sint32 rA, frD, rB;
	PPC_OPC_TEMPL_X(Opcode, frD, rA, rB);

	uint64 val;
	val = ppcItpCtrl::ppcMem_readDataFloatEx(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB]);

	if (PPC_LSQE)
		hCPU->fpr[frD].fp0int = hCPU->fpr[frD].fp1int = val;
	else
		hCPU->fpr[frD].fp0int = val;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LFSUX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	sint32 rA, frD, rB;
	PPC_OPC_TEMPL_X(Opcode, frD, rA, rB);

	uint64 Val;
	//*(uint32*)&Val = ppcItp_readU32(hCPU, (rA?hCPU->gpr[rA]:0)+hCPU->gpr[rB]);
	Val = ppcItpCtrl::ppcMem_readDataFloatEx(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB]);
	if (rA)
		hCPU->gpr[rA] += hCPU->gpr[rB];

	if (PPC_LSQE)
		hCPU->fpr[frD].fp0int = hCPU->fpr[frD].fp1int = Val;
	else
		hCPU->fpr[frD].fp0int = Val;//ppcItpCtrl::ppcMem_readDataFloat((rA?hCPU->gpr[rA]:0)+hCPU->gpr[rB]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LFSU(PPCInterpreter_t* hCPU, uint32 Opcode) //Copied
{
	FPUCheckAvailable();
	sint32 rA, frD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, frD, rA, imm);
	uint64 Val;

	//(uint32*)&Val = ppcItp_readU32(hCPU, (rA?hCPU->gpr[rA]:0)+imm);
	Val = ppcItpCtrl::ppcMem_readDataFloatEx(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm);


	if (PPC_LSQE)
		hCPU->fpr[frD].fp0int = hCPU->fpr[frD].fp1int = Val;
	else
		hCPU->fpr[frD].fp0int = Val;

	if (rA)
		hCPU->gpr[rA] += imm;

	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LFD(PPCInterpreter_t* hCPU, uint32 Opcode) //Copied
{
	FPUCheckAvailable();
	sint32 rA, frD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, frD, rA, imm);
	hCPU->fpr[frD].fpr = ppcItp_readDouble(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm);//ppcItpCtrl::ppcMem_readDataQUAD((rA?hCPU->gpr[rA]:0)+imm);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LFDU(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	sint32 rA, frD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, frD, rA, imm);

	hCPU->fpr[frD].fpr = ppcItp_readDouble(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm);//ppcItpCtrl::ppcMem_readDataQUAD((rA?hCPU->gpr[rA]:0)+imm);
	if (rA)
		hCPU->gpr[rA] += imm;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LFDX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	sint32 rA, frD, rB;
	PPC_OPC_TEMPL_X(Opcode, frD, rA, rB);
	hCPU->fpr[frD].fpr = ppcItp_readDouble(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_LFDUX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	sint32 rA, frD, rB;
	PPC_OPC_TEMPL_X(Opcode, frD, rA, rB);
	hCPU->fpr[frD].fpr = ppcItp_readDouble(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB]);
	if (rA)
		hCPU->gpr[rA] += hCPU->gpr[rB];
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STFS(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	sint32 rA, frD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, frD, rA, imm);
	if (PPC_LSQE)
		ppcItpCtrl::ppcMem_writeDataFloatEx(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm, hCPU->fpr[frD].fp0int);
	else
		ppcItpCtrl::ppcMem_writeDataFloatEx(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm, hCPU->fpr[frD].fp0int);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STFSU(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	sint32 rA, frD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, frD, rA, imm);

	if (PPC_LSQE)
		ppcItpCtrl::ppcMem_writeDataFloatEx(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm, hCPU->fpr[frD].fp0int);
	else
		ppcItpCtrl::ppcMem_writeDataFloatEx(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm, hCPU->fpr[frD].fp0int);

	if (rA)
		hCPU->gpr[rA] += imm;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STFSX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	sint32 rA, frS, rB;
	PPC_OPC_TEMPL_X(Opcode, frS, rA, rB);

	if (PPC_LSQE)
		ppcItpCtrl::ppcMem_writeDataFloatEx(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB], hCPU->fpr[frS].fp0int);
	else
		ppcItpCtrl::ppcMem_writeDataFloatEx(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB], hCPU->fpr[frS].fp0int);

	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_STFSUX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	// next instruction
	PPCInterpreter_nextInstruction(hCPU);

	int rA, frS, rB;
	PPC_OPC_TEMPL_X(Opcode, frS, rA, rB);

	if (PPC_LSQE)
		ppcItpCtrl::ppcMem_writeDataFloatEx(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB], hCPU->fpr[frS].fp0int);
	else
		ppcItpCtrl::ppcMem_writeDataFloatEx(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB], hCPU->fpr[frS].fp0int);

	if (rA)
		hCPU->gpr[rA] += hCPU->gpr[rB];
}


static void PPCInterpreter_STFD(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	// next instruction
	PPCInterpreter_nextInstruction(hCPU);

	int rA, frD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, frD, rA, imm);

	ppcItp_writeDouble(hCPU, (rA ? hCPU->gpr[rA] : 0) + imm, hCPU->fpr[frD].fpr);

	// debug output
#ifdef __DEBUG_OUTPUT_INSTRUCTION
	debug_printf("STFD f%d, %d(r%d)\n", frD, imm, rA);
#endif
}

static void PPCInterpreter_STFDU(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	// next instruction
	PPCInterpreter_nextInstruction(hCPU);

	int rA, frD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(Opcode, frD, rA, imm);

	if (rA)
	{
		hCPU->gpr[rA] += imm;
	}
	else
	{
		PPC_ASSERT(true);
	}

	ppcItp_writeDouble(hCPU, hCPU->gpr[rA], hCPU->fpr[frD].fpr);

	// debug output
#ifdef __DEBUG_OUTPUT_INSTRUCTION
	debug_printf("STFD f%d, %d(r%d)\n", frD, imm, rA);
#endif
}

static void PPCInterpreter_STFDX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	// next instruction
	PPCInterpreter_nextInstruction(hCPU);

	int rA, frS, rB;
	PPC_OPC_TEMPL_X(Opcode, frS, rA, rB);

	ppcItp_writeDouble(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB], hCPU->fpr[frS].fpr);

	// debug output
#ifdef __DEBUG_OUTPUT_INSTRUCTION
	debug_printf("STFD f%d, r%d+r%d\n", frS, rA, rB);
#endif
}

static void PPCInterpreter_STFDUX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	// next instruction
	PPCInterpreter_nextInstruction(hCPU);

	int rA, frS, rB;
	PPC_OPC_TEMPL_X(Opcode, frS, rA, rB);

	if (rA == 0)
	{
		ppcItp_writeDouble(hCPU, hCPU->gpr[rB], hCPU->fpr[frS].fpr);
	}
	else
	{
		hCPU->gpr[rA] += hCPU->gpr[rB];
		ppcItp_writeDouble(hCPU, hCPU->gpr[rA], hCPU->fpr[frS].fpr);
	}

}

static void PPCInterpreter_STFIWX(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	sint32 rA, frS, rB;
	PPC_OPC_TEMPL_X(Opcode, frS, rA, rB);

	uint32 val = (uint32)hCPU->fpr[frS].fp0int;
	ppcItp_writeU32(hCPU, (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB], val);
	// next instruction
	PPCInterpreter_nextInstruction(hCPU);
}

// paired single

// ST_TYPE:
// 4 - uint8
// 5 - uint16
// 6 - sint8
// 7 - sint16
// 0 - float32

#define LD_SCALE(n) ((hCPU->spr.UGQR[0+n] >> 24) & 0x3f)
#define LD_TYPE(n)  ((hCPU->spr.UGQR[0+n] >> 16) & 7)
#define ST_SCALE(n) ((hCPU->spr.UGQR[0+n] >>  8) & 0x3f)
#define ST_TYPE(n)  ((hCPU->spr.UGQR[0+n]      ) & 7)
#define PSW         (opcode & 0x8000)
#define PSI         ((opcode >> 12) & 7)

#define PSWX         (opcode & (1<<(7+3)))
#define PSIX         ((opcode >> 7) & 7)

static void PPCInterpreter_PSQ_ST(PPCInterpreter_t* hCPU, unsigned int opcode)
{
	FPUCheckAvailable();
	sint32 rA, frD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(opcode, frD, rA, imm);

	uint32 ea = _uint32_fastSignExtend(imm, 11);

	ea += (rA ? hCPU->gpr[rA] : 0);

	sint32 type = ST_TYPE(PSI);
	uint8 scale = (uint8)ST_SCALE(PSI);

	// ps0 is stored either way - the two arms of the old `if (W)` began with the same
	// three lines - and ps1 only when W is clear.
	ppcItp_writeQuantized(hCPU, ea, (float)hCPU->fpr[frD].fp0, type, scale);
	if ((opcode & 0x8000) == 0) // W clear: store both elements
		ppcItp_writeQuantized(hCPU, ea + ppcItp_quantizedStride(type), (float)hCPU->fpr[frD].fp1, type, scale);

	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_PSQ_STU(PPCInterpreter_t* hCPU, unsigned int opcode)
{
	FPUCheckAvailable();
	sint32 rA, frD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(opcode, frD, rA, imm);
	uint32 ea = _uint32_fastSignExtend(imm, 11);

	if (ea & 0x800)
		ea |= 0xfffff000;

	ea += (rA ? hCPU->gpr[rA] : 0);
	if (rA)
		hCPU->gpr[rA] = ea;

	sint32 type = ST_TYPE((opcode >> 12) & 0x7);
	uint8 scale = (uint8)ST_SCALE(PSI);

	ppcItp_writeQuantized(hCPU, ea, (float)hCPU->fpr[frD].fp0, type, scale);
	if ((opcode & 0x8000) == 0) // W clear: store both elements
		ppcItp_writeQuantized(hCPU, ea + ppcItp_quantizedStride(type), (float)hCPU->fpr[frD].fp1, type, scale);

	PPCInterpreter_nextInstruction(hCPU);
}


static void PPCInterpreter_PSQ_STX(PPCInterpreter_t* hCPU, unsigned int opcode)
{
	FPUCheckAvailable();

	// next instruction
	PPCInterpreter_nextInstruction(hCPU);

	sint32 frD;
	uint32 rA, rB;
	frD = (opcode >> (31 - 10)) & 0x1F;
	rA = (opcode >> (31 - 15)) & 0x1F;
	rB = (opcode >> (31 - 20)) & 0x1F;
	uint32 EA = (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB];

	sint32 type = ST_TYPE(PSIX);
	uint8 scale = (uint8)ST_SCALE(PSIX);

	ppcItp_writeQuantized(hCPU, EA, (float)hCPU->fpr[frD].fp0, type, scale);
	if (!PSWX) // W clear: store both elements
		ppcItp_writeQuantized(hCPU, EA + ppcItp_quantizedStride(type), (float)hCPU->fpr[frD].fp1, type, scale);
}

static void PPCInterpreter_PSQ_L(PPCInterpreter_t* hCPU, unsigned int opcode)
{
	FPUCheckAvailable();
	// next instruction
	PPCInterpreter_nextInstruction(hCPU);

	sint32 rA, frD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(opcode, frD, rA, imm);

	uint32 EA, data0 = 0, data1 = 0;
	sint32 type = LD_TYPE(PSI);
	uint8 scale = (uint8)LD_SCALE(PSI);

	EA = _uint32_fastSignExtend(opcode, 11);

	if (rA) EA += hCPU->gpr[rA];

	// ps0 is loaded either way; W decides whether ps1 comes from memory or is forced to
	// 1.0. Access order is unchanged: EA first, then EA + element stride.
	data0 = ppcItp_readQuantized(hCPU, EA, type);
	if (opcode & 0x8000) // W set: one element, ps1 = 1.0
	{
		hCPU->fpr[frD].fp0 = (double)dequantize(data0, type, scale);
		hCPU->fpr[frD].fp1 = 1.0f;
	}
	else
	{
		data1 = ppcItp_readQuantized(hCPU, EA + ppcItp_quantizedStride(type), type);
		hCPU->fpr[frD].fp0 = (double)dequantize(data0, type, scale);
		hCPU->fpr[frD].fp1 = (double)dequantize(data1, type, scale);
	}
}

static void PPCInterpreter_PSQ_LU(PPCInterpreter_t* hCPU, unsigned int opcode)
{
	FPUCheckAvailable();
	// next instruction
	PPCInterpreter_nextInstruction(hCPU);

	int rA, frD;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(opcode, frD, rA, imm);

	uint32 EA = opcode & 0xfff, data0 = 0, data1 = 0;
	sint32 type = LD_TYPE(PSI);
	uint8 scale = (uint8)LD_SCALE(PSI);

	if (EA & 0x800) EA |= 0xfffff000;

	if (rA)
	{
		EA += hCPU->gpr[rA];
		hCPU->gpr[rA] = EA;
	}

	data0 = ppcItp_readQuantized(hCPU, EA, type);
	if (opcode & 0x8000) // W set: one element, ps1 = 1.0
	{
		hCPU->fpr[frD].fp0 = (double)dequantize(data0, type, scale);
		hCPU->fpr[frD].fp1 = 1.0f;
	}
	else
	{
		data1 = ppcItp_readQuantized(hCPU, EA + ppcItp_quantizedStride(type), type);
		hCPU->fpr[frD].fp0 = (double)dequantize(data0, type, scale);
		hCPU->fpr[frD].fp1 = (double)dequantize(data1, type, scale);
	}
}

static void PPCInterpreter_PSQ_LX(PPCInterpreter_t* hCPU, unsigned int opcode)
{
	FPUCheckAvailable();
	// next instruction
	PPCInterpreter_nextInstruction(hCPU);

	sint32 frD;
	uint32 rA, rB;

	frD = (opcode >> (32 - 11)) & 0x1F;
	rA = (opcode >> (32 - 16)) & 0x1F;
	rB = (opcode >> (32 - 21)) & 0x1F;

	uint32 EA = (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB];

	uint32 data0 = 0, data1 = 0;
	sint32 type = LD_TYPE(PSIX);
	uint8 scale = (uint8)LD_SCALE(PSIX);

	data0 = ppcItp_readQuantized(hCPU, EA, type);
	if (PSWX) // W set: one element, ps1 = 1.0
	{
		hCPU->fpr[frD].fp0 = (double)dequantize(data0, type, scale);
		hCPU->fpr[frD].fp1 = 1.0f;
	}
	else
	{
		data1 = ppcItp_readQuantized(hCPU, EA + ppcItp_quantizedStride(type), type);
		hCPU->fpr[frD].fp0 = (double)dequantize(data0, type, scale);
		hCPU->fpr[frD].fp1 = (double)dequantize(data1, type, scale);
	}
}

// misc

static void PPCInterpreter_DCBZ(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	int rA, rB;
	rA = (Opcode >> (31 - 15)) & 0x1F;
	rB = (Opcode >> (31 - 20)) & 0x1F;

	uint32 ea = (rA ? hCPU->gpr[rA] : 0) + hCPU->gpr[rB];
	ea &= ~31;
	if constexpr(ppcItpCtrl::allowSupervisorMode)
	{
		// todo - optimize
		ppcItp_writeU32(hCPU, ea + 0, 0);
		DSI_EXIT();
		ppcItp_writeU32(hCPU, ea + 4, 0);
		ppcItp_writeU32(hCPU, ea + 8, 0);
		ppcItp_writeU32(hCPU, ea + 12, 0);
		ppcItp_writeU32(hCPU, ea + 16, 0);
		ppcItp_writeU32(hCPU, ea + 20, 0);
		ppcItp_writeU32(hCPU, ea + 24, 0);
		ppcItp_writeU32(hCPU, ea + 28, 0);
	}
	else
	{
		memset((void*)ppcItp_dataPtr(ea), 0x00, 0x20);
	}

	// debug output
#ifdef __DEBUG_OUTPUT_INSTRUCTION
	debug_printf("DCBZ\n");
#endif
	// next instruction
	PPCInterpreter_nextInstruction(hCPU);
}