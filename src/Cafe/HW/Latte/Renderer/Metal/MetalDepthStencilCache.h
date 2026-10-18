#pragma once

#include <Metal/Metal.hpp>
#include <unordered_map>

#include "HW/Latte/ISA/LatteReg.h"

class MetalDepthStencilCache
{
public:
    MetalDepthStencilCache(class MetalRenderer* metalRenderer) : m_mtlr{metalRenderer} {}
    ~MetalDepthStencilCache();

    // hasDepthAttachment / hasStencilAttachment: what the render pass really has bound (MetalAttachmentsInfo). The depth
    // test needs the first and the stencil test the second; a test the guest enabled against an attachment the pass
    // does not have is left off, as it is on the Vulkan backend where a missing attachment disables the test.
    MTL::DepthStencilState* GetDepthStencilState(const LatteContextRegister& lcr, bool hasDepthAttachment, bool hasStencilAttachment);

private:
    class MetalRenderer* m_mtlr;

    std::unordered_map<uint64, MTL::DepthStencilState*> m_depthStencilCache;

    uint64 CalculateDepthStencilHash(const LatteContextRegister& lcr, bool hasDepthAttachment, bool hasStencilAttachment);
};
