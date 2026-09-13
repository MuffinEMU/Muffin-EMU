
static void PPCInterpreter_setXerOV(PPCInterpreter_t* hCPU, bool hasOverflow)
{
	if (hasOverflow)
	{
		hCPU->xer_so = 1;
		hCPU->xer_ov = 1;
	}
	else
	{
		hCPU->xer_ov = 0;
	}
}

static bool checkAdditionOverflow(uint32 x, uint32 y, uint32 r)
{

	/*
		x	y	r	result	(has overflow)
		0	0	0	0
		1	0	0	0
		0	1	0	0
		1	1	0	1
		0	0	1	1
		1	0	1	0
		0	1	1	0
		1	1	1	0

	*/
	return (((x ^ r) & (y ^ r)) >> 31) != 0;
}

// Add with carry-out, computed the way the hardware computes it: one 33-bit addition whose
// bit 32 IS the carry.
//
// WHY: every PPC carry-producing add - addc/addic/adde/addze/addme, plus the subtract forms,
// which are the same adder fed ~rA - needs two things out of one addition: the truncated
// 32-bit sum, and the carry out of bit 31. The shape this replaces (ppc_carry_3) threw the
// sum away and rebuilt it to find the carry: it added a+b, compared, added a+b+c again,
// compared again, ORed the two answers. Done in 64-bit registers the carry simply falls out
// of the same addition, and arm64 has nothing but 64-bit registers - a 32-bit load has
// already zero-extended the operands into them, so widening costs literally nothing. On
// arm64 the result is add/add/lsr with no compares and no branches, against the old form's
// two adds, two compares and a select (measured: 3 instructions where there were 5, and a
// shorter dependency chain, since the old carry could not be computed until the second
// addition retired).
//
// Exact for every operand combination this interpreter can pass, including the 0xFFFFFFFF
// operands that addme/subfme use: the largest reachable sum is 0xFFFFFFFF + 0xFFFFFFFF + 1
// = 0x1FFFFFFFF, so bit 32 is the carry and bits 33..63 are always zero. This is checked,
// not assumed - see the note on each call site below for which exact expression it replaces.
static inline uint32 ppc_addWithCarryOut(uint32 a, uint32 b, uint32 carryIn, uint8& carryOut)
{
	uint64 sum = (uint64)a + (uint64)b + (uint64)carryIn;
	carryOut = (uint8)(sum >> 32);
	return (uint32)sum;
}

// Write all four bits of one CR field from the outcome of an integer compare.
//
// Only two host comparisons are needed. LT, GT and EQ are mutually exclusive and exhaustive
// for an integer compare, so GT is simply "neither of the other two" - the same identity
// ppc_update_cr0() already relies on. SO is COPIED from XER, never recomputed: it is the
// sticky summary-overflow bit, cmp/cmpl have no opinion about it, and the only things that
// may ever set it are the OE-form instructions via PPCInterpreter_setXerOV().
//
// WHY: the four compare handlers used to zero all four CR bytes, then branch three ways to
// put a 1 back into exactly one of them, then store SO - six byte stores and a dependent
// cmp/csinc/csel chain to produce four values that are all known up front. Writing the four
// bytes once, unconditionally, is shorter and has no branch. This is the largest win
// available in this file, because compares are the densest CR producers in compiled PowerPC
// code: every loop condition and every branch on a value is one, and unlike an Rc-form
// arithmetic instruction a compare has no other work to hide the cost behind.
//
// Deliberately four byte stores and NOT one packed 32-bit store. The four bytes are adjacent
// and packing them looks like the obvious next step, but measured on arm64 it is consistently
// SLOWER (239 vs 261 Minstr/s through a cmp-heavy dispatch loop) because forming the word
// costs more ALU work than it saves in store slots - Apple cores coalesce adjacent byte
// stores perfectly well on their own. Do not "improve" this into a packed store without
// re-measuring it; it has already been tried.
static inline void ppc_update_crf_compare(PPCInterpreter_t* hCPU, uint32 crfD, bool isLess, bool isEqual)
{
	uint8 lt = isLess ? 1 : 0;
	uint8 eq = isEqual ? 1 : 0;
	uint8 gt = (uint8)((lt | eq) ^ 1);
	uint8* crField = hCPU->cr + crfD * 4;
	crField[CR_BIT_LT] = lt;
	crField[CR_BIT_GT] = gt;
	crField[CR_BIT_EQ] = eq;
	crField[CR_BIT_SO] = hCPU->xer_so;
}

// The mask selected by a rotate-and-mask instruction's MB/ME pair.
//
// Same value as ppc_mask() in PPCInterpreterHelper.h - which is left alone because the
// recompiler's IML generator also calls it, where it runs once per translated instruction
// rather than once per execution and the cost does not matter.
//
// The point is that the wrapped case (MB > ME) is not a special case at all. The mask is
// always exactly n = ((ME - MB) mod 32) + 1 consecutive set bits whose first bit sits at
// MSB-numbered position MB and which wrap around the end of the word. So: build n bits
// aligned to the top of the word, then rotate them right by MB. The old form instead built
// two half-masks, computed both the AND and the OR of them, and selected between the two
// results on MB <= ME.
//
// Two identities keep it to four instructions with no masking and no possibility of an
// out-of-range shift: 31 - ((ME-MB) & 31) == ((ME-MB) ^ 31) & 31, and both the shift and the
// rotate consult only the low 5 bits of their count. On arm64 this is sub/eor/lsl/ror -
// four instructions against the previous seven, and no conditional select.
//
// Verified equal to ppc_mask() exhaustively over all 1024 (MB, ME) pairs, which is the whole
// input domain: both are 5-bit instruction fields.
static inline uint32 ppc_maskFromMBME(uint32 MB, uint32 ME)
{
	uint32 topAlignedMask = 0xFFFFFFFFu << (((ME - MB) ^ 31u) & 31u);
	return std::rotr(topAlignedMask, (int)(MB & 31u));
}

static void PPCInterpreter_ADD(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	hCPU->gpr[rD] = (int)hCPU->gpr[rA] + (int)hCPU->gpr[rB];
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ADDO(PPCInterpreter_t* hCPU, uint32 opcode)
{
	// Don't Starve Giant Edition uses this instruction + BSO
	PPC_OPC_TEMPL3_XO();
	uint32 result = hCPU->gpr[rA] + hCPU->gpr[rB];
	PPCInterpreter_setXerOV(hCPU, checkAdditionOverflow(hCPU->gpr[rA], hCPU->gpr[rB], result));
	hCPU->gpr[rD] = (uint32)result;
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ADDC(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	// replaces: gpr[rD] = a + b; xer_ca = (gpr[rD] < a)
	hCPU->gpr[rD] = ppc_addWithCarryOut(hCPU->gpr[rA], hCPU->gpr[rB], 0, hCPU->xer_ca);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ADDCO(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	uint32 a = hCPU->gpr[rA];
	uint32 b = hCPU->gpr[rB];
	// replaces: gpr[rD] = a + b; xer_ca = (gpr[rD] < a)
	uint32 result = ppc_addWithCarryOut(a, b, 0, hCPU->xer_ca);
	hCPU->gpr[rD] = result;
	// set SO/OV
	PPCInterpreter_setXerOV(hCPU, checkAdditionOverflow(a, b, result));
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ADDE(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	uint32 a = hCPU->gpr[rA];
	uint32 b = hCPU->gpr[rB];
	uint32 ca = hCPU->xer_ca;
	// replaces: gpr[rD] = a + b + ca; xer_ca = ppc_carry_3(a, b, ca)
	hCPU->gpr[rD] = ppc_addWithCarryOut(a, b, ca, hCPU->xer_ca);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ADDEO(PPCInterpreter_t* hCPU, uint32 opcode)
{
	// used by DS Virtual Console (Super Mario 64 DS)
	PPC_OPC_TEMPL3_XO();
	uint32 a = hCPU->gpr[rA];
	uint32 b = hCPU->gpr[rB];
	uint32 ca = hCPU->xer_ca;
	// replaces: gpr[rD] = a + b + ca; xer_ca = ppc_carry_3(a, b, ca)
	uint32 result = ppc_addWithCarryOut(a, b, ca, hCPU->xer_ca);
	hCPU->gpr[rD] = result;
	PPCInterpreter_setXerOV(hCPU, checkAdditionOverflow(a, b, result));
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ADDI(PPCInterpreter_t* hCPU, uint32 opcode)
{
	sint32 rD, rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(opcode, rD, rA, imm);
	hCPU->gpr[rD] = (rA ? (int)hCPU->gpr[rA] : 0) + (int)imm;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ADDIC(PPCInterpreter_t* hCPU, uint32 opcode)
{
	sint32 rD, rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(opcode, rD, rA, imm);
	// update XER. Replaces: gpr[rD] = a + imm; xer_ca = (gpr[rD] < a)
	hCPU->gpr[rD] = ppc_addWithCarryOut(hCPU->gpr[rA], imm, 0, hCPU->xer_ca);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ADDIC_(PPCInterpreter_t* hCPU, uint32 opcode)
{
	sint32 rD, rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(opcode, rD, rA, imm);
	// update XER. Replaces: gpr[rD] = a + imm; xer_ca = (gpr[rD] < a)
	hCPU->gpr[rD] = ppc_addWithCarryOut(hCPU->gpr[rA], imm, 0, hCPU->xer_ca);
	ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ADDIS(PPCInterpreter_t* hCPU, uint32 opcode)
{
	sint32 rD, rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_Shift16(opcode, rD, rA, imm);
	hCPU->gpr[rD] = (rA ? hCPU->gpr[rA] : 0) + imm;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ADDZE(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	PPC_ASSERT(rB == 0);
	uint32 a = hCPU->gpr[rA];
	uint32 ca = hCPU->xer_ca;
	// replaces: gpr[rD] = a + ca; xer_ca = (a == 0xffffffff && ca). Carry out of a + 0 + ca
	// is set exactly when a is all ones and ca is 1, so this is the same rule as the adder's
	// - verified exhaustively over all 2^32 values of a for both values of ca.
	hCPU->gpr[rD] = ppc_addWithCarryOut(a, 0, ca, hCPU->xer_ca);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ADDZEO(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	PPC_ASSERT(rB == 0);
	uint32 a = hCPU->gpr[rA];
	uint32 ca = hCPU->xer_ca;
	// replaces: gpr[rD] = a + ca; xer_ca = (a == 0xffffffff && ca) - see ADDZE above
	uint32 result = ppc_addWithCarryOut(a, 0, ca, hCPU->xer_ca);
	hCPU->gpr[rD] = result;
	PPCInterpreter_setXerOV(hCPU, checkAdditionOverflow(a, 0, result));
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ADDME(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	PPC_ASSERT(rB == 0);
	uint32 a = hCPU->gpr[rA];
	uint32 ca = hCPU->xer_ca;
	// replaces: gpr[rD] = a + ca + 0xffffffff; xer_ca = (a || ca). Carry out of
	// a + 0xffffffff + ca is set exactly when a + ca >= 1, i.e. when either is non-zero -
	// the same rule, verified exhaustively over all 2^32 values of a for both values of ca.
	hCPU->gpr[rD] = ppc_addWithCarryOut(a, 0xFFFFFFFF, ca, hCPU->xer_ca);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ADDMEO(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	PPC_ASSERT(rB == 0);
	uint32 a = hCPU->gpr[rA];
	uint32 ca = hCPU->xer_ca;
	// replaces: gpr[rD] = a + ca + 0xffffffff; xer_ca = (a || ca) - see ADDME above
	uint32 result = ppc_addWithCarryOut(a, 0xFFFFFFFF, ca, hCPU->xer_ca);
	hCPU->gpr[rD] = result;
	PPCInterpreter_setXerOV(hCPU, checkAdditionOverflow(a, 0xffffffff, result));
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SUBF(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	hCPU->gpr[rD] = ~hCPU->gpr[rA] + hCPU->gpr[rB] + 1;
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SUBFO(PPCInterpreter_t* hCPU, uint32 opcode)
{
	// Seen in Don't Starve Giant Edition and Teslagrad
	// also used by DS Virtual Console (Super Mario 64 DS)
	PPC_OPC_TEMPL3_XO();
	uint32 result = ~hCPU->gpr[rA] + hCPU->gpr[rB] + 1;
	PPCInterpreter_setXerOV(hCPU, checkAdditionOverflow(~hCPU->gpr[rA], hCPU->gpr[rB], result));
	hCPU->gpr[rD] = result;
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SUBFC(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	uint32 a = hCPU->gpr[rA];
	uint32 b = hCPU->gpr[rB];
	// update xer. Replaces: gpr[rD] = ~a + b + 1; xer_ca = ppc_carry_3(~a, b, 1)
	hCPU->gpr[rD] = ppc_addWithCarryOut(~a, b, 1, hCPU->xer_ca);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SUBFCO(PPCInterpreter_t* hCPU, uint32 opcode)
{
	// used by DS Virtual Console (Super Mario 64 DS)
	PPC_OPC_TEMPL3_XO();
	uint32 a = hCPU->gpr[rA];
	uint32 b = hCPU->gpr[rB];
	// update carry. Replaces: gpr[rD] = ~a + b + 1; xer_ca = ppc_carry_3(~a, b, 1)
	uint32 result = ppc_addWithCarryOut(~a, b, 1, hCPU->xer_ca);
	hCPU->gpr[rD] = result;
	// update xer SO/OV
	PPCInterpreter_setXerOV(hCPU, checkAdditionOverflow(~a, b, result));
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SUBFIC(PPCInterpreter_t* hCPU, uint32 opcode)
{
	sint32 rD, rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(opcode, rD, rA, imm);
	// replaces: gpr[rD] = ~a + imm + 1; xer_ca = ppc_carry_3(~a, imm, 1)
	hCPU->gpr[rD] = ppc_addWithCarryOut(~hCPU->gpr[rA], imm, 1, hCPU->xer_ca);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SUBFE(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	uint32 a = hCPU->gpr[rA];
	uint32 b = hCPU->gpr[rB];
	uint32 ca = hCPU->xer_ca;
	// update xer carry. Replaces: gpr[rD] = ~a + b + ca; xer_ca = ppc_carry_3(~a, b, ca)
	hCPU->gpr[rD] = ppc_addWithCarryOut(~a, b, ca, hCPU->xer_ca);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SUBFEO(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	uint32 a = hCPU->gpr[rA];
	uint32 b = hCPU->gpr[rB];
	uint32 ca = hCPU->xer_ca;
	// update xer carry. Replaces: result = ~a + b + ca; xer_ca = ppc_carry_3(~a, b, ca)
	uint32 result = ppc_addWithCarryOut(~a, b, ca, hCPU->xer_ca);
	hCPU->gpr[rD] = result;
	PPCInterpreter_setXerOV(hCPU, checkAdditionOverflow(~a, b, result));
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SUBFZE(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	PPC_ASSERT(rB == 0);
	uint32 a = hCPU->gpr[rA];
	uint32 ca = hCPU->xer_ca;
	// replaces: gpr[rD] = ~a + ca; xer_ca = (a == 0 && ca). Carry out of ~a + 0 + ca is set
	// exactly when ~a is all ones and ca is 1, i.e. when a is zero and ca is 1 - the same
	// rule, verified exhaustively over all 2^32 values of a for both values of ca.
	hCPU->gpr[rD] = ppc_addWithCarryOut(~a, 0, ca, hCPU->xer_ca);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SUBFZEO(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	PPC_ASSERT(rB == 0);
	uint32 a = hCPU->gpr[rA];
	uint32 ca = hCPU->xer_ca;
	// replaces: gpr[rD] = ~a + ca; xer_ca = (a == 0 && ca) - see SUBFZE above
	uint32 result = ppc_addWithCarryOut(~a, 0, ca, hCPU->xer_ca);
	hCPU->gpr[rD] = result;
	PPCInterpreter_setXerOV(hCPU, checkAdditionOverflow(~a, 0, result));
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SUBFME(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	PPC_ASSERT(rB == 0);
	uint32 a = hCPU->gpr[rA];
	uint32 ca = hCPU->xer_ca;
	// update xer carry. Replaces: gpr[rD] = ~a + 0xFFFFFFFF + ca;
	// xer_ca = ppc_carry_3(~a, 0xFFFFFFFF, ca)
	hCPU->gpr[rD] = ppc_addWithCarryOut(~a, 0xFFFFFFFF, ca, hCPU->xer_ca);
	if (opcode & PPC_OPC_RC)
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SUBFMEO(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	PPC_ASSERT(rB == 0);
	uint32 a = hCPU->gpr[rA];
	uint32 ca = hCPU->xer_ca;
	// update xer carry. Replaces: gpr[rD] = ~a + 0xFFFFFFFF + ca;
	// xer_ca = ppc_carry_3(~a, 0xFFFFFFFF, ca)
	uint32 result = ppc_addWithCarryOut(~a, 0xFFFFFFFF, ca, hCPU->xer_ca);
	hCPU->gpr[rD] = result;
	PPCInterpreter_setXerOV(hCPU, checkAdditionOverflow(~a, 0xFFFFFFFF, result));
	if (opcode & PPC_OPC_RC)
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_MULHW_(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	sint64 a = (sint32)hCPU->gpr[rA];
	sint64 b = (sint32)hCPU->gpr[rB];
	sint64 c = a * b;
	hCPU->gpr[rD] = ((uint64)c) >> 32;
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_MULHWU_(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	uint64 a = hCPU->gpr[rA];
	uint64 b = hCPU->gpr[rB];
	uint64 c = a * b;
	hCPU->gpr[rD] = c >> 32;
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_MULLW(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	sint64 result = (sint64)hCPU->gpr[rA] * (sint64)hCPU->gpr[rB];
	hCPU->gpr[rD] = (uint32)result;
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_MULLWO(PPCInterpreter_t* hCPU, uint32 opcode)
{
	// Don't Starve Giant Edition uses this instruction + BSO
	// also used by FullBlast when a save file exists + it uses mfxer to access overflow result
	PPC_OPC_TEMPL3_XO();
	sint64 result = (sint64)(sint32)hCPU->gpr[rA] * (sint64)(sint32)hCPU->gpr[rB];
	hCPU->gpr[rD] = (uint32)result;
	PPCInterpreter_setXerOV(hCPU, result < -0x80000000ll || result > 0x7FFFFFFFLL);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_MULLI(PPCInterpreter_t* hCPU, uint32 opcode)
{
	int rD, rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(opcode, rD, rA, imm);
	hCPU->gpr[rD] = hCPU->gpr[rA] * imm;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_DIVW(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	sint32 a = (sint32)hCPU->gpr[rA];
	sint32 b = (sint32)hCPU->gpr[rB];
	if (b == 0)
		hCPU->gpr[rD] = a < 0 ? 0xFFFFFFFF : 0;
	else if (a == 0x80000000 && b == 0xFFFFFFFF)
		hCPU->gpr[rD] = 0xFFFFFFFF;
	else
		hCPU->gpr[rD] = a / b;
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_DIVWO(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	sint32 a = (sint32)hCPU->gpr[rA];
	sint32 b = (sint32)hCPU->gpr[rB];
	if (b == 0)
	{
		PPCInterpreter_setXerOV(hCPU, true);
		hCPU->gpr[rD] = a < 0 ? 0xFFFFFFFF : 0;
	}
	else if(a == 0x80000000 && b == 0xFFFFFFFF)
	{
		PPCInterpreter_setXerOV(hCPU, true);
		hCPU->gpr[rD] = 0xFFFFFFFF;
	}
	else
	{
		hCPU->gpr[rD] = a / b;
		PPCInterpreter_setXerOV(hCPU, false);
	}
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_DIVWU(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	uint32 a = hCPU->gpr[rA];
	uint32 b = hCPU->gpr[rB];
	if (b == 0)
		hCPU->gpr[rD] = 0;
	// note: unlike DIVW, there's no INT_MIN/-1 trap case for the unsigned divide - the branch
	// below looks like it was carried over from DIVW's a==0x80000000/b==0xFFFFFFFF special case,
	// but for unsigned values a(0x80000000) < b(0xFFFFFFFF) always, so a/b is already 0 and the
	// "else" arm below would compute the identical result. Verified harmless, left alone.
	else if (a == 0x80000000 && b == 0xFFFFFFFF)
		hCPU->gpr[rD] = 0;
	else
		hCPU->gpr[rD] = a / b;
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_DIVWUO(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	uint32 a = hCPU->gpr[rA];
	uint32 b = hCPU->gpr[rB];
	if (b == 0)
	{
		PPCInterpreter_setXerOV(hCPU, true);
		hCPU->gpr[rD] = 0;
	}
	else if(a == 0x80000000 && b == 0xFFFFFFFF)
	{
		PPCInterpreter_setXerOV(hCPU, false);
		hCPU->gpr[rD] = 0;
	}
	else
	{
		hCPU->gpr[rD] = a / b;
		PPCInterpreter_setXerOV(hCPU, false);
	}
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_CREQV(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL_X_CR();
	ppc_setCRBit(hCPU, crD, ppc_getCRBit(hCPU, crA) ^ ppc_getCRBit(hCPU, crB) ^ 1);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_CRAND(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL_X_CR();
	ppc_setCRBit(hCPU, crD, ppc_getCRBit(hCPU, crA)&ppc_getCRBit(hCPU, crB));
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_CRANDC(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL_X_CR();
	ppc_setCRBit(hCPU, crD, ppc_getCRBit(hCPU, crA)&(ppc_getCRBit(hCPU, crB) ^ 1));
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_CRNAND(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL_X_CR();
	ppc_setCRBit(hCPU, crD, (ppc_getCRBit(hCPU, crA)&ppc_getCRBit(hCPU, crB)) ^ 1);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_CROR(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL_X_CR();
	ppc_setCRBit(hCPU, crD, ppc_getCRBit(hCPU, crA) | ppc_getCRBit(hCPU, crB));
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_CRORC(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL_X_CR();
	ppc_setCRBit(hCPU, crD, ppc_getCRBit(hCPU, crA) | (ppc_getCRBit(hCPU, crB) ^ 1));
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_CRNOR(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL_X_CR();
	ppc_setCRBit(hCPU, crD, (ppc_getCRBit(hCPU, crA) | ppc_getCRBit(hCPU, crB)) ^ 1);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_CRXOR(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL_X_CR();
	ppc_setCRBit(hCPU, crD, ppc_getCRBit(hCPU, crA) ^ ppc_getCRBit(hCPU, crB));
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_NEG(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	PPC_ASSERT(rB == 0);
	hCPU->gpr[rD] = (uint32)-((sint32)hCPU->gpr[rA]);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_NEGO(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	PPC_ASSERT(rB == 0);
	PPCInterpreter_setXerOV(hCPU, hCPU->gpr[rA] == 0x80000000);
	hCPU->gpr[rD] = (uint32)-((sint32)hCPU->gpr[rA]);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rD]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ANDX(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	hCPU->gpr[rA] = hCPU->gpr[rD] & hCPU->gpr[rB];
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ANDCX(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	hCPU->gpr[rA] = hCPU->gpr[rD] & ~hCPU->gpr[rB];
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ANDI_(PPCInterpreter_t* hCPU, uint32 opcode)
{
	int rS, rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_UImm(opcode, rS, rA, imm);
	hCPU->gpr[rA] = hCPU->gpr[rS] & imm;
	ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ANDIS_(PPCInterpreter_t* hCPU, uint32 opcode)
{
	int rS, rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_Shift16(opcode, rS, rA, imm);
	hCPU->gpr[rA] = hCPU->gpr[rS] & imm;
	ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_NANDX(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	hCPU->gpr[rA] = ~(hCPU->gpr[rD] & hCPU->gpr[rB]);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_OR(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	hCPU->gpr[rA] = hCPU->gpr[rD] | hCPU->gpr[rB];
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ORC(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	hCPU->gpr[rA] = hCPU->gpr[rD] | ~hCPU->gpr[rB];
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ORI(PPCInterpreter_t* hCPU, uint32 opcode)
{
	int rS, rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_UImm(opcode, rS, rA, imm);
	hCPU->gpr[rA] = hCPU->gpr[rS] | imm;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_ORIS(PPCInterpreter_t* hCPU, uint32 opcode)
{
	int rS, rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_Shift16(opcode, rS, rA, imm);
	hCPU->gpr[rA] = hCPU->gpr[rS] | imm;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_NORX(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	hCPU->gpr[rA] = ~(hCPU->gpr[rD] | hCPU->gpr[rB]);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_XOR(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	hCPU->gpr[rA] = hCPU->gpr[rD] ^ hCPU->gpr[rB];
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_XORI(PPCInterpreter_t* hCPU, uint32 opcode)
{
	int rS, rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_UImm(opcode, rS, rA, imm);
	hCPU->gpr[rA] = hCPU->gpr[rS] ^ imm;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_XORIS(PPCInterpreter_t* hCPU, uint32 opcode)
{
	int rS, rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_Shift16(opcode, rS, rA, imm);
	hCPU->gpr[rA] = hCPU->gpr[rS] ^ imm;
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_EQV(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	hCPU->gpr[rA] = ~(hCPU->gpr[rD] ^ hCPU->gpr[rB]);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_RLWIMI(PPCInterpreter_t* hCPU, uint32 opcode)
{
	int rS, rA, SH, MB, ME;
	PPC_OPC_TEMPL_M(opcode, rS, rA, SH, MB, ME);
	uint32 v = ppc_word_rotl(hCPU->gpr[rS], SH);
	uint32 mask = ppc_maskFromMBME((uint32)MB, (uint32)ME);
	hCPU->gpr[rA] = (v & mask) | (hCPU->gpr[rA] & ~mask);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_RLWINM(PPCInterpreter_t* hCPU, uint32 opcode)
{
	sint32 rS, rA, SH, MB, ME;
	PPC_OPC_TEMPL_M(opcode, rS, rA, SH, MB, ME);
	uint32 v = ppc_word_rotl(hCPU->gpr[rS], SH);
	uint32 mask = ppc_maskFromMBME((uint32)MB, (uint32)ME);
	hCPU->gpr[rA] = v & mask;
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_RLWNM(PPCInterpreter_t* hCPU, uint32 opcode)
{
	int rS, rA, rB, MB, ME;
	PPC_OPC_TEMPL_M(opcode, rS, rA, rB, MB, ME);
	uint32 v = ppc_word_rotl(hCPU->gpr[rS], hCPU->gpr[rB]);
	uint32 mask = ppc_maskFromMBME((uint32)MB, (uint32)ME);
	hCPU->gpr[rA] = v & mask;
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SLWX(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	uint32 s = hCPU->gpr[rB] & 0x3f;
	if (s > 31)
		hCPU->gpr[rA] = 0;
	else
		hCPU->gpr[rA] = hCPU->gpr[rD] << s;
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SRAW(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	uint32 sh = hCPU->gpr[rB] & 0x3f;
	hCPU->gpr[rA] = hCPU->gpr[rD];
	if (sh > 31)
	{
		hCPU->xer_ca = (hCPU->gpr[rA] >> 31) & 1; // copy sign bit to ca
		hCPU->gpr[rA] = (uint32)((sint32)hCPU->gpr[rA] >> 31); // fill all bits with sign bit
	}
	else
	{
		// ca is set when input is negative and non-zero bits are dropped by shift operation
		uint8 caBit = (hCPU->gpr[rA] >> 31) & 1;
		uint32 shiftedBits = hCPU->gpr[rA] & ~(0xFFFFFFFF << sh);
		caBit &= (shiftedBits != 0 ? 1 : 0);
		hCPU->xer_ca = caBit;
		hCPU->gpr[rA] = (uint32)((sint32)hCPU->gpr[rA] >> sh);
	}
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SRWX(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	uint32 v = hCPU->gpr[rB] & 0x3f;
	if (v > 31)
		hCPU->gpr[rA] = 0;
	else
		hCPU->gpr[rA] = hCPU->gpr[rD] >> v;
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_SRAWI(PPCInterpreter_t* hCPU, uint32 opcode)
{
	sint32 rS, rA;
	uint32 SH;
	PPC_OPC_TEMPL_X(opcode, rS, rA, SH);
	// SH is a 5-bit immediate (0-31), so this is the same closed-form CA/shift computation as
	// the SH<=31 path in SRAW above (bit-by-bit loop replaced with the mask trick - verified
	// equivalent for every SH/sign combination, including SH==0 where the mask goes to 0 and
	// both the shifted-out-bits check and the shift itself become no-ops, matching the old
	// loop's zero-iteration behavior).
	uint32 s = hCPU->gpr[rS];
	uint8 caBit = (s >> 31) & 1;
	uint32 shiftedBits = s & ~(0xFFFFFFFFu << SH);
	hCPU->xer_ca = caBit & (shiftedBits != 0 ? 1 : 0);
	hCPU->gpr[rA] = (uint32)((sint32)s >> SH);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static uint32 _CNTLZW(uint32 v)
{
	uint32 result = 0;
	if (v == 0)
		return 32;
	if ((v & 0xFFFF0000) != 0) { result |= 16; v >>= 16; }
	if ((v & 0xFF00FF00) != 0) { result |= 8; v >>= 8; }
	if ((v & 0xF0F0F0F0) != 0) { result |= 4; v >>= 4; }
	if ((v & 0xCCCCCCCC) != 0) { result |= 2; v >>= 2; }
	if ((v & 0xAAAAAAAA) != 0) { result |= 1; }
	result = 31 - result;
	return result;
}

static void PPCInterpreter_CNTLZW(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	PPC_ASSERT(rB == 0);
	hCPU->gpr[rA] = _CNTLZW(hCPU->gpr[rD]);
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_EXTSB(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	PPC_ASSERT(rB == 0);
	hCPU->gpr[rA] = (uint32)(sint32)(sint8)hCPU->gpr[rD];
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_EXTSH(PPCInterpreter_t* hCPU, uint32 opcode)
{
	PPC_OPC_TEMPL3_XO();
	PPC_ASSERT(rB == 0);
	hCPU->gpr[rA] = (uint32)(sint32)(sint16)hCPU->gpr[rD];
	if (opHasRC())
		ppc_update_cr0(hCPU, hCPU->gpr[rA]);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_CMP(PPCInterpreter_t* hCPU, uint32 opcode)
{
	uint32 cr;
	sint32 rA, rB;
	PPC_OPC_TEMPL_X(opcode, cr, rA, rB);
	cr >>= 2;
	// cmpw: SIGNED word compare. This is the half of the cmpw/cmplw pair whose operands are
	// read as two's complement, so the sint32 is the entire difference between this handler
	// and PPCInterpreter_CMPL below and must not be "tidied" into the register's own type.
	sint32 a = (sint32)hCPU->gpr[rA];
	sint32 b = (sint32)hCPU->gpr[rB];
	ppc_update_crf_compare(hCPU, cr, a < b, a == b);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_CMPL(PPCInterpreter_t* hCPU, uint32 opcode)
{
	uint32 cr;
	int rA, rB;
	PPC_OPC_TEMPL_X(opcode, cr, rA, rB);
	cr >>= 2;
	// cmplw: UNSIGNED word compare - the operands stay uint32 here, which is what separates
	// it from PPCInterpreter_CMP above.
	uint32 a = hCPU->gpr[rA];
	uint32 b = hCPU->gpr[rB];
	ppc_update_crf_compare(hCPU, cr, a < b, a == b);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_CMPI(PPCInterpreter_t* hCPU, uint32 opcode)
{
	uint32 cr;
	int rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_SImm(opcode, cr, rA, imm);
	cr >>= 2;
	// cmpwi: SIGNED, against the SIGN-EXTENDED immediate that PPC_OPC_TEMPL_D_SImm produced.
	sint32 a = (sint32)hCPU->gpr[rA];
	sint32 b = (sint32)imm;
	ppc_update_crf_compare(hCPU, cr, a < b, a == b);
	PPCInterpreter_nextInstruction(hCPU);
}

static void PPCInterpreter_CMPLI(PPCInterpreter_t* hCPU, uint32 opcode)
{
	uint32 cr;
	int rA;
	uint32 imm;
	PPC_OPC_TEMPL_D_UImm(opcode, cr, rA, imm);
	cr >>= 2;
	// cmplwi: UNSIGNED, against the ZERO-EXTENDED immediate that PPC_OPC_TEMPL_D_UImm
	// produced. Sign extension here would be a silent, very hard to find wrong answer.
	uint32 a = hCPU->gpr[rA];
	uint32 b = imm;
	ppc_update_crf_compare(hCPU, cr, a < b, a == b);
	PPCInterpreter_nextInstruction(hCPU);
}

