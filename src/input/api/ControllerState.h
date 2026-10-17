#pragma once

#include <glm/vec2.hpp>
#include "util/helpers/fspinlock.h"

enum class PositionVisibility {
	NONE = 0,
	FULL = 1,
	PARTIAL = 2
};

// helper class for storing and managing button press states in a thread-safe manner
struct ControllerButtonState
{
	ControllerButtonState() = default;
	ControllerButtonState(const ControllerButtonState& other)
	{
		this->m_pressedButtons = other.m_pressedButtons;
	}

	ControllerButtonState(ControllerButtonState&& other)
	{
		this->m_pressedButtons = std::move(other.m_pressedButtons);
	}

	void SetButtonState(uint32 buttonId, bool isPressed)
	{
		std::lock_guard _l(this->m_spinlock);
		if (isPressed)
		{
			if (std::find(m_pressedButtons.cbegin(), m_pressedButtons.cend(), buttonId) != m_pressedButtons.end())
				return;
			m_pressedButtons.emplace_back(buttonId);
		}
		else
		{
			std::erase(m_pressedButtons, buttonId);
		}
	}

	// set multiple buttons at once within a single lock interval
	void SetPressedButtons(std::span<uint32> buttonList)
	{
		std::lock_guard _l(this->m_spinlock);
		for (auto& buttonId : buttonList)
		{
			if (std::find(m_pressedButtons.cbegin(), m_pressedButtons.cend(), buttonId) == m_pressedButtons.end())
				m_pressedButtons.emplace_back(buttonId);
		}
	}

	// returns true if pressed
	bool GetButtonState(uint32 buttonId) const
	{
		std::lock_guard _l(this->m_spinlock);
		bool r = std::find(m_pressedButtons.cbegin(), m_pressedButtons.cend(), buttonId) != m_pressedButtons.cend();
		return r;
	}

	// remove pressed state for all pressed buttons in buttonsToUnset
	void UnsetButtons(const ControllerButtonState& buttonsToUnset)
	{
		std::scoped_lock _l(this->m_spinlock, buttonsToUnset.m_spinlock);
		for (auto it = m_pressedButtons.begin(); it != m_pressedButtons.end();)
		{
			if (std::find(buttonsToUnset.m_pressedButtons.cbegin(), buttonsToUnset.m_pressedButtons.cend(), *it) == buttonsToUnset.m_pressedButtons.cend())
			{
				++it;
				continue;
			}
			it = m_pressedButtons.erase(it);
		}
	}

	// returns true if no buttons are pressed
	bool IsIdle() const
	{
		std::lock_guard _l(this->m_spinlock);
		const bool r = m_pressedButtons.empty();
		return r;
	}

	std::vector<uint32> GetButtonList() const
	{
		std::lock_guard _l(this->m_spinlock);
		std::vector<uint32> copy = m_pressedButtons;
		return copy;
	}

	bool operator==(const ControllerButtonState& other) const
	{
		std::scoped_lock _l(this->m_spinlock, other.m_spinlock);
		auto& otherButtons = other.m_pressedButtons;
		if (m_pressedButtons.size() != otherButtons.size())
		{
			return false;
		}
		for (auto& buttonId : m_pressedButtons)
		{
			if (std::find(otherButtons.cbegin(), otherButtons.cend(), buttonId) == otherButtons.cend())
			{
				return false;
			}
		}
		return true;
	}

	ControllerButtonState& operator=(ControllerButtonState&& other)
	{
		cemu_assert_debug(!other.m_spinlock.is_locked());
		std::scoped_lock _l(this->m_spinlock, other.m_spinlock);
		this->m_pressedButtons = std::move(other.m_pressedButtons);
		return *this;
	}

private:
	std::vector<uint32> m_pressedButtons; // since only very few buttons are pressed at a time, using a vector with linear scan is more efficient than a set/map
	mutable FSpinlock m_spinlock;
};

struct ControllerState
{
	// when does a axis counts as pressed
#if BOOST_OS_IOS
	// Small enough to pass anything a stick can mean, and only large enough to keep out the kMinAxisValue bias
	// below and float noise. ControllerBase::get_axis_value only returns a stick component whose direction bit
	// is set, and that bit was only set past 0.1 on that axis, so a stick pushed mostly along one axis had the
	// other component cut to 0 and its direction snapped to the cardinal: at 40% deflection, 30 degrees off
	// vertical, the sideways 0.09 was lost. The desktop threshold is also the one the input-settings window
	// captures a moved axis with, and there is no such window here. Every stick that reaches the core on iOS
	// has already had its deadzone (the on-screen sticks the player's own, a physical controller's the bridge's
	// radial 0.25, ios_physical_stick_deadzone in CemuBridge.mm) and both give an exact 0 inside it, so nothing
	// is let through at rest.
	constexpr static float kAxisThreshold = 0.001f;
#else
	constexpr static float kAxisThreshold = 0.1f;
#endif

	// on the real console the stick x or y values never really reach 0.0 if one of the axis is moved
	// some games rely on this due to incorrectly checking if the stick is tilted via if (vstick.x != 0 && vstick.y != 0)
	// here we simulate a slight bias if the axis is almost perfectly centered
	constexpr static float kMinAxisValue = 0.0000001f;

	// [-1; 1]
	glm::vec2 axis{ };
	glm::vec2 rotation{ };
	glm::vec2 trigger{ };

	ControllerButtonState buttons{};

	uint64 last_state = 0;

	bool operator==(const ControllerState& other) const;
	bool operator!=(const ControllerState& other) const
	{
		return !(*this == other);
	}
};
