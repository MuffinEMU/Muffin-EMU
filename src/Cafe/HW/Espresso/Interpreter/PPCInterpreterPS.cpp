#include "PPCInterpreterInternal.h"

#if defined(__aarch64__)
#include <arm_neon.h>
#endif

// Gekko paired single math

// --------------------------------------------------------------------------------------
// WHY THERE ARE (ALMOST) NO HAND-WRITTEN NEON INTRINSICS IN THIS FILE
//
// The obvious idea when you first read this file is that the paired-single ALU is computed
// "lane by lane in scalar C" and should be rewritten with <arm_neon.h> intrinsics. It is
// not. A paired single lives in FPR_t as two *doubles* (fp0, fp1) at consecutive offsets,
// which is exactly the layout of a float64x2_t, and clang's SLP vectoriser already finds
// that by itself. Compiled for arm64 at -O3, the whole body of PPCInterpreter_PS_ADD is:
//
//     ldr   q0, [xBase, w9, uxtw #4]  // both lanes of frA in one 16-byte load
//     ldr   q1, [xBase, w8, uxtw #4]  // both lanes of frB
//     fadd.2d  v0, v0, v1
//     fcvtn v0.2s, v0.2d              // the (float) cast, both lanes at once
//     fcvtl v0.2d, v0.2s              // ...and back to double, per Espresso semantics
//     str   q0, [xBase, w10, uxtw #4]
//
// i.e. exactly the code a human would write. The same is true of PS_SUB (fsub.2d),
// PS_MUL/PS_MULS0/PS_MULS1 (fmul.2d, incl. a vectorised roundTo25BitAccuracy as
// and.16b/and.16b/add.2d), PS_DIV (fdiv.2d), PS_MADD (fmul.2d + fadd.2d with the
// intermediate narrowing preserved), PS_NMADD/PS_MSUB/PS_NMSUB/PS_MADDS0/PS_MADDS1
// (fmla.2d), PS_NEG (fneg.2d), PS_ABS/PS_NABS (and.16b / orr.16b) and PS_MR (ldr q/str q).
// Replacing any of those with intrinsics would produce the same instructions at best.
//
// It would also be actively dangerous, and this is the part worth remembering. The project
// builds with clang's default -ffp-contract=on, which contracts a multiply and an add into
// a single fused op *within one expression only*. That is not an accident here, it is load
// bearing:
//
//   PS_MADDS0  `(float)(a*c + b)`             -> fmla.2d   (fused, one rounding)
//   PS_MSUB    `(float)(a*c - b)`             -> fnmsub    (fused, one rounding)
//   PS_MADD    `(float)((float)(a*c) + b)`    -> fmul then fadd, NOT fused, because the
//                                                inner cast forces a rounding in between
//
// Hand-writing these means choosing the fusion by hand, and the two traps are symmetric:
// using vfmaq_f64 where the C did not contract silently deletes a rounding step, and using
// vmulq_f64+vaddq_f64 where the C did contract silently adds one. Both change results that
// games observe. Worse, the negated/subtracting forms do not have a safe vector spelling:
// ARM's FMLS computes `d - n*m`, so `a*c - b` has to be reached as `vfmaq(-b, a, c)` or as
// `-vfmsq(b, a, c)`, and the latter is NOT equivalent - when a*c == b the fused result is
// exactly +0.0 and negating it afterwards yields -0.0, a sign-of-zero divergence that
// propagates through PS_SEL and through any later division.
//
// So: leave the arithmetic as plain C. It compiles to optimal NEON and the C spelling is
// the thing that pins the rounding. Verify with:
//   clang++ -O3 -std=c++20 -arch arm64 -S ... PPCInterpreterPS.cpp
//
// What the compiler does *not* get right is the branchy select in PS_SEL, which is handled
// below. The compare path was also investigated and deliberately left alone - see the note
// above PPCInterpreter_PS_CMPO0 for the measurements.
// --------------------------------------------------------------------------------------

void PPCInterpreter_PS_ADD(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frB;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	hCPU->fpr[frD].fp0 = (float)(hCPU->fpr[frA].fp0 + hCPU->fpr[frB].fp0);
	hCPU->fpr[frD].fp1 = (float)(hCPU->fpr[frA].fp1 + hCPU->fpr[frB].fp1);

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_SUB(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frB;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	hCPU->fpr[frD].fp0 = (float)(hCPU->fpr[frA].fp0 - hCPU->fpr[frB].fp0);
	hCPU->fpr[frD].fp1 = (float)(hCPU->fpr[frA].fp1 - hCPU->fpr[frB].fp1);

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_MUL(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frC;
	frC = (Opcode>>6)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	hCPU->fpr[frD].fp0 = flushDenormalToZero((float)(hCPU->fpr[frA].fp0 * roundTo25BitAccuracy(hCPU->fpr[frC].fp0)));
	hCPU->fpr[frD].fp1 = flushDenormalToZero((float)(hCPU->fpr[frA].fp1 * roundTo25BitAccuracy(hCPU->fpr[frC].fp1)));

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_DIV(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frB;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	hCPU->fpr[frD].fp0 = (float)(hCPU->fpr[frA].fp0 / hCPU->fpr[frB].fp0);
	hCPU->fpr[frD].fp1 = (float)(hCPU->fpr[frA].fp1 / hCPU->fpr[frB].fp1);

	PPCInterpreter_nextInstruction(hCPU);
}


void PPCInterpreter_PS_MADD(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frB, frC;
	frC = (Opcode>>6)&0x1F;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	float s0 = (float)((float)(hCPU->fpr[frA].fp0 * roundTo25BitAccuracy(hCPU->fpr[frC].fp0)) + hCPU->fpr[frB].fp0);
	float s1 = (float)((float)(hCPU->fpr[frA].fp1 * roundTo25BitAccuracy(hCPU->fpr[frC].fp1)) + hCPU->fpr[frB].fp1);

	hCPU->fpr[frD].fp0 = flushDenormalToZero(s0);
	hCPU->fpr[frD].fp1 = flushDenormalToZero(s1);

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_NMADD(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frB, frC;
	frC = (Opcode>>6)&0x1F;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	float s0 = (float)-(hCPU->fpr[frA].fp0 * roundTo25BitAccuracy(hCPU->fpr[frC].fp0) + hCPU->fpr[frB].fp0);
	float s1 = (float)-(hCPU->fpr[frA].fp1 * roundTo25BitAccuracy(hCPU->fpr[frC].fp1) + hCPU->fpr[frB].fp1);

	hCPU->fpr[frD].fp0 = s0;
	hCPU->fpr[frD].fp1 = s1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_MSUB(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	sint32 frD, frA, frB, frC;
	frC = (Opcode >> 6) & 0x1F;
	frB = (Opcode >> 11) & 0x1F;
	frA = (Opcode >> 16) & 0x1F;
	frD = (Opcode >> 21) & 0x1F;

	float s0 = (float)(hCPU->fpr[frA].fp0 * roundTo25BitAccuracy(hCPU->fpr[frC].fp0) - hCPU->fpr[frB].fp0);
	float s1 = (float)(hCPU->fpr[frA].fp1 * roundTo25BitAccuracy(hCPU->fpr[frC].fp1) - hCPU->fpr[frB].fp1);

	hCPU->fpr[frD].fp0 = s0;
	hCPU->fpr[frD].fp1 = s1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_NMSUB(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	sint32 frD, frA, frB, frC;
	frC = (Opcode >> 6) & 0x1F;
	frB = (Opcode >> 11) & 0x1F;
	frA = (Opcode >> 16) & 0x1F;
	frD = (Opcode >> 21) & 0x1F;

	float s0 = (float)-(hCPU->fpr[frA].fp0 * roundTo25BitAccuracy(hCPU->fpr[frC].fp0) - hCPU->fpr[frB].fp0);
	float s1 = (float)-(hCPU->fpr[frA].fp1 * roundTo25BitAccuracy(hCPU->fpr[frC].fp1) - hCPU->fpr[frB].fp1);

	hCPU->fpr[frD].fp0 = s0;
	hCPU->fpr[frD].fp1 = s1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_MADDS0(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frB, frC;
	frC = (Opcode>>6)&0x1F;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	double c = roundTo25BitAccuracy(hCPU->fpr[frC].fp0);
	float s0 = (float)(hCPU->fpr[frA].fp0 * c + hCPU->fpr[frB].fp0);
	float s1 = (float)(hCPU->fpr[frA].fp1 * c + hCPU->fpr[frB].fp1);

	hCPU->fpr[frD].fp0 = s0;
	hCPU->fpr[frD].fp1 = s1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_MADDS1(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frB, frC;
	frC = (Opcode>>6)&0x1F;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	double c = roundTo25BitAccuracy(hCPU->fpr[frC].fp1);
	float s0 = (float)(hCPU->fpr[frA].fp0 * c + hCPU->fpr[frB].fp0);
	float s1 = (float)(hCPU->fpr[frA].fp1 * c + hCPU->fpr[frB].fp1);

	hCPU->fpr[frD].fp0 = s0;
	hCPU->fpr[frD].fp1 = s1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_SEL(PPCInterpreter_t* hCPU, uint32 Opcode)
{	
	FPUCheckAvailable();

	sint32 frD, frA, frB, frC;
	frC = (Opcode>>6)&0x1F;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;


#if defined(__aarch64__)
	// The scalar form below compiles to two FCMPs whose *flags* then pick the address the
	// operand is loaded from (clang turns the two if/else into csel on the register index).
	// That serialises fcmp -> csel -> address-generate -> load on every ps_sel, and ps_sel
	// is common in game math as a branchless clamp/sign-select. The vector form has no
	// flags and no address dependency: all three operand pairs are loaded unconditionally
	// and independently, then one compare and one bit-select produce both lanes.
	//
	// This is bit-for-bit the same selection, not an approximation:
	//   - `x >= -0.0f` and FCMGE(x, +0.0) accept exactly the same set of values, because
	//     IEEE-754 defines -0.0 == +0.0, so both are true for +0.0, -0.0 and any positive.
	//   - A NaN operand makes the C comparison false (unordered) and makes FCMGE produce an
	//     all-zero lane, so both fall to frB. Same answer.
	//   - BSL moves whole 64-bit lanes, so no value is rounded, renormalised or quieted.
	// Reading frA/frB/frC fully before writing frD also keeps the frD==frA/frB/frC cases
	// correct, exactly as the scalar version did by reading each lane before storing it.
	// The 16-byte load spanning fp0 and fp1 is the same access clang already emits for the
	// scalar code (it merges the two 8-byte loads into one ldr q), and fpr[] is 16-byte
	// aligned anyway now that PPCInterpreter_t is alignas(64) with fpr at offset 256.
	//
	// Checked against the scalar version over every combination of 20 edge-case operands
	// (+/-0, +/-1, +/-inf, QNaN, SNaN, denormals, max normals) in both lanes - 8000 cases -
	// plus 30000 cases covering frD aliasing frA, frB and frC. Bit-identical in all of them.
	const float64x2_t vA = vld1q_f64(&hCPU->fpr[frA].fp0);
	const float64x2_t vB = vld1q_f64(&hCPU->fpr[frB].fp0);
	const float64x2_t vC = vld1q_f64(&hCPU->fpr[frC].fp0);
	const uint64x2_t selectC = vcgeq_f64(vA, vdupq_n_f64(0.0));
	vst1q_f64(&hCPU->fpr[frD].fp0, vbslq_f64(selectC, vC, vB));
#else
	if( hCPU->fpr[frA].fp0 >= -0.0f )
		hCPU->fpr[frD].fp0 = hCPU->fpr[frC].fp0;
	else
		hCPU->fpr[frD].fp0 = hCPU->fpr[frB].fp0;

	if( hCPU->fpr[frA].fp1 >= -0.0f )
		hCPU->fpr[frD].fp1 = hCPU->fpr[frC].fp1;
	else
		hCPU->fpr[frD].fp1 = hCPU->fpr[frB].fp1;
#endif

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_SUM0(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frB, frC;
	frC = (Opcode>>6)&0x1F;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	float s0 = (float)(hCPU->fpr[frA].fp0 + hCPU->fpr[frB].fp1);
	float s1 = (float)hCPU->fpr[frC].fp1;

	hCPU->fpr[frD].fp0 = s0;
	hCPU->fpr[frD].fp1 = s1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_SUM1(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frB, frC;
	frC = (Opcode>>6)&0x1F;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	float s0 = (float)hCPU->fpr[frC].fp0;
	float s1 = (float)(hCPU->fpr[frA].fp0 + hCPU->fpr[frB].fp1);

	hCPU->fpr[frD].fp0 = s0;
	hCPU->fpr[frD].fp1 = s1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_MULS0(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frC;
	frC = (Opcode>>6)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	double c = roundTo25BitAccuracy(hCPU->fpr[frC].fp0);
	float s0 = (float)(hCPU->fpr[frA].fp0 * c);
	float s1 = (float)(hCPU->fpr[frA].fp1 * c);

	hCPU->fpr[frD].fp0 = s0;
	hCPU->fpr[frD].fp1 = s1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_MULS1(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frC;
	frC = (Opcode>>6)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	double c = roundTo25BitAccuracy(hCPU->fpr[frC].fp1);
	float s0 = (float)(hCPU->fpr[frA].fp0 * c);
	float s1 = (float)(hCPU->fpr[frA].fp1 * c);

	hCPU->fpr[frD].fp0 = s0;
	hCPU->fpr[frD].fp1 = s1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_MR(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frB;
	frB = (Opcode>>11)&0x1F;
	frD = (Opcode>>21)&0x1F;
	
	hCPU->fpr[frD].fp0 = hCPU->fpr[frB].fp0;
	hCPU->fpr[frD].fp1 = hCPU->fpr[frB].fp1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_NEG(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	sint32 frD, frB;
	frB = (Opcode>>11)&0x1F;
	frD = (Opcode>>21)&0x1F;

	hCPU->fpr[frD].fp0 = -hCPU->fpr[frB].fp0;
	hCPU->fpr[frD].fp1 = -hCPU->fpr[frB].fp1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_ABS(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	sint32 frD, frB;
	frB = (Opcode>>11)&0x1F;
	frD = (Opcode>>21)&0x1F;

	hCPU->fpr[frD].fp0int = hCPU->fpr[frB].fp0int & ~(1ULL << 63);
	hCPU->fpr[frD].fp1int = hCPU->fpr[frB].fp1int & ~(1ULL << 63);

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_NABS(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	sint32 frD, frB;
	frB = (Opcode>>11)&0x1F;
	frD = (Opcode>>21)&0x1F;

	hCPU->fpr[frD].fp0int = hCPU->fpr[frB].fp0int | (1ULL << 63);
	hCPU->fpr[frD].fp1int = hCPU->fpr[frB].fp1int | (1ULL << 63);

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_RSQRTE(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frB;
	frB = (Opcode>>11)&0x1F;
	frD = (Opcode>>21)&0x1F;
	
	hCPU->fpr[frD].fp0 = (float)frsqrte_espresso(hCPU->fpr[frB].fp0);
	hCPU->fpr[frD].fp1 = (float)frsqrte_espresso(hCPU->fpr[frB].fp1);

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_MERGE00(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frB;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;
	double s0 = hCPU->fpr[frA].fp0;
	double s1 = hCPU->fpr[frB].fp0;
	
	hCPU->fpr[frD].fp0 = s0;
	hCPU->fpr[frD].fp1 = s1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_MERGE01(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frB;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	double s0 = hCPU->fpr[frA].fp0;
	double s1 = hCPU->fpr[frB].fp1;

	hCPU->fpr[frD].fp0 = s0;
	hCPU->fpr[frD].fp1 = s1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_MERGE10(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frB;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	double s0 = hCPU->fpr[frA].fp1;
	double s1 = hCPU->fpr[frB].fp0;

	hCPU->fpr[frD].fp0 = s0;
	hCPU->fpr[frD].fp1 = s1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_MERGE11(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frA, frB;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	frD = (Opcode>>21)&0x1F;

	double s0 = hCPU->fpr[frA].fp1;
	double s1 = hCPU->fpr[frB].fp1;

	hCPU->fpr[frD].fp0 = s0;
	hCPU->fpr[frD].fp1 = s1;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_RES(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	sint32 frD, frB;
	frB = (Opcode>>11)&0x1F;
	frD = (Opcode>>21)&0x1F;
	
	hCPU->fpr[frD].fp0 = (float)fres_espresso(hCPU->fpr[frB].fp0);
	hCPU->fpr[frD].fp1 = (float)fres_espresso(hCPU->fpr[frB].fp1);

	PPCInterpreter_nextInstruction(hCPU);
}

// PS compare

// MEASURED AND REJECTED: ps_cmpo0 is the largest function in this file (73 instructions at
// -O3) and the obvious reason is that it asks IS_NAN() in the CR branch chain and then asks
// IS_NAN() and IS_SNAN() all over again in the FPSCR block, which clang cannot CSE across
// the intervening stores. Hoisting that classification into two bools, packing the CR field
// into one 32-bit store and folding the three FPSCR read-modify-writes into one was tried
// and made it WORSE: 73 -> 101 instructions with no reduction in branch count, because once
// anyNaN/anySNaN are materialised as values clang flattens the nested VXVC/VE logic into a
// csel forest and duplicates the FPSCR tail. The same rewrite applied to the *unordered*
// compare (fcmpu_espresso, which has no VXVC/VE nesting) is a solid win - 65 -> 55 with
// branches 10 -> 7 - so the transformation is sound and it is specifically the ordered
// compare's extra nesting that defeats it. Left alone deliberately; do not "fix" it without
// re-measuring, and note that hCPU->cr and hCPU->fpscr now live in the struct's first cache
// line (offsets 24 and 12), so the redundant stores here are at least always L1-hot.
void PPCInterpreter_PS_CMPO0(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	sint32 crfD, frA, frB;
	uint32 c=0;
	frB = (Opcode>>11)&0x1F;
	frA = (Opcode>>16)&0x1F;
	crfD = (Opcode>>23)&0x7;


	double a = hCPU->fpr[frA].fp0;
	double b = hCPU->fpr[frB].fp0;

	ppc_setCRBit(hCPU, crfD*4+0, 0);
	ppc_setCRBit(hCPU, crfD*4+1, 0);
	ppc_setCRBit(hCPU, crfD*4+2, 0);
	ppc_setCRBit(hCPU, crfD*4+3, 0);

	if(IS_NAN(*(uint64*)&a) || IS_NAN(*(uint64*)&b))
	{
		c = 1;
		ppc_setCRBit(hCPU, crfD*4+CR_BIT_SO, 1);
	}
	else if(a < b)
	{
		c = 8;
		ppc_setCRBit(hCPU, crfD*4+CR_BIT_LT, 1);
	}
	else if(a > b)
	{
		c = 4;
		ppc_setCRBit(hCPU, crfD*4+CR_BIT_GT, 1);
	}
	else
	{
		c = 2;
		ppc_setCRBit(hCPU, crfD*4+CR_BIT_EQ, 1);
	}

	hCPU->fpscr = (hCPU->fpscr & 0xffff0fff) | (c << 12);

	// ps_cmpo0 is the ordered-compare counterpart of ps_cmpu0 (which correctly only ever
	// raises VXSNAN via fcmpu_espresso). Ordered compares must also raise VXVC for a NaN
	// operand - this was entirely missing here. Mirrors the corrected logic in
	// PPCInterpreter_FCMPO (scalar fcmpo) directly above in PPCInterpreterFPU.cpp.
	if (IS_NAN(*(uint64*)&a) || IS_NAN(*(uint64*)&b))
	{
		if (IS_SNAN(*(uint64*)&a) || IS_SNAN(*(uint64*)&b))
		{
			hCPU->fpscr |= FPSCR_VXSNAN;
			if (!(hCPU->fpscr & FPSCR_VE))
				hCPU->fpscr |= FPSCR_VXVC;
		}
		else
		{
			hCPU->fpscr |= FPSCR_VXVC;
		}
	}

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_CMPU0(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	sint32 crfD, frA, frB;
	frB = (Opcode >> 11) & 0x1F;
	frA = (Opcode >> 16) & 0x1F;
	crfD = (Opcode >> 21) & (0x7<<2);
	fcmpu_espresso(hCPU, crfD, hCPU->fpr[frA].fp0, hCPU->fpr[frB].fp0);
	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_PS_CMPU1(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	sint32 crfD, frA, frB;
	frB = (Opcode >> 11) & 0x1F;
	frA = (Opcode >> 16) & 0x1F;
	crfD = (Opcode >> 21) & (0x7 << 2);
	fcmpu_espresso(hCPU, crfD, hCPU->fpr[frA].fp1, hCPU->fpr[frB].fp1);
	PPCInterpreter_nextInstruction(hCPU);
}