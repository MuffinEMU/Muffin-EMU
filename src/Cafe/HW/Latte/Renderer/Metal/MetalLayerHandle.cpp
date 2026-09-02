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
    if (m_drawable)
        m_drawable->release();
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

    // nextDrawable() is a Cocoa "get" accessor, not an alloc/new/copy one - like
    // commandQueue()->commandBuffer() in MetalRenderer::GetCommandBuffer(), it returns
    // an autoreleased object the caller does not own. GetCommandBuffer() retains its
    // result for exactly this reason; this call site never did, so m_drawable held a
    // pointer good only until the nearest autorelease pool drained - which could
    // easily happen before PresentDrawable() runs, since a full GX2 frame's worth of
    // other rendering happens in between. Presenting (or destroying/moving this handle
    // while holding) an already-deallocated drawable never gives the real drawable back
    // to the CAMetalLayer's fixed-size pool, so it permanently loses one slot each time
    // this raced - draining the pool over the first few frames until nextDrawable()
    // starts returning nil immediately, forever, which is indistinguishable from a
    // frozen title (GX2 frame count keeps climbing - the guest is still producing
    // frames - while nothing ever reaches the screen and memory climbs unbounded, since
    // whatever was backing the un-released drawables never gets reclaimed either).
    m_drawable = m_layer->nextDrawable();
    if (!m_drawable)
    {
        // Rate-limited: the whole point of retaining above is that this can now legally
        // fail every single frame on a title that is genuinely outrunning its swapchain
        // (as opposed to the old dangling-pointer failure, which fires this line
        // hundreds of times a second and buries every other log line under it - the same
        // volume that has been truncating whole crash reports read back over mail).
        cemuLog_logOnce(LogType::Force, "layer {} failed to acquire next drawable", (void*)this);
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
