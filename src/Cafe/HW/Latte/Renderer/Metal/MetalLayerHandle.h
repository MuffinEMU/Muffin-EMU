#pragma once

#include <QuartzCore/QuartzCore.hpp>

#include "Cafe/HW/Latte/Renderer/Metal/MetalCommon.h"
#include "util/math/vector2.h"

class MetalLayerHandle
{
public:
    MetalLayerHandle() = default;
    MetalLayerHandle(MTL::Device* device, const Vector2i& size, bool mainWindow);

    ~MetalLayerHandle();

    // Move-only: copying would duplicate the drawable pointer and double-release it.
    MetalLayerHandle(const MetalLayerHandle&) = delete;
    MetalLayerHandle& operator=(const MetalLayerHandle&) = delete;
    MetalLayerHandle(MetalLayerHandle&& other) noexcept;
    MetalLayerHandle& operator=(MetalLayerHandle&& other) noexcept;

    // scale < 0 keeps the current scale factor (see the .cpp).
    void Resize(const Vector2i& size, double scale = -1.0);

    bool AcquireDrawable();

    void PresentDrawable(MTL::CommandBuffer* commandBuffer);

    CA::MetalLayer* GetLayer() const { return m_layer; }

    CA::MetalDrawable* GetDrawable() const { return m_drawable; }

private:
    CA::MetalLayer* m_layer = nullptr;
    float m_layerScaleX = 1.0f;
    float m_layerScaleY = 1.0f;

    CA::MetalDrawable* m_drawable = nullptr;
};
