#include "../interface/WindowSystem.h"
#include "Cafe/HW/Latte/Core/Latte.h"
#include "config/ActiveSettings.h"
#include "config/NetworkSettings.h"
#include "config/CemuConfig.h"
#include "Cafe/HW/Latte/Renderer/Renderer.h"
#include "Cafe/CafeSystem.h"

WindowSystem::WindowInfo g_window_info{};

std::shared_mutex g_mutex;

void WindowSystem::Create()
{
}

// There is no modal dialog to show here, but discarding the message outright - which
// is what this did - loses the only explanation the engine ever produces for several
// paths that then kill the process outright:
//
//   MMU.cpp memory_init()        -> "Unable to reserve 4GB of memory"    -> exit(-1)
//   MMU.cpp MMURange::mapMem()   -> "Unable to allocate {} memory"       -> exit(-1)
//   CafeSystem.cpp LoadMainExecutable() -> damaged executable            -> exit(0)
//   KeyCache.cpp                 -> keys.txt unreadable/uncreatable      -> continues
//
// exit() is not a signal, so CemuBridge.mm's signal handler never fires and
// CemuCrashLog.txt stays empty; iOS reports it as a normal termination. The symptom
// on device is the app simply vanishing with no crash report and no log line - which
// is indistinguishable from the several other ways boot can currently fail, and is
// exactly the class of failure the first three of those are plausible candidates for
// on a memory-constrained sideloaded process. Log it instead, at LogType::Force so it
// is never filtered out, and flush synchronously: every caller above is either about
// to exit or has just failed at something load-bearing, so there may be no later
// opportunity for the writer thread to drain the cache to disk.
void WindowSystem::ShowErrorDialog(std::string_view message, std::string_view title, std::optional<WindowSystem::ErrorCategory> /*errorId*/)
{
	if (title.empty())
		cemuLog_log(LogType::Force, "[error] {}", message);
	else
		cemuLog_log(LogType::Force, "[error] {}: {}", title, message);
	cemuLog_waitForFlush();
}

WindowSystem::WindowInfo& WindowSystem::GetWindowInfo()
{
	return g_window_info;
}

// There is no window title to update on iOS, but this is the engine's only
// push of a real, measured frame rate to the UI layer: LattePerformanceMonitor
// (LattePerformanceMonitor.cpp:114) calls it roughly once a second with the fps it
// just computed. Keep the last value so cemu_bridge_get_fps() can hand it to the
// Swift HUD, which previously had a hardcoded 0 to display.
static std::atomic<double> s_ios_last_fps{0.0};

void WindowSystem::UpdateWindowTitles(bool isIdle, bool isLoading, double fps)
{
	// isIdle/isLoading both mean "not producing frames right now" - report 0 rather
	// than leaving the last real reading on screen while nothing is being rendered.
	s_ios_last_fps.store((isIdle || isLoading) ? 0.0 : fps);
}

// Declared in CemuBridge.mm (the only caller); no header of its own, matching the
// rest of this platform shim.
double IOSWindowSystem_GetLastFPS()
{
	return s_ios_last_fps.load();
}

void WindowSystem::GetWindowSize(int& w, int& h)
{
	w = g_window_info.width;
	h = g_window_info.height;
}

void WindowSystem::GetPadWindowSize(int& w, int& h)
{
	if (g_window_info.pad_open)
	{
		w = g_window_info.pad_width;
		h = g_window_info.pad_height;
	}
	else
	{
		w = 0;
		h = 0;
	}
}

void WindowSystem::GetWindowPhysSize(int& w, int& h)
{
	w = g_window_info.phys_width;
	h = g_window_info.phys_height;
}

void WindowSystem::GetPadWindowPhysSize(int& w, int& h)
{
	if (g_window_info.pad_open)
	{
		w = g_window_info.phys_pad_width;
		h = g_window_info.phys_pad_height;
	}
	else
	{
		w = 0;
		h = 0;
	}
}

double WindowSystem::GetWindowDPIScale()
{
	return g_window_info.dpi_scale;
}

double WindowSystem::GetPadDPIScale()
{
	return g_window_info.pad_open ? g_window_info.pad_dpi_scale.load() : 1.0;
}

bool WindowSystem::IsPadWindowOpen()
{
	return g_window_info.pad_open;
}

bool WindowSystem::IsKeyDown(uint32 key)
{
	return g_window_info.get_keystate(key);
}

bool WindowSystem::IsKeyDown(PlatformKeyCodes platformKey)
{
	return g_window_info.get_keystate(static_cast<uint32>(platformKey));
}

std::string WindowSystem::GetKeyCodeName(uint32 button)
{
	return fmt::format("key_{}", button);
}

bool WindowSystem::InputConfigWindowHasFocus()
{
	return false;
}

void WindowSystem::NotifyGameLoaded()
{
}

void WindowSystem::NotifyGameExited()
{
}

void WindowSystem::RefreshGameList()
{
}

void WindowSystem::CaptureInput(const ControllerState& currentState, const ControllerState& lastState)
{
}

bool WindowSystem::IsFullScreen()
{
	return true;
}
