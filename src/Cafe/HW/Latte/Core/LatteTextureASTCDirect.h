#pragma once
#include <cstdint>
#include <cstring>

// Direct BC to ASTC 4x4 block transcoding, with no encoder search.
//
// Most BC blocks are a straight line between two colours with 4 or 8 evenly spaced steps. ASTC 4x4 with one
// partition, two 8-bit endpoints and a 4x4 grid of 2-bit (4 steps) or 3-bit (8 steps) weights is the same
// line, so such a block becomes an ASTC block by packing bits: no decode to RGBA8 and no astcenc. The result
// is at least as close to the BC source as the astcenc FASTEST encode it replaces (it differs from the
// decoded source by rounding only). A block that is not such a line (BC1 with transparency, BC3 with varying
// alpha, BC4 in its 6-step mode) returns false and goes through astcenc as before.
//
// Block layout written here (ASTC spec, single partition, LDR):
//   bits 0-10   block mode: 4x4 weight grid, one plane, QUANT_4 (0x042) or QUANT_8 (0x053)
//   bits 11-12  partition count - 1 = 0
//   bits 13-16  colour endpoint mode: 8 (RGB direct) or 12 (RGBA direct)
//   bits 17-    endpoint values v0..v5 (or v0..v7), 8 bits each (QUANT_256 always fits in what is left)
//   top bits    the 16 weights, bit-reversed from bit 127 down
// RGB/RGBA direct decodes with blue contraction when v1+v3+v5 < v0+v2+v4, so endpoints are ordered to keep
// the second sum >= the first, flipping the weights when they are swapped.

namespace ASTCDirect
{
	inline uint8_t UNorm8(float v)
	{
		// Same rounding as astcFloatToUNorm8, so endpoints equal the decoded texels the astcenc path saw.
		if (v < 0.0f) v = 0.0f;
		if (v > 1.0f) v = 1.0f;
		return (uint8_t)(v * 255.0f + 0.5f);
	}

	inline uint64_t Reverse64(uint64_t v)
	{
		v = ((v >> 1) & 0x5555555555555555ull) | ((v & 0x5555555555555555ull) << 1);
		v = ((v >> 2) & 0x3333333333333333ull) | ((v & 0x3333333333333333ull) << 2);
		v = ((v >> 4) & 0x0F0F0F0F0F0F0F0Full) | ((v & 0x0F0F0F0F0F0F0F0Full) << 4);
		v = ((v >> 8) & 0x00FF00FF00FF00FFull) | ((v & 0x00FF00FF00FF00FFull) << 8);
		v = ((v >> 16) & 0x0000FFFF0000FFFFull) | ((v & 0x0000FFFF0000FFFFull) << 16);
		return (v >> 32) | (v << 32);
	}

	// e0/e1: RGBA endpoints. weights: 16 values in [0, 2^weightBits). weightBits 2 or 3. withAlpha picks CEM 12.
	inline void Pack(uint8_t* block, uint8_t e0[4], uint8_t e1[4], uint8_t weights[16], uint32_t weightBits, bool withAlpha)
	{
		const uint32_t maxWeight = (1u << weightBits) - 1;
		bool flip = false;
		if ((uint32_t)e1[0] + e1[1] + e1[2] < (uint32_t)e0[0] + e0[1] + e0[2])
		{
			uint8_t* t = e0; e0 = e1; e1 = t;
			flip = true;
		}
		// Header and endpoints: the endpoint bytes run from bit 17 to bit 65 (RGB) or 81 (RGBA).
		uint64_t lo = (weightBits == 2 ? 0x042ull : 0x053ull) | ((withAlpha ? 12ull : 8ull) << 13);
		uint64_t hi = 0;
		const uint32_t channels = withAlpha ? 4 : 3;
		for (uint32_t c = 0; c < channels; c++)
		{
			const uint32_t pos = 17 + c * 16;
			const uint64_t pair = (uint64_t)e0[c] | ((uint64_t)e1[c] << 8);
			if (pos >= 64)
				hi |= pair << (pos - 64);
			else
			{
				lo |= pair << pos;
				if (pos + 16 > 64)
					hi |= pair >> (64 - pos);
			}
		}
		// Weights: a little-endian bit stream, stored bit-reversed from bit 127 down.
		uint64_t stream = 0;
		for (uint32_t i = 0; i < 16; i++)
			stream |= (uint64_t)(flip ? maxWeight - weights[i] : weights[i]) << (i * weightBits);
		hi |= Reverse64(stream);
		memcpy(block, &lo, 8);
		memcpy(block + 8, &hi, 8);
	}

	// BC colour block (BC1, or the colour half of BC2/BC3). fourColour: BC2/BC3 always interpolate 4 colours.
	// Writes the RGB endpoints and the weights; false when the block cannot be a 4-step line.
	inline bool ColourLine(const uint8_t* bc, bool alwaysFourColour, uint8_t e0[4], uint8_t e1[4], uint8_t weights[16])
	{
		uint16_t c0, c1;
		uint32_t indices;
		memcpy(&c0, bc + 0, 2);
		memcpy(&c1, bc + 2, 2);
		memcpy(&indices, bc + 4, 4);
		const bool fourColour = alwaysFourColour || c0 > c1;
		if (!fourColour)
		{
			// Three colours plus transparent black. Still a line when only the two endpoints are used and
			// index 3 (transparent) never is; the 1/2 step has no exact ASTC 2-bit weight.
			for (int i = 0; i < 16; i++)
				if (((indices >> (2 * i)) & 3) >= 2)
					return false;
		}
		e0[0] = UNorm8((float)((c0 >> 11) & 0x1F) / 31.0f);
		e0[1] = UNorm8((float)((c0 >> 5) & 0x3F) / 63.0f);
		e0[2] = UNorm8((float)(c0 & 0x1F) / 31.0f);
		e1[0] = UNorm8((float)((c1 >> 11) & 0x1F) / 31.0f);
		e1[1] = UNorm8((float)((c1 >> 5) & 0x3F) / 63.0f);
		e1[2] = UNorm8((float)(c1 & 0x1F) / 31.0f);
		// BC index 0 = c0, 1 = c1, 2 = 2/3 c0 + 1/3 c1, 3 = 1/3 c0 + 2/3 c1. ASTC 2-bit weights are 0, 1/3, 2/3, 1
		// of the way to e1.
		static const uint8_t kMap[4] = {0, 3, 1, 2};
		for (int i = 0; i < 16; i++)
			weights[i] = kMap[(indices >> (2 * i)) & 3];
		return true;
	}

	inline bool BC1(const uint8_t* bc, uint8_t* out)
	{
		uint8_t e0[4], e1[4], w[16];
		if (!ColourLine(bc, false, e0, e1, w))
			return false;
		e0[3] = e1[3] = 255;
		Pack(out, e0, e1, w, 2, false);
		return true;
	}

	// BC2/BC3: the colour half is always a 4-step line; the block is direct when every texel has the same alpha.
	inline bool WithConstantAlpha(const uint8_t* bc, uint8_t alpha, uint8_t* out)
	{
		uint8_t e0[4], e1[4], w[16];
		ColourLine(bc + 8, true, e0, e1, w);
		e0[3] = e1[3] = alpha;
		Pack(out, e0, e1, w, 2, alpha != 255);
		return true;
	}

	inline bool BC2(const uint8_t* bc, uint8_t* out)
	{
		const uint8_t code = bc[0] & 0xF;
		for (int i = 0; i < 8; i++)
			if (bc[i] != (uint8_t)(code | (code << 4)))
				return false;
		return WithConstantAlpha(bc, UNorm8((float)(code | (code << 4)) / 255.0f), out);
	}

	// The alpha of every texel of a BC3/BC4 8-value block; false when the indices are not all one value.
	inline bool ConstantBC4Value(const uint8_t* b, float& value)
	{
		uint64_t bits = 0;
		for (int i = 0; i < 6; i++)
			bits |= (uint64_t)b[2 + i] << (8 * i);
		const uint32_t first = bits & 7;
		for (int i = 1; i < 16; i++)
			if (((bits >> (3 * i)) & 7) != first)
				return false;
		const float a0 = b[0] / 255.0f, a1 = b[1] / 255.0f;
		static const float k7[8] = {0, 7, 1, 2, 3, 4, 5, 6}; // steps toward a1, out of 7
		static const float k5[8] = {0, 5, 1, 2, 3, 4, 0, 0};
		if (b[0] > b[1])
			value = (a0 * (7.0f - k7[first]) + a1 * k7[first]) / 7.0f;
		else if (first == 6)
			value = 0.0f;
		else if (first == 7)
			value = 1.0f;
		else
			value = (a0 * (5.0f - k5[first]) + a1 * k5[first]) / 5.0f;
		return true;
	}

	inline bool BC3(const uint8_t* bc, uint8_t* out)
	{
		float alpha;
		if (!ConstantBC4Value(bc, alpha))
			return false;
		return WithConstantAlpha(bc, UNorm8(alpha), out);
	}

	// BC4 unsigned decodes to (r, 0, 0, 255), the same as the RGBA8 the astcenc path encodes.
	inline bool BC4U(const uint8_t* bc, uint8_t* out)
	{
		uint64_t bits = 0;
		for (int i = 0; i < 6; i++)
			bits |= (uint64_t)bc[2 + i] << (8 * i);
		uint8_t w[16];
		uint32_t weightBits;
		if (bc[0] > bc[1])
		{
			// 8 steps: index 0 = r0, 1 = r1, k = 2..7 is (k - 1)/7 of the way to r1.
			static const uint8_t kMap[8] = {0, 7, 1, 2, 3, 4, 5, 6};
			for (int i = 0; i < 16; i++)
				w[i] = kMap[(bits >> (3 * i)) & 7];
			weightBits = 3;
		}
		else
		{
			// 6-step mode with explicit 0 and 1: a line only when just the two endpoints are used.
			for (int i = 0; i < 16; i++)
			{
				const uint32_t idx = (bits >> (3 * i)) & 7;
				if (idx >= 2)
					return false;
				w[i] = (uint8_t)(idx * 3);
			}
			weightBits = 2;
		}
		uint8_t e0[4] = {UNorm8(bc[0] / 255.0f), 0, 0, 255};
		uint8_t e1[4] = {UNorm8(bc[1] / 255.0f), 0, 0, 255};
		Pack(out, e0, e1, w, weightBits, false);
		return true;
	}
}
