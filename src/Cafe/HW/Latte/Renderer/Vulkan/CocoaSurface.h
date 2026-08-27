#pragma once

// iOS defines this in UIKitSurface.mm and macOS in CocoaSurface.mm; exactly one of the
// two is ever compiled. BOOST_OS_MACOS is 0 on iOS (see VulkanAPI.h), so without the
// second term the declaration would vanish on the platform that still needs it.
#if BOOST_OS_MACOS || defined(CEMU_PLATFORM_IOS)

#include <vulkan/vulkan.h>

VkSurfaceKHR CreateCocoaSurface(VkInstance instance, void* handle);

#endif
