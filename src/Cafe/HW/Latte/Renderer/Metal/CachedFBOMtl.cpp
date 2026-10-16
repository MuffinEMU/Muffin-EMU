#include <algorithm>
#include "Cafe/HW/Latte/Renderer/Metal/CachedFBOMtl.h"
#include "Cafe/HW/Latte/Renderer/Metal/LatteTextureViewMtl.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalRenderer.h"
#include "Cafe/HW/Latte/Renderer/Metal/LatteToMtl.h"

CachedFBOMtl::CachedFBOMtl(class MetalRenderer* metalRenderer, uint64 key) : LatteCachedFBO(key)
{
	m_renderPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();

	bool hasAttachment = false;
	auto trackRenderArea = [this](MTL::Texture* texture) {
		if (!texture)
			return;
		const uint32 width = (uint32)texture->width();
		const uint32 height = (uint32)texture->height();
		m_renderAreaWidth = m_renderAreaWidth == 0 ? width : std::min(m_renderAreaWidth, width);
		m_renderAreaHeight = m_renderAreaHeight == 0 ? height : std::min(m_renderAreaHeight, height);
	};
	for (int i = 0; i < 8; ++i)
	{
		const auto& buffer = colorBuffer[i];
		auto textureView = (LatteTextureViewMtl*)buffer.texture;
		// no view when the texture got no GPU memory; MetalAttachmentsInfo leaves the attachment out the same way
		MTL::Texture* attachmentTexture = textureView ? textureView->GetRGBAView() : nullptr;
		if (!attachmentTexture)
		{
			continue;
		}
		auto colorAttachment = m_renderPassDescriptor->colorAttachments()->object(i);
		colorAttachment->setTexture(attachmentTexture);
		trackRenderArea(attachmentTexture);
		colorAttachment->setLoadAction(MTL::LoadActionLoad);
		colorAttachment->setStoreAction(MTL::StoreActionStore);

		hasAttachment = true;
	}

	// setup depth attachment
	MTL::Texture* depthTexture = depthBuffer.texture ? static_cast<LatteTextureViewMtl*>(depthBuffer.texture)->GetRGBAView() : nullptr;
	if (depthTexture)
	{
		auto depthAttachment = m_renderPassDescriptor->depthAttachment();
		depthAttachment->setTexture(depthTexture);
		trackRenderArea(depthTexture);
		depthAttachment->setLoadAction(MTL::LoadActionLoad);
		depthAttachment->setStoreAction(MTL::StoreActionStore);

		// setup stencil attachment
		if (depthBuffer.hasStencil && GetMtlPixelFormatInfo(depthBuffer.texture->format, true).hasStencil)
		{
		    auto stencilAttachment = m_renderPassDescriptor->stencilAttachment();
            stencilAttachment->setTexture(depthTexture);
            stencilAttachment->setLoadAction(MTL::LoadActionLoad);
            stencilAttachment->setStoreAction(MTL::StoreActionStore);
		}

		hasAttachment = true;
	}

	// HACK: setup a dummy color attachment to prevent Metal from discarding draws for stremout draws in Super Smash Bros. for Wii U (works fine on MoltenVK without this hack though)
	if (!hasAttachment)
	{
        auto colorAttachment = m_renderPassDescriptor->colorAttachments()->object(0);
    	colorAttachment->setTexture(metalRenderer->GetNullTexture2D());
    	colorAttachment->setLoadAction(MTL::LoadActionDontCare);
    	colorAttachment->setStoreAction(MTL::StoreActionDontCare);
	}

	// Visibility buffer
	m_renderPassDescriptor->setVisibilityResultBuffer(metalRenderer->GetOcclusionQueryResultBuffer());
}

CachedFBOMtl::~CachedFBOMtl()
{
	m_renderPassDescriptor->release();
}
