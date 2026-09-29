#include "Cafe/HW/Latte/Renderer/Metal/MetalLayerHandle.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalLayer.h"

#include "gui/interface/WindowSystem.h"

MetalLayerHandle::MetalLayerHandle(MTL::Device* device, const Vector2i& size, bool mainWindow)
{
    const auto& windowInfo = (mainWindow ? WindowSystem::GetWindowInfo().window_main : WindowSystem::GetWindowInfo().window_pad);

    m_layer = (CA::MetalLayer*)CreateMetalLayer(windowInfo.surface, m_layerScaleX, m_layerScaleY);
    m_layer->setDevice(device);

    // Take the scale from the window system (dpi_scale), not by measuring the layer: UIKit can
    // change the layer's drawable size after the bridge has set the scale, and the two would disagree.
    const auto& windowSystemInfo = WindowSystem::GetWindowInfo();
    const double authoritativeScale = mainWindow ? windowSystemInfo.dpi_scale.load()
                                                 : windowSystemInfo.pad_dpi_scale.load();
    // Keep the scale CreateMetalLayer() seeded if the window system has none yet (a zero would mean a zero-sized drawable).
    if (authoritativeScale > 0.0)
    {
        m_layerScaleX = (float)authoritativeScale;
        m_layerScaleY = (float)authoritativeScale;
    }

    m_layer->setDrawableSize(CGSize{(float)size.x * m_layerScaleX, (float)size.y * m_layerScaleY});
    m_layer->setFramebufferOnly(true);
}

MetalLayerHandle::~MetalLayerHandle()
{
    // m_layer is not owned: it is the CAMetalLayer that belongs to the UIView tree, so it is not released here.
    // m_drawable is retained in AcquireDrawable() and released here if it was never presented.
    if (m_drawable)
        m_drawable->release();
}

MetalLayerHandle::MetalLayerHandle(MetalLayerHandle&& other) noexcept
    : m_layer(other.m_layer), m_layerScaleX(other.m_layerScaleX), m_layerScaleY(other.m_layerScaleY),
      m_drawable(other.m_drawable)
{
    other.m_layer = nullptr;
    other.m_drawable = nullptr;
}

MetalLayerHandle& MetalLayerHandle::operator=(MetalLayerHandle&& other) noexcept
{
    if (this == &other)
        return *this;
    // m_layer is not owned (see the destructor); only m_drawable is released.
    if (m_drawable)
        m_drawable->release();
    m_layer = other.m_layer;
    m_layerScaleX = other.m_layerScaleX;
    m_layerScaleY = other.m_layerScaleY;
    m_drawable = other.m_drawable;
    other.m_layer = nullptr;
    other.m_drawable = nullptr;
    return *this;
}

void MetalLayerHandle::Resize(const Vector2i& size, double scale)
{
    // May be called before a layer exists for this window.
    if (!m_layer)
        return;
    // scale < 0 keeps the current scale. The caller passes its dpi scale explicitly rather than
    // reading it back from the layer, so there is a single source of truth.
    if (scale >= 0.0)
    {
        m_layerScaleX = (float)scale;
        m_layerScaleY = (float)scale;
    }
    m_layer->setDrawableSize(CGSize{(float)size.x * m_layerScaleX, (float)size.y * m_layerScaleY});
}

bool MetalLayerHandle::AcquireDrawable()
{
    if (m_drawable)
        return true;

    // nextDrawable() returns an autoreleased object; retain it until PresentDrawable() or the destructor releases it.
    m_drawable = m_layer->nextDrawable();
    if (!m_drawable)
    {
        cemuLog_log(LogType::Force, "layer {} failed to acquire next drawable", (void*)this);
        return false;
    }
    m_drawable->retain();

    return true;
}

void MetalLayerHandle::PresentDrawable(MTL::CommandBuffer* commandBuffer)
{
    commandBuffer->presentDrawable(m_drawable);
    m_drawable->release();
    m_drawable = nullptr;
}
