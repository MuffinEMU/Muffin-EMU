#include "Cafe/HW/Latte/Renderer/Metal/MetalLayerHandle.h"
#include "Cafe/HW/Latte/Core/Latte.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalLayer.h"

#include "gui/interface/WindowSystem.h"

MetalLayerHandle::MetalLayerHandle(MTL::Device* device, const Vector2i& size, bool mainWindow)
{
    const auto& windowInfo = (mainWindow ? WindowSystem::GetWindowInfo().window_main : WindowSystem::GetWindowInfo().window_pad);

    m_device = device;
    m_isMainWindow = mainWindow;
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
    m_lastGoodWidth = (double)size.x * m_layerScaleX;
    m_lastGoodHeight = (double)size.y * m_layerScaleY;
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
      m_drawable(other.m_drawable), m_device(other.m_device), m_isMainWindow(other.m_isMainWindow),
      m_lastGoodWidth(other.m_lastGoodWidth), m_lastGoodHeight(other.m_lastGoodHeight), m_acquireCount(other.m_acquireCount)
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
    m_device = other.m_device;
    m_isMainWindow = other.m_isMainWindow;
    m_lastGoodWidth = other.m_lastGoodWidth;
    m_lastGoodHeight = other.m_lastGoodHeight;
    m_acquireCount = other.m_acquireCount;
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
    const double width = (double)size.x * m_layerScaleX;
    const double height = (double)size.y * m_layerScaleY;
    // A layer with a zero-sized drawable hands out no drawables at all, so a transient zero-sized
    // layout (a view being rebuilt, a container that has not been measured yet) must not be applied.
    if (width < 1.0 || height < 1.0)
    {
        cemuLog_log(LogType::Force, "layer {} ignoring a degenerate resize to {}x{}", (void*)this, width, height);
        return;
    }
    m_layer->setDrawableSize(CGSize{width, height});
    m_lastGoodWidth = width;
    m_lastGoodHeight = height;
}

void MetalLayerHandle::RecordLayerState() const
{
    if (!m_isMainWindow || !m_layer)
        return;
    auto& state = LatteWait::Get();
    const CGSize drawableSize = m_layer->drawableSize();
    state.tvDrawableWidth.store((uint32_t)drawableSize.width, std::memory_order_relaxed);
    state.tvDrawableHeight.store((uint32_t)drawableSize.height, std::memory_order_relaxed);
    state.tvLayerHasDevice.store(m_layer->device() != nullptr, std::memory_order_relaxed);
}

// Puts back what the layer needs to hand out drawables, if something took it away.
void MetalLayerHandle::RepairLayer()
{
    if (m_device && m_layer->device() != m_device)
    {
        cemuLog_log(LogType::Force, "layer {} lost its Metal device, setting it again", (void*)this);
        m_layer->setDevice(m_device);
    }
    const CGSize drawableSize = m_layer->drawableSize();
    if ((drawableSize.width < 1.0 || drawableSize.height < 1.0) && m_lastGoodWidth >= 1.0 && m_lastGoodHeight >= 1.0)
    {
        cemuLog_log(LogType::Force, "layer {} has a {}x{} drawable, restoring {}x{}", (void*)this, drawableSize.width, drawableSize.height, m_lastGoodWidth, m_lastGoodHeight);
        m_layer->setDrawableSize(CGSize{m_lastGoodWidth, m_lastGoodHeight});
    }
}

bool MetalLayerHandle::AcquireDrawable()
{
    if (m_drawable)
        return true;

    // nextDrawable() returns an autoreleased object; retain it until PresentDrawable() or the destructor releases it.
    // It can block (up to a second) when every drawable is still in use, so it leaves a breadcrumb.
    {
        LatteWait::Scope waitScope("waiting for a screen drawable", LatteWait::Kind::Display);
        m_drawable = m_layer->nextDrawable();
    }
    if (!m_drawable)
    {
        auto& state = LatteWait::Get();
        if (m_isMainWindow)
        {
            state.drawableFailures.fetch_add(1, std::memory_order_relaxed);
            const uint32_t inARow = state.drawableFailuresInARow.fetch_add(1, std::memory_order_relaxed) + 1;
            RecordLayerState();
            // Log the first failure and then every 120th, so a dead layer cannot flood the log at frame rate.
            if (inARow == 1 || inARow % 120 == 0)
            {
                const CGSize drawableSize = m_layer->drawableSize();
                cemuLog_log(LogType::Force, "layer {} failed to acquire next drawable ({} in a row), drawable size {}x{}, device {}", (void*)this, inARow, drawableSize.width, drawableSize.height, m_layer->device() ? "set" : "MISSING");
            }
            if (inARow == 3)
                RepairLayer();
        }
        else
        {
            cemuLog_log(LogType::Force, "layer {} failed to acquire next drawable", (void*)this);
        }
        return false;
    }
    m_drawable->retain();
    if (m_isMainWindow)
    {
        LatteWait::Get().drawableFailuresInARow.store(0, std::memory_order_relaxed);
        LatteWait::Get().tvDrawableHeld.store(true, std::memory_order_relaxed);
        if ((m_acquireCount++ % 120) == 0)
            RecordLayerState();
    }

    return true;
}

void MetalLayerHandle::PresentDrawable(MTL::CommandBuffer* commandBuffer)
{
    // Full speed renders: keep each frame on screen for at least the game's own frame interval,
    // the GX2 swap interval in 60 Hz vsyncs (1 = 60 fps, 2 = 30 fps), so frames arrive evenly and
    // never faster than on the console. 1.5 ms under the exact interval so a frame that is on time
    // is not pushed a whole refresh later (on a 60 Hz panel 16.7 ms would otherwise become 33.3).
    // Swap interval 0 means the game asked for no vsync: present at once, as before.
    const uint32 swapInterval = LatteGPUState.sharedArea ? LatteGPUState.sharedArea->swapInterval : 0;
    if (g_latteFullSpeedRenders.load(std::memory_order_relaxed) && swapInterval > 0 && swapInterval <= 4)
        commandBuffer->presentDrawableAfterMinimumDuration(m_drawable, (double)swapInterval / 60.0 - 0.0015);
    else
        commandBuffer->presentDrawable(m_drawable);
    m_drawable->release();
    m_drawable = nullptr;
    if (m_isMainWindow)
    {
        LatteWait::Get().tvDrawableHeld.store(false, std::memory_order_relaxed);
        LatteWait::Get().presentedFrames.fetch_add(1, std::memory_order_relaxed);
    }
}
