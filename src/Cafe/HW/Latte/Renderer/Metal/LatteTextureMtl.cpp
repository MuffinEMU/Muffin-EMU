#include "Cafe/HW/Latte/Renderer/Metal/LatteTextureMtl.h"
#include "Cafe/HW/Latte/Renderer/Metal/LatteTextureViewMtl.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalRenderer.h"
#include "Cafe/HW/Latte/Renderer/Metal/LatteToMtl.h"
#include "Cemu/Logging/CemuLogging.h"

#include <set>

LatteTextureMtl::LatteTextureMtl(class MetalRenderer* mtlRenderer, Latte::E_DIM dim, MPTR physAddress, MPTR physMipAddress, Latte::E_GX2SURFFMT format, uint32 width, uint32 height, uint32 depth, uint32 pitch, uint32 mipLevels, uint32 swizzle,
	Latte::E_HWTILEMODE tileMode, bool isDepth)
	: LatteTexture(dim, physAddress, physMipAddress, format, width, height, depth, pitch, mipLevels, swizzle, tileMode, isDepth), m_mtlr(mtlRenderer)
{
    NS_STACK_SCOPED MTL::TextureDescriptor* desc = MTL::TextureDescriptor::alloc()->init();
    desc->setStorageMode(MTL::StorageModePrivate);
    //desc->setCpuCacheMode(MTL::CPUCacheModeWriteCombined);

	sint32 effectiveBaseWidth = width;
	sint32 effectiveBaseHeight = height;
	sint32 effectiveBaseDepth = depth;
	if (overwriteInfo.hasResolutionOverwrite)
	{
		effectiveBaseWidth = overwriteInfo.width;
		effectiveBaseHeight = overwriteInfo.height;
		effectiveBaseDepth = overwriteInfo.depth;
	}
	effectiveBaseWidth = std::max(1, effectiveBaseWidth);
	effectiveBaseHeight = std::max(1, effectiveBaseHeight);
	effectiveBaseDepth = std::max(1, effectiveBaseDepth);

	MTL::TextureType textureType;
	switch (dim)
    {
    case Latte::E_DIM::DIM_1D:
        textureType = MTL::TextureType1D;
        effectiveBaseHeight = 1;
        break;
    case Latte::E_DIM::DIM_2D:
    case Latte::E_DIM::DIM_2D_MSAA:
        textureType = MTL::TextureType2D;
        break;
    case Latte::E_DIM::DIM_2D_ARRAY:
        textureType = MTL::TextureType2DArray;
        break;
    case Latte::E_DIM::DIM_3D:
        textureType = MTL::TextureType3D;
        break;
    case Latte::E_DIM::DIM_CUBEMAP:
        cemu_assert_debug(effectiveBaseDepth % 6 == 0 && "cubemaps must have an array length multiple of 6");

        textureType = MTL::TextureTypeCubeArray;
        break;
    default:
        cemu_assert_unimplemented();
        textureType = MTL::TextureType2D;
        break;
    }
    desc->setTextureType(textureType);

    // Clamp mip levels
    mipLevels = std::min(mipLevels, (uint32)maxPossibleMipLevels);
    mipLevels = std::max(mipLevels, (uint32)1);

    // Metal has no mipmapped 1D textures - MSL's texture1d can't even be sampled with
    // an LOD - and a descriptor asking for one is rejected with an abort.
    if (textureType == MTL::TextureType1D)
        mipLevels = 1;

	desc->setWidth(effectiveBaseWidth);
	desc->setHeight(effectiveBaseHeight);
	desc->setMipmapLevelCount(mipLevels);

	if (textureType == MTL::TextureType3D)
	{
		desc->setDepth(effectiveBaseDepth);
	}
	else if (textureType == MTL::TextureTypeCubeArray)
	{
		// depth is the slice count and is meant to be a multiple of 6, but a game that
		// declares fewer than 6 slices would round down to an array length of 0 here,
		// and Metal aborts on a zero-length array rather than returning nil.
		desc->setArrayLength(std::max(1, effectiveBaseDepth / 6));
	}
	else if (textureType == MTL::TextureType2DArray)
	{
		desc->setArrayLength(effectiveBaseDepth);
	}

	auto pixelFormat = GetMtlPixelFormat(format, isDepth);
	desc->setPixelFormat(pixelFormat);

	MTL::TextureUsage usage = MTL::TextureUsageShaderRead | MTL::TextureUsagePixelFormatView;
	if (FormatIsRenderable(format) && textureType != MTL::TextureType1D)
		usage |= MTL::TextureUsageRenderTarget;
	desc->setUsage(usage);

	// Metal reports a descriptor it can't satisfy by calling abort(), which takes the
	// log with it, so write down what we are about to ask for. Once per distinct
	// dimension/format pair, otherwise this drowns the log - that is still enough for
	// the last line before a crash to name the texture that caused it.
	{
		static std::set<uint64> s_describedTextures;
		uint64 descriptionKey = ((uint64)dim << 32) | ((uint64)format << 1) | (isDepth ? 1 : 0);
		if (s_describedTextures.insert(descriptionKey).second)
		{
			cemuLog_log(LogType::Force, "Metal: first texture of GX2 format {:#x} (depth: {}, dim: {}) -> pixel format {}, {}x{}x{}, {} mips",
				(uint32)format, isDepth, (uint32)dim, (uint32)pixelFormat, effectiveBaseWidth, effectiveBaseHeight, effectiveBaseDepth, mipLevels);
		}
	}

	m_texture = mtlRenderer->GetDevice()->newTexture(desc);
	if (!m_texture)
	{
		// Nil rather than an abort - the descriptor was legal but the allocation failed,
		// which on a 6 GB device usually means we are out of texture memory. Say so here;
		// otherwise this surfaces later as a null dereference with no explanation.
		cemuLog_log(LogType::Force, "Metal: failed to allocate a {}x{}x{} texture (GX2 format {:#x}, pixel format {}, {} mips)",
			effectiveBaseWidth, effectiveBaseHeight, effectiveBaseDepth, (uint32)format, (uint32)pixelFormat, mipLevels);
	}
}

LatteTextureMtl::~LatteTextureMtl()
{
	// The constructor now tolerates a failed allocation, so this can legitimately be null
	if (m_texture)
		m_texture->release();
}

LatteTextureView* LatteTextureMtl::CreateView(Latte::E_DIM dim, Latte::E_GX2SURFFMT format, sint32 firstMip, sint32 mipCount, sint32 firstSlice, sint32 sliceCount)
{
	cemu_assert_debug(mipCount > 0);
	cemu_assert_debug(sliceCount > 0);
	cemu_assert_debug((firstMip + mipCount) <= this->mipLevels);
	cemu_assert_debug((firstSlice + sliceCount) <= this->depth);

	return new LatteTextureViewMtl(m_mtlr, this, dim, format, firstMip, mipCount, firstSlice, sliceCount);
}

// TODO: lazy allocation?
void LatteTextureMtl::AllocateOnHost()
{
	// The texture is already allocated
}
