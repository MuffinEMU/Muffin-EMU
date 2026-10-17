#include "Cafe/HW/Latte/Renderer/Metal/MetalSamplerCache.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalRenderer.h"
#include "Cafe/HW/Latte/Core/LatteShader.h"
#include "Cafe/HW/Latte/Renderer/Metal/LatteToMtl.h"

MTL::SamplerBorderColor GetBorderColor(LatteConst::ShaderType shaderType, uint32 stageSamplerIndex, const _LatteRegisterSetSampler* samplerWords, bool logWorkaround = false)
{
    auto borderType = samplerWords->WORD0.get_BORDER_COLOR_TYPE();

    MTL::SamplerBorderColor borderColor;
    if (borderType == Latte::LATTE_SQ_TEX_SAMPLER_WORD0_0::E_BORDER_COLOR_TYPE::TRANSPARENT_BLACK)
        borderColor = MTL::SamplerBorderColorTransparentBlack;
    else if (borderType == Latte::LATTE_SQ_TEX_SAMPLER_WORD0_0::E_BORDER_COLOR_TYPE::OPAQUE_BLACK)
        borderColor = MTL::SamplerBorderColorOpaqueBlack;
    else if (borderType == Latte::LATTE_SQ_TEX_SAMPLER_WORD0_0::E_BORDER_COLOR_TYPE::OPAQUE_WHITE)
        borderColor = MTL::SamplerBorderColorOpaqueWhite;
    else [[unlikely]]
    {
        _LatteRegisterSetSamplerBorderColor* borderColorReg;
		if (shaderType == LatteConst::ShaderType::Vertex)
			borderColorReg = LatteGPUState.contextNew.TD_VS_SAMPLER_BORDER_COLOR + stageSamplerIndex;
		else if (shaderType == LatteConst::ShaderType::Pixel)
			borderColorReg = LatteGPUState.contextNew.TD_PS_SAMPLER_BORDER_COLOR + stageSamplerIndex;
		else // geometry
			borderColorReg = LatteGPUState.contextNew.TD_GS_SAMPLER_BORDER_COLOR + stageSamplerIndex;
		float r = borderColorReg->red.get_channelValue();
		float g = borderColorReg->green.get_channelValue();
		float b = borderColorReg->blue.get_channelValue();
		float a = borderColorReg->alpha.get_channelValue();

		// Metal doesn't support custom border color
		// Let's find the best match
		bool opaque = (a == 1.0f);
		bool white = (r == 1.0f);
		if (opaque)
		{
		    if (white)
                borderColor = MTL::SamplerBorderColorOpaqueWhite;
            else
                borderColor = MTL::SamplerBorderColorOpaqueBlack;
		}
		else
		{
		    borderColor = MTL::SamplerBorderColorTransparentBlack;
		}

		if (logWorkaround)
		{
		    float newR, newG, newB, newA;
			switch (borderColor)
			{
			case MTL::SamplerBorderColorTransparentBlack:
                newR = 0.0f;
                newG = 0.0f;
                newB = 0.0f;
                newA = 0.0f;
                break;
            case MTL::SamplerBorderColorOpaqueBlack:
                newR = 0.0f;
                newG = 0.0f;
                newB = 0.0f;
                newA = 1.0f;
                break;
            case MTL::SamplerBorderColorOpaqueWhite:
                newR = 1.0f;
                newG = 1.0f;
                newB = 1.0f;
                newA = 1.0f;
                break;
            }

            if (r != newR || g != newG || b != newB || a != newA)
                cemuLog_log(LogType::Force, "Custom border color ({}, {}, {}, {}) is not supported on Metal, using ({}, {}, {}, {}) instead", r, g, b, a, newR, newG, newB, newA);
		}
    }

    return borderColor;
}

MetalSamplerCache::~MetalSamplerCache()
{
    for (auto& pair : m_samplerCache)
    {
        pair.second->release();
    }
    m_samplerCache.clear();
}

MTL::SamplerState* MetalSamplerCache::GetSamplerState(const LatteContextRegister& lcr, LatteConst::ShaderType shaderType, uint32 stageSamplerIndex, const _LatteRegisterSetSampler* samplerWords, bool depthCompare)
{
    uint64 stateHash = CalculateSamplerHash(lcr, shaderType, stageSamplerIndex, samplerWords, depthCompare);
    auto& samplerState = m_samplerCache[stateHash];
    if (samplerState)
        return samplerState;

	// Sampler state


    NS_STACK_SCOPED MTL::SamplerDescriptor* samplerDescriptor = MTL::SamplerDescriptor::alloc()->init();
	samplerDescriptor->setSupportArgumentBuffers(true);

    // lod
    uint32 iMinLOD = samplerWords->WORD1.get_MIN_LOD();
    uint32 iMaxLOD = samplerWords->WORD1.get_MAX_LOD();
    //sint32 iLodBias = samplerWords->WORD1.get_LOD_BIAS();

    auto filterMip = samplerWords->WORD0.get_MIP_FILTER();
    if (filterMip == Latte::LATTE_SQ_TEX_SAMPLER_WORD0_0::E_Z_FILTER::NONE)
    {
        samplerDescriptor->setMipFilter(MTL::SamplerMipFilterNearest);
        samplerDescriptor->setLodMinClamp(0.0f);
        samplerDescriptor->setLodMaxClamp(0.25f);
    }
    else if (filterMip == Latte::LATTE_SQ_TEX_SAMPLER_WORD0_0::E_Z_FILTER::POINT)
    {
        samplerDescriptor->setMipFilter(MTL::SamplerMipFilterNearest);
        samplerDescriptor->setLodMinClamp((float)iMinLOD / 64.0f);
        samplerDescriptor->setLodMaxClamp((float)iMaxLOD / 64.0f);
    }
    else if (filterMip == Latte::LATTE_SQ_TEX_SAMPLER_WORD0_0::E_Z_FILTER::LINEAR)
    {
        samplerDescriptor->setMipFilter(MTL::SamplerMipFilterLinear);
        samplerDescriptor->setLodMinClamp((float)iMinLOD / 64.0f);
        samplerDescriptor->setLodMaxClamp((float)iMaxLOD / 64.0f);
    }
    else
    {
        // fallback for invalid constants
        samplerDescriptor->setMipFilter(MTL::SamplerMipFilterLinear);
        samplerDescriptor->setLodMinClamp((float)iMinLOD / 64.0f);
        samplerDescriptor->setLodMaxClamp((float)iMaxLOD / 64.0f);
    }

    auto filterMin = samplerWords->WORD0.get_XY_MIN_FILTER();
    cemu_assert_debug(filterMin != Latte::LATTE_SQ_TEX_SAMPLER_WORD0_0::E_XY_FILTER::BICUBIC); // todo
    samplerDescriptor->setMinFilter((filterMin == Latte::LATTE_SQ_TEX_SAMPLER_WORD0_0::E_XY_FILTER::POINT || filterMin == Latte::LATTE_SQ_TEX_SAMPLER_WORD0_0::E_XY_FILTER::ANISO_POINT) ? MTL::SamplerMinMagFilterNearest : MTL::SamplerMinMagFilterLinear);

    auto filterMag = samplerWords->WORD0.get_XY_MAG_FILTER();
    samplerDescriptor->setMagFilter((filterMag == Latte::LATTE_SQ_TEX_SAMPLER_WORD0_0::E_XY_FILTER::POINT || filterMag == Latte::LATTE_SQ_TEX_SAMPLER_WORD0_0::E_XY_FILTER::ANISO_POINT) ? MTL::SamplerMinMagFilterNearest : MTL::SamplerMinMagFilterLinear);

    auto filterZ = samplerWords->WORD0.get_Z_FILTER();
    // todo: z-filter for texture array samplers is customizable for GPU7 but OpenGL/Vulkan doesn't expose this functionality?

    auto clampX = samplerWords->WORD0.get_CLAMP_X();
    auto clampY = samplerWords->WORD0.get_CLAMP_Y();
    auto clampZ = samplerWords->WORD0.get_CLAMP_Z();

    samplerDescriptor->setSAddressMode(GetMtlSamplerAddressMode(clampX));
    samplerDescriptor->setTAddressMode(GetMtlSamplerAddressMode(clampY));
    samplerDescriptor->setRAddressMode(GetMtlSamplerAddressMode(clampZ));

    auto maxAniso = samplerWords->WORD0.get_MAX_ANISO_RATIO();

    // The field is 3 bits wide and 16:1 (4) is the highest ratio the GPU defines; 5 to 7 would ask Metal for 32 to 128,
    // outside the 1 to 16 it accepts, and the descriptor is then refused.
    if (maxAniso > 0)
        samplerDescriptor->setMaxAnisotropy(std::min<NS::UInteger>(16, 1u << maxAniso));

    // TODO: set lod bias
    //samplerInfo.mipLodBias = (float)iLodBias / 64.0f;

    // depth compare
    // Only for a unit the shader samples with sample_compare, as the Vulkan backend sets compareEnable only for units
    // the shader compares. The register can hold a compare function while the shader reads the texture plainly (or
    // emulates the compare itself), and such a read never asked for one. Never is what Metal uses otherwise.
    // E_DEPTH_COMPARE and E_COMPAREFUNC share their encoding (NEVER, LESS, EQUAL, LEQUAL, GREATER, NOTEQUAL, GEQUAL, ALWAYS).
    if (depthCompare)
        samplerDescriptor->setCompareFunction(GetMtlCompareFunc((Latte::E_COMPAREFUNC)samplerWords->WORD0.get_DEPTH_COMPARE_FUNCTION()));

    // Border color
    auto borderColor = GetBorderColor(shaderType, stageSamplerIndex, samplerWords, true);
    samplerDescriptor->setBorderColor(borderColor);

    samplerState = m_mtlr->GetDevice()->newSamplerState(samplerDescriptor);

    return samplerState;
}

uint64 MetalSamplerCache::CalculateSamplerHash(const LatteContextRegister& lcr, LatteConst::ShaderType shaderType, uint32 stageSamplerIndex, const _LatteRegisterSetSampler* samplerWords, bool depthCompare)
{
    // GetSamplerState() builds the sampler from WORD0, the MIN_LOD and MAX_LOD fields of WORD1, the Metal border
    // colour and whether the compare function is applied, and nothing else (Metal has no LOD bias on the sampler, and
    // WORD2 is not used). Those fit in 55 bits, so they are packed into the key as they are rather than hashed. The
    // old rotate-and-add hash let the border colour land on the bits of the depth compare function, so a shadow
    // sampler could be handed a sampler with another compare function (or border colour) that shared its key.
    const uint64 word0 = samplerWords->WORD0.getRawValue();
    const uint64 lodRange = samplerWords->WORD1.getRawValue() & 0xFFFFF; // MIN_LOD (bits 0-9), MAX_LOD (bits 10-19)
    const uint64 borderColor = (uint64)GetBorderColor(shaderType, stageSamplerIndex, samplerWords) & 0x3;

    return word0 | (lodRange << 32) | (borderColor << 52) | ((depthCompare ? 1ull : 0ull) << 54);
}
