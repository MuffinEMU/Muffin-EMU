#include "Cafe/HW/Latte/Renderer/Metal/MetalLayerHandle.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalLayer.h"

#include "gui/interface/WindowSystem.h"

MetalLayerHandle::MetalLayerHandle(MTL::Device* device, const Vector2i& size, bool mainWindow)
{
    const auto& windowInfo = (mainWindow ? WindowSystem::GetWindowInfo().window_main : WindowSystem::GetWindowInfo().window_pad);

    m_layer = (CA::MetalLayer*)CreateMetalLayer(windowInfo.surface, m_layerScaleX, m_layerScaleY);
    m_layer->setDevice(device);

    // The layer's own contentsScale is already correct by the time this runs - iOS sets
    // it explicitly at registration (CemuUIKit_SetMainView()/cemu_bridge_register_
    // render_surface() in CemuBridge.mm), before InitializeLayer() - which constructs
    // this - is ever called. Deriving m_layerScaleX/Y from it directly, rather than
    // back-computing a guess from whatever drawableSize the layer happened to already
    // report (a fragile self-referential read: the answer depended on whatever the layer
    // had been left at by something else, not on anything this code actually knew to be
    // true), is what Resize() below also does on every later call now - construction and
    // every resize after it agree on the same source of truth instead of only the first
    // one having a chance of being right.
    const double contentsScale = m_layer->contentsScale();
    if (contentsScale > 0.0)
    {
        m_layerScaleX = (float)contentsScale;
        m_layerScaleY = (float)contentsScale;
    }

    m_layer->setDrawableSize(CGSize{(float)size.x * m_layerScaleX, (float)size.y * m_layerScaleY});
    m_layer->setFramebufferOnly(true);
}

MetalLayerHandle::~MetalLayerHandle()
{
    // m_layer is NOT owned here, deliberately - CreateMetalLayer() (MetalLayer.mm) does
    // not create anything despite its name; it hands back windowInfo.surface itself, an
    // existing CAMetalLayer that belongs to the UIView tree on the Swift side (a
    // __bridge cast, not a retain). Releasing it here would decrement a refcount this
    // object never incremented - a real over-release of a layer something else still
    // owns, not a fix. m_drawable is different: nextDrawable() genuinely hands this
    // object an autoreleased reference it retains in AcquireDrawable(), so a drawable
    // acquired but never presented (a dropped/skipped frame, or this handle being torn
    // down mid-frame) needs the matching release here.
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
    // No m_layer->release() here either - see the destructor's comment. Only
    // m_drawable is ever owned by this object.
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

void MetalLayerHandle::Resize(const Vector2i& size)
{
    // Reachable before InitializeLayer() has ever run for this window - iOS now calls
    // this from CemuUIKit_UpdateMainWindowSize()/UpdatePadWindowSize() on every layout
    // change, not only after a layer exists for it (a default-constructed handle, with
    // m_layer still null, is a real and expected state here, not a bug on its own).
    if (!m_layer)
        return;
    // Re-derive fresh every call, same reasoning as the constructor above - this used to
    // trust whatever m_layerScaleX/Y the constructor computed once and never revisit it,
    // which is why calling this on every resize (a fix that shipped in v1.8) still didn't
    // make Single Screen fullscreen under the Metal backend: the WIDTH/HEIGHT going in
    // were correct, but they were being multiplied by a scale factor that may never have
    // been right in the first place.
    const double contentsScale = m_layer->contentsScale();
    if (contentsScale > 0.0)
    {
        m_layerScaleX = (float)contentsScale;
        m_layerScaleY = (float)contentsScale;
    }
    m_layer->setDrawableSize(CGSize{(float)size.x * m_layerScaleX, (float)size.y * m_layerScaleY});
}

bool MetalLayerHandle::AcquireDrawable()
{
    if (m_drawable)
        return true;

    // nextDrawable() follows Cocoa's autoreleased-return convention (no "copy"/"new"/
    // "alloc"/"create" in the name), so without this retain() the drawable can be
    // deallocated out from under m_drawable the moment the current autorelease pool
    // drains - typically before PresentDrawable() ever gets to use it, on whichever
    // later run-loop turn or GPU-thread iteration that happens to be. Balanced by the
    // release() in PresentDrawable() below and in the destructor, for a drawable
    // acquired but never presented (a dropped/skipped frame).
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
