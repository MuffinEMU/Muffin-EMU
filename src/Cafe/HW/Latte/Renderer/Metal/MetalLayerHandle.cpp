#include "Cafe/HW/Latte/Renderer/Metal/MetalLayerHandle.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalLayer.h"

#include "gui/interface/WindowSystem.h"

MetalLayerHandle::MetalLayerHandle(MTL::Device* device, const Vector2i& size, bool mainWindow)
{
    const auto& windowInfo = (mainWindow ? WindowSystem::GetWindowInfo().window_main : WindowSystem::GetWindowInfo().window_pad);

    m_layer = (CA::MetalLayer*)CreateMetalLayer(windowInfo.surface, m_layerScaleX, m_layerScaleY);
    m_layer->setDevice(device);

    const CGSize drawableSize = m_layer->drawableSize();
    if (size.x > 0 && drawableSize.width > 0.0)
        m_layerScaleX = (float)drawableSize.width / (float)size.x;
    if (size.y > 0 && drawableSize.height > 0.0)
        m_layerScaleY = (float)drawableSize.height / (float)size.y;

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

void MetalLayerHandle::Resize(const Vector2i& size, double scale)
{
    // Reachable before InitializeLayer() has ever run for this window - iOS now calls
    // this from CemuUIKit_UpdateMainWindowSize()/UpdatePadWindowSize() on every layout
    // change, not only after a layer exists for it (a default-constructed handle, with
    // m_layer still null, is a real and expected state here, not a bug on its own).
    if (!m_layer)
        return;
    // scale < 0 (the desktop wxWidgets caller, MetalCanvas.cpp, which never had a scale
    // concept of its own here) means "leave m_layerScaleX/Y exactly as they are" - purely
    // additive, so that caller's behavior is unchanged. iOS always passes its real,
    // current dpiScale explicitly (CemuUIKit_UpdateMainWindowSize()/UpdatePadWindowSize()
    // in WindowSystem.mm both already have it on hand for exactly this call).
    //
    // The first version of this fix tried to re-derive the scale by reading it back off
    // the layer itself (CA::MetalLayer::contentsScale()) instead of taking it as a
    // parameter - metal-cpp's binding does not expose that member at all, which is a
    // build break a fresh CI run caught immediately (no local Xcode/metal-cpp headers to
    // check it against before pushing). Taking the value the caller already has, rather
    // than trying to read it back through an API surface this file cannot fully verify
    // locally, is the more robust fix anyway: one source of truth instead of two that
    // could disagree.
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
