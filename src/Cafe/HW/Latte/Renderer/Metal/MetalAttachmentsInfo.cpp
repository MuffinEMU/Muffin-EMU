#include "Cafe/HW/Latte/Renderer/Metal/MetalAttachmentsInfo.h"
#include "Cafe/HW/Latte/Renderer/Metal/CachedFBOMtl.h"
#include "Cafe/HW/Latte/Renderer/Metal/LatteTextureViewMtl.h"
#include "Cafe/HW/Latte/Renderer/Metal/LatteToMtl.h"

MetalAttachmentsInfo::MetalAttachmentsInfo(class CachedFBOMtl* fbo)
{
    for (uint8 i = 0; i < LATTE_NUM_COLOR_TARGET; i++)
	{
	    const auto& colorBuffer = fbo->colorBuffer[i];
		auto texture = static_cast<LatteTextureViewMtl*>(colorBuffer.texture);
		// Must describe exactly the attachments CachedFBOMtl binds, or the pipeline's formats disagree with the
		// render pass: a view that could not be made (texture with no GPU memory) is not attached there
		if (!texture || !texture->GetRGBAView())
		    continue;

		colorFormats[i] = texture->format;
	}

	// Depth stencil attachment
	auto depthTexture = static_cast<LatteTextureViewMtl*>(fbo->depthBuffer.texture);
	if (depthTexture && depthTexture->GetRGBAView())
	{
        // The texture's own format, not the view's: a depth view always has the pixel format of the texture it was
        // made from (LatteTextureViewMtl::CreateSwizzledView), and the pipeline has to name that format
        depthFormat = depthTexture->baseTexture->format;
        // Same condition as the stencil attachment in CachedFBOMtl: a stencil pixel format for the pipeline only
        // when the texture's format really has stencil, never a depth-only format in the stencil slot
        hasStencil = fbo->depthBuffer.hasStencil && GetMtlPixelFormatInfo(depthFormat, true).hasStencil;
	}
}

MetalAttachmentsInfo::MetalAttachmentsInfo(const LatteContextRegister& lcr, const LatteDecompilerShader* pixelShader)
{
    uint8 cbMask = LatteMRT::GetActiveColorBufferMask(pixelShader, lcr);
	bool dbMask = LatteMRT::GetActiveDepthBufferMask(lcr);

	// Color attachments
	for (int i = 0; i < 8; ++i)
	{
		if ((cbMask & (1 << i)) == 0)
			continue;

		colorFormats[i] = LatteMRT::GetColorBufferFormat(i, lcr);
	}

	// Depth stencil attachment
	if (dbMask)
	{
		Latte::E_GX2SURFFMT format = LatteMRT::GetDepthBufferFormat(lcr);
		depthFormat = format;
		hasStencil = GetMtlPixelFormatInfo(format, true).hasStencil;
	}
}
