#pragma once

#if BOOST_OS_WINDOWS
#include "input/api/DirectInput/DirectInputControllerProvider.h"
#include "input/api/XInput/XInputControllerProvider.h"
#endif

#ifdef SUPPORTS_WIIMOTE
#include "input/api/Wiimote/WiimoteControllerProvider.h"
#endif

#include "util/helpers/Singleton.h"

#include "input/api/SDL/SDLControllerProvider.h"
#include "input/api/Keyboard/KeyboardControllerProvider.h"
#include "input/api/DSU/DSUControllerProvider.h"
#include "input/api/GameCube/GameCubeControllerProvider.h"

#if BOOST_PLAT_ANDROID
#include "input/api/Android/AndroidControllerProvider.h"
#include "input/api/Device/DeviceControllerProvider.h"
#endif

#include "input/emulated/VPADController.h"
#include "input/emulated/WPADController.h"

#include <atomic>
#include <optional>

class InputManager : public Singleton<InputManager>
{
	friend class Singleton<InputManager>;
	InputManager();
	~InputManager();

	friend class MainWindow;
	friend class PadViewFrame;

public:
	constexpr static size_t kMaxController = 8;
	constexpr static size_t kMaxVPADControllers = 2;
	constexpr static size_t kMaxWPADControllers = 7;
	
	static bool input_config_window_has_focus();
	static void set_input_config_window_focus(bool has_focus);

	void load() noexcept;
	bool load(size_t player_index, std::string_view filename = {});

	bool migrate_config(const fs::path& file_path);

	void save() noexcept;
	bool save(size_t player_index, std::string_view filename = {});

	bool is_gameprofile_set(size_t player_index) const;

	EmulatedControllerPtr set_controller(EmulatedControllerPtr controller);
	EmulatedControllerPtr set_controller(size_t player_index, EmulatedController::Type type);
	EmulatedControllerPtr set_controller(size_t player_index, EmulatedController::Type type, const std::shared_ptr<ControllerBase>& controller);

	EmulatedControllerPtr delete_controller(size_t player_index, bool delete_profile = false);
	
	EmulatedControllerPtr get_controller(size_t player_index) const;
	std::shared_ptr<VPADController> get_vpad_controller(size_t index) const;
	std::shared_ptr<WPADController> get_wpad_controller(size_t index) const;
	std::pair<size_t, size_t> get_controller_count() const;

	bool is_api_available(InputAPI::Type api) const { return !m_api_available[api].empty(); }
	
	ControllerProviderPtr get_api_provider(std::string_view api_name) const;
	ControllerProviderPtr get_api_provider(InputAPI::Type api) const;
	// will create the provider with the given settings if it doesn't exist yet
	ControllerProviderPtr get_api_provider(InputAPI::Type api, const ControllerProviderSettings& settings);

	const auto& get_api_providers() const
	{
		return m_api_available;
	}

	void apply_game_profile();
	void on_device_changed();


	static std::vector<std::string> get_profiles();
	static bool is_valid_profilename(const std::string& name);

	struct MouseInfo
	{
		mutable std::shared_mutex m_mutex;
		glm::ivec2 position{};
		bool left_down = false;
		bool right_down = false;

		bool left_down_toggle = false;
		bool right_down_toggle = false;
	} m_main_mouse{}, m_pad_mouse{}, m_main_touch{}, m_pad_touch{};
	glm::ivec2 get_mouse_position(bool pad_window) const;
	std::optional<glm::ivec2> get_left_down_mouse_info(bool* is_pad);
	std::optional<glm::ivec2> get_right_down_mouse_info(bool* is_pad);

	std::atomic<float> m_mouse_wheel;
private:
	void update_thread();

	std::thread m_update_thread;
	std::atomic<bool> m_update_thread_shutdown{false};

	std::array<std::vector<ControllerProviderPtr>, InputAPI::MAX> m_api_available{ };

	mutable std::shared_mutex m_mutex;
	std::array<EmulatedControllerPtr, kMaxVPADControllers> m_vpad;
	std::array<EmulatedControllerPtr, kMaxWPADControllers> m_wpad;

	std::array<bool, kMaxController> m_is_gameprofile_set{};

	template<std::derived_from<ControllerProviderBase> TProvider>
	void create_provider()
	{
		try
		{
			auto controller = std::make_shared<TProvider>();
			m_api_available[controller->api()] = std::vector<ControllerProviderPtr>{controller};
		} catch (const std::exception& ex)
		{
			cemuLog_log(LogType::Force, ex.what());
		}
	}
};

#if defined(CEMU_PLATFORM_IOS)
// iOS input bring-up.
//
// Desktop Cemu does this work in two places that simply do not exist on iOS:
// src/main.cpp calls InputManager::instance().load(), and the wxWidgets input-settings
// dialog is what creates an emulated controller and binds a physical one to it. The iOS
// app is launched by SwiftUI, so main() is never entered, and there is no input
// configuration UI at all. The consequence is not "input needs configuring" - it is that
// InputManager is never constructed until CafeSystem happens to touch it mid-boot, no
// controller profile is ever loaded, and the running title sees zero emulated
// controllers no matter what hardware is attached.
//
// Implemented at the bottom of InputManager.cpp (guarded the same way) rather than in a
// file of its own, so it stays next to the InputManager internals it depends on and adds
// nothing to the build graph for other platforms.

// Constructs InputManager (which brings up the SDL controller provider, i.e. SDL_Init),
// loads any controller profile present under <userdata>/controllerProfiles/, and - if
// that left player 0 without a usable GamePad - creates one and binds the first attached
// physical controller to it using Cemu's own default mapping.
//
// Idempotent. Call once during engine initialization, from the main thread: SDL's iOS
// joystick backend is a GameController.framework client, so bring it up where UIKit
// lives rather than on whichever background thread happens to boot the engine first.
void IOSInput_Initialize();

// Re-runs only the binding step, for a controller paired *after* startup - the normal
// case on iOS, where Bluetooth controllers connect whenever they feel like it. Safe to
// call from any thread and does nothing before IOSInput_Initialize() has run. It is
// already wired to SDL's own device-added/removed event, so callers only need this for a
// belt-and-braces rescan (e.g. immediately before booting a title).
void IOSInput_RefreshDevices();

// Holds or releases one button on player 1's emulated GamePad on behalf of the
// on-screen controls. `button` is a CemuBridgeButton (src/ios/Bridge/CemuBridge.h), not
// a VPADController::ButtonId - the app's numbering is a published contract with the
// Swift call sites, Cemu's internal one is not, and iosMapBridgeButton() is the single
// place the two meet.
//
// Held, not tapped: `pressed` stays true until the finger lifts. It writes into the
// emulated controller's override state, which is checked ahead of any physical
// controller's mapping, so the touch pad and an attached MFi controller both work and
// neither cancels the other.
//
// Safe to call from the UI thread while the title polls VPADRead from its own: the
// override is an atomic bool, and IOSInput_Initialize() has already reserved every slot
// so no call here can rehash the map the reader is walking. A no-op before
// IOSInput_Initialize() has run, and repeated identical calls cost nothing.
void IOSInput_SetButtonState(int button, bool pressed);

// Positions one analog stick on player 1's emulated GamePad from the on-screen controls.
// `stick` is a CemuBridgeStick (0 = left, 1 = right); `x`/`y` are in -1..1 with +x right
// and +y UP, i.e. the console's convention, and the caller has already clamped them.
//
// Separate from IOSInput_SetButtonState() because Cemu keeps the two separate: VPADRead
// skips the eight kButtonId_Stick*_ ids in its button loop and derives the sticks from
// get_axis()/get_rotation() instead, so a stick direction delivered as a button press is
// not an approximation of a stick - it is discarded. This writes the four axis mappings
// the stick is actually made of.
//
// (0, 0) clears the override rather than pinning the stick to centre, so releasing the
// on-screen stick hands that axis back to whatever physical controller is bound instead
// of holding it still. Same thread-safety terms as IOSInput_SetButtonState().
void IOSInput_SetStickAxis(int stick, float x, float y);

// Releases everything the on-screen pad is holding, sticks included. Every press is supposed to be
// paired with a release by the view that started it, but a gesture the system cancels
// (backgrounding, an incoming call, a view torn out from under a finger) does not always
// produce one - and a button left down is a title stuck walking into a wall with nothing
// on screen touching it. Same thread-safety terms as above.
void IOSInput_ReleaseAllButtons();
#endif // CEMU_PLATFORM_IOS
