// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU for Android: what the Kotlin app calls, and what the core calls back. The iOS bridge
// (src/ios/Bridge/CemuBridge.mm) is the model; this is the part of it a first Android build needs:
// initialize the core, hand it the surface, boot a title, feed it the on-screen pad and a physical
// controller, pause and stop. The title-launch, pause and CafeSystem host code is shared with iOS
// (src/ios/Bridge/Core), compiled into libCemu.so next to this file.

#include "AndroidBridge.h"

#include "Cafe/CafeSystem.h"
#include "Cafe/HW/Latte/Core/Latte.h"
#include "Cafe/HW/Latte/Renderer/Renderer.h"
#include "Cafe/Filesystem/FST/KeyCache.h"
#include "Cemu/Logging/CemuLogging.h"
#include "config/ActiveSettings.h"
#include "config/CemuConfig.h"
#include "input/InputManager.h"
#include "input/api/ControllerState.h"
#include "input/api/iOS/GCControllerProvider.h"
#include "input/emulated/EmulatedController.h"

#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>

#include <atomic>
#include <cmath>
#include <deque>
#include <mutex>
#include <string>

// src/gui/android/WindowSystem.cpp
extern "C" {
void CemuAndroid_SetMainWindow(ANativeWindow* window, int width, int height, double scale);
void CemuAndroid_UpdateMainWindowSize(int width, int height, double scale);
ANativeWindow* CemuAndroid_GetMainWindow();
void CemuAndroid_SetShowsGamePad(bool gamePad);
void CemuAndroid_SetVisibleOutputs(bool tv);
void CemuAndroid_SetPadTouch(float x, float y, bool down);
void CemuAndroid_SetGameLoadedCallback(void (*callback)());
void CemuAndroid_SetGameExitCallback(void (*callback)());
void CemuAndroid_SetErrorDialogCallback(void (*callback)(const char*, const char*));
void CemuUIKit_InitializeLayer(bool main);
// src/main.cpp
void CemuInitialize(const char* execPath, const char* user_data_path, const char* config_path, const char* cache_path, const char* data_path);
void CemuRun();
void CemuPrepareRenderer();
void CemuShutdown();
// src/input/api/iOS/GCControllerProvider.mm
void* GCControllerBridge_add(const GCBridgeControllerDesc* desc);
void GCControllerBridge_notifyChanged(void);
}

// src/ios/Bridge/Core
int IOSTitleLaunch_PrepareForegroundTitle(const char* pathStr);
const char* IOSTitleLaunch_LastErrorDetail();
int IOSTitleLaunch_ReloadAndCountKeys();
void IOSSystemImplementation_Install();
bool IOSSystemImplementation_TitleExited(int* statusOut);
void IOSSystemImplementation_ReportFatal(const char* reason);
const char* IOSSystemImplementation_FatalReason();
void IOSSystemImplementation_ResetExit();
bool IOSTitlePause_Pause();
bool IOSTitlePause_Resume();
bool IOSTitlePause_IsPaused();
void IOSTitlePause_Forget();

#define ALOG(...) __android_log_print(ANDROID_LOG_INFO, "MuffinEMU", __VA_ARGS__)
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, "MuffinEMU", __VA_ARGS__)

namespace
{
std::atomic<bool> g_initialized{false};
std::atomic<bool> g_titleRunning{false};

std::mutex g_statusMutex;
std::string g_status = "Core not initialized.";
std::deque<std::string> g_messages; // error dialogs the core asked for, for the app to show

void setStatus(const std::string& text)
{
	std::lock_guard lock(g_statusMutex);
	g_status = text;
	ALOG("%s", text.c_str());
}

void onErrorDialog(const char* title, const char* message)
{
	std::lock_guard lock(g_statusMutex);
	g_messages.push_back(std::string(title) + "\n" + message);
	if (g_messages.size() > 16)
		g_messages.pop_front();
}

void onGameExited()
{
	g_titleRunning.store(false);
	setStatus("The game ended.");
}

// ---------------------------------------------------------------------------
// Input. One emulated GamePad, fed by the on-screen pad and a physical controller the app reads through
// Android's input events. The core polls through the GameController provider's callback table.
constexpr int kBitA = 0, kBitB = 1, kBitX = 2, kBitY = 3, kBitL = 4, kBitR = 5, kBitZL = 6, kBitZR = 7,
	kBitMinus = 8, kBitPlus = 9, kBitStickL = 10, kBitStickR = 11;

int buttonBit(int button)
{
	switch (button)
	{
	case ANDROID_PAD_A: return kBitA;
	case ANDROID_PAD_B: return kBitB;
	case ANDROID_PAD_X: return kBitX;
	case ANDROID_PAD_Y: return kBitY;
	case ANDROID_PAD_L: return kBitL;
	case ANDROID_PAD_R: return kBitR;
	case ANDROID_PAD_ZL: return kBitZL;
	case ANDROID_PAD_ZR: return kBitZR;
	case ANDROID_PAD_MINUS: return kBitMinus;
	case ANDROID_PAD_PLUS: return kBitPlus;
	case ANDROID_PAD_STICK_L: return kBitStickL;
	case ANDROID_PAD_STICK_R: return kBitStickR;
	case ANDROID_PAD_UP: return kButtonUp;
	case ANDROID_PAD_DOWN: return kButtonDown;
	case ANDROID_PAD_LEFT: return kButtonLeft;
	case ANDROID_PAD_RIGHT: return kButtonRight;
	default: return -1;
	}
}

std::mutex g_inputMutex;
uint32_t g_touchButtons = 0;
uint32_t g_physicalButtons = 0;
GCBridgeVec2 g_touchSticks[2]{};
GCBridgeVec2 g_physicalSticks[2]{};
float g_physicalTriggers[2]{};
void* g_inputHandle = nullptr;

GCBridgeControllerState pollState(void*)
{
	std::lock_guard lock(g_inputMutex);
	GCBridgeControllerState s{};
	s.buttons = g_touchButtons | g_physicalButtons;
	for (int i = 0; i < 2; i++)
	{
		const GCBridgeVec2& touch = g_touchSticks[i];
		(i == 0 ? s.leftStick : s.rightStick) = (touch.x != 0.0f || touch.y != 0.0f) ? touch : g_physicalSticks[i];
	}
	s.leftTrigger = std::max(g_physicalTriggers[0], (s.buttons & (1u << kBitZL)) ? 1.0f : 0.0f);
	s.rightTrigger = std::max(g_physicalTriggers[1], (s.buttons & (1u << kBitZR)) ? 1.0f : 0.0f);
	return s;
}

GCBridgeMotionState pollMotion(void*)
{
	return GCBridgeMotionState{}; // no motion yet: the device's sensors come in a later step
}

void inputStart()
{
	if (g_inputHandle)
		return;
	GCBridgeControllerDesc desc{};
	desc.display_name = "Muffin GamePad";
	desc.controllerType = (uint8)EmulatedController::Type::VPAD;
	desc.poll_state = pollState;
	desc.poll_motion = pollMotion;
	g_inputHandle = GCControllerBridge_add(&desc);
	if (!g_inputHandle)
	{
		ALOGE("input: the core's GameController provider refused the GamePad; no input will reach titles");
		return;
	}
	GCControllerBridge_notifyChanged();
	ALOG("input: GamePad registered with the core");
}

std::string jstringToUtf8(JNIEnv* env, jstring s)
{
	if (!s)
		return {};
	const char* chars = env->GetStringUTFChars(s, nullptr);
	std::string out = chars ? chars : "";
	if (chars)
		env->ReleaseStringUTFChars(s, chars);
	return out;
}
} // namespace

// Called by the shared CafeSystem host implementation (IOSSystemImplementation.cpp) on a Wii U Menu title switch.
bool IOSBridge_RecreateRenderSurface()
{
	try
	{
		CemuPrepareRenderer();
		return true;
	}
	catch (const std::exception& ex)
	{
		ALOGE("title switch: the renderer could not be rebuilt: %s", ex.what());
		return false;
	}
}

void IOSBridge_TitleSwitching(uint64 titleId)
{
	ALOG("title switch to %016llx", (unsigned long long)titleId);
}

extern "C" {

JNIEXPORT jint JNI_OnLoad(JavaVM*, void*)
{
	return JNI_VERSION_1_6;
}

// initialize(userDataDir, dataDir): userDataDir holds mlc, config, caches and keys.txt (the app's own files
// directory, or its external files directory so the player can reach it); dataDir holds the read-only
// CemuData the app unpacks from its assets (shared fonts, game profiles).
JNIEXPORT jboolean JNICALL Java_io_github_muffinemu_NativeBridge_initialize(JNIEnv* env, jclass, jstring jUserData, jstring jData)
{
	if (g_initialized.exchange(true))
		return JNI_TRUE;
	const std::string userData = jstringToUtf8(env, jUserData);
	const std::string data = jstringToUtf8(env, jData);
	std::error_code ec;
	fs::create_directories(fs::path(userData) / "cache", ec);
	const std::string cache = (fs::path(userData) / "cache").string();

	CemuAndroid_SetErrorDialogCallback(onErrorDialog);
	CemuAndroid_SetGameExitCallback(onGameExited);
	KeyCache_ResetForNewPaths();
	try
	{
		CemuInitialize("", userData.c_str(), userData.c_str(), cache.c_str(), data.c_str());
	}
	catch (const std::exception& ex)
	{
		setStatus(std::string("The emulator core failed to start: ") + ex.what());
		g_initialized.store(false);
		return JNI_FALSE;
	}
	catch (...)
	{
		setStatus("The emulator core failed to start.");
		g_initialized.store(false);
		return JNI_FALSE;
	}
	IOSSystemImplementation_Install();
	cemuLog_setActiveLoggingFlags(cemuLog_getFlag(LogType::CoreinitLogging) | cemuLog_getFlag(LogType::APIErrors));
	// Android allows JIT with no enabler, so the recompiler is the default; one host thread per emulated core.
	GetConfig().cpu_mode = CPUMode::MulticoreRecompiler;
	GetConfig().graphic_api = kVulkan;
	GetConfig().vsync = 1;
	GetConfig().async_compile = true;
	inputStart();
	setStatus("Core ready (no title running).");
	return JNI_TRUE;
}

JNIEXPORT void JNICALL Java_io_github_muffinemu_NativeBridge_setSurface(JNIEnv* env, jclass, jobject surface, jint width, jint height, jfloat scale)
{
	ANativeWindow* window = surface ? ANativeWindow_fromSurface(env, surface) : nullptr;
	CemuAndroid_SetMainWindow(window, width, height, scale);
	if (window)
		ANativeWindow_release(window); // the window system took its own reference
	// A surface that arrives while a title runs (the activity came back) gets a swapchain at once.
	if (window && g_titleRunning.load())
	{
		try
		{
			CemuUIKit_InitializeLayer(true);
		}
		catch (const std::exception& ex)
		{
			ALOGE("surface: could not be initialized: %s", ex.what());
		}
	}
}

JNIEXPORT void JNICALL Java_io_github_muffinemu_NativeBridge_resizeSurface(JNIEnv*, jclass, jint width, jint height, jfloat scale)
{
	CemuAndroid_UpdateMainWindowSize(width, height, scale);
}

JNIEXPORT void JNICALL Java_io_github_muffinemu_NativeBridge_setShowsGamePad(JNIEnv*, jclass, jboolean gamePad)
{
	CemuAndroid_SetShowsGamePad(gamePad == JNI_TRUE);
}

// Returns 0 when the title started; otherwise the launch status (IOSTitleLaunch.cpp's enum), with the
// reason in statusText().
JNIEXPORT jint JNICALL Java_io_github_muffinemu_NativeBridge_bootTitle(JNIEnv* env, jclass, jstring jPath)
{
	if (!g_initialized.load())
	{
		setStatus("The emulator core is not initialized.");
		return 100;
	}
	if (g_titleRunning.load())
	{
		setStatus("A game is already running.");
		return 101;
	}
	if (!CemuAndroid_GetMainWindow())
	{
		setStatus("No surface to draw into yet.");
		return 102;
	}
	const std::string path = jstringToUtf8(env, jPath);
	int prepared = 13;
	try
	{
		prepared = IOSTitleLaunch_PrepareForegroundTitle(path.c_str());
	}
	catch (const std::exception& ex)
	{
		ALOGE("boot: preparing the title threw: %s", ex.what());
		CafeSystem::AbortPreparedTitle();
	}
	catch (...)
	{
		CafeSystem::AbortPreparedTitle();
	}
	switch (prepared)
	{
	case 0: break;
	case 1: setStatus("Invalid RPX."); return prepared;
	case 2: setStatus("Unable to mount the title (bad path)."); return prepared;
	case 3: setStatus("This game is encrypted and no key in keys.txt opens it. Put the keys.txt you dumped from your own Wii U in MuffinEMU's folder, then try again."); return prepared;
	case 4: setStatus("This game folder is missing title.tik (the ticket), which MuffinEMU needs to decrypt it."); return prepared;
	case 6: setStatus("That looks like an update or DLC. Launch the base game instead."); return prepared;
	case 7: setStatus("This game folder's title.tmd couldn't be read."); return prepared;
	case 8: setStatus("This game folder's title.tik couldn't be read."); return prepared;
	case 9: setStatus("MuffinEMU couldn't decrypt this game folder with its title.tik."); return prepared;
	case 10: setStatus(std::string("This game folder is missing ") + IOSTitleLaunch_LastErrorDetail() + ", which title.tmd lists."); return prepared;
	case 11: setStatus("That system title isn't installed."); return prepared;
	case 13: setStatus("MuffinEMU hit an internal error while opening this game. Details are in log.txt."); return prepared;
	default: setStatus("Not a Wii U title this build can launch."); return prepared;
	}

	IOSSystemImplementation_ResetExit();
	IOSTitlePause_Forget();
	CemuAndroid_SetVisibleOutputs(true);
	try
	{
		CemuRun(); // builds the Vulkan renderer on the surface and starts the title thread
	}
	catch (const std::exception& ex)
	{
		ALOGE("boot: CemuRun() threw: %s", ex.what());
		CafeSystem::AbortPreparedTitle();
		g_renderer.reset();
		setStatus(std::string("The title failed to start: the graphics renderer could not be created. ") + ex.what());
		return 103;
	}
	catch (...)
	{
		CafeSystem::AbortPreparedTitle();
		g_renderer.reset();
		setStatus("The title failed to start: the graphics renderer could not be created.");
		return 103;
	}
	g_titleRunning.store(true);
	setStatus("Title running.");
	return 0;
}

JNIEXPORT void JNICALL Java_io_github_muffinemu_NativeBridge_stopTitle(JNIEnv*, jclass)
{
	if (!g_titleRunning.exchange(false))
		return;
	IOSTitlePause_Forget();
	try
	{
		CafeSystem::ShutdownTitle();
	}
	catch (const std::exception& ex)
	{
		ALOGE("stop: ShutdownTitle threw: %s", ex.what());
	}
	setStatus("Core ready (no title running).");
}

JNIEXPORT jboolean JNICALL Java_io_github_muffinemu_NativeBridge_setPaused(JNIEnv*, jclass, jboolean paused)
{
	if (!g_titleRunning.load())
		return JNI_FALSE;
	return (paused ? IOSTitlePause_Pause() : IOSTitlePause_Resume()) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL Java_io_github_muffinemu_NativeBridge_isTitleRunning(JNIEnv*, jclass)
{
	if (g_titleRunning.load() && !CafeSystem::IsTitleRunning())
		g_titleRunning.store(false);
	return g_titleRunning.load() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL Java_io_github_muffinemu_NativeBridge_statusText(JNIEnv* env, jclass)
{
	int exitStatus = 0;
	if (const char* fatal = IOSSystemImplementation_FatalReason())
		setStatus(fatal);
	else if (g_titleRunning.load() && IOSSystemImplementation_TitleExited(&exitStatus))
		setStatus("The game closed itself (exit status " + std::to_string(exitStatus) + ").");
	std::lock_guard lock(g_statusMutex);
	return env->NewStringUTF(g_status.c_str());
}

// The next message the core asked the player to see, or null.
JNIEXPORT jstring JNICALL Java_io_github_muffinemu_NativeBridge_pollMessage(JNIEnv* env, jclass)
{
	std::lock_guard lock(g_statusMutex);
	if (g_messages.empty())
		return nullptr;
	const std::string next = g_messages.front();
	g_messages.pop_front();
	return env->NewStringUTF(next.c_str());
}

JNIEXPORT jdouble JNICALL Java_io_github_muffinemu_NativeBridge_framesPerSecond(JNIEnv*, jclass)
{
	return (jdouble)LatteGPUState.frameCounter; // the app differences this per second
}

JNIEXPORT jint JNICALL Java_io_github_muffinemu_NativeBridge_reloadAndCountKeys(JNIEnv*, jclass)
{
	if (!g_initialized.load())
		return -1;
	return IOSTitleLaunch_ReloadAndCountKeys();
}

// On-screen pad
JNIEXPORT void JNICALL Java_io_github_muffinemu_NativeBridge_setButton(JNIEnv*, jclass, jint button, jboolean pressed)
{
	const int bit = buttonBit(button);
	if (bit < 0)
		return;
	std::lock_guard lock(g_inputMutex);
	if (pressed)
		g_touchButtons |= (1u << bit);
	else
		g_touchButtons &= ~(1u << bit);
}

JNIEXPORT void JNICALL Java_io_github_muffinemu_NativeBridge_setStick(JNIEnv*, jclass, jint stick, jfloat x, jfloat y)
{
	const float magnitude = std::sqrt(x * x + y * y);
	if (magnitude > 1.0f)
	{
		x /= magnitude;
		y /= magnitude;
	}
	if (std::isnan(x) || std::isnan(y))
		return;
	std::lock_guard lock(g_inputMutex);
	g_touchSticks[stick == 1 ? 1 : 0] = GCBridgeVec2{x, y};
}

JNIEXPORT void JNICALL Java_io_github_muffinemu_NativeBridge_setPadTouch(JNIEnv*, jclass, jfloat x, jfloat y, jboolean down)
{
	CemuAndroid_SetPadTouch(x, y, down == JNI_TRUE);
}

// A physical controller, as the app reads it: a full snapshot each time anything changes.
JNIEXPORT void JNICALL Java_io_github_muffinemu_NativeBridge_setPhysicalState(JNIEnv*, jclass, jint buttons, jfloat lx, jfloat ly, jfloat rx, jfloat ry, jfloat lt, jfloat rt)
{
	uint32_t bits = 0;
	for (int b = 0; b < ANDROID_PAD_COUNT; b++)
	{
		if (!(buttons & (1 << b)))
			continue;
		const int bit = buttonBit(b);
		if (bit >= 0)
			bits |= (1u << bit);
	}
	std::lock_guard lock(g_inputMutex);
	g_physicalButtons = bits;
	g_physicalSticks[0] = GCBridgeVec2{lx, ly};
	g_physicalSticks[1] = GCBridgeVec2{rx, ry};
	g_physicalTriggers[0] = lt;
	g_physicalTriggers[1] = rt;
}

JNIEXPORT void JNICALL Java_io_github_muffinemu_NativeBridge_releaseAllButtons(JNIEnv*, jclass)
{
	std::lock_guard lock(g_inputMutex);
	g_touchButtons = 0;
	g_physicalButtons = 0;
	g_touchSticks[0] = g_touchSticks[1] = GCBridgeVec2{};
	g_physicalSticks[0] = g_physicalSticks[1] = GCBridgeVec2{};
	g_physicalTriggers[0] = g_physicalTriggers[1] = 0.0f;
}

} // extern "C"
