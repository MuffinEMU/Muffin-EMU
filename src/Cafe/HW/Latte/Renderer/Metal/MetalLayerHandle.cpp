#include "Cafe/HW/Latte/Renderer/Metal/MetalLayerHandle.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalLayer.h"

#include "gui/interface/WindowSystem.h"

MetalLayerHandle::MetalLayerHandle(MTL::Device* device, const Vector2i& size, bool mainWindow)
{
    const auto& windowInfo = (mainWindow ? WindowSystem::GetWindowInfo().window_main : WindowSystem::GetWindowInfo().window_pad);

    m_layer = (CA::MetalLayer*)CreateMetalLayer(windowInfo.surface, m_layerScaleX, m_layerScaleY);
    m_layer->setDevice(device);

    // Take the scale from the window system, NOT by measuring the layer.
    //
    // This constructor used to re-derive it: `m_layerScaleX = drawableSize.width /
    // size.x`, reading CoreAnimation's own current drawableSize back off the layer. That
    // is what made Single Screen render a small, correctly-proportioned picture in the
    // TOP-LEFT corner with black around it, and it did so from the original port onward -
    // it is in v1.0 verbatim.
    //
    // The sequence: the bridge sets the layer's contentsScale to dpiScale (the user's
    // Render Scale; the DEFAULT "Balanced" is HALF native, so 1.0 on this 2x iPad Pro),
    // and sets phys_width/phys_height = points * that same 1.0. Then `tvRenderView` is
    // added to its container and enters a window for the first time. contentsScale on a
    // UIView's own backing layer belongs to UIKit, which re-asserts the trait
    // collection's display scale - 2.0 - and CoreAnimation recomputes drawableSize to
    // bounds * 2.0. Boot reaches InitializeLayer() seconds later, on the emulation
    // thread, and this constructor measured that 2.0 and made it authoritative.
    //
    // The result is that the drawable is twice the linear size the rest of the engine
    // believes the window is. LatteRenderTarget_getScreenImageArea() sizes the output
    // rect from phys_width/phys_height, and MetalRenderer.cpp's setViewport/
    // setScissorRect apply that rect to the drawable with Metal's top-left origin - so
    // the image is drawn into the top-left quarter of a drawable twice as wide and tall,
    // and LoadActionClear blacks out the rest. Nothing rescales it afterwards, because
    // drawableSize here exactly equals bounds * contentsScale, so CoreAnimation has no
    // mismatch to correct and presents precisely what was drawn. contentsGravity is
    // irrelevant to this and setting it would not have helped.
    //
    // Why only Single Screen: in the two-screen layouts the container's size genuinely
    // changes when the layout resolves, so DisplayRouter.deviceContainerDidLayout() gets
    // a cache miss and calls ResizeLayer(), whose `scale` parameter overwrites
    // m_layerScaleX/Y with the correct dpi_scale - repairing this as a side effect.
    // Single Screen's container never changes size, the size-equality early-return in
    // deviceContainerDidLayout() suppresses every later call, and nothing ever repairs
    // it. That is also why four attempts at rewriting the SwiftUI layout could not fix
    // this: the SwiftUI shape was never wrong (it is character-for-character MeloCafe's
    // own EmulationView.screens), and a fifth attempt that set contentsScale inside
    // CemuUIKit_UpdateMainWindowSize failed because that function is exactly the one
    // that stops being called after boot in this layout.
    //
    // Resize() below already takes the scale as a parameter rather than reading it back
    // off the layer, for the reason its own comment gives: one source of truth instead
    // of two that could disagree. This constructor was the second source it failed to
    // eliminate. Both now read the same value the bridge already wrote.
    const auto& windowSystemInfo = WindowSystem::GetWindowInfo();
    const double authoritativeScale = mainWindow ? windowSystemInfo.dpi_scale.load()
                                                 : windowSystemInfo.pad_dpi_scale.load();
    // Falls back to whatever CreateMetalLayer() seeded (the screen's scale) if the window
    // system has not been told a scale yet - a pad surface can in principle initialize
    // before its first CemuUIKit_UpdatePadWindowSize(), and a zero here would mean a
    // zero-sized drawable, which is strictly worse than the behaviour this replaces.
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
