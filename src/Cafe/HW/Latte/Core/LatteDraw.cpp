#include "Cafe/HW/Latte/Core/LatteDraw.h"
#include "Cafe/HW/Latte/Core/Latte.h"
#include "Cafe/HW/Latte/Core/LatteTexture.h"
#include "Cafe/HW/Latte/ISA/RegDefines.h"
#include "Cafe/HW/Latte/Renderer/Renderer.h"
#include "Cemu/Logging/CemuLogging.h"

#if !defined(CEMU_PLATFORM_IOS)
#include "Cafe/HW/Latte/Renderer/OpenGL/LatteTextureViewGL.h"
#endif

// Backend-agnostic: reads shared LatteGPUState registers and, on every backend but
// OpenGL, clears through the fully generic g_renderer->texture_clear*Slice()
// interface. Only ever physically lived in OpenGLRendererCore.cpp - which desktop
// links unconditionally alongside every other backend, but which iOS deliberately
// excludes entirely (Metal-only, see src/Cafe/CMakeLists.txt) - so MetalRenderer's
// and VulkanRenderer's calls to this (both already forward-declare it, expecting
// exactly this shared definition) left it as a genuine undefined symbol on iOS,
// not dead code like the OpenGL-only branch inside it.
void LatteDraw_handleSpecialState8_clearAsDepth()
{
	if (LatteGPUState.contextNew.GetSpecialStateValues()[0] == 0)
		cemuLog_logDebug(LogType::Force, "Special state 8 requires special state 0 but it is not set?");
	// get depth buffer information
	uint32 regDepthBuffer = LatteGPUState.contextRegister[mmDB_HTILE_DATA_BASE];
	uint32 regDepthSize = LatteGPUState.contextRegister[mmDB_DEPTH_SIZE];
	uint32 regDepthBufferInfo = LatteGPUState.contextRegister[mmDB_DEPTH_INFO];
	// get format and tileMode from info reg
	uint32 depthBufferTileMode = (regDepthBufferInfo >> 15) & 0xF;

	MPTR depthBufferPhysMem = regDepthBuffer << 8;
	uint32 depthBufferPitch = (((regDepthSize >> 0) & 0x3FF) + 1);
	uint32 depthBufferHeight = ((((regDepthSize >> 10) & 0xFFFFF) + 1) / depthBufferPitch);
	depthBufferPitch <<= 3;
	depthBufferHeight <<= 3;
	uint32 depthBufferWidth = depthBufferPitch;

	sint32 sliceIndex = 0; // todo
	sint32 mipIndex = 0;

	// clear all color buffers that match the format of the depth buffer
	sint32 searchIndex = 0;
	while (true)
	{
		LatteTextureView* view = LatteTC_LookupTextureByData(depthBufferPhysMem, depthBufferWidth, depthBufferHeight, depthBufferPitch, 0, 1, sliceIndex, 1, &searchIndex);
		if (!view)
		{
			// should we clear in RAM instead?
			break;
		}
		sint32 effectiveClearWidth = view->baseTexture->width;
		sint32 effectiveClearHeight = view->baseTexture->height;
		LatteTexture_scaleToEffectiveSize(view->baseTexture, &effectiveClearWidth, &effectiveClearHeight, 0);

		// hacky way to get clear color
		float* regClearColor = (float*)(LatteGPUState.contextRegister + 0xC000 + 0); // REG_BASE_ALU_CONST

		uint8 clearColor[4] = { 0 };
		clearColor[0] = (uint8)(regClearColor[0] * 255.0f);
		clearColor[1] = (uint8)(regClearColor[1] * 255.0f);
		clearColor[2] = (uint8)(regClearColor[2] * 255.0f);
		clearColor[3] = (uint8)(regClearColor[3] * 255.0f);

		// todo - use fragment shader software emulation (evoke for one pixel) to determine clear color
		// todo - dont clear entire slice, use effectiveClearWidth, effectiveClearHeight

#if !defined(CEMU_PLATFORM_IOS)
		if (g_renderer->GetType() == RendererAPI::OpenGL)
		{
			//cemu_assert_debug(false); // implement g_renderer->texture_clearColorSlice properly for OpenGL renderer
			if (glClearTexSubImage)
				glClearTexSubImage(((LatteTextureViewGL*)view)->glTexId, mipIndex, 0, 0, 0, effectiveClearWidth, effectiveClearHeight, 1, GL_RGBA, GL_UNSIGNED_BYTE, clearColor);
		}
		else
#endif
		{
			if (view->baseTexture->isDepth)
				g_renderer->texture_clearDepthSlice(view->baseTexture, sliceIndex + view->firstSlice, mipIndex + view->firstMip, true, view->baseTexture->hasStencil, 0.0f, 0);
			else
				g_renderer->texture_clearColorSlice(view->baseTexture, sliceIndex + view->firstSlice, mipIndex + view->firstMip, clearColor[0], clearColor[1], clearColor[2], clearColor[3]);
		}
	}
}
