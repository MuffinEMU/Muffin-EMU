#pragma once

struct LatteSurfaceCopyParam
{
	// effective parameters (with mip index baked into them)
	MPTR physDataAddr; // points to actual mip
	uint32 swizzle;
	Latte::E_GX2SURFFMT surfaceFormat;
	sint32 heightInTexels;
	uint32 pitch;
	Latte::E_DIM dim;
	Latte::E_GX2TILEMODE tilemode;
	sint32 aa;
	sint32 sliceIndex;
};

struct LatteSurfaceCopyRect
{
	uint32 x;
	uint32 y;
	uint32 width; // in pixels
	uint32 height;
	bool skipCPUReadback = false;
};

constexpr uint32 LATTE_SURFACE_COPY_FLAG_SKIP_CPU_READBACK = 1u << 0;

void LatteSurfaceCopy_copySurfaceNew(const LatteSurfaceCopyParam& src, const LatteSurfaceCopyParam& dst, const LatteSurfaceCopyRect& rect);
