#pragma once

#include <Metal/Metal.hpp>

#include "Cafe/HW/Latte/Core/LatteTexture.h"
#include "HW/Latte/ISA/LatteReg.h"
#include "util/ChunkedHeap/ChunkedHeap.h"

class LatteTextureMtl : public LatteTexture
{
public:
	LatteTextureMtl(class MetalRenderer* mtlRenderer, Latte::E_DIM dim, MPTR physAddress, MPTR physMipAddress, Latte::E_GX2SURFFMT format, uint32 width, uint32 height, uint32 depth, uint32 pitch, uint32 mipLevels,
		uint32 swizzle, Latte::E_HWTILEMODE tileMode, bool isDepth, bool isRenderTarget);
	~LatteTextureMtl();

	MTL::Texture* GetTexture() const {
	    return m_texture;
	}

	void AllocateOnHost() override;

	// True when the GPU had no memory for this texture and it is standing on the shared 1x1 null texture instead.
	// Such a texture samples as black and renders nowhere, so the renderer drops it to let the next use try again.
	bool IsNullSubstitute() const {
	    return m_isNullSubstitute;
	}

protected:
	LatteTextureView* CreateView(Latte::E_DIM dim, Latte::E_GX2SURFFMT format, sint32 firstMip, sint32 mipCount, sint32 firstSlice, sint32 sliceCount) override;

private:
	class MetalRenderer* m_mtlr;

	MTL::Texture* m_texture;
	bool m_isNullSubstitute = false;
};
