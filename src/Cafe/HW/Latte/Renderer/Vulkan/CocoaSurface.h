#pragma once

#if BOOST_OS_MACOS || BOOST_OS_IOS

#include <vulkan/vulkan.h>
#include <string>

VkSurfaceKHR CreateCocoaSurface(VkInstance instance, void* handle);

// Highest Apple GPU family of the system default Metal device, plus its name (for the Vulkan startup diagnostic).
std::string GetAppleGpuFamilyDescription();

#endif
