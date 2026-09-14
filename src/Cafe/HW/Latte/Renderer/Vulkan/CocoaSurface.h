#pragma once

#if BOOST_OS_MACOS || BOOST_OS_IOS

#include <vulkan/vulkan.h>

VkSurfaceKHR CreateCocoaSurface(VkInstance instance, void* handle);

#endif
