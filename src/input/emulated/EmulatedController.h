#pragma once
#include <pugixml.hpp>

class ControllerBase;

#include "input/motion/MotionSample.h"

#include "input/api/ControllerState.h"
#include "input/api/InputAPI.h"

#include "util/helpers/helpers.h"

// mapping = wii u controller button id
// button = api button id

class EmulatedController
{
	friend class InputManager;
public:
	EmulatedController(size_t player_index);
	virtual ~EmulatedController() = default;

	virtual void load(const pugi::xml_node& node){};
	virtual void save(pugi::xml_node& node){};

	enum Type
	{
		VPAD,
		Pro,
		Classic,
		Wiimote,

		MAX
	};
	virtual Type type() const = 0;
	std::string_view type_string() const { return type_to_string(type()); }

	static std::string_view type_to_string(Type type);
	static Type type_from_string(std::string_view str);

	size_t player_index() const { return m_player_index; }
	const std::string& get_profile_name() const { return m_profile_name; }
	bool has_profile_name() const { return !m_profile_name.empty() && m_profile_name != "default"; }

	void calibrate();

	void connect();
	virtual void update();
	void controllers_update_states();

	virtual glm::vec2 get_axis() const = 0;
	virtual glm::vec2 get_rotation() const = 0;
	virtual glm::vec2 get_trigger() const = 0;

	void start_rumble();
	void stop_rumble();

	bool is_battery_low() const;

	bool has_motion() const;
	MotionSample get_motion_data() const;

	// some controllers (nunchuck) provide extra motion data
	bool has_second_motion() const;
	MotionSample get_second_motion_data() const;

	bool has_position() const;
	glm::vec2 get_position() const;
	glm::vec2 get_prev_position() const;
	PositionVisibility GetPositionVisibility() const;

	void add_controller(std::shared_ptr<ControllerBase> controller);
	void remove_controller(const std::shared_ptr<ControllerBase>& controller);
	void clear_controllers();
	const std::vector<std::shared_ptr<ControllerBase>>& get_controllers() const { return m_controllers; }

	bool is_mapping_down(uint64 mapping) const;
	std::string get_mapping_name(uint64 mapping) const;
	std::shared_ptr<ControllerBase> get_mapping_controller(uint64 mapping) const;
	void delete_mapping(uint64 mapping);
	void clear_mappings();
	void set_mapping(uint64 mapping, const std::shared_ptr<ControllerBase>& controller_base, uint64 button);

	virtual uint32 get_emulated_button_flag(uint32 mapping) const = 0;

	bool operator==(const EmulatedController& o) const;
	bool operator!=(const EmulatedController& o) const;

	virtual size_t get_highest_mapping_id() const = 0;
	virtual bool is_axis_mapping(uint64 mapping) const = 0;

	virtual bool is_start_down() const = 0;
	virtual bool is_left_down() const = 0;
	virtual bool is_right_down() const = 0;
	virtual bool is_up_down() const = 0;
	virtual bool is_down_down() const = 0;
	virtual bool is_a_down() const = 0;
	virtual bool is_b_down() const = 0;
	virtual bool is_home_down() const = 0;

	bool was_home_button_down() { return std::exchange(m_homebutton_down, false); }

	virtual bool set_default_mapping(const std::shared_ptr<ControllerBase>& controller) { return false; }
	// Host-UI override for a single mapping, for on-screen controls that are not backed
	// by any physical device (Android's overlay, iOS's touch pad). Checked *before*
	// m_mappings by is_mapping_down()/get_axis_value(), so an on-screen press works
	// whether or not a controller is attached and whatever profile is loaded.
	//
	// Callable from the host UI thread while the emulated title polls the same state
	// from its own thread - see the comment on m_overriddenButtonMappings below for what
	// makes that safe and what the caller still has to do first.
	void setButtonValue(uint64 mapping, bool value);
	void setAxisValue(uint64 mapping, float value);
protected:
	size_t m_player_index;
	std::string m_profile_name = "default";

	mutable std::shared_mutex m_mutex;
	std::vector<std::shared_ptr<ControllerBase>> m_controllers;

	float get_axis_value(uint64 mapping) const;
	bool m_rumble = false;

	struct Mapping
	{
		std::weak_ptr<ControllerBase> controller;
		uint64 button;
	};
	std::unordered_map<uint64, Mapping> m_mappings;

	// std::atomic<bool>, not bool. is_mapping_down() reads this from the emulated
	// title's own thread and takes no lock at all (it is called once per mapping per
	// VPADRead, i.e. in the poll loop, so it cannot afford one), while setButtonValue()
	// writes it from the host UI thread. As a plain bool that pairing is a data race by
	// the language definition; as an atomic it is a well-defined load/store and the
	// reader sees either the old value or the new one.
	//
	// That leaves exactly one hazard, which the type cannot fix: inserting a key the map
	// has never seen may rehash, and rehashing while another thread is walking a bucket
	// chain in find() is a genuine crash, not a stale read. std::unordered_map is
	// node-based so existing elements never move - only the bucket array is rebuilt -
	// so a caller can close the hole completely by touching every mapping id it will
	// ever use ONCE, before the title thread exists. IOSInput_Initialize() does this;
	// anything else driving these overrides from a second thread must do the same.
	std::unordered_map<uint64, std::atomic<bool>> m_overriddenButtonMappings;
	std::unordered_map<uint64, float> m_overriddenAxisMappings;
 
	bool m_homebutton_down = false;
};

using EmulatedControllerPtr = std::shared_ptr<EmulatedController>;

template <>
struct fmt::formatter<EmulatedController::Type> : formatter<string_view> {
	template <typename FormatContext>
	auto format(EmulatedController::Type v, FormatContext& ctx) const {
		switch (v)
		{
		case EmulatedController::Type::VPAD: return formatter<string_view>::format("Wii U Gamepad", ctx);
		case EmulatedController::Type::Pro: return formatter<string_view>::format("Wii U Pro Controller", ctx);
		case EmulatedController::Type::Classic: return formatter<string_view>::format("Wii U Classic Controller Pro", ctx);
		case EmulatedController::Type::Wiimote: return formatter<string_view>::format("Wiimote", ctx);
		}
		throw std::invalid_argument(fmt::format("invalid emulated controller type with value {}", to_underlying(v)));
	}
};
