#import "../interface/WindowSystem.h"
#include "Cafe/HW/Latte/Core/Latte.h"
#ifdef ENABLE_METAL
#include "Cafe/HW/Latte/Renderer/Metal/MetalRenderer.h"
#endif
#ifdef ENABLE_VULKAN
#include "Cafe/HW/Latte/Renderer/Vulkan/VulkanRenderer.h"
#endif
#include "input/InputManager.h"
#import <UIKit/UIKit.h>
#include "NativeKeyboard.h"

using namespace WindowSystem;

namespace WindowSystem {

static WindowInfo g_windowInfo;

static UIWindow* g_mainWindow = nil;
static UIView* g_mainView = nil;
static UIView* g_padView = nil;

static bool metal = false;

typedef void (*GameLoadedCallback)();
typedef void (*GameExitCallback)();

static GameLoadedCallback g_onGameLoaded = nullptr;
static GameExitCallback g_onGameExit = nullptr;

WindowInfo& GetWindowInfo()
{
    return g_windowInfo;
}

void Create()
{
}

void GetWindowSize(int& w, int& h)
{
    w = g_windowInfo.width;
    h = g_windowInfo.height;
}

void GetPadWindowSize(int& w, int& h)
{
    if (g_windowInfo.pad_open)
    {
        w = g_windowInfo.pad_width;
        h = g_windowInfo.pad_height;
    }
    else
    {
        w = 0;
        h = 0;
    }
}

void GetWindowPhysSize(int& w, int& h)
{
    w = g_windowInfo.phys_width;
    h = g_windowInfo.phys_height;
}

void GetPadWindowPhysSize(int& w, int& h)
{
    if (g_windowInfo.pad_open)
    {
        w = g_windowInfo.phys_pad_width;
        h = g_windowInfo.phys_pad_height;
    }
    else
    {
        w = 0;
        h = 0;
    }
}

double GetWindowDPIScale()
{
    return g_windowInfo.dpi_scale;
}

double GetPadDPIScale()
{
    return g_windowInfo.pad_open ? g_windowInfo.pad_dpi_scale.load() : 1.0;
}

bool IsPadWindowOpen()
{
    return g_windowInfo.pad_open;
}

bool IsFullScreen()
{
    return true;
}

bool InputConfigWindowHasFocus()
{
    return false;
}

bool IsKeyDown(uint32 key)
{
    return g_windowInfo.get_keystate(key);
}

bool IsKeyDown(PlatformKeyCodes key)
{
    return g_windowInfo.get_keystate((uint32)key);
}

std::string GetKeyCodeName(uint32 key)
{
    return std::to_string(key);
}

void NotifyGameLoaded()
{
    if (g_onGameLoaded)
        g_onGameLoaded();
}

void NotifyGameExited()
{
    HideNativeKeyboard();
    if (g_onGameExit)
        g_onGameExit();
}

void RefreshGameList()
{
}

void UpdateWindowTitles(bool, bool, double)
{
}

void CaptureInput(const ControllerState&, const ControllerState&)
{
}



void ShowErrorDialog(std::string_view message,
                     std::string_view title,
                     std::optional<ErrorCategory>)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* msg = [NSString stringWithUTF8String:message.data()];
        NSString* ttl = [NSString stringWithUTF8String:title.data()];

        UIAlertController* alert =
        [UIAlertController alertControllerWithTitle:ttl
                                            message:msg
                                     preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction* ok =
        [UIAlertAction actionWithTitle:@"OK"
                                 style:UIAlertActionStyleDefault
                               handler:nil];

        [alert addAction:ok];

        [g_mainWindow.rootViewController
            presentViewController:alert
                         animated:YES
                       completion:nil];
    });
}

}

void ShowErrorDialog(std::string_view title,
                     std::string_view message,
                     void (^callback)(void))
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* msg = [NSString stringWithUTF8String:message.data()];
        NSString* ttl = [NSString stringWithUTF8String:title.data()];

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:msg
                                                                       message:ttl
                                                                preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * _Nonnull action) {
            if (callback) {
                callback();
            }
        }];

        [alert addAction:okAction];
        [g_mainWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}


extern "C" void CemuUIKit_UpdatePadWindowSize();

extern "C" {

void CemuUIKit_SetMainWindow(UIWindow* window)
{
    g_mainWindow = window;
}

void CemuUIKit_SetMetal(bool metals)
{
    WindowSystem::metal = metals;
}

void CemuUIKit_SetMainView(UIView* view)
{
    g_mainView = view;

    // Use the screen's native scale instead of hardcoding 1.0
    CAMetalLayer* metalLayer = (CAMetalLayer*)view.layer;
    metalLayer.contentsScale = view.window
        ? view.window.screen.nativeScale
        : UIScreen.mainScreen.nativeScale;

    WindowHandleInfo info { WindowHandleInfo::Backend::UIKit, view,
                            (__bridge_retained CAMetalLayer*)view.layer };
    g_windowInfo.window_main = info;
    g_windowInfo.canvas_main = info;
}

void CemuUIKit_InitializeLayer(bool main)
{
    UIView* view = main ? g_mainView : g_padView;
    if (!view)
        return;

    if (metal) {
#ifdef ENABLE_METAL
        auto metal_renderer = MetalRenderer::GetInstance();
        metal_renderer->InitializeLayer({
            static_cast<int>(view.bounds.size.width),
            static_cast<int>(view.bounds.size.height)
        }, main);
#else
        cemu_assert_debug(false);
#endif
    } else {
#ifdef ENABLE_VULKAN
        auto vk_renderer = VulkanRenderer::GetInstance();
        vk_renderer->InitializeSurface({
            static_cast<int>(view.bounds.size.width),
            static_cast<int>(view.bounds.size.height)
        }, main);
#else
        cemu_assert_debug(false);
#endif
    }

    if (!main) {
        g_windowInfo.pad_open = true;
        CemuUIKit_UpdatePadWindowSize();
    }
}

void CemuUIKit_ShutdownLayer(bool main) {
    if (metal) {
#ifdef ENABLE_METAL
        auto metal_renderer = MetalRenderer::GetInstance();
        metal_renderer->ShutdownLayer(main);
#else
        cemu_assert_debug(false);
#endif
    } else {
#ifdef ENABLE_VULKAN
        auto vk_renderer = VulkanRenderer::GetInstance();
        if (!main)
            vk_renderer->StopUsingPadAndWait();
#else
        cemu_assert_debug(false);
#endif
    }

    if (!main)
        g_windowInfo.pad_open = false;
}

void CemuUIKit_UpdateMainWindowSize(CGFloat width, CGFloat height, CGFloat scale)
{
    auto update = ^{
        CGFloat resolvedScale = (scale == 0) ? UIScreen.mainScreen.nativeScale : scale;

        g_windowInfo.width = width;
        g_windowInfo.height = height;
        g_windowInfo.phys_width  = width  * resolvedScale;
        g_windowInfo.phys_height = height * resolvedScale;
        g_windowInfo.dpi_scale   = resolvedScale;

        // This is the ONLY thing on iOS that keeps the Metal CAMetalLayer's own
        // drawableSize in step with the window it actually sits in. MetalRenderer::
        // ResizeLayer() exists and does exactly this, but its only other caller is the
        // desktop wxWidgets canvas (MetalCanvas.cpp) - nothing on iOS ever called it, so
        // the drawable stayed exactly the size it was the one time InitializeLayer() ran
        // (at boot, or whenever this window's surface was first registered) no matter
        // how many times the container view was resized after that. A screen-layout
        // switch to Single Screen updates g_windowInfo's width/height above (which is
        // what the aspect-fit letterbox math in LatteRenderTarget_getScreenImageArea
        // reads), but without this call the actual rendered image stayed pinned to
        // whatever tiny size the drawable was first created at, centered inside the new,
        // correctly-sized-but-otherwise-unrelated canvas - a small, correctly
        // proportioned picture surrounded by black, not a crash or a hang, which is
        // exactly what made it easy to mistake for a SwiftUI layout bug instead. Vulkan
        // does not need the equivalent call: MoltenVK reads the CAMetalLayer's own
        // drawableSize itself when it rebuilds the swapchain on the next present, rather
        // than caching a copy of it the way MetalLayerHandle does.
#ifdef ENABLE_METAL
        if (metal)
        {
            if (auto* metalRenderer = MetalRenderer::GetInstance())
                metalRenderer->ResizeLayer({(int)width, (int)height}, true);
        }
#endif
    };

    if ([NSThread isMainThread])
        update();
    else
        dispatch_sync(dispatch_get_main_queue(), update);
}

void CemuUIKit_SetPadView(UIView* view)
{
    g_padView = view;

    WindowHandleInfo info { WindowHandleInfo::Backend::UIKit, view, (__bridge_retained CAMetalLayer*)view.layer };

    g_windowInfo.window_pad = info;
    g_windowInfo.canvas_pad = info;

    g_windowInfo.pad_open = false;
}

void CemuUIKit_UpdatePadWindowSize()
{
    if (!g_padView)
        return;

    auto update = ^{
        CGSize size = g_padView.bounds.size;
        CAMetalLayer* layer = (CAMetalLayer*)g_padView.layer;
        CGFloat scale = layer.contentsScale;

        // Same gap as CemuUIKit_UpdateMainWindowSize(), and it matters here too even
        // though this reads layer.drawableSize back directly rather than caching a copy
        // the way MetalLayerHandle does: drawableSize is a plain property, not something
        // CAMetalLayer keeps in sync with bounds on its own, so without this call it
        // just keeps reporting whatever it was set to at the one point something last
        // called ResizeLayer()/InitializeLayer() for this window - which, on iOS,
        // before this fix, was never after the very first registration.
#ifdef ENABLE_METAL
        if (metal)
        {
            if (auto* metalRenderer = MetalRenderer::GetInstance())
                metalRenderer->ResizeLayer({(int)size.width, (int)size.height}, false);
        }
#endif

        g_windowInfo.pad_width = size.width;
        g_windowInfo.pad_height = size.height;

        g_windowInfo.phys_pad_width = layer.drawableSize.width;
        g_windowInfo.phys_pad_height = layer.drawableSize.height;

        g_windowInfo.pad_dpi_scale = scale;
    };

    if ([NSThread isMainThread])
        update();
    else
        dispatch_sync(dispatch_get_main_queue(), update);
}

void CemuUIKit_SetPadTouch(CGFloat x, CGFloat y, bool down)
{
    auto& input = InputManager::instance();
    std::scoped_lock lock(input.m_pad_touch.m_mutex);
    input.m_pad_touch.position = { (int)x, (int)y };
    input.m_pad_touch.left_down = down;
    if (down)
        input.m_pad_touch.left_down_toggle = true;
}

void CemuUIKit_SetGameLoadedCallback(void (*callback)())
{
    g_onGameLoaded = callback;
}

void CemuUIKit_SetVisibleOutputs(bool tv, bool pad)
{
    g_windowInfo.visible_outputs.store((tv ? 1u : 0u) | (pad ? 2u : 0u));
}

void CemuUIKit_SetDRCPrimary(bool enabled)
{
    LatteGPUState.isDRCPrimary = enabled;
}

void CemuUIKit_SetGameExitCallback(void (*callback)())
{
    g_onGameExit = callback;
}

}
