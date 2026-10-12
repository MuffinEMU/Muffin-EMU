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

    // Null when there is no drawable (or it has no texture), so callers can bail out instead of dereferencing.
    MTL::Texture* GetDrawableTexture() const { return m_drawable ? m_drawable->texture() : nullptr; }

private:
    CA::MetalLayer* m_layer = nullptr;
    float m_layerScaleX = 1.0f;
    float m_layerScaleY = 1.0f;

    CA::MetalDrawable* m_drawable = nullptr;

    // Kept so a layer that lost its device or was given a degenerate size can be put back.
    MTL::Device* m_device = nullptr;
    bool m_isMainWindow = false;
    double m_lastGoodWidth = 0.0;
    double m_lastGoodHeight = 0.0;
    uint32_t m_acquireCount = 0;
    // A layer whose drawables do not come back (not on screen, display not consuming them, app in the
    // background) makes nextDrawable() block for up to a second per call. After one such call the next few
    // acquires are skipped outright, so the GPU thread keeps rendering and that output simply is not
    // presented for a moment, instead of the whole emulation running at one frame per second.
    uint32_t m_skipAcquires = 0;
    uint32_t m_starvedCount = 0;

    void RecordLayerState() const;
    void RepairLayer();
};
