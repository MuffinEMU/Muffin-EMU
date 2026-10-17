// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// The Android window system: the same role src/gui/uikit/WindowSystem.mm plays on iOS. The app owns one
// SurfaceView; its ANativeWindow is the core's main surface and the Vulkan renderer builds its swapchain
// on it (VulkanRenderer::CreateAndroidSurface). There is no separate GamePad window: the app shows either
// Wii U screen in the one surface (output_sources), as the iOS app does in Single Screen.

#include "gui/interface/WindowSystem.h"
#include "Cafe/HW/Latte/Core/Latte.h"
#ifdef ENABLE_VULKAN
#include "Cafe/HW/Latte/Renderer/Vulkan/VulkanRenderer.h"
#endif
#include "input/InputManager.h"

#include <android/log.h>
#include <android/native_window.h>

#include <mutex>
#include <string>

namespace WindowSystem
{
static WindowInfo g_windowInfo;
static ANativeWindow* g_mainWindow = nullptr;

typedef void (*GameLoadedCallback)();
typedef void (*GameExitCallback)();
typedef void (*ErrorDialogCallback)(const char* title, const char* message);

static GameLoadedCallback g_onGameLoaded = nullptr;
static GameExitCallback g_onGameExit = nullptr;
static ErrorDialogCallback g_onErrorDialog = nullptr;

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
	w = 0;
	h = 0;
}

void GetWindowPhysSize(int& w, int& h)
{
	w = g_windowInfo.phys_width;
	h = g_windowInfo.phys_height;
}

void GetPadWindowPhysSize(int& w, int& h)
{
	w = 0;
	h = 0;
}

double GetWindowDPIScale()
{
	return g_windowInfo.dpi_scale;
}

double GetPadDPIScale()
{
	return 1.0;
}

bool IsPadWindowOpen()
{
	return false;
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

// The core calls this from worker threads (guest memory setup, the title loader) and some callers exit the
// process the moment it returns. The message goes to logcat and to the app, which shows it; nothing waits
// on the player here, since an Android dialog cannot block a native thread the way a UIKit alert is made to.
void ShowErrorDialog(std::string_view message, std::string_view title, std::optional<ErrorCategory>)
{
	const std::string titleCopy(title.empty() ? std::string_view("MuffinEMU") : title);
	const std::string messageCopy(message);
	__android_log_print(ANDROID_LOG_ERROR, "MuffinEMU", "%s: %s", titleCopy.c_str(), messageCopy.c_str());
	if (g_onErrorDialog)
		g_onErrorDialog(titleCopy.c_str(), messageCopy.c_str());
}
} // namespace WindowSystem

using namespace WindowSystem;

extern "C" {

// The app's surface. width/height are in density-independent points, like the iOS view's bounds; scale is
// the pixel density the surface is drawn at (the app's render scale setting times the display density).
void CemuAndroid_SetMainWindow(ANativeWindow* window, int width, int height, double scale)
{
	if (g_mainWindow && g_mainWindow != window)
		ANativeWindow_release(g_mainWindow);
	if (window && window != g_mainWindow)
		ANativeWindow_acquire(window);
	g_mainWindow = window;

	WindowHandleInfo info{WindowHandleInfo::Backend::Android, nullptr, window};
	g_windowInfo.window_main = info;
	g_windowInfo.canvas_main = info;
	g_windowInfo.pad_open = false;
	if (scale <= 0.0)
		scale = 1.0;
	g_windowInfo.width = width;
	g_windowInfo.height = height;
	g_windowInfo.phys_width = (int)(width * scale);
	g_windowInfo.phys_height = (int)(height * scale);
	g_windowInfo.dpi_scale = scale;
	g_windowInfo.visible_outputs.store(window ? 1u : 0u);
}

void CemuAndroid_UpdateMainWindowSize(int width, int height, double scale)
{
	if (scale <= 0.0)
		scale = g_windowInfo.dpi_scale.load() > 0.0 ? g_windowInfo.dpi_scale.load() : 1.0;
	g_windowInfo.width = width;
	g_windowInfo.height = height;
	g_windowInfo.phys_width = (int)(width * scale);
	g_windowInfo.phys_height = (int)(height * scale);
	g_windowInfo.dpi_scale = scale;
}

ANativeWindow* CemuAndroid_GetMainWindow()
{
	return g_mainWindow;
}

// Which Wii U screen the one surface shows: false = TV, true = GamePad.
void CemuAndroid_SetShowsGamePad(bool gamePad)
{
	g_windowInfo.output_sources.store(gamePad ? 1u : 0u);
}

void CemuAndroid_SetVisibleOutputs(bool tv)
{
	g_windowInfo.visible_outputs.store(tv ? 1u : 0u);
}

void CemuAndroid_SetPadTouch(float x, float y, bool down)
{
	auto& input = InputManager::instance();
	std::scoped_lock lock(input.m_pad_touch.m_mutex);
	input.m_pad_touch.position = {(int)x, (int)y};
	input.m_pad_touch.left_down = down;
	if (down)
		input.m_pad_touch.left_down_toggle = true;
}

void CemuAndroid_SetGameLoadedCallback(void (*callback)())
{
	g_onGameLoaded = callback;
}

void CemuAndroid_SetGameExitCallback(void (*callback)())
{
	g_onGameExit = callback;
}

void CemuAndroid_SetErrorDialogCallback(void (*callback)(const char*, const char*))
{
	g_onErrorDialog = callback;
}

// The two entry points main.cpp's CemuPrepareRenderer() calls on every platform with a headless core
// (named after the iOS window system, where they began). Android has Vulkan only, and one surface.
void CemuUIKit_SetMetal(bool)
{
}

void CemuUIKit_InitializeLayer(bool main)
{
	if (!main)
		return; // no GamePad window on Android
#ifdef ENABLE_VULKAN
	auto* renderer = VulkanRenderer::GetInstance();
	if (!renderer || !g_mainWindow)
		return;
	renderer->InitializeSurface({g_windowInfo.phys_width.load(), g_windowInfo.phys_height.load()}, true);
#endif
}

} // extern "C"
