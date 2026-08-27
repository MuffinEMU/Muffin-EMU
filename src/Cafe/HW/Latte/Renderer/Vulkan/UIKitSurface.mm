#include "Cafe/HW/Latte/Renderer/Vulkan/CocoaSurface.h"

#include <TargetConditionals.h>

#if TARGET_OS_IOS

#include "Cafe/HW/Latte/Renderer/Vulkan/VulkanAPI.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalLayer.h"
#include "gui/interface/WindowSystem.h"

#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>

// iOS implementation of CreateCocoaSurface(). The macOS definition lives in
// CocoaSurface.mm and only one of the two is ever compiled into a given build, so both
// platforms can share one call site in VulkanRenderer.cpp.
//
// That call site is guarded by BOOST_OS_MACOS || defined(CEMU_PLATFORM_IOS), and the
// second term is load-bearing. Boost.Predef does NOT set BOOST_OS_MACOS for every __APPLE__ &&
// __MACH__ target, as was assumed here originally: it evaluates os/ios.h first, and a
// detected OS suppresses the rest, so on iOS BOOST_OS_MACOS is 0. With only the macOS
// term the surface entry point went undeclared and CreateFramebufferSurface returned an
// uninitialized handle.
//
// Both platforms hand a CAMetalLayer to VK_EXT_metal_surface, which is the extension
// MoltenVK presents through. The only difference is where the layer comes from: macOS
// gets it as an NSView's own backing layer (MetalView, via +layerClass), whereas on
// iOS we reuse CreateMetalLayer() from the Metal backend, because the layer geometry
// on this platform has a history of being subtly wrong in ways that read as a black
// screen, and that function is where every one of those fixes already lives -- the
// points-vs-pixels contentsScale handling, and the explicit frame instead of
// view.bounds (which is frequently still CGRectZero when a render surface is first
// registered, producing a zero-sized invisible layer). Duplicating that here would
// mean re-earning those fixes on the Vulkan path.
//
// This is safe to call only when the Metal renderer is NOT also running: both paths
// addSublayer: onto the same view, and two CAMetalLayers stacked on one view is not a
// configuration either backend expects. Renderer selection is exclusive, so that
// holds today.
VkSurfaceKHR CreateCocoaSurface(VkInstance instance, void* handle)
{
	UIView* view = (__bridge UIView*)handle;

	// Points, per CreateMetalLayer()'s contract. Fall back to the screen if the view
	// has not been laid out yet -- a zero-sized surface is not a recoverable state
	// further down, and this at least fails as a visibly wrong size rather than as a
	// blank screen with no error.
	CGSize sizeInPoints = view.bounds.size;
	if (sizeInPoints.width <= 0.0 || sizeInPoints.height <= 0.0)
	{
		sizeInPoints = UIScreen.mainScreen.bounds.size;
		cemuLog_log(LogType::Force, "Vulkan surface: host view had no size yet, falling back to screen bounds {}x{}",
					(sint32)sizeInPoints.width, (sint32)sizeInPoints.height);
	}

	// Which of the two Wii U outputs this surface is for, decided by the handle itself
	// rather than by a parameter: CreateFramebufferSurface() passes only the surface
	// pointer, and both canvases are filled in by cemu_bridge_register_*_render_surface()
	// from two different UIViews. When no pad view is registered canvas_pad is null, so
	// the TV branch is also the correct default.
	auto& windowInfo = WindowSystem::GetWindowInfo();
	const bool isPadSurface = (windowInfo.canvas_pad.surface.load() == handle) &&
							  (windowInfo.canvas_main.surface.load() != handle);

	// The scale the app already committed to for this window - NOT the view's own
	// contentScaleFactor. phys_width/phys_height (and therefore GetWindowPhysSize(), which
	// UpdateSwapchainProperties() checks against the live swapchain extent on every
	// acquire) were computed from this number. MoltenVK reports the layer's drawable size
	// as the surface's currentExtent, and ChooseSwapExtent() returns currentExtent
	// verbatim - so if the layer is built at a different scale the two disagree
	// permanently and every frame tears down and rebuilds the swapchain. See
	// CreateMetalLayer()'s contract in MetalLayer.h.
	const float requestedScale = (float)(isPadSurface ? windowInfo.pad_dpi_scale.load()
													  : windowInfo.dpi_scale.load());

	float scaleX = 1.0f;
	float scaleY = 1.0f;
	void* layer = CreateMetalLayer(handle,
								   Vector2i((sint32)sizeInPoints.width, (sint32)sizeInPoints.height),
								   requestedScale,
								   scaleX, scaleY);
	if (!layer)
	{
		cemuLog_log(LogType::Force, "Cannot create a Metal layer for the Vulkan surface");
		throw std::runtime_error("Cannot create a Metal layer for the Vulkan surface");
	}

	VkMetalSurfaceCreateInfoEXT surface;
	surface.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
	surface.pNext = NULL;
	surface.flags = 0;
	surface.pLayer = (CAMetalLayer*)layer;

	VkSurfaceKHR result;
	VkResult err;
	if ((err = vkCreateMetalSurfaceEXT(instance, &surface, nullptr, &result)) != VK_SUCCESS)
	{
		cemuLog_log(LogType::Force, "Cannot create a Metal Vulkan surface: {}", (sint32)err);
		throw std::runtime_error(fmt::format("Cannot create a Metal Vulkan surface: {}", err));
	}

	return result;
}

#endif // TARGET_OS_IOS
