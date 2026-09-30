#pragma once

#include <Metal/Metal.hpp>

#include "Cafe/HW/Latte/LegacyShaderDecompiler/LatteDecompiler.h"
#include "Cafe/HW/Latte/Core/LatteCachedFBO.h"

class CachedFBOMtl : public LatteCachedFBO
{
public:
	CachedFBOMtl(class MetalRenderer* metalRenderer, uint64 key);

	~CachedFBOMtl();

	MTL::RenderPassDescriptor* GetRenderPassDescriptor()
	{
	    return m_renderPassDescriptor;
	}

	// Size of the smallest real attachment, in pixels of the level the attachment renders to.
	// 0 when the pass has no real attachment (the dummy one used for streamout-only draws).
	// Metal requires a scissor rectangle to lie inside this area.
	uint32 GetRenderAreaWidth() const { return m_renderAreaWidth; }
	uint32 GetRenderAreaHeight() const { return m_renderAreaHeight; }

private:
    MTL::RenderPassDescriptor* m_renderPassDescriptor = nullptr;
    uint32 m_renderAreaWidth = 0;
    uint32 m_renderAreaHeight = 0;
};
