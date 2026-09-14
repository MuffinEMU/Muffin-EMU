#include "Cafe/HW/Latte/Renderer/Vulkan/CocoaSurface.h"
#include "Cafe/HW/Latte/Renderer/Vulkan/VulkanAPI.h"

#include "Cafe/HW/Latte/Renderer/MetalView.h"

VkSurfaceKHR CreateCocoaSurface(VkInstance instance, void* handle)
{
    VkMetalSurfaceCreateInfoEXT surface;
    surface.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
    surface.pNext = NULL;
    surface.flags = 0;
    surface.pLayer = (CAMetalLayer*)handle;

    VkSurfaceKHR result;
    VkResult err;
    if ((err = vkCreateMetalSurfaceEXT(instance, &surface, nullptr, &result)) != VK_SUCCESS)
    {
        cemuLog_log(LogType::Force, "Cannot create a Metal Vulkan surface: {}", (sint32)err);
        throw std::runtime_error(fmt::format("Cannot create a Metal Vulkan surface: {}", err));
    }

    return result;
}
