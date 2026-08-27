#include "Cafe/HW/Latte/Renderer/Metal/MetalLayerHandle.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalLayer.h"

#include "gui/interface/WindowSystem.h"

MetalLayerHandle::MetalLayerHandle(MTL::Device* device, const Vector2i& size, bool mainWindow)
{
    const auto& windowInfo = (mainWindow ? WindowSystem::GetWindowInfo().window_main : WindowSystem::GetWindowInfo().window_pad);

    // The scale this window's phys_width/phys_height were already derived from, rather
    // than whatever the host view reports for itself - see CreateMetalLayer()'s contract
    // in MetalLayer.h. A layer built at a different scale than the size the engine
    // believes the window is puts the output blit's viewport
    // (LatteRenderTarget_getScreenImageArea, driven by GetWindowPhysSize()) and the
    // drawable permanently out of step.
    const float requestedScale = (float)(mainWindow ? WindowSystem::GetWindowInfo().dpi_scale.load()
                                                    : WindowSystem::GetWindowInfo().pad_dpi_scale.load());

    m_layer = (CA::MetalLayer*)CreateMetalLayer(windowInfo.surface, size, requestedScale, m_layerScaleX, m_layerScaleY);
    m_layer->setDevice(device);
    m_layer->setDrawableSize(CGSize{(float)size.x * m_layerScaleX, (float)size.y * m_layerScaleY});
    m_layer->setFramebufferOnly(true);
}

MetalLayerHandle::~MetalLayerHandle()
{
    if (m_layer)
        m_layer->release();
}

void MetalLayerHandle::Resize(const Vector2i& size)
{
    m_layer->setDrawableSize(CGSize{(float)size.x * m_layerScaleX, (float)size.y * m_layerScaleY});
}

void MetalLayerHandle::ResizeWithScale(const Vector2i& sizeInPoints, float scale)
{
    if (!m_layer)
        return;
    m_layerScaleX = scale;
    m_layerScaleY = scale;
    ResizeMetalLayer(m_layer, sizeInPoints, scale);
    Resize(sizeInPoints);
}

bool MetalLayerHandle::AcquireDrawable()
{
    if (m_drawable)
        return true;

    m_drawable = m_layer->nextDrawable();
    if (!m_drawable)
    {
        cemuLog_log(LogType::Force, "layer {} failed to acquire next drawable", (void*)this);
        return false;
    }

    return true;
}

void MetalLayerHandle::PresentDrawable(MTL::CommandBuffer* commandBuffer)
{
    commandBuffer->presentDrawable(m_drawable);
    m_drawable = nullptr;
}
