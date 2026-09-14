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

    // A user-declared destructor suppresses the implicit move ctor/assignment, so
    // without these, `layer = MetalLayerHandle(device, size, mainWindow);`
    // (MetalRenderer.cpp, on every resize/recreate) would fall back to memberwise COPY:
    // the temporary's m_drawable pointer duplicated into the target, then the
    // temporary's own destructor releasing that same drawable out from under it - a
    // double-release the moment m_drawable actually owns something to release (see
    // AcquireDrawable()/the destructor below). m_layer isn't owned by this object at
    // all, so the copy never touched its lifetime - only m_drawable's. The assignment
    // above is already a move (source is a prvalue); it just needs a move operation to
    // actually take instead of copying.
    MetalLayerHandle(const MetalLayerHandle&) = delete;
    MetalLayerHandle& operator=(const MetalLayerHandle&) = delete;
    MetalLayerHandle(MetalLayerHandle&& other) noexcept;
    MetalLayerHandle& operator=(MetalLayerHandle&& other) noexcept;

    void Resize(const Vector2i& size);

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
