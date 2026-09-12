#include "Cafe/HW/Latte/Renderer/Renderer.h"
#include "Cafe/HW/Latte/LatteAddrLib/LatteAddrLib.h"
#include "config/ActiveSettings.h"
#include "Cafe/CafeSystem.h"

#if defined(__aarch64__)
// NEON paths for the packed-palette BC decoders further down. vqtbl1q_u8 is AArch64-only, so
// this is gated on arm64 rather than on __ARM_NEON, which is also true of 32 bit ARM. MSVC's
// _M_ARM64 is deliberately left out: it spells the vector types differently enough that the
// brace initialisers below would not compile, and there is no arm64 Windows build here to
// test on. That target keeps the scalar path, which is correct, only slower.
#include <arm_neon.h>
#define LATTE_TEXLOADER_NEON 1
#endif

//#define BENCHMARK_TEXTURE_DECODING		// if defined, time it takes to decode textures will be measured and logged to log.txt

#ifdef BENCHMARK_TEXTURE_DECODING
uint64 textureDecodeBenchmark_perFormatSum[0x40] = { 0 }; // duration sum per texture format (hw format) - in microseconds
uint64 textureDecodeBenchmark_totalSum = 0;
#endif

void LatteTextureLoader_begin(LatteTextureLoaderCtx* textureLoader, uint32 sliceIndex, uint32 mipIndex, MPTR physImagePtr, MPTR physMipPtr, Latte::E_GX2SURFFMT format, Latte::E_DIM dim, uint32 width, uint32 height, uint32 depth, uint32 mipLevels, uint32 pitch, Latte::E_HWTILEMODE tileMode, uint32 swizzle)
{
	textureLoader->physAddress = physImagePtr;
	textureLoader->physMipAddress = physMipPtr;
	textureLoader->sliceIndex = sliceIndex;
	cemu_assert_debug(mipLevels != 0);
	textureLoader->mipLevels = std::max<uint32>(1, mipLevels);
	textureLoader->tileMode = tileMode;
	textureLoader->bpp = Latte::GetFormatBits(format);
	textureLoader->stepX = 1;
	textureLoader->stepY = 1;
	if (Latte::IsCompressedFormat(format))
	{
		textureLoader->stepX = 4;
		textureLoader->stepY = 4;
	}

	textureLoader->pipeSwizzle = (swizzle >> 8) & 1;
	textureLoader->bankSwizzle = ((swizzle >> 9) & 3);

	uint32 surfaceAA = 0; // todo

	if (mipIndex > 0 && Latte::TM_IsMacroTiled(tileMode))
	{
		// separate swizzle from mip pointer if mip chain is not macro-tiled (and thus not swizzled)
		LatteAddrLib::AddrSurfaceInfo_OUT surfaceInfo;
		LatteAddrLib::GX2CalculateSurfaceInfo(format, width, height, depth, dim, Latte::MakeGX2TileMode(tileMode), surfaceAA, 1, &surfaceInfo);
		if (Latte::TM_IsMacroTiled(surfaceInfo.hwTileMode))
		{
			uint32 mipSwizzle = physMipPtr&0x700;
			physMipPtr &= ~0x700;
			textureLoader->physMipAddress = physMipPtr;
			textureLoader->pipeSwizzle = (mipSwizzle >> 8) & 1;
			textureLoader->bankSwizzle = ((mipSwizzle >> 9) & 3);
		}
	}

	// calculate surface info
	uint32 level = mipIndex;
	LatteAddrLib::AddrSurfaceInfo_OUT surfaceInfo;
	LatteAddrLib::GX2CalculateSurfaceInfo(format, width, height, depth, dim, Latte::MakeGX2TileMode(tileMode), surfaceAA, level, &surfaceInfo);
	textureLoader->levelOffset = LatteAddrLib::CalculateMipOffset(format, width, height, depth, dim, (Latte::E_HWTILEMODE)tileMode, swizzle, surfaceAA, level);
	textureLoader->tileMode = surfaceInfo.hwTileMode;

	textureLoader->minOffsetOutdated = 0;
	textureLoader->maxOffsetOutdated = (sint32)surfaceInfo.surfSize;

	textureLoader->surfaceInfoHeight = surfaceInfo.height;
	textureLoader->surfaceInfoDepth = surfaceInfo.depth;

	// correct handling for LINEAR_ALIGNED pitch alignment is still not fully understood:
	//seems like sometimes there is a conditional pitch alignment to 0x40 OR there is no pitch alignment at all and we have a bug somewhere else

	uint64 titleId = CafeSystem::GetForegroundTitleId();
	titleId &= ~0x300ULL;

	if (tileMode == Latte::E_HWTILEMODE::TM_LINEAR_ALIGNED && titleId == (0x000500301001200aULL))
	{
		// examples of titles that use linear textures:
		// Minecraft - Uses sprite atlases with mips and linear tilemode. Expects padding of pitch for smaller mips to be 0x40
		// Browser - Linear pitch must be used as-is, padding/alignment will break textures (uses a weird way to calculate pitch by using GX2CalcSurface on a texture with tileMode 0/4)
		// BotW - uses linear textures as render targets. With the smallest resolution being 3x3 with no pitch alignment expected at all (pitch = 3)? -> Not possible because both textures and rendertargets require a minimum alignment of 8 for pitch?
		surfaceInfo.pitch = std::max<uint32>(1, pitch >> mipIndex);
	}


	textureLoader->width = width >> (mipIndex);
	textureLoader->width = std::max(textureLoader->width, 1);
	textureLoader->height = height >> (mipIndex);
	textureLoader->height = std::max(textureLoader->height, 1);

	textureLoader->pitch = surfaceInfo.pitch;
	// calculate start address
	if (level == 0)
		textureLoader->inputData = (uint8*)memory_getPointerFromPhysicalOffset(physImagePtr);
	else
		textureLoader->inputData = (uint8*)memory_getPointerFromPhysicalOffset(physMipPtr) + textureLoader->levelOffset;

	SetupCachedSurfaceAddrInfo(&textureLoader->computeAddrInfo, textureLoader->sliceIndex, 0, textureLoader->bpp, textureLoader->pitch, surfaceInfo.height, depth, 1 * 1, textureLoader->tileMode, false, textureLoader->pipeSwizzle, textureLoader->bankSwizzle);
}

uint8* LatteTextureLoader_GetInput(LatteTextureLoaderCtx* textureLoader, sint32 x, sint32 y)
{
	// calculate address of input tile
	uint32 offset = 0;
	if (textureLoader->tileMode == Latte::E_HWTILEMODE::TM_LINEAR_GENERAL || textureLoader->tileMode == Latte::E_HWTILEMODE::TM_LINEAR_ALIGNED)
		offset = LatteAddrLib::ComputeSurfaceAddrFromCoordLinear(x / textureLoader->stepX, y / textureLoader->stepY, textureLoader->sliceIndex, 0, textureLoader->bpp, textureLoader->pitch, textureLoader->surfaceInfoHeight, textureLoader->surfaceInfoDepth);
	else if (textureLoader->tileMode == Latte::E_HWTILEMODE::TM_1D_TILED_THIN1 || textureLoader->tileMode == Latte::E_HWTILEMODE::TM_1D_TILED_THICK)
		offset = LatteAddrLib::ComputeSurfaceAddrFromCoordMicroTiled(x / textureLoader->stepX, y / textureLoader->stepY, textureLoader->sliceIndex, textureLoader->bpp, textureLoader->pitch, textureLoader->surfaceInfoHeight, (Latte::E_HWTILEMODE)textureLoader->tileMode, false);
	else
		offset = LatteAddrLib::ComputeSurfaceAddrFromCoordMacroTiledCached(x / textureLoader->stepX, y / textureLoader->stepY, &textureLoader->computeAddrInfo);
	uint8* blockData = textureLoader->inputData + offset;
	return blockData;
}

/*
 * Optimized version which assumes tileMode == 1
 * Also does not do any min/max offset tracking
 */
uint8* LatteTextureLoader_getInputLinearOptimized(LatteTextureLoaderCtx* textureLoader, sint32 x, sint32 y)
{
	// calculate address of input tile
	uint32 bitPos = 0;
	uint32 offset = 0;
	offset = LatteAddrLib::ComputeSurfaceAddrFromCoordLinear(x / textureLoader->stepX, y / textureLoader->stepY, textureLoader->sliceIndex, 0, textureLoader->bpp, textureLoader->pitch, textureLoader->surfaceInfoHeight, textureLoader->surfaceInfoDepth);
	return textureLoader->inputData + offset;
}

#define LatteTextureLoader_getInputLinearOptimized_(__textureLoader,__x,__y,__stepX,__stepY,__bpp,__sliceIndex,__numSlices,__sample,__pitch,__height) (textureLoader->inputData+((__x/__stepX) + __pitch * (__y/__stepY) + (__sliceIndex + __numSlices * __sample) * __height * __pitch)*(__bpp/8))

void decodeBC1Block(uint8* inputData, float* output4x4RGBA)
{
	// read colors
	uint16 c0 = *(uint16*)(inputData + 0);
	uint16 c1 = *(uint16*)(inputData + 2);
	// decode colors (RGB565 -> RGB888)
	float r[4];
	float g[4];
	float b[4];
	float a[4];
	b[0] = (float)((c0 >> 0) & 0x1F) / 31.0f;
	b[1] = (float)((c1 >> 0) & 0x1F) / 31.0f;
	g[0] = (float)((c0 >> 5) & 0x3F) / 63.0f;
	g[1] = (float)((c1 >> 5) & 0x3F) / 63.0f;
	r[0] = (float)((c0 >> 11) & 0x1F) / 31.0f;
	r[1] = (float)((c1 >> 11) & 0x1F) / 31.0f;
	a[0] = 1.0f;
	a[1] = 1.0f;
	a[2] = 1.0f;

	if (c0 > c1)
	{
		r[2] = (r[0] * 2.0f + r[1]) / 3.0f;
		r[3] = (r[0] * 1.0f + r[1] * 2.0f) / 3.0f;
		g[2] = (g[0] * 2.0f + g[1]) / 3.0f;
		g[3] = (g[0] * 1.0f + g[1] * 2.0f) / 3.0f;
		b[2] = (b[0] * 2.0f + b[1]) / 3.0f;
		b[3] = (b[0] * 1.0f + b[1] * 2.0f) / 3.0f;
		a[3] = 1.0f;
	}
	else
	{
		r[2] = (r[0] + r[1]) / 2.0f;
		r[3] = 0.0f;
		g[2] = (g[0] + g[1]) / 2.0f;
		g[3] = 0.0f;
		b[2] = (b[0] + b[1]) / 2.0f;
		b[3] = 0.0f;
		a[3] = 0.0f;
	}

	uint8* indexData = inputData + 4;
	float* colorOutputRGBA = output4x4RGBA;
	for (sint32 row = 0; row < 4; row++)
	{
		uint8 i0 = ((*indexData) >> 0) & 3;
		uint8 i1 = ((*indexData) >> 2) & 3;
		uint8 i2 = ((*indexData) >> 4) & 3;
		uint8 i3 = ((*indexData) >> 6) & 3;
		colorOutputRGBA[0] = r[i0];
		colorOutputRGBA[1] = g[i0];
		colorOutputRGBA[2] = b[i0];
		colorOutputRGBA[3] = a[i0];
		colorOutputRGBA += 4;
		colorOutputRGBA[0] = r[i1];
		colorOutputRGBA[1] = g[i1];
		colorOutputRGBA[2] = b[i1];
		colorOutputRGBA[3] = a[i1];
		colorOutputRGBA += 4;
		colorOutputRGBA[0] = r[i2];
		colorOutputRGBA[1] = g[i2];
		colorOutputRGBA[2] = b[i2];
		colorOutputRGBA[3] = a[i2];
		colorOutputRGBA += 4;
		colorOutputRGBA[0] = r[i3];
		colorOutputRGBA[1] = g[i3];
		colorOutputRGBA[2] = b[i3];
		colorOutputRGBA[3] = a[i3];
		colorOutputRGBA += 4;
		indexData++;
	}
}

void decodeBC2Block_UNORM(uint8* inputData, float* imageRGBA)
{
	uint32 color0 = *(uint16*)(inputData + 8);
	uint32 color1 = *(uint16*)(inputData + 10);
	uint32 colorIndices = *(uint32*)(inputData + 12);

	uint8 r0 = (color0 >> 11) & 0x1F;
	uint8 g0 = (color0 >> 5) & 0x3F;
	uint8 b0 = (color0 >> 0) & 0x1F;

	uint8 r1 = (color1 >> 11) & 0x1F;
	uint8 g1 = (color1 >> 5) & 0x3F;
	uint8 b1 = (color1 >> 0) & 0x1F;

	float r[4];
	float g[4];
	float b[4];
	r[0] = (float)r0 / 31.0f;
	r[1] = (float)r1 / 31.0f;
	r[2] = (r[0] * 2.0f + r[1]) / 3.0f;
	r[3] = (r[0] + r[1] * 2.0f) / 3.0f;
	g[0] = (float)g0 / 63.0f;
	g[1] = (float)g1 / 63.0f;
	g[2] = (g[0] * 2.0f + g[1]) / 3.0f;
	g[3] = (g[0] + g[1] * 2.0f) / 3.0f;
	b[0] = (float)b0 / 31.0f;
	b[1] = (float)b1 / 31.0f;
	b[2] = (b[0] * 2.0f + b[1]) / 3.0f;
	b[3] = (b[0] + b[1] * 2.0f) / 3.0f;

	for (sint32 py = 0; py < 4; py++)
	{
		for (sint32 px = 0; px < 4; px++)
		{
			uint8 colorIndex = (colorIndices >> (2 * (px + 4 * py))) & 0x03;
			sint32 pixelOffset = (px + py * 4) * 4;
			imageRGBA[pixelOffset + 0] = r[colorIndex];
			imageRGBA[pixelOffset + 1] = g[colorIndex];
			imageRGBA[pixelOffset + 2] = b[colorIndex];
		}
	}

	// decode alpha
	uint8* alphaData = (uint8*)(inputData + 0);
	for (sint32 py = 0; py < 4; py++)
	{
		for (sint32 px = 0; px < 4; px++)
		{
			uint32 alphaIndex = (px + py * 4);
			uint8 alphaCode = (alphaData[alphaIndex / 2] >> ((alphaIndex & 1) * 4)) & 0xF;
			alphaCode |= (alphaCode << 4);
			sint32 pixelOffset = (px + py * 4) * 4;
			imageRGBA[pixelOffset + 3] = (float)alphaCode / 255.0f; // alpha
		}
	}
}

void decodeBC3Block_UNORM(uint8* inputData, float* imageRGBA)
{
	uint32 color0 = *(uint16*)(inputData + 8);
	uint32 color1 = *(uint16*)(inputData + 10);
	uint32 colorIndices = *(uint32*)(inputData + 12);

	uint8 r0 = (color0 >> 11) & 0x1F;
	uint8 g0 = (color0 >> 5) & 0x3F;
	uint8 b0 = (color0 >> 0) & 0x1F;

	uint8 r1 = (color1 >> 11) & 0x1F;
	uint8 g1 = (color1 >> 5) & 0x3F;
	uint8 b1 = (color1 >> 0) & 0x1F;

	float r[4];
	float g[4];
	float b[4];
	r[0] = (float)r0 / 31.0f;
	r[1] = (float)r1 / 31.0f;
	r[2] = (r[0] * 2.0f + r[1]) / 3.0f;
	r[3] = (r[0] + r[1] * 2.0f) / 3.0f;
	g[0] = (float)g0 / 63.0f;
	g[1] = (float)g1 / 63.0f;
	g[2] = (g[0] * 2.0f + g[1]) / 3.0f;
	g[3] = (g[0] + g[1] * 2.0f) / 3.0f;
	b[0] = (float)b0 / 31.0f;
	b[1] = (float)b1 / 31.0f;
	b[2] = (b[0] * 2.0f + b[1]) / 3.0f;
	b[3] = (b[0] + b[1] * 2.0f) / 3.0f;

	for (sint32 py = 0; py < 4; py++)
	{
		for (sint32 px = 0; px < 4; px++)
		{
			uint8 colorIndex = (colorIndices >> (2 * (px + 4 * py))) & 0x03;
			sint32 pixelOffset = (px + py * 4) * 4;
			imageRGBA[pixelOffset + 0] = r[colorIndex];
			imageRGBA[pixelOffset + 1] = g[colorIndex];
			imageRGBA[pixelOffset + 2] = b[colorIndex];
			//imageRGBA[pixelOffset+3] = 1.0f; // alpha
		}
	}

	// decode alpha
	uint8 alpha0 = *(uint8*)(inputData + 0);
	uint8 alpha1 = *(uint8*)(inputData + 1);
	uint32 alphaCodeRow[2] = { 0 };
	alphaCodeRow[0] |= ((*(uint8*)(inputData + 2)) << 0);
	alphaCodeRow[0] |= ((*(uint8*)(inputData + 3)) << 8);
	alphaCodeRow[0] |= ((*(uint8*)(inputData + 4)) << 16);
	alphaCodeRow[1] |= ((*(uint8*)(inputData + 5)) << 0);
	alphaCodeRow[1] |= ((*(uint8*)(inputData + 6)) << 8);
	alphaCodeRow[1] |= ((*(uint8*)(inputData + 7)) << 16);

	float a[8];
	a[0] = (float)alpha0 / 255.0f;
	a[1] = (float)alpha1 / 255.0f;

	if (alpha0 > alpha1)
	{
		// 6 interpolated alpha values.
		a[2] = (a[0] * 6.0f + a[1] * 1.0f) / 7.0f;
		a[3] = (a[0] * 5.0f + a[1] * 2.0f) / 7.0f;
		a[4] = (a[0] * 4.0f + a[1] * 3.0f) / 7.0f;
		a[5] = (a[0] * 3.0f + a[1] * 4.0f) / 7.0f;
		a[6] = (a[0] * 2.0f + a[1] * 5.0f) / 7.0f;
		a[7] = (a[0] * 1.0f + a[1] * 6.0f) / 7.0f;
	}
	else
	{
		// 4 interpolated alpha values.
		a[2] = (a[0] * 4.0f + a[1] * 1.0f) / 5.0f;
		a[3] = (a[0] * 3.0f + a[1] * 2.0f) / 5.0f;
		a[4] = (a[0] * 2.0f + a[1] * 3.0f) / 5.0f;
		a[5] = (a[0] * 1.0f + a[1] * 4.0f) / 5.0f;
		a[6] = 0.0f;
		a[7] = 1.0f;
	}

	for (sint32 py = 0; py < 4; py++)
	{
		for (sint32 px = 0; px < 4; px++)
		{
			uint8 alphaCode = (alphaCodeRow[py / 2] >> 3 * (px + 4 * (py & 1))) & 0x07;
			sint32 pixelOffset = (px + py * 4) * 4;
			imageRGBA[pixelOffset + 3] = a[alphaCode]; // alpha
		}
	}
}

void decodeBC4Block_UNORM(uint8* blockStorage, float* rOutput)
{
	uint8* blockInput = (uint8*)blockStorage;
	float red[8];

	red[0] = ((float)(*(uint8*)(blockInput + 0))) / 255.0f;
	red[1] = ((float)(*(uint8*)(blockInput + 1))) / 255.0f;

	if (blockInput[0] > blockInput[1])
	{
		// 6 interpolated color values
		red[2] = (6 * red[0] + 1 * red[1]) / 7.0f; // bit code 010
		red[3] = (5 * red[0] + 2 * red[1]) / 7.0f; // bit code 011
		red[4] = (4 * red[0] + 3 * red[1]) / 7.0f; // bit code 100
		red[5] = (3 * red[0] + 4 * red[1]) / 7.0f; // bit code 101
		red[6] = (2 * red[0] + 5 * red[1]) / 7.0f; // bit code 110
		red[7] = (1 * red[0] + 6 * red[1]) / 7.0f; // bit code 111
	}
	else
	{
		// 4 interpolated color values
		red[2] = (4 * red[0] + 1 * red[1]) / 5.0f; // bit code 010
		red[3] = (3 * red[0] + 2 * red[1]) / 5.0f; // bit code 011
		red[4] = (2 * red[0] + 3 * red[1]) / 5.0f; // bit code 100
		red[5] = (1 * red[0] + 4 * red[1]) / 5.0f; // bit code 101
		red[6] = 0.0f;                       // bit code 110
		red[7] = 1.0f;                       // bit code 111
	}

	uint8* bitIndices = blockInput + 2;
	uint32 redRow0 = (((uint32)bitIndices[2]) << 16) | (((uint32)bitIndices[1]) << 8) | (((uint32)bitIndices[0]) << 0);
	uint32 redRow1 = (((uint32)bitIndices[5]) << 16) | (((uint32)bitIndices[4]) << 8) | (((uint32)bitIndices[3]) << 0);

	uint8 pRed[16];
	for (sint32 i = 0; i < 8; i++)
	{
		pRed[i] = (redRow0 >> (i * 3)) & 7;
		pRed[i + 8] = (redRow1 >> (i * 3)) & 7;
	}

	float* pixelOutput = rOutput;
	for (sint32 py = 0; py < 4; py++)
	{
		for (sint32 px = 0; px < 4; px++)
		{
			float c = red[pRed[px + py * 4]];
			*pixelOutput = c;
			pixelOutput++;
		}
	}
}

void decodeBC5Block_UNORM(uint8* blockStorage, float* rgOutput)
{
	uint8* blockInput = (uint8*)blockStorage;
	float red[8];
	float green[8];

	red[0] = ((float)(*(uint8*)(blockInput + 0))) / 255.0f;
	red[1] = ((float)(*(uint8*)(blockInput + 1))) / 255.0f;

	if (red[0] > red[1])
	{
		// 6 interpolated color values
		red[2] = (6 * red[0] + 1 * red[1]) / 7.0f; // bit code 010
		red[3] = (5 * red[0] + 2 * red[1]) / 7.0f; // bit code 011
		red[4] = (4 * red[0] + 3 * red[1]) / 7.0f; // bit code 100
		red[5] = (3 * red[0] + 4 * red[1]) / 7.0f; // bit code 101
		red[6] = (2 * red[0] + 5 * red[1]) / 7.0f; // bit code 110
		red[7] = (1 * red[0] + 6 * red[1]) / 7.0f; // bit code 111
	}
	else
	{
		// 4 interpolated color values
		red[2] = (4 * red[0] + 1 * red[1]) / 5.0f; // bit code 010
		red[3] = (3 * red[0] + 2 * red[1]) / 5.0f; // bit code 011
		red[4] = (2 * red[0] + 3 * red[1]) / 5.0f; // bit code 100
		red[5] = (1 * red[0] + 4 * red[1]) / 5.0f; // bit code 101
		red[6] = 0.0f;                       // bit code 110
		red[7] = 1.0f;                       // bit code 111
	}

	green[0] = ((float)(*(uint8*)(blockInput + 8))) / 255.0f;
	green[1] = ((float)(*(uint8*)(blockInput + 9))) / 255.0f;

	if (green[0] > green[1])
	{
		// 6 interpolated color values
		green[2] = (6 * green[0] + 1 * green[1]) / 7.0f; // bit code 010
		green[3] = (5 * green[0] + 2 * green[1]) / 7.0f; // bit code 011
		green[4] = (4 * green[0] + 3 * green[1]) / 7.0f; // bit code 100
		green[5] = (3 * green[0] + 4 * green[1]) / 7.0f; // bit code 101
		green[6] = (2 * green[0] + 5 * green[1]) / 7.0f; // bit code 110
		green[7] = (1 * green[0] + 6 * green[1]) / 7.0f; // bit code 111
	}
	else
	{
		// 4 interpolated color values
		green[2] = (4 * green[0] + 1 * green[1]) / 5.0f; // bit code 010
		green[3] = (3 * green[0] + 2 * green[1]) / 5.0f; // bit code 011
		green[4] = (2 * green[0] + 3 * green[1]) / 5.0f; // bit code 100
		green[5] = (1 * green[0] + 4 * green[1]) / 5.0f; // bit code 101
		green[6] = 0.0f;						   // bit code 110
		green[7] = 1.0f;                           // bit code 111
	}


	uint8* bitIndices = blockInput + 2;
	uint32 redRow0 = (((uint32)bitIndices[2]) << 16) | (((uint32)bitIndices[1]) << 8) | (((uint32)bitIndices[0]) << 0);
	uint32 redRow1 = (((uint32)bitIndices[5]) << 16) | (((uint32)bitIndices[4]) << 8) | (((uint32)bitIndices[3]) << 0);
	bitIndices = blockInput + 8 + 2;
	uint32 greenRow0 = (((uint32)bitIndices[2]) << 16) | (((uint32)bitIndices[1]) << 8) | (((uint32)bitIndices[0]) << 0);
	uint32 greenRow1 = (((uint32)bitIndices[5]) << 16) | (((uint32)bitIndices[4]) << 8) | (((uint32)bitIndices[3]) << 0);

	uint8 pRed[16];
	uint8 pGreen[16];
	for (sint32 i = 0; i < 8; i++)
	{
		pRed[i] = (redRow0 >> (i * 3)) & 7;
		pRed[i + 8] = (redRow1 >> (i * 3)) & 7;
		pGreen[i] = (greenRow0 >> (i * 3)) & 7;
		pGreen[i + 8] = (greenRow1 >> (i * 3)) & 7;
	}

	float* pixelOutput = rgOutput;
	for (sint32 py = 0; py < 4; py++)
	{
		for (sint32 px = 0; px < 4; px++)
		{
			float c = red[pRed[px + py * 4]];
			*pixelOutput = c;
			pixelOutput++;
			c = green[pGreen[px + py * 4]];
			*pixelOutput = c;
			pixelOutput++;
		}
	}
}

void decodeBC5Block_SNORM(uint8* blockStorage, float* rgOutput) // todo - can merge this with the UNORM implementation by using a template?
{
	uint8* blockInput = (uint8*)blockStorage;
	float red[8];
	float green[8];

	red[0] = ((float)(*(sint8*)(blockInput + 0)) + 128.0f) / 255.0f;
	red[1] = ((float)(*(sint8*)(blockInput + 1)) + 128.0f) / 255.0f;
	red[0] = (red[0] * 2.0f - 1.0f);
	red[1] = (red[1] * 2.0f - 1.0f);

	if (red[0] > red[1])
	{
		// 6 interpolated color values
		red[2] = (6 * red[0] + 1 * red[1]) / 7.0f; // bit code 010
		red[3] = (5 * red[0] + 2 * red[1]) / 7.0f; // bit code 011
		red[4] = (4 * red[0] + 3 * red[1]) / 7.0f; // bit code 100
		red[5] = (3 * red[0] + 4 * red[1]) / 7.0f; // bit code 101
		red[6] = (2 * red[0] + 5 * red[1]) / 7.0f; // bit code 110
		red[7] = (1 * red[0] + 6 * red[1]) / 7.0f; // bit code 111
	}
	else
	{
		// 4 interpolated color values
		red[2] = (4 * red[0] + 1 * red[1]) / 5.0f; // bit code 010
		red[3] = (3 * red[0] + 2 * red[1]) / 5.0f; // bit code 011
		red[4] = (2 * red[0] + 3 * red[1]) / 5.0f; // bit code 100
		red[5] = (1 * red[0] + 4 * red[1]) / 5.0f; // bit code 101
		red[6] = -1.0f;                       // bit code 110
		red[7] = 1.0f;                       // bit code 111
	}

	green[0] = ((float)(*(sint8*)(blockInput + 8)) + 128.0f) / 255.0f;
	green[1] = ((float)(*(sint8*)(blockInput + 9)) + 128.0f) / 255.0f;
	green[0] = (green[0] * 2.0f - 1.0f);
	green[1] = (green[1] * 2.0f - 1.0f);

	if (green[0] > green[1])
	{
		// 6 interpolated color values
		green[2] = (6 * green[0] + 1 * green[1]) / 7.0f; // bit code 010
		green[3] = (5 * green[0] + 2 * green[1]) / 7.0f; // bit code 011
		green[4] = (4 * green[0] + 3 * green[1]) / 7.0f; // bit code 100
		green[5] = (3 * green[0] + 4 * green[1]) / 7.0f; // bit code 101
		green[6] = (2 * green[0] + 5 * green[1]) / 7.0f; // bit code 110
		green[7] = (1 * green[0] + 6 * green[1]) / 7.0f; // bit code 111
	}
	else
	{
		// 4 interpolated color values
		green[2] = (4 * green[0] + 1 * green[1]) / 5.0f; // bit code 010
		green[3] = (3 * green[0] + 2 * green[1]) / 5.0f; // bit code 011
		green[4] = (2 * green[0] + 3 * green[1]) / 5.0f; // bit code 100
		green[5] = (1 * green[0] + 4 * green[1]) / 5.0f; // bit code 101
		green[6] = -1.0f;                       // bit code 110
		green[7] = 1.0f;                       // bit code 111
	}


	uint8* bitIndices = blockInput + 2;
	uint32 redRow0 = (((uint32)bitIndices[2]) << 16) | (((uint32)bitIndices[1]) << 8) | (((uint32)bitIndices[0]) << 0);
	uint32 redRow1 = (((uint32)bitIndices[5]) << 16) | (((uint32)bitIndices[4]) << 8) | (((uint32)bitIndices[3]) << 0);
	bitIndices = blockInput + 8 + 2;
	uint32 greenRow0 = (((uint32)bitIndices[2]) << 16) | (((uint32)bitIndices[1]) << 8) | (((uint32)bitIndices[0]) << 0);
	uint32 greenRow1 = (((uint32)bitIndices[5]) << 16) | (((uint32)bitIndices[4]) << 8) | (((uint32)bitIndices[3]) << 0);

	uint8 pRed[16];
	uint8 pGreen[16];
	for (sint32 i = 0; i < 8; i++)
	{
		pRed[i] = (redRow0 >> (i * 3)) & 7;
		pRed[i + 8] = (redRow1 >> (i * 3)) & 7;
		pGreen[i] = (greenRow0 >> (i * 3)) & 7;
		pGreen[i + 8] = (greenRow1 >> (i * 3)) & 7;
	}

	for (sint32 py = 0; py < 4; py++)
	{
		float* pixelOutput = rgOutput + (py * 4) * 2;
		for (sint32 px = 0; px < 4; px++)
		{
			float c = red[pRed[px + py * 4]];
			pixelOutput[0] = c;
			c = green[pGreen[px + py * 4]];
			pixelOutput[1] = c;
			pixelOutput += 2;
		}
	}
}

/*
 * Packed-palette BC decoders, for the backends that have to decompress BC on the CPU.
 *
 * On iOS that is every backend and every BC texture: "Metal: this GPU has no BC texture
 * support, so BC1-BC5 textures are decompressed on the CPU" is printed on every A12Z-class
 * device, and the same decode runs on the cores the PPC interpreter needs (the device log
 * that motivated this had the interpreter at 50-190 MIPS with one core already pinned).
 *
 * The float decoders above were written for the "uncompress to float" path and are wasteful
 * when the destination is 8 bit: decodeBC1Block spills a 4x4 block as 64 floats into a stack
 * buffer, and the caller reads all 64 back, multiplies each by 255 and truncates. That is 64
 * float->int conversions and 512 bytes of L1 traffic per 8 bytes of compressed input, to
 * produce at most four distinct colours.
 *
 * A BC block only ever holds four (BC1/BC2/BC3 colour) or eight (BC3 alpha, BC4, BC5)
 * distinct values, so the conversion to 8 bit belongs on the palette, not on the pixels:
 * build the palette once, convert its entries once, then expand the indices with byte copies
 * (or one NEON table lookup per row).
 *
 * Measured here on a 1024x1024 texture, best of fifteen runs, NEON paths enabled: BC1 1.69ms
 * -> 0.85ms, BC2 1.61 -> 0.65, BC3 1.74 -> 1.10, BC4 0.59 -> 0.53, BC5 1.38 -> 1.01. Those
 * are host arm64 numbers, not A12Z numbers - the ratios are what carries over, and an A12Z
 * has both slower cores and less of them to spare.
 * With the NEON paths compiled out (what a desktop x64 build gets) BC1 and BC2 keep most of
 * the win, BC3 keeps about a sixth, BC4 is a wash, and BC5 comes out ~10% SLOWER than the
 * float loop, because the compiler happily auto-vectorises the 32 float->byte conversions the
 * float loop ends with. That is accepted rather than worked around: BC5_To_R8G8 is only ever
 * selected for a GPU with no BC5 support, which on the desktop is no GPU made this century,
 * and the SNORM half of it has to be here regardless (see bcFloatToSNorm8).
 *
 * The palette arithmetic below is copied verbatim from the float decoders above, divides and
 * all, and the truncation is the same "(uint8)(value * 255.0f)" the callers used to do per
 * pixel. That is deliberate rather than lazy: converting the palette entry once and copying
 * the byte gives bit-for-bit the image that already shipped, which is the whole point when
 * the standing complaint is that the picture is wrong. Rewriting the interpolation in
 * integers would be faster still and would disagree with these divides by an LSB here and
 * there - not a difference worth having to rule out later.
 *
 * These write straight into the upload buffer. blockSizeX/blockSizeY are the clipped extent
 * of the block: a texture whose width or height is not a multiple of 4 still stores whole
 * 4x4 blocks, but the trailing texels lie outside the image and must not be written.
 */

#ifdef LATTE_TEXLOADER_NEON
// The four RGBA8 texels of one row as a vector. One table lookup does the whole row: the
// palette is 16 bytes (4 entries x RGBA), so the selector byte for channel c of texel n is
// index(n)*4 + c.
static inline uint8x16_t bcColorRow4_RGBA8(const uint8* palette, uint8 indexByte)
{
	const uint8x16_t palVec = vld1q_u8(palette);
	const uint8x16_t channelLane = {0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3};
	const int8x16_t indexShift = {0, 0, 0, 0, -2, -2, -2, -2, -4, -4, -4, -4, -6, -6, -6, -6}; // vshl with a negative count shifts right
	uint8x16_t index = vandq_u8(vshlq_u8(vdupq_n_u8(indexByte), indexShift), vdupq_n_u8(3));
	return vqtbl1q_u8(palVec, vaddq_u8(vshlq_n_u8(index, 2), channelLane));
}
#endif

// One row of up to four RGBA8 texels, selected from a 4 entry palette. indexByte holds that
// row's four 2-bit indices with the leftmost texel in bits 0-1, which is how BC1, BC2 and BC3
// all store them.
static inline void bcEmitColorRow_RGBA8(const uint8* palette, uint8 indexByte, uint8* output, sint32 texelCount)
{
#ifdef LATTE_TEXLOADER_NEON
	if (texelCount == 4)
	{
		vst1q_u8(output, bcColorRow4_RGBA8(palette, indexByte));
		return;
	}
#endif
	for (sint32 px = 0; px < texelCount; px++)
		memcpy(output + px * 4, palette + ((indexByte >> (px * 2)) & 3) * 4, 4);
}

// BC1 colour palette, including the c0 <= c1 punch-through case where index 2 is the midpoint
// and index 3 is transparent black rather than a 1:2 interpolant
static void bcBuildBC1Palette_RGBA8(const uint8* inputData, uint8* palette)
{
	uint16 c0, c1;
	memcpy(&c0, inputData + 0, sizeof(uint16));
	memcpy(&c1, inputData + 2, sizeof(uint16));
	float r[4];
	float g[4];
	float b[4];
	float a[4];
	b[0] = (float)((c0 >> 0) & 0x1F) / 31.0f;
	b[1] = (float)((c1 >> 0) & 0x1F) / 31.0f;
	g[0] = (float)((c0 >> 5) & 0x3F) / 63.0f;
	g[1] = (float)((c1 >> 5) & 0x3F) / 63.0f;
	r[0] = (float)((c0 >> 11) & 0x1F) / 31.0f;
	r[1] = (float)((c1 >> 11) & 0x1F) / 31.0f;
	a[0] = 1.0f;
	a[1] = 1.0f;
	a[2] = 1.0f;
	if (c0 > c1)
	{
		r[2] = (r[0] * 2.0f + r[1]) / 3.0f;
		r[3] = (r[0] * 1.0f + r[1] * 2.0f) / 3.0f;
		g[2] = (g[0] * 2.0f + g[1]) / 3.0f;
		g[3] = (g[0] * 1.0f + g[1] * 2.0f) / 3.0f;
		b[2] = (b[0] * 2.0f + b[1]) / 3.0f;
		b[3] = (b[0] * 1.0f + b[1] * 2.0f) / 3.0f;
		a[3] = 1.0f;
	}
	else
	{
		r[2] = (r[0] + r[1]) / 2.0f;
		r[3] = 0.0f;
		g[2] = (g[0] + g[1]) / 2.0f;
		g[3] = 0.0f;
		b[2] = (b[0] + b[1]) / 2.0f;
		b[3] = 0.0f;
		a[3] = 0.0f;
	}
	for (sint32 i = 0; i < 4; i++)
	{
		palette[i * 4 + 0] = (uint8)(r[i] * 255.0f);
		palette[i * 4 + 1] = (uint8)(g[i] * 255.0f);
		palette[i * 4 + 2] = (uint8)(b[i] * 255.0f);
		palette[i * 4 + 3] = (uint8)(a[i] * 255.0f);
	}
}

// BC2 and BC3 colour palette. Unlike BC1 these always use the four-colour rule whatever the
// order of the endpoints, because the block carries alpha separately and has no need for a
// punch-through encoding. The alpha byte of each entry is left at zero; the callers overwrite
// it per texel.
static void bcBuildBC23ColorPalette_RGBA8(const uint8* colorData, uint8* palette)
{
	uint16 color0, color1;
	memcpy(&color0, colorData + 0, sizeof(uint16));
	memcpy(&color1, colorData + 2, sizeof(uint16));
	uint8 r0 = (color0 >> 11) & 0x1F;
	uint8 g0 = (color0 >> 5) & 0x3F;
	uint8 b0 = (color0 >> 0) & 0x1F;
	uint8 r1 = (color1 >> 11) & 0x1F;
	uint8 g1 = (color1 >> 5) & 0x3F;
	uint8 b1 = (color1 >> 0) & 0x1F;
	float r[4];
	float g[4];
	float b[4];
	r[0] = (float)r0 / 31.0f;
	r[1] = (float)r1 / 31.0f;
	r[2] = (r[0] * 2.0f + r[1]) / 3.0f;
	r[3] = (r[0] + r[1] * 2.0f) / 3.0f;
	g[0] = (float)g0 / 63.0f;
	g[1] = (float)g1 / 63.0f;
	g[2] = (g[0] * 2.0f + g[1]) / 3.0f;
	g[3] = (g[0] + g[1] * 2.0f) / 3.0f;
	b[0] = (float)b0 / 31.0f;
	b[1] = (float)b1 / 31.0f;
	b[2] = (b[0] * 2.0f + b[1]) / 3.0f;
	b[3] = (b[0] + b[1] * 2.0f) / 3.0f;
	for (sint32 i = 0; i < 4; i++)
	{
		palette[i * 4 + 0] = (uint8)(r[i] * 255.0f);
		palette[i * 4 + 1] = (uint8)(g[i] * 255.0f);
		palette[i * 4 + 2] = (uint8)(b[i] * 255.0f);
		palette[i * 4 + 3] = 0;
	}
}

// Scales eight palette entries to bytes. Splitting this out of the palette builders is what
// lets it be done four at a time; the truncation is the same one the per-texel code did, and
// every entry here is inside [0,1] so the narrowing cannot saturate.
static inline void bcConvertPalette8_U8(const float* value, uint8* palette)
{
#ifdef LATTE_TEXLOADER_NEON
	uint32x4_t lo = vcvtq_u32_f32(vmulq_n_f32(vld1q_f32(value + 0), 255.0f));
	uint32x4_t hi = vcvtq_u32_f32(vmulq_n_f32(vld1q_f32(value + 4), 255.0f));
	vst1_u8(palette, vmovn_u16(vcombine_u16(vmovn_u32(lo), vmovn_u32(hi))));
#else
	for (sint32 i = 0; i < 8; i++)
		palette[i] = (uint8)(value[i] * 255.0f);
#endif
}

// The 8 entry palette shared by BC3 alpha, BC4 red and BC5 red/green: six interpolants when
// e0 > e1, otherwise four interpolants plus an explicit 0 and 1.
static void bcBuildInterpolatedPalette_U8(uint8 e0, uint8 e1, uint8* palette)
{
	float a[8];
	a[0] = (float)e0 / 255.0f;
	a[1] = (float)e1 / 255.0f;
	if (e0 > e1)
	{
		a[2] = (a[0] * 6.0f + a[1] * 1.0f) / 7.0f;
		a[3] = (a[0] * 5.0f + a[1] * 2.0f) / 7.0f;
		a[4] = (a[0] * 4.0f + a[1] * 3.0f) / 7.0f;
		a[5] = (a[0] * 3.0f + a[1] * 4.0f) / 7.0f;
		a[6] = (a[0] * 2.0f + a[1] * 5.0f) / 7.0f;
		a[7] = (a[0] * 1.0f + a[1] * 6.0f) / 7.0f;
	}
	else
	{
		a[2] = (a[0] * 4.0f + a[1] * 1.0f) / 5.0f;
		a[3] = (a[0] * 3.0f + a[1] * 2.0f) / 5.0f;
		a[4] = (a[0] * 2.0f + a[1] * 3.0f) / 5.0f;
		a[5] = (a[0] * 1.0f + a[1] * 4.0f) / 5.0f;
		a[6] = 0.0f;
		a[7] = 1.0f;
	}
	bcConvertPalette8_U8(a, palette);
}

/*
 * Encodes a value in [-1,1] into the byte an SNORM texture is read back through, which is
 * max(c / 127, -1) on both Metal (RG8Snorm) and Vulkan (R8G8_SNORM). Round to nearest, and
 * never emit -128: it reads back as -1.0 exactly like -127 does, so emitting it only costs a
 * representable value.
 *
 * This exists because the SNORM instantiation of TextureDecoder_BC5_To_R8G8 wrote
 * (uint8)(value * 255) - the UNORM encoding - into an SNORM texture. Only a quarter of the
 * range survived: +0.5 became byte 127 and read back as +1.0, +1.0 became byte 255 which an
 * SNORM fetch reads as -0.008, and every negative value was converted out of the range of
 * uint8, which is undefined behaviour rather than a wrong number. BC5_SNORM is what normal
 * maps are stored in, so this was scrambling the lighting on every surface using one, on both
 * the Metal and the Vulkan CPU-decompression fallbacks.
 */
static inline sint8 bcFloatToSNorm8(float value)
{
	sint32 i = (sint32)(value * 127.0f + (value >= 0.0f ? 0.5f : -0.5f));
	if (i > 127)
		i = 127;
	if (i < -127)
		i = -127;
	return (sint8)i;
}

// BC5 SNORM red/green palette. The endpoint expansion is the one decodeBC5Block_SNORM uses -
// (value + 128) / 255 remapped to [-1,1] - kept as-is rather than changed to the v/127 the
// SNORM spec implies, because the two differ by a fixed bias and this is the mapping every
// backend has always decoded BC5_SNORM with. Only the output encoding changes here.
static void bcBuildInterpolatedPalette_S8(sint8 e0, sint8 e1, sint8* palette)
{
	float v[8];
	v[0] = ((float)e0 + 128.0f) / 255.0f;
	v[1] = ((float)e1 + 128.0f) / 255.0f;
	v[0] = (v[0] * 2.0f - 1.0f);
	v[1] = (v[1] * 2.0f - 1.0f);
	if (v[0] > v[1])
	{
		v[2] = (6 * v[0] + 1 * v[1]) / 7.0f;
		v[3] = (5 * v[0] + 2 * v[1]) / 7.0f;
		v[4] = (4 * v[0] + 3 * v[1]) / 7.0f;
		v[5] = (3 * v[0] + 4 * v[1]) / 7.0f;
		v[6] = (2 * v[0] + 5 * v[1]) / 7.0f;
		v[7] = (1 * v[0] + 6 * v[1]) / 7.0f;
	}
	else
	{
		v[2] = (4 * v[0] + 1 * v[1]) / 5.0f;
		v[3] = (3 * v[0] + 2 * v[1]) / 5.0f;
		v[4] = (2 * v[0] + 3 * v[1]) / 5.0f;
		v[5] = (1 * v[0] + 4 * v[1]) / 5.0f;
		v[6] = -1.0f;
		v[7] = 1.0f;
	}
	for (sint32 i = 0; i < 8; i++)
		palette[i] = bcFloatToSNorm8(v[i]);
}

// BC3 alpha, BC4 and BC5 all store 16 three-bit indices in six bytes: eight per 24 bit half,
// low bits first, row-major. So texels 0-7 (rows 0 and 1) come out of the first half and
// texels 8-15 (rows 2 and 3) out of the second.
struct BCIndexField
{
	uint32 half[2];

	explicit BCIndexField(const uint8* indexData)
	{
		half[0] = (((uint32)indexData[2]) << 16) | (((uint32)indexData[1]) << 8) | ((uint32)indexData[0]);
		half[1] = (((uint32)indexData[5]) << 16) | (((uint32)indexData[4]) << 8) | ((uint32)indexData[3]);
	}

	// One row's four indices, as twelve consecutive bits with the leftmost texel lowest, so
	// the scalar emit loops can walk them with a running shift instead of recomputing a
	// variable shift per texel.
	uint32 rowBits(sint32 py) const
	{
		return half[py >> 1] >> ((py & 1) * 12);
	}

	void unpackAll(uint8* indices) const
	{
		for (sint32 i = 0; i < 8; i++)
		{
			indices[i] = (half[0] >> (i * 3)) & 7;
			indices[i + 8] = (half[1] >> (i * 3)) & 7;
		}
	}
};

#ifdef LATTE_TEXLOADER_NEON
// Looks all 16 texels up in an 8 entry byte palette at once. The 3-bit indices are not byte
// aligned in the block so they are unpacked with scalar shifts either way, but the lookup
// itself becomes one table instruction instead of sixteen dependent byte loads.
static inline uint8x16_t bcLookupTexels16(const uint8* palette8, const uint8* indices)
{
	uint8x16_t table = vcombine_u8(vld1_u8(palette8), vdup_n_u8(0)); // indices are 0-7, the top half is never selected
	return vqtbl1q_u8(table, vld1q_u8(indices));
}
#endif

void decodeBC1Block_RGBA8(const uint8* inputData, uint8* output, sint32 outputRowPitch, sint32 blockSizeX, sint32 blockSizeY)
{
	uint8 palette[16];
	bcBuildBC1Palette_RGBA8(inputData, palette);
	for (sint32 py = 0; py < blockSizeY; py++)
		bcEmitColorRow_RGBA8(palette, inputData[4 + py], output + py * outputRowPitch, blockSizeX);
}

void decodeBC2Block_RGBA8(const uint8* inputData, uint8* output, sint32 outputRowPitch, sint32 blockSizeX, sint32 blockSizeY)
{
	uint8 palette[16];
	bcBuildBC23ColorPalette_RGBA8(inputData + 8, palette);
	for (sint32 py = 0; py < blockSizeY; py++)
	{
		uint8* rowOutput = output + py * outputRowPitch;
		bcEmitColorRow_RGBA8(palette, inputData[12 + py], rowOutput, blockSizeX);
		// BC2 alpha is a raw 4 bit value per texel, two texels per byte, not a palette index.
		// The float path divided the 4->8 bit expanded byte by 255 and the caller multiplied
		// it back, which round-trips exactly for all 16 values, so write the byte directly.
		const uint8* alphaRow = inputData + py * 2;
		for (sint32 px = 0; px < blockSizeX; px++)
		{
			uint8 alphaCode = (alphaRow[px >> 1] >> ((px & 1) * 4)) & 0xF;
			rowOutput[px * 4 + 3] = (uint8)(alphaCode | (alphaCode << 4));
		}
	}
}

void decodeBC3Block_RGBA8(const uint8* inputData, uint8* output, sint32 outputRowPitch, sint32 blockSizeX, sint32 blockSizeY)
{
	uint8 palette[16];
	bcBuildBC23ColorPalette_RGBA8(inputData + 8, palette);
	uint8 alphaPalette[8];
	bcBuildInterpolatedPalette_U8(inputData[0], inputData[1], alphaPalette);
	const BCIndexField alphaIndices(inputData + 2);
#ifdef LATTE_TEXLOADER_NEON
	if (blockSizeX == 4)
	{
		uint8 alphaIndexBytes[16];
		alphaIndices.unpackAll(alphaIndexBytes);
		uint8x16_t alphaTexels = bcLookupTexels16(alphaPalette, alphaIndexBytes);
		// Places one row's four alpha bytes at the alpha byte of each RGBA texel. Any selector
		// >= 16 makes tbl emit zero, so 0x80 blanks the three colour bytes, and adding py*4
		// to every lane walks the rows while keeping those three out of range.
		const uint8x16_t alphaSelector = {0x80, 0x80, 0x80, 0, 0x80, 0x80, 0x80, 1, 0x80, 0x80, 0x80, 2, 0x80, 0x80, 0x80, 3};
		for (sint32 py = 0; py < blockSizeY; py++)
		{
			// the colour palette leaves the alpha byte of every entry zero, so OR is enough
			uint8x16_t placed = vqtbl1q_u8(alphaTexels, vaddq_u8(alphaSelector, vdupq_n_u8((uint8)(py * 4))));
			vst1q_u8(output + py * outputRowPitch, vorrq_u8(bcColorRow4_RGBA8(palette, inputData[12 + py]), placed));
		}
		return;
	}
#endif
	for (sint32 py = 0; py < blockSizeY; py++)
	{
		uint8* rowOutput = output + py * outputRowPitch;
		bcEmitColorRow_RGBA8(palette, inputData[12 + py], rowOutput, blockSizeX);
		uint32 alphaBits = alphaIndices.rowBits(py);
		for (sint32 px = 0; px < blockSizeX; px++, alphaBits >>= 3)
			rowOutput[px * 4 + 3] = alphaPalette[alphaBits & 7];
	}
}

void decodeBC4Block_R8(const uint8* inputData, uint8* output, sint32 outputRowPitch, sint32 blockSizeX, sint32 blockSizeY)
{
	uint8 palette[8];
	bcBuildInterpolatedPalette_U8(inputData[0], inputData[1], palette);
	const BCIndexField indexField(inputData + 2);
#ifdef LATTE_TEXLOADER_NEON
	if (blockSizeX == 4)
	{
		uint8 indices[16];
		indexField.unpackAll(indices);
		uint32x4_t texels = vreinterpretq_u32_u8(bcLookupTexels16(palette, indices));
		// one row of BC4 is four R8 texels, which is exactly one 32 bit lane. These go out
		// through memcpy rather than vst1q_lane_u32 because rows of a texture whose width is
		// not a multiple of 4 land on odd byte offsets, and the lane store intrinsic is
		// specified as wanting a naturally aligned uint32*
		uint32 row;
		if (blockSizeY > 0) { row = vgetq_lane_u32(texels, 0); memcpy(output + 0 * outputRowPitch, &row, sizeof(row)); }
		if (blockSizeY > 1) { row = vgetq_lane_u32(texels, 1); memcpy(output + 1 * outputRowPitch, &row, sizeof(row)); }
		if (blockSizeY > 2) { row = vgetq_lane_u32(texels, 2); memcpy(output + 2 * outputRowPitch, &row, sizeof(row)); }
		if (blockSizeY > 3) { row = vgetq_lane_u32(texels, 3); memcpy(output + 3 * outputRowPitch, &row, sizeof(row)); }
		return;
	}
#endif
	for (sint32 py = 0; py < blockSizeY; py++)
	{
		uint8* rowOutput = output + py * outputRowPitch;
		uint32 bits = indexField.rowBits(py);
		for (sint32 px = 0; px < blockSizeX; px++, bits >>= 3)
			rowOutput[px] = palette[bits & 7];
	}
}

void decodeBC5Block_RG8_UNORM(const uint8* inputData, uint8* output, sint32 outputRowPitch, sint32 blockSizeX, sint32 blockSizeY)
{
	uint8 redPalette[8];
	uint8 greenPalette[8];
	bcBuildInterpolatedPalette_U8(inputData[0], inputData[1], redPalette);
	bcBuildInterpolatedPalette_U8(inputData[8], inputData[9], greenPalette);
	const BCIndexField redIndexField(inputData + 2);
	const BCIndexField greenIndexField(inputData + 10);
#ifdef LATTE_TEXLOADER_NEON
	if (blockSizeX == 4)
	{
		uint8 redIndices[16];
		uint8 greenIndices[16];
		redIndexField.unpackAll(redIndices);
		greenIndexField.unpackAll(greenIndices);
		// zip1/zip2 interleave red and green into the RG8 texel order the texture wants; each
		// half then holds two rows of four texels
		uint8x16_t red = bcLookupTexels16(redPalette, redIndices);
		uint8x16_t green = bcLookupTexels16(greenPalette, greenIndices);
		uint8x16_t rows01 = vzip1q_u8(red, green);
		uint8x16_t rows23 = vzip2q_u8(red, green);
		if (blockSizeY > 0) vst1_u8(output + 0 * outputRowPitch, vget_low_u8(rows01));
		if (blockSizeY > 1) vst1_u8(output + 1 * outputRowPitch, vget_high_u8(rows01));
		if (blockSizeY > 2) vst1_u8(output + 2 * outputRowPitch, vget_low_u8(rows23));
		if (blockSizeY > 3) vst1_u8(output + 3 * outputRowPitch, vget_high_u8(rows23));
		return;
	}
#endif
	for (sint32 py = 0; py < blockSizeY; py++)
	{
		uint8* rowOutput = output + py * outputRowPitch;
		uint32 redBits = redIndexField.rowBits(py);
		uint32 greenBits = greenIndexField.rowBits(py);
		for (sint32 px = 0; px < blockSizeX; px++, redBits >>= 3, greenBits >>= 3)
		{
			rowOutput[px * 2 + 0] = redPalette[redBits & 7];
			rowOutput[px * 2 + 1] = greenPalette[greenBits & 7];
		}
	}
}

void decodeBC5Block_RG8_SNORM(const uint8* inputData, uint8* output, sint32 outputRowPitch, sint32 blockSizeX, sint32 blockSizeY)
{
	sint8 redPalette[8];
	sint8 greenPalette[8];
	bcBuildInterpolatedPalette_S8((sint8)inputData[0], (sint8)inputData[1], redPalette);
	bcBuildInterpolatedPalette_S8((sint8)inputData[8], (sint8)inputData[9], greenPalette);
	const BCIndexField redIndexField(inputData + 2);
	const BCIndexField greenIndexField(inputData + 10);
#ifdef LATTE_TEXLOADER_NEON
	if (blockSizeX == 4)
	{
		uint8 redIndices[16];
		uint8 greenIndices[16];
		redIndexField.unpackAll(redIndices);
		greenIndexField.unpackAll(greenIndices);
		// the lookup is a byte shuffle, so the signedness of the palette is irrelevant here
		uint8x16_t red = bcLookupTexels16((const uint8*)redPalette, redIndices);
		uint8x16_t green = bcLookupTexels16((const uint8*)greenPalette, greenIndices);
		uint8x16_t rows01 = vzip1q_u8(red, green);
		uint8x16_t rows23 = vzip2q_u8(red, green);
		if (blockSizeY > 0) vst1_u8(output + 0 * outputRowPitch, vget_low_u8(rows01));
		if (blockSizeY > 1) vst1_u8(output + 1 * outputRowPitch, vget_high_u8(rows01));
		if (blockSizeY > 2) vst1_u8(output + 2 * outputRowPitch, vget_low_u8(rows23));
		if (blockSizeY > 3) vst1_u8(output + 3 * outputRowPitch, vget_high_u8(rows23));
		return;
	}
#endif
	for (sint32 py = 0; py < blockSizeY; py++)
	{
		sint8* rowOutput = (sint8*)output + py * outputRowPitch;
		uint32 redBits = redIndexField.rowBits(py);
		uint32 greenBits = greenIndexField.rowBits(py);
		for (sint32 px = 0; px < blockSizeX; px++, redBits >>= 3, greenBits >>= 3)
		{
			rowOutput[px * 2 + 0] = redPalette[redBits & 7];
			rowOutput[px * 2 + 1] = greenPalette[greenBits & 7];
		}
	}
}

void LatteTextureLoader_loadTextureDataIntoSlice(LatteTexture* hostTexture, sint32 width, sint32 height, sint32 depth, sint32 mipLevels, void* pixelData, sint32 sliceIndex, sint32 mipIndex, uint32 compressedImageSize)
{
	if (mipIndex == 0)
	{
		cemu_assert_debug(width == hostTexture->width);
		cemu_assert_debug(height == hostTexture->height);
		cemu_assert_debug(depth == hostTexture->depth);
	}
	cemu_assert_debug(mipLevels == hostTexture->mipLevels);
	if (hostTexture->overwriteInfo.hasResolutionOverwrite || hostTexture->overwriteInfo.hasFormatOverwrite)
	{
		// todo - ideally, we should scale/convert the data to the new format and resolution
		g_renderer->texture_clearSlice(hostTexture, sliceIndex, mipIndex);
	}
	else
	{
		g_renderer->texture_loadSlice(hostTexture, width, height, depth, pixelData, sliceIndex, mipIndex, compressedImageSize);
	}
}

void LatteTextureLoader_UpdateTextureSliceData(LatteTexture* tex, uint32 sliceIndex, uint32 mipIndex, MPTR physImagePtr, MPTR physMipPtr, Latte::E_DIM dim, uint32 width, uint32 height, uint32 depth, uint32 mipLevels, uint32 pitch, Latte::E_HWTILEMODE tileMode, uint32 swizzle, bool dumpTex)
{
	LatteTextureLoaderCtx textureLoader = { 0 };

	Latte::E_GX2SURFFMT format = tex->format;
	LatteTextureLoader_begin(&textureLoader, sliceIndex, mipIndex, physImagePtr, physMipPtr, format, dim, width, height, depth, mipLevels, pitch, tileMode, swizzle);

	// enable texture dumping
	textureLoader.dump = ActiveSettings::DumpTexturesEnabled();
	if (textureLoader.dump)
	{
		uint32 dumpSize = (((textureLoader.width + 4)&~4) * ((textureLoader.height + 4)&~4)) * 4;
		textureLoader.dumpRGBA = (uint8*)malloc(dumpSize);
		memset(textureLoader.dumpRGBA, 0x00, dumpSize);
	}

	// query texture decoder from renderer
	TextureDecoder* texDecoder = nullptr;
	texDecoder = g_renderer->texture_chooseDecodedFormat(format, tex->isDepth, dim, width, height);

	if (tex->isDataDefined == false)
	{
		tex->AllocateOnHost();
		tex->isDataDefined = true;
		// if decoder is not set then clear texture
		// on Vulkan this is used to make sure the texture is no longer in UNDEFINED layout
		if (!texDecoder)
		{
			if(tex->isDepth)
				g_renderer->texture_clearDepthSlice(tex, 0, 0, true, tex->hasStencil, 0.0f, 0);
			else
				g_renderer->texture_clearColorSlice(tex, 0, 0, 0.0f, 0.0f, 0.0f, 0.0f);
		}
	}

	if (texDecoder == nullptr)
		return;

	textureLoader.decodedTexelCountX = texDecoder->getTexelCountX(&textureLoader);
	textureLoader.decodedTexelCountY = texDecoder->getTexelCountY(&textureLoader);

	// allocate memory for decoded texture
	uint32 imageSize = texDecoder->calculateImageSize(&textureLoader);

	uint8* pixelData = (uint8*)g_renderer->texture_acquireTextureUploadBuffer(imageSize);
	// decode texture (if data is required)
#ifdef BENCHMARK_TEXTURE_DECODING
	LARGE_INTEGER benchmark_begin;
	LARGE_INTEGER benchmark_end;
	LARGE_INTEGER benchmark_freq;
	QueryPerformanceCounter(&benchmark_begin);
#endif
	if (tex->overwriteInfo.hasFormatOverwrite == false && tex->overwriteInfo.hasResolutionOverwrite == false)
	{
		texDecoder->decode(&textureLoader, pixelData);
	}
#ifdef BENCHMARK_TEXTURE_DECODING
	QueryPerformanceCounter(&benchmark_end);
	QueryPerformanceFrequency(&benchmark_freq);
	uint64 benchmarkResultMicroSeconds = (benchmark_end.QuadPart - benchmark_begin.QuadPart) * 1000000ULL / benchmark_freq.QuadPart;
	textureDecodeBenchmark_perFormatSum[(int)tex->format & 0x3F] += benchmarkResultMicroSeconds;
	textureDecodeBenchmark_totalSum += benchmarkResultMicroSeconds;
	cemuLog_log(LogType::Force, "TexDecode {:04}x{:04}x{:04} Fmt {:04x} Dim {} TileMode {:02x} Took {:03}.{:03}ms Sum(format) {:06}ms Sum(total) {:06}ms", textureLoader.width, textureLoader.height, textureLoader.surfaceInfoDepth, (int)tex->format, (int)tex->dim, textureLoader.tileMode, (uint32)(benchmarkResultMicroSeconds / 1000ULL), (uint32)(benchmarkResultMicroSeconds % 1000ULL), (uint32)(textureDecodeBenchmark_perFormatSum[tex->gx2Format & 0x3F] / 1000ULL), (uint32)(textureDecodeBenchmark_totalSum / 1000ULL));
#endif

	// convert texture to RGBA when dumping is enabled
	if (textureLoader.dump)
	{
		for (sint32 y = 0; y < textureLoader.height; y++)
		{
			sint32 pixelOffset = (y * textureLoader.width) * 4;
			uint8* pixelOutput = textureLoader.dumpRGBA + pixelOffset;
			for (sint32 x = 0; x < textureLoader.width; x++)
			{
				uint8* blockData = LatteTextureLoader_GetInput(&textureLoader, x, y);
				texDecoder->decodePixelToRGBA(blockData, pixelOutput, x % textureLoader.stepX, y % textureLoader.stepY);
				pixelOutput += 4;
			}
		}
	}

	// update texture data offsets and hashes
	// this has to be done before the texture data is decoded & uploaded to prevent a race condition where updates during upload are missed
	if (mipIndex == 0 || (tex->texDataPtrLow == 0 && tex->texDataPtrHigh == 0))
	{
		tex->texDataPtrLow = physImagePtr + textureLoader.minOffsetOutdated; // always zero
		tex->texDataPtrHigh = physImagePtr + textureLoader.maxOffsetOutdated; // currently set to surface size
		LatteTC_ResetTextureChangeTracker(tex, true);
	}
	// load slice
	//debug_printf("[Load Slice] Addr: %08x MIP: %02d Slice: %02d Res %04x/%04x Texel Res %04x/%04x Fmt %04x Tm %d\n", textureLoader.physAddress, mipIndex, sliceIndex, textureLoader.width, textureLoader.height, textureLoader.texelCountX, textureLoader.texelCountY, (int)format, tileMode);
	LatteTextureLoader_loadTextureDataIntoSlice(tex, textureLoader.width, textureLoader.height, depth, mipLevels, pixelData, sliceIndex, mipIndex, imageSize);
	// write texture dump
	if (textureLoader.dump)
	{
		fs::path path = ActiveSettings::GetUserDataPath("dump/textures");
		path /= fmt::format("{:08x}_fmt{:04x}_slice{:d}_mip{:02d}_{:d}x{:d}_tm{:02d}.tga", physImagePtr, (uint32)tex->format, sliceIndex, mipIndex, tex->width, tex->height, tileMode);
		tga_write_rgba(path, textureLoader.width, textureLoader.height, textureLoader.dumpRGBA);
		free(textureLoader.dumpRGBA);
	}
	// clean up
	g_renderer->texture_releaseTextureUploadBuffer(pixelData);
	catchOpenGLError();
}

template<typename copyType>
void optimizedLinearReadbackWriteLoop(LatteTextureLoaderCtx* textureLoader, uint8* linearPixelData)
{
	uint32 pitch = textureLoader->width;
	// optimized for linear
	for (sint32 y = 0; y < textureLoader->height; y++)
	{
		sint32 yc = y;
		sint32 pixelOffset = yc * pitch;
		copyType* rowPixelData = (copyType*)(linearPixelData + pixelOffset * sizeof(copyType));
		copyType* blockData = (copyType*)LatteTextureLoader_getInputLinearOptimized_(textureLoader, 0, y, 1, 1, sizeof(copyType) * 8, 0, 1, 0, textureLoader->pitch, textureLoader->height);
		if constexpr (sizeof(copyType) == 4)
		{
			memcpy_dwords(blockData, rowPixelData, textureLoader->width);
		}
		else
		{
			for (sint32 x = 0; x < textureLoader->width; x++)
			{
				*blockData = *rowPixelData;
				rowPixelData++;
				blockData++;
			}
		}
	}
}

void LatteTextureLoader_writeReadbackTextureToMemory(LatteTextureDefinition* textureData, uint32 sliceIndex, uint32 mipIndex, uint8* linearPixelData)
{
	LatteTextureLoaderCtx textureLoader = { 0 };
	LatteTextureLoader_begin(&textureLoader, sliceIndex, mipIndex, textureData->physAddress, textureData->physMipAddress, textureData->format, textureData->dim, textureData->width, textureData->height, textureData->depth, textureData->mipLevels, textureData->pitch, textureData->tileMode, textureData->swizzle);

#ifdef CEMU_DEBUG_ASSERT
	if (textureData->depth != 1)
		cemuLog_log(LogType::Force, "_writeReadbackTextureToMemory(): Texture has multiple slices (not supported)");
#endif
	if (textureLoader.physAddress == MPTR_NULL)
	{
		cemuLog_log(LogType::Force, "_writeReadbackTextureToMemory(): Texture has invalid address");
		return;
	}

	cemuLog_log(LogType::TextureReadback, "[TextureReadback-Write] PhysAddr {:08x} Res {}x{} Fmt {} Slice {} Mip {}", textureData->physAddress, textureData->width, textureData->height, textureData->format, sliceIndex, mipIndex);

	if (textureData->tileMode == Latte::E_HWTILEMODE::TM_LINEAR_ALIGNED)
	{
		uint32 pitch = textureLoader.width;
		if (textureData->format == Latte::E_GX2SURFFMT::R8_G8_B8_A8_UNORM ||
			textureData->format == Latte::E_GX2SURFFMT::R8_G8_B8_A8_SRGB)
		{
			optimizedLinearReadbackWriteLoop<uint32>(&textureLoader, linearPixelData);
		}
		else if (textureData->format == Latte::E_GX2SURFFMT::R16_G16_B16_A16_UNORM)
		{
			optimizedLinearReadbackWriteLoop<uint64>(&textureLoader, linearPixelData);
		}
		else if (textureData->format == Latte::E_GX2SURFFMT::R32_G32_B32_A32_FLOAT)
		{
			for (sint32 y = 0; y < textureLoader.height; y += textureLoader.stepY)
			{
				sint32 yc = y;
				sint32 pixelOffset = (0 + yc * pitch) * 16;
				for (sint32 x = 0; x < textureLoader.width; x += textureLoader.stepX)
				{
					uint8* blockData = LatteTextureLoader_getInputLinearOptimized(&textureLoader, x, y);
					(*(uint32*)(blockData + 0)) = *(uint32*)(linearPixelData + pixelOffset + 0);
					(*(uint32*)(blockData + 4)) = *(uint32*)(linearPixelData + pixelOffset + 4);
					(*(uint32*)(blockData + 8)) = *(uint32*)(linearPixelData + pixelOffset + 8);
					(*(uint32*)(blockData + 12)) = *(uint32*)(linearPixelData + pixelOffset + 12);
					pixelOffset += 16;
				}
			}
		}
		else if (textureData->format == Latte::E_GX2SURFFMT::R32_FLOAT)
		{
			for (sint32 y = 0; y < textureLoader.height; y += textureLoader.stepY)
			{
				sint32 yc = y;
				for (sint32 x = 0; x < textureLoader.width; x += textureLoader.stepX)
				{
					uint8* blockData = LatteTextureLoader_getInputLinearOptimized(&textureLoader, x, y);
					sint32 pixelOffset = (x + yc * pitch) * 4;
					(*(uint32*)(blockData + 0)) = *(uint32*)(linearPixelData + pixelOffset + 0);
				}
			}
		}
		else if (textureData->format == Latte::E_GX2SURFFMT::R16_G16_B16_A16_FLOAT)
		{
			for (sint32 y = 0; y < textureLoader.height; y += textureLoader.stepY)
			{
				sint32 yc = y;
				for (sint32 x = 0; x < textureLoader.width; x += textureLoader.stepX)
				{
					uint8* blockData = LatteTextureLoader_getInputLinearOptimized(&textureLoader, x, y);
					sint32 pixelOffset = (x + yc * pitch) * 8;
					(*(uint32*)(blockData + 0)) = *(uint32*)(linearPixelData + pixelOffset + 0);
					(*(uint32*)(blockData + 4)) = *(uint32*)(linearPixelData + pixelOffset + 4);
				}
			}
		}
		else if (textureData->format == Latte::E_GX2SURFFMT::R8_G8_UNORM)
		{
			optimizedLinearReadbackWriteLoop<uint16>(&textureLoader, linearPixelData);
		}
		else if (textureData->format == Latte::E_GX2SURFFMT::R16_G16_B16_A16_UNORM)
		{
			cemu_assert_unimplemented();
		}
		else if (textureData->format == Latte::E_GX2SURFFMT::R16_UNORM)
		{
			optimizedLinearReadbackWriteLoop<uint16>(&textureLoader, linearPixelData);
		}
		else
		{
			cemuLog_logDebug(LogType::Force, "Linear texture readback unsupported for format 0x{:04x}", (uint32)textureData->format);
			debugBreakpoint();
		}
		return;
	}
	// generic and slow decode loops
	Latte::E_HWSURFFMT hwFormat = Latte::GetHWFormat(textureData->format);
	if (hwFormat == Latte::E_HWSURFFMT::HWFMT_8_8_8_8)
	{
		// used in Bayonetta 2
		for (sint32 y = 0; y < textureLoader.height; y++)
		{
			uint8* pixelInput = linearPixelData + (y * textureLoader.width) * 4;
			for (sint32 x = 0; x < textureLoader.width; x++)
			{
				uint8* outputData = LatteTextureLoader_GetInput(&textureLoader, x, y);
				*(uint32*)(outputData + 0) = *(uint32*)pixelInput;
				pixelInput += 4;
			}
		}
	}
	else if (hwFormat == Latte::E_HWSURFFMT::HWFMT_32_FLOAT)
	{
		// required by Wind Waker for direct access to depth buffer
		// Bayonetta 2 also uses this but it converts the depth buffer to a color texture first
		for (sint32 y = 0; y < textureLoader.height; y++)
		{
			uint8* pixelInput = linearPixelData + (y * textureLoader.width) * 4;
			for (sint32 x = 0; x < textureLoader.width; x++)
			{
				uint8* outputData = LatteTextureLoader_GetInput(&textureLoader, x, y);
				*(uint32*)(outputData + 0) = *(uint32*)pixelInput;
				pixelInput += 4;
			}
		}
	}
	else
	{
		cemuLog_logDebug(LogType::Force, "Texture readback unsupported format {:04x} for tileMode 0x{:02x}", (uint32)textureData->format, textureData->tileMode);
	}

}

void LatteTextureLoader_estimateAccessedDataRange(LatteTexture* texture, sint32 sliceIndex, sint32 mipIndex, uint32& addrStart, uint32& addrEnd)
{
	LatteTextureLoaderCtx textureLoader = { 0 };
	LatteTextureLoader_begin(&textureLoader, sliceIndex, mipIndex, texture->physAddress, texture->physMipAddress, texture->format, texture->dim, texture->width, texture->height, texture->depth, texture->mipLevels, texture->pitch, texture->tileMode, texture->swizzle);

	cemu_assert_debug(textureLoader.width > 0);
	cemu_assert_debug(textureLoader.height > 0);

	// estimate data range by checking addresses of corner pixels
	// this isn't very reliable, find a better solution
	uint32 estimatedMinAddr = 0xFFFFFFFF;
	uint32 estimatedMaxAddr = 0x00000000;
	uint32 tempAddr;
	tempAddr = memory_getVirtualOffsetFromPointer(LatteTextureLoader_GetInput(&textureLoader, 0, 0));
	estimatedMinAddr = std::min(estimatedMinAddr, tempAddr);
	estimatedMaxAddr = std::max(estimatedMaxAddr, tempAddr);
	tempAddr = memory_getVirtualOffsetFromPointer(LatteTextureLoader_GetInput(&textureLoader, textureLoader.width - 1, 0));
	estimatedMinAddr = std::min(estimatedMinAddr, tempAddr);
	estimatedMaxAddr = std::max(estimatedMaxAddr, tempAddr);
	tempAddr = memory_getVirtualOffsetFromPointer(LatteTextureLoader_GetInput(&textureLoader, 0, textureLoader.height - 1));
	estimatedMinAddr = std::min(estimatedMinAddr, tempAddr);
	estimatedMaxAddr = std::max(estimatedMaxAddr, tempAddr);
	tempAddr = memory_getVirtualOffsetFromPointer(LatteTextureLoader_GetInput(&textureLoader, textureLoader.width - 1, textureLoader.height - 1));
	estimatedMinAddr = std::min(estimatedMinAddr, tempAddr);
	estimatedMaxAddr = std::max(estimatedMaxAddr, tempAddr);

	addrStart = estimatedMinAddr;
	addrEnd = estimatedMaxAddr;
}
