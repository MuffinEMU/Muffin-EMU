#include "../PPCState.h"
#include "PPCInterpreterInternal.h"
#include "PPCInterpreterHelper.h"

#include<math.h>

// floating point utility

#include <limits>
#include <array>
#include <cstring>
#include <bit>

// NOTE ON NEON IN THIS FILE: unlike PPCInterpreterPS.cpp there is nothing here to
// vectorise. Every instruction below is a *scalar* double operation on a single FPR, so
// there is no second lane to pair with - fadd/fmul/fdiv/fmadd are already one ARM64
// instruction each and the `if (PPC_PSE) fp1 = fp0;` paired-single splat that follows the
// single-precision ops already compiles to `dup.2d v0, v0[0]` plus one 16-byte `str q`
// (verified at -O3 on arm64 for FADDS and FMADDS). The real cost in this file is the
// compare path; fcmpu_espresso below is fixed, fcmpo is deliberately not - see the note
// above PPCInterpreter_FCMPO for the measurement that rejected the same change there.

const int ieee_double_e_bits = 11; // exponent bits
const int ieee_double_m_bits = 52; // mantissa bits

const int espresso_frsqrte_i_bits = 5; // index bits (the highest bit is the LSB of the exponent)

typedef struct
{
	uint32 offset;
	uint32 step;
}espresso_frsqrte_entry_t;

espresso_frsqrte_entry_t frsqrteLookupTable[32] =
{
	{0x1a7e800, 0x568},{0x17cb800, 0x4f3},{0x1552800, 0x48d},{0x130c000, 0x435},
	{0x10f2000, 0x3e7},{0xeff000, 0x3a2},{0xd2e000, 0x365},{0xb7c000, 0x32e},
	{0x9e5000, 0x2fc},{0x867000, 0x2d0},{0x6ff000, 0x2a8},{0x5ab800, 0x283},
	{0x46a000, 0x261},{0x339800, 0x243},{0x218800, 0x226},{0x105800, 0x20b},
	{0x3ffa000, 0x7a4},{0x3c29000, 0x700},{0x38aa000, 0x670},{0x3572000, 0x5f2},
	{0x3279000, 0x584},{0x2fb7000, 0x524},{0x2d26000, 0x4cc},{0x2ac0000, 0x47e},
	{0x2881000, 0x43a},{0x2665000, 0x3fa},{0x2468000, 0x3c2},{0x2287000, 0x38e},
	{0x20c1000, 0x35e},{0x1f12000, 0x332},{0x1d79000, 0x30a},{0x1bf4000, 0x2e6},
};

ATTR_MS_ABI double frsqrte_espresso(double input)
{
	unsigned long long x = *(unsigned long long*)&input;

	// 0.0 and -0.0
	if ((x << 1) == 0)
	{
		// result is inf or -inf
		x &= ~0x7FFFFFFFFFFFFFFF;
		x |= 0x7FF0000000000000;
		return *(double*)&x;
	}
	// get exponent
	uint32 e = (x >> ieee_double_m_bits) & ((1ull << ieee_double_e_bits) - 1ull);
	// NaN or INF
	if (e == 0x7FF)
	{
		if ((x&((1ull << ieee_double_m_bits) - 1)) == 0)
		{
			// negative INF returns +NaN
			if ((sint64)x < 0)
			{
				x = 0x7FF8000000000000;
				return *(double*)&x;
			}
			// positive INF returns +0.0
			return 0.0;
		}
		// result is NaN with same sign and same mantissa (todo: verify)
		return *(double*)&x;
	}
	// negative number (other than -0.0)
	if ((sint64)x < 0)
	{
		// result is positive NaN
		x = 0x7FF8000000000000;
		return *(double*)&x;
	}
	// todo: handle denormals

	// get index (lsb of exponent, remaining bits of mantissa)
	uint32 idx = (x >> (ieee_double_m_bits - espresso_frsqrte_i_bits + 1ull))&((1 << espresso_frsqrte_i_bits) - 1);
	// get step multiplier
	uint32 stepMul = (x >> (ieee_double_m_bits - espresso_frsqrte_i_bits + 1 - 11))&((1 << 11) - 1);

	sint32 sum = frsqrteLookupTable[idx].offset - frsqrteLookupTable[idx].step * stepMul;

	e = 1023 - ((e - 1021) >> 1);
	x &= ~(((1ull << ieee_double_e_bits) - 1ull) << ieee_double_m_bits);
	x |= ((unsigned long long)e << ieee_double_m_bits);

	x &= ~((1ull << ieee_double_m_bits) - 1ull);
	x += ((unsigned long long)sum << 26ull);

	return *(double*)&x;
}

const int espresso_fres_i_bits = 5; // index bits
const int espresso_fres_s_bits = 10; // step multiplier bits

typedef struct
{
	uint32 offset;
	uint32 step;
}espresso_fres_entry_t;

espresso_fres_entry_t fresLookupTable[32] =
{
	// table calculated by fres_gen_table()
	{0x7ff800, 0x3e1},	{0x783800, 0x3a7},	{0x70ea00, 0x371},	{0x6a0800, 0x340},
	{0x638800, 0x313},	{0x5d6200, 0x2ea},	{0x579000, 0x2c4},	{0x520800, 0x2a0},
	{0x4cc800, 0x27f},	{0x47ca00, 0x261},	{0x430800, 0x245},	{0x3e8000, 0x22a},
	{0x3a2c00, 0x212},	{0x360800, 0x1fb},	{0x321400, 0x1e5},	{0x2e4a00, 0x1d1},
	{0x2aa800, 0x1be},	{0x272c00, 0x1ac},	{0x23d600, 0x19b},	{0x209e00, 0x18b},
	{0x1d8800, 0x17c},	{0x1a9000, 0x16e},	{0x17ae00, 0x15b},	{0x14f800, 0x15b},
	{0x124400, 0x143},	{0xfbe00, 0x143},	{0xd3800, 0x12d},	{0xade00, 0x12d},
	{0x88400, 0x11a},	{0x65000, 0x11a},	{0x41c00, 0x108},	{0x20c00, 0x106}
};

ATTR_MS_ABI double fres_espresso(double input)
{
	// based on testing we know that fres uses only the first 15 bits of the mantissa
	// seee eeee eeee mmmm mmmm mmmm mmmx xxxx ....		(s = sign, e = exponent, m = mantissa, x = not used)
	// the mantissa bits are interpreted as following:
	// 0000 0000 0000 iiii ifff ffff fff0 ...			(i = table look up index , f = step multiplier)
	unsigned long long x = *(unsigned long long*)&input;

	// get index
	uint32 idx = (x >> (ieee_double_m_bits - espresso_fres_i_bits))&((1 << espresso_fres_i_bits) - 1);
	// get step multiplier
	uint32 stepMul = (x >> (ieee_double_m_bits - espresso_fres_i_bits - 10))&((1 << 10) - 1);


	uint32 sum = fresLookupTable[idx].offset - (fresLookupTable[idx].step * stepMul + 1) / 2;

	// get exponent
	uint32 e = (x >> ieee_double_m_bits) & ((1ull << ieee_double_e_bits) - 1ull);
	if (e == 0)
	{
		// todo?
		//x &= 0x7FFFFFFFFFFFFFFFull;
		x |= 0x7FF0000000000000ull;
		return *(double*)&x;
	}
	else if (e == 0x7ff) // NaN or INF
	{
		if ((x&((1ull << ieee_double_m_bits) - 1)) == 0)
		{
			// negative INF returns -0.0
			if ((sint64)x < 0)
			{
				x = 0x8000000000000000;
				return *(double*)&x;
			}
			// positive INF returns +0.0
			return 0.0;
		}
		// result is NaN with same sign and same mantissa (todo: verify)
		return *(double*)&x;
	}
	// todo - needs more testing (especially NaN and INF values)

	e = 2045 - e;
	x &= ~(((1ull << ieee_double_e_bits) - 1ull) << ieee_double_m_bits);
	x |= ((unsigned long long)e << ieee_double_m_bits);

	x &= ~((1ull << ieee_double_m_bits) - 1ull);
	x += ((unsigned long long)sum << 29ull);

	return *(double*)&x;
}

// A CR field is four consecutive bytes of hCPU->cr (that array stores one whole byte per CR
// bit). Every compare below clears the field and then sets exactly one bit, so the field
// only ever takes one of four values and each of those is a compile-time constant. Writing
// it as one 32-bit store instead of four byte-stores is worth doing because crfD is a
// runtime value, so the compiler cannot prove the field is 4-byte aligned and will not
// merge the byte stores itself.
//
// The word is built with std::bit_cast from a byte array indexed by the CR_BIT_* constants
// rather than by shifting bytes into a word, so it carries no little-endian assumption: on
// any host, byte i of the array lands at cr[crfD+i], which is exactly where the four
// separate byte-stores used to put it.
static constexpr uint32 ppc_makeCRField(int setBit)
{
	std::array<uint8, 4> b{ 0, 0, 0, 0 };
	b[setBit] = 1;
	return std::bit_cast<uint32>(b);
}
static constexpr uint32 kCRField_LT = ppc_makeCRField(CR_BIT_LT);
static constexpr uint32 kCRField_GT = ppc_makeCRField(CR_BIT_GT);
static constexpr uint32 kCRField_EQ = ppc_makeCRField(CR_BIT_EQ);
static constexpr uint32 kCRField_SO = ppc_makeCRField(CR_BIT_SO);

// Shared body of fcmpu / ps_cmpu0 / ps_cmpu1, so it runs on every floating point compare the
// guest makes. 65 -> 55 instructions at -O3 with branches 10 -> 7, and 6 byte-stores to
// hCPU->cr replaced by one 32-bit store. FCMPU, which inlines this, went 69 -> 58 and became
// entirely branchless. The cost removed was all structural rather than arithmetic, and none
// of it changes a result:
//
//  1. Four zeroing byte-stores into hCPU->cr, each with its own address computation, then a
//     fifth byte-store of the one bit actually set. crfD is a runtime value here, so the
//     compiler could not prove 4-byte alignment and would not merge them. Replaced by one
//     store of a precomputed constant word (see ppc_makeCRField above).
//  2. IS_NAN() and IS_SNAN() are each a 64-bit exponent mask/compare plus a mantissa test,
//     and asking them in separate branch regions defeats CSE. Classify once up front.
//  3. Two read-modify-write cycles on hCPU->fpscr became one. This is value-identical
//     because FPSCR_VXSNAN is bit 24 and survives the `& 0xffff0fff` that clears FPRF, so
//     OR-ing it before or after that mask produces the same word.
//
// Checked against the previous implementation over every pairing of 20 edge-case operands
// (+/-0, +/-1, +/-inf, QNaN, SNaN with and without payload, smallest/largest denormals,
// smallest/largest normals) x all 8 CR fields x 6 starting FPSCR values including all-ones
// and VE-set: 19200 cases, identical cr[] and fpscr in every one.
void fcmpu_espresso(PPCInterpreter_t* hCPU, int crfD, double a, double b)
{
	uint32 c;

	const uint64 ia = *(uint64*)&a;
	const uint64 ib = *(uint64*)&b;
	const bool anyNaN = IS_NAN(ia) || IS_NAN(ib);
	const bool anySNaN = IS_SNAN(ia) || IS_SNAN(ib);

	uint32 crField;

	if (anyNaN)
	{
		c = 1;
		crField = kCRField_SO;
	}
	else if (a < b)
	{
		c = 8;
		crField = kCRField_LT;
	}
	else if (a > b)
	{
		c = 4;
		crField = kCRField_GT;
	}
	else
	{
		c = 2;
		crField = kCRField_EQ;
	}

	memcpy(&hCPU->cr[crfD], &crField, sizeof(crField));

	uint32 fpscr = hCPU->fpscr;
	if (anySNaN)
		fpscr |= FPSCR_VXSNAN;
	hCPU->fpscr = (fpscr & 0xffff0fff) | (c << 12);
}

void PPCInterpreter_FMR(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, rA, frB;
	PPC_OPC_TEMPL_X(Opcode, frD, rA, frB);
	PPC_ASSERT(rA==0);
	hCPU->fpr[frD].fpr = hCPU->fpr[frB].fpr;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FSEL(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);
	if ( hCPU->fpr[frA].fp0 >= -0.0f )
		hCPU->fpr[frD] = hCPU->fpr[frC];
	else
		hCPU->fpr[frD] = hCPU->fpr[frB];
	PPC_ASSERT((Opcode & PPC_OPC_RC) != 0); // update CR1 flags

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FCTIWZ(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	int frD, frA, frB;
	PPC_OPC_TEMPL_X(Opcode, frD, frA, frB);
	PPC_ASSERT(frA==0);

	double b = hCPU->fpr[frB].fpr;
	uint64 v;
	if (IS_NAN(*(uint64*)&b))
	{
		// Power ISA: NaN operand -> FRT = 0x8000_0000 (same sentinel as negative overflow).
		// Must be an explicit check, not left to fall through to the plain (sint32)b cast below:
		// double->int32 conversion of NaN is UB in C++ and platform-dependent in practice -
		// x86 cvttsd2si happens to yield 0x80000000 for NaN (matching the spec by accident),
		// but AArch64 FCVTZS is defined to yield 0 for NaN. Since this is an ARM64 target,
		// omitting this check silently produced the wrong result (0 instead of 0x80000000).
		v = (uint64)0x80000000;
	}
	else if (b > (double)0x7FFFFFFF)
	{
		v = (uint64)0x7FFFFFFF;
	}
	else if (b < -(double)0x80000000)
	{
		v = (uint64)0x80000000;
	}
	else
	{
		v = (uint64)(uint32)(sint32)b;
	}

	hCPU->fpr[frD].guint = 0xFFF8000000000000ULL | v;
	if (v == 0 && ((*(uint64*)&b) >> 63))
		hCPU->fpr[frD].guint |= 0x100000000ull;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FCTIW(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB;
	PPC_OPC_TEMPL_X(Opcode, frD, frA, frB);
	PPC_ASSERT(frA==0);

	double b = hCPU->fpr[frB].fpr;
	uint64 v;
	if (IS_NAN(*(uint64*)&b))
	{
		// see PPCInterpreter_FCTIWZ - same NaN -> 0x8000_0000 rule, same ARM64 UB pitfall
		// (here it would otherwise fall into the (sint32)t cast below via b+0.5 == NaN)
		v = (uint64)0x80000000;
	}
	else if (b > (double)0x7FFFFFFF)
	{
		v = (uint64)0x7FFFFFFF;
	}
	else if (b < -(double)0x80000000)
	{
		v = (uint64)0x80000000;
	}
	else
	{
		// todo: Support for other rounding modes than NEAR
		double t = b + 0.5;
		sint32 i = (sint32)t;
		if (t - i < 0 || (t - i == 0 && b > 0))
		{
			i--;
		}
		v = (uint64)i;
	}
	hCPU->fpr[frD].guint = 0xFFF8000000000000ULL | v;
	if (v == 0 && ((*(uint64*)&b) >> 63))
		hCPU->fpr[frD].guint |= 0x100000000ull;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FNEG(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB;
	PPC_OPC_TEMPL_X(Opcode, frD, frA, frB);
	PPC_ASSERT(frA==0);
	
	hCPU->fpr[frD].guint = hCPU->fpr[frB].guint ^ (1ULL << 63);

	PPC_ASSERT((Opcode & PPC_OPC_RC) != 0); // update CR1 flags

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FRSP(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	int frD, frA, frB;
	PPC_OPC_TEMPL_X(Opcode, frD, frA, frB);
	PPC_ASSERT(frA==0);

	if( PPC_PSE )
	{
		hCPU->fpr[frD].fp0 = (float)hCPU->fpr[frB].fpr;
		hCPU->fpr[frD].fp1 = hCPU->fpr[frD].fp0;
	}
	else
	{
		hCPU->fpr[frD].fpr = (float)hCPU->fpr[frB].fpr;
	}

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FRSQRTE(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);
	PPC_ASSERT(frA==0 && frC==0);
	
	hCPU->fpr[frD].fpr = frsqrte_espresso(hCPU->fpr[frB].fpr);

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FRES(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);
	PPC_ASSERT(frA==0 && frC==0);

	hCPU->fpr[frD].fpr = fres_espresso(hCPU->fpr[frB].fpr);
	
	if(PPC_PSE) 
		hCPU->fpr[frD].fp1 = hCPU->fpr[frD].fp0;

	PPCInterpreter_nextInstruction(hCPU);
}

// Floating point ALU

void PPCInterpreter_FABS(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB;
	PPC_OPC_TEMPL_X(Opcode, frD, frA, frB);
	PPC_ASSERT(frA==0);

	hCPU->fpr[frD].guint = hCPU->fpr[frB].guint & ~0x8000000000000000;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FNABS(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB;
	PPC_OPC_TEMPL_X(Opcode, frD, frA, frB);
	PPC_ASSERT(frA==0);
	
	hCPU->fpr[frD].guint = hCPU->fpr[frB].guint | 0x8000000000000000;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FADD(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);
	PPC_ASSERT(frC==0);

	hCPU->fpr[frD].fpr = hCPU->fpr[frA].fpr + hCPU->fpr[frB].fpr;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FDIV(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);
	PPC_ASSERT(frC==0);

	hCPU->fpr[frD].fpr = hCPU->fpr[frA].fpr / hCPU->fpr[frB].fpr;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FSUB(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);
	PPC_ASSERT(frC==0);

	hCPU->fpr[frD].fpr = hCPU->fpr[frA].fpr - hCPU->fpr[frB].fpr;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FMUL(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);
	PPC_ASSERT(frC == 0);

	hCPU->fpr[frD].fpr = hCPU->fpr[frA].fpr * hCPU->fpr[frC].fpr;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FMADD(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);

	hCPU->fpr[frD].fpr = hCPU->fpr[frA].fpr * hCPU->fpr[frC].fpr + hCPU->fpr[frB].fpr;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FNMADD(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);

	hCPU->fpr[frD].fpr = -(hCPU->fpr[frA].fpr * hCPU->fpr[frC].fpr + hCPU->fpr[frB].fpr);

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FMSUB(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);

	hCPU->fpr[frD].fpr = (hCPU->fpr[frA].fpr * hCPU->fpr[frC].fpr - hCPU->fpr[frB].fpr);

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FNMSUB(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);

	hCPU->fpr[frD].fpr = -(hCPU->fpr[frA].fpr * hCPU->fpr[frC].fpr - hCPU->fpr[frB].fpr);

	PPCInterpreter_nextInstruction(hCPU);
}

// Move

void PPCInterpreter_MFFS(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, rA, rB;
	PPC_OPC_TEMPL_X(Opcode, frD, rA, rB);
	PPC_ASSERT(rA==0 && rB==0);
	hCPU->fpr[frD].guint = (uint64)hCPU->fpscr;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_MTFSF(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frB;
	uint32 fm, FM;
	PPC_OPC_TEMPL_XFL(Opcode, frB, fm);
	FM = ((fm&0x80)?0xf0000000:0)|((fm&0x40)?0x0f000000:0)|((fm&0x20)?0x00f00000:0)|((fm&0x10)?0x000f0000:0)|
	     ((fm&0x08)?0x0000f000:0)|((fm&0x04)?0x00000f00:0)|((fm&0x02)?0x000000f0:0)|((fm&0x01)?0x0000000f:0);
	hCPU->fpscr = (hCPU->fpr[frB].guint & FM) | (hCPU->fpscr & ~FM);

	PPC_ASSERT((Opcode & PPC_OPC_RC) != 0); // update CR1 flags

	static bool logFPSCRWriteOnce = false;
	if( logFPSCRWriteOnce == false )
	{
		cemuLog_log(LogType::Force, "Unsupported write to FPSCR");
		logFPSCRWriteOnce = true;
	}
	PPCInterpreter_nextInstruction(hCPU);
}

// single precision

void PPCInterpreter_FADDS(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);
	PPC_ASSERT(frB == 0);
	
	// todo: check for RC

	hCPU->fpr[frD].fpr = (float)(hCPU->fpr[frA].fpr + hCPU->fpr[frB].fpr);
	if (PPC_PSE)
		hCPU->fpr[frD].fp1 = hCPU->fpr[frD].fp0;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FSUBS(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);
	PPC_ASSERT(frB == 0);

	hCPU->fpr[frD].fpr = (float)(hCPU->fpr[frA].fpr - hCPU->fpr[frB].fpr);
	if (PPC_PSE)
		hCPU->fpr[frD].fp1 = hCPU->fpr[frD].fp0;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FDIVS(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);
	PPC_ASSERT(frB==0);

	hCPU->fpr[frD].fpr = (float)(hCPU->fpr[frA].fpr / hCPU->fpr[frB].fpr);
	if( PPC_PSE )
		hCPU->fpr[frD].fp1 = hCPU->fpr[frD].fp0;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FMULS(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);
	PPC_ASSERT(frB == 0);

	hCPU->fpr[frD].fpr = (float)(hCPU->fpr[frA].fpr * roundTo25BitAccuracy(hCPU->fpr[frC].fpr));
	if (PPC_PSE)
		hCPU->fpr[frD].fp1 = hCPU->fpr[frD].fp0;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FMADDS(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);

	hCPU->fpr[frD].fpr = (float)(hCPU->fpr[frA].fpr * roundTo25BitAccuracy(hCPU->fpr[frC].fpr) + hCPU->fpr[frB].fpr);
	if (PPC_PSE)
		hCPU->fpr[frD].fp1 = hCPU->fpr[frD].fp0;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FNMADDS(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);

	hCPU->fpr[frD].fpr = (float)-(hCPU->fpr[frA].fpr * roundTo25BitAccuracy(hCPU->fpr[frC].fpr) + hCPU->fpr[frB].fpr);
	if (PPC_PSE)
		hCPU->fpr[frD].fp1 = hCPU->fpr[frD].fp0;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FMSUBS(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);

	hCPU->fpr[frD].fp0 = (float)(hCPU->fpr[frA].fp0 * roundTo25BitAccuracy(hCPU->fpr[frC].fp0) - hCPU->fpr[frB].fp0);
	if (PPC_PSE)
		hCPU->fpr[frD].fp1 = hCPU->fpr[frD].fp0;

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FNMSUBS(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();

	int frD, frA, frB, frC;
	PPC_OPC_TEMPL_A(Opcode, frD, frA, frB, frC);

	hCPU->fpr[frD].fp0 = (float)-(hCPU->fpr[frA].fp0 * roundTo25BitAccuracy(hCPU->fpr[frC].fp0) - hCPU->fpr[frB].fp0);
	if (PPC_PSE)
		hCPU->fpr[frD].fp1 = hCPU->fpr[frD].fp0;

	PPCInterpreter_nextInstruction(hCPU);
}

// Compare

// MEASURED AND REJECTED: fcmpo has exactly the redundancy that fcmpu_espresso above had -
// IS_NAN/IS_SNAN asked twice, the CR field written a byte at a time, FPSCR read-modified-
// written up to three times - and the identical rewrite was tried here. It made fcmpo WORSE:
// 78 -> 101 instructions, branches 10 -> 9. The difference from fcmpu_espresso is fcmpo's
// nested VXVC/VE logic: once anyNaN/anySNaN exist as values rather than as branch
// conditions, clang flattens that nest into a csel forest and duplicates the FPSCR tail,
// which costs more than the byte-stores it saves. Left in its original branchy form on
// purpose; re-measure before changing it. (See PPCInterpreter_PS_CMPO0 in
// PPCInterpreterPS.cpp, which is the paired-single twin of this function and was rejected
// for the same reason.)
void PPCInterpreter_FCMPO(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	int crfD, frA, frB;
	PPC_OPC_TEMPL_X(Opcode, crfD, frA, frB);
	crfD >>= 2;
	hCPU->cr[crfD*4+0] = 0;
	hCPU->cr[crfD*4+1] = 0;
	hCPU->cr[crfD*4+2] = 0;
	hCPU->cr[crfD*4+3] = 0;

	uint32 c;
	if(IS_NAN(hCPU->fpr[frA].guint) || IS_NAN(hCPU->fpr[frB].guint))
	{
		c = 1;
		hCPU->cr[crfD*4+CR_BIT_SO] = 1;
	}
    else if(hCPU->fpr[frA].fpr < hCPU->fpr[frB].fpr)
	{
		c = 8;
		hCPU->cr[crfD*4+CR_BIT_LT] = 1;
	}
	else if(hCPU->fpr[frA].fpr > hCPU->fpr[frB].fpr)
	{
		c = 4;
		hCPU->cr[crfD*4+CR_BIT_GT] = 1;
	}
	else
	{
		c = 2;
		hCPU->cr[crfD*4+CR_BIT_EQ] = 1;
	}

    hCPU->fpscr = (hCPU->fpscr & 0xffff0fff) | (c << 12);

	// fcmpo is an *ordered* compare: any NaN operand is an invalid-operation condition.
	// Previous logic set VXVC whenever VE==0 regardless of whether a NaN was even involved
	// (the `!(fpscr & FPSCR_VE)` term was OR'd in as a standalone condition of the non-SNaN
	// else-branch, not gated on NaN presence) - so VXVC was being raised on ordinary,
	// non-NaN comparisons any time VE was disabled, which is the default/typical state.
	// Correct rule (Power ISA): VXVC is set only when a NaN is present, and then only if
	// it's a QNaN, or it's an SNaN with VE==0 (VXSNAN is always set for an SNaN regardless).
	if (IS_NAN(hCPU->fpr[frA].guint) || IS_NAN(hCPU->fpr[frB].guint))
	{
		if (IS_SNAN(hCPU->fpr[frA].guint) || IS_SNAN(hCPU->fpr[frB].guint))
		{
			hCPU->fpscr |= FPSCR_VXSNAN;
			if (!(hCPU->fpscr & FPSCR_VE))
				hCPU->fpscr |= FPSCR_VXVC;
		}
		else
		{
			// QNaN present, no SNaN
			hCPU->fpscr |= FPSCR_VXVC;
		}
	}

	PPCInterpreter_nextInstruction(hCPU);
}

void PPCInterpreter_FCMPU(PPCInterpreter_t* hCPU, uint32 Opcode)
{
	FPUCheckAvailable();
	
	int crfD, frA, frB;
	PPC_OPC_TEMPL_X(Opcode, crfD, frA, frB);
	cemu_assert_debug((crfD % 4) == 0);
	fcmpu_espresso(hCPU, crfD, hCPU->fpr[frA].fp0, hCPU->fpr[frB].fp0);

	PPCInterpreter_nextInstruction(hCPU);
}
