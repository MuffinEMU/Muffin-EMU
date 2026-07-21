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

    // This class declares a destructor that unconditionally releases m_layer, which
    // (per the standard C++ rule that a user-declared destructor suppresses implicit
    // move operations) meant `existingHandle = MetalLayerHandle(...)` - exactly what
    // MetalRenderer::InitializeLayer() does every time it runs - fell back to the
    // implicitly-generated COPY assignment operator: a naive memberwise copy of
    // m_layer/m_drawable into the target, followed immediately by the temporary's
    // destructor releasing that SAME now-aliased m_layer pointer. A confirmed live
    // device crash (MetalRenderer::BeginFrame -> nextDrawable, "unrecognized
    // selector"/segfault, deterministic on every boot, unaffected by two earlier
    // fixes targeting the Swift-side view's lifecycle instead) traced back to this -
    // the freed CAMetalLayer's memory getting reused by something else entirely
    // before the GPU thread's next draw call. Almost certainly latent on desktop too
    // (InitializeLayer() typically runs once per window there, so the dangling
    // pointer just happens to sit unused/untouched for the rest of the session,
    // rather than getting its memory reused quickly the way iOS's busier allocator
    // does) - not something introduced by any iOS-specific work.
    // Explicit move operations transfer ownership properly (nulling the source so
    // its destructor is a no-op); copy is deleted outright since there's no
    // legitimate reason to duplicate ownership of one CAMetalLayer/drawable pair.
    MetalLayerHandle(const MetalLayerHandle&) = delete;
    MetalLayerHandle& operator=(const MetalLayerHandle&) = delete;

    MetalLayerHandle(MetalLayerHandle&& other) noexcept
        : m_layer(other.m_layer), m_layerScaleX(other.m_layerScaleX), m_layerScaleY(other.m_layerScaleY), m_drawable(other.m_drawable)
    {
        other.m_layer = nullptr;
        other.m_drawable = nullptr;
    }

    MetalLayerHandle& operator=(MetalLayerHandle&& other) noexcept
    {
        if (this != &other)
        {
            if (m_layer)
                m_layer->release();
            m_layer = other.m_layer;
            m_layerScaleX = other.m_layerScaleX;
            m_layerScaleY = other.m_layerScaleY;
            m_drawable = other.m_drawable;
            other.m_layer = nullptr;
            other.m_drawable = nullptr;
        }
        return *this;
    }

    void Resize(const Vector2i& size);

    bool AcquireDrawable();

    void PresentDrawable(MTL::CommandBuffer* commandBuffer);

    CA::MetalLayer* GetLayer() const { return m_layer; }

    CA::MetalDrawable* GetDrawable() const { return m_drawable; }

private:
    CA::MetalLayer* m_layer = nullptr;
    float m_layerScaleX, m_layerScaleY;

    CA::MetalDrawable* m_drawable = nullptr;
};
