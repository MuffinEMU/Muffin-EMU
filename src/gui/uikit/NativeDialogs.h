// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>

// Mailbox between the core's guest-facing dialogs (swkbd, erreula) and the iOS app's native
// UI. While the app has switched this on (SetEnabled), those dialogs publish a request here
// instead of drawing with ImGui; the app polls the request through CemuBridge and sends the
// user's answer back. Everything is guarded by one mutex; the atomics only make the "nothing
// pending" polls free. Header-only, standard library only.
namespace NativeDialogs
{
struct KeyboardRequest
{
	std::u16string text; // what the field starts with (and what Cancel puts back)
	std::u16string hint;
	uint32_t maxLength = 0; // UTF-16 units
	bool multiline = false;
};

struct ErrorRequest
{
	std::u16string title;
	std::u16string message;
	std::u16string button1;
	std::u16string button2; // empty: a single-button dialog
};

enum class KeyboardAnswer : int
{
	Update = 0, // text changed, keep the dialog open
	Accept = 1, // OK
	Cancel = 2  // Cancel: the dialog's starting text is accepted instead
};

namespace detail
{
struct State
{
	std::mutex mutex;
	std::atomic_bool enabled{false};
	std::atomic_bool visible{false};        // something is waiting for the app to show it
	std::atomic_bool keyboardResult{false}; // something is waiting for the core to read it
	uint64_t nextId = 0;

	bool keyboardActive = false;
	bool keyboardAnswered = false;
	uint64_t keyboardId = 0;
	KeyboardRequest keyboard;
	bool resultPending = false;
	bool resultAccepted = false;
	std::u16string resultText;

	bool errorActive = false;
	bool errorAnswered = false;
	uint64_t errorId = 0;
	ErrorRequest error;
	int errorChoice = -1;
};

inline State& Get()
{
	static State state;
	return state;
}

inline void Refresh(State& s)
{
	s.visible.store((s.keyboardActive && !s.keyboardAnswered) || (s.errorActive && !s.errorAnswered), std::memory_order_relaxed);
	s.keyboardResult.store(s.resultPending, std::memory_order_relaxed);
}

inline void AppendUtf8(std::string& out, uint32_t c)
{
	if (c < 0x80)
		out += static_cast<char>(c);
	else if (c < 0x800)
	{
		out += static_cast<char>(0xC0 | (c >> 6));
		out += static_cast<char>(0x80 | (c & 0x3F));
	}
	else if (c < 0x10000)
	{
		out += static_cast<char>(0xE0 | (c >> 12));
		out += static_cast<char>(0x80 | ((c >> 6) & 0x3F));
		out += static_cast<char>(0x80 | (c & 0x3F));
	}
	else
	{
		out += static_cast<char>(0xF0 | (c >> 18));
		out += static_cast<char>(0x80 | ((c >> 12) & 0x3F));
		out += static_cast<char>(0x80 | ((c >> 6) & 0x3F));
		out += static_cast<char>(0x80 | (c & 0x3F));
	}
}
} // namespace detail

// UTF-16 to UTF-8. Lone surrogates become U+FFFD; the 0x1E / 0x1F separators the bridge uses
// become spaces so they can't split a field.
inline std::string ToUtf8(const std::u16string& s)
{
	std::string out;
	out.reserve(s.size());
	for (size_t i = 0; i < s.size(); ++i)
	{
		uint32_t c = s[i];
		if (c >= 0xD800 && c < 0xDC00 && i + 1 < s.size() && s[i + 1] >= 0xDC00 && s[i + 1] < 0xE000)
		{
			c = 0x10000 + ((c - 0xD800) << 10) + (s[i + 1] - 0xDC00);
			++i;
		}
		else if (c >= 0xD800 && c < 0xE000)
			c = 0xFFFD;
		if (c == 0x1E || c == 0x1F)
			c = ' ';
		detail::AppendUtf8(out, c);
	}
	return out;
}

inline std::u16string FromUtf8(const char* s)
{
	std::u16string out;
	if (!s)
		return out;
	const unsigned char* p = reinterpret_cast<const unsigned char*>(s);
	while (*p)
	{
		uint32_t c = *p;
		int extra = 0;
		if (c < 0x80)
			extra = 0;
		else if ((c & 0xE0) == 0xC0)
		{
			c &= 0x1F;
			extra = 1;
		}
		else if ((c & 0xF0) == 0xE0)
		{
			c &= 0x0F;
			extra = 2;
		}
		else if ((c & 0xF8) == 0xF0)
		{
			c &= 0x07;
			extra = 3;
		}
		else
			c = 0xFFFD;
		++p;
		for (int i = 0; i < extra; ++i)
		{
			if ((*p & 0xC0) != 0x80)
			{
				c = 0xFFFD;
				break;
			}
			c = (c << 6) | (*p & 0x3F);
			++p;
		}
		if (c >= 0x10000 && c <= 0x10FFFF)
		{
			c -= 0x10000;
			out.push_back(static_cast<char16_t>(0xD800 + (c >> 10)));
			out.push_back(static_cast<char16_t>(0xDC00 + (c & 0x3FF)));
		}
		else if (c > 0x10FFFF || (c >= 0xD800 && c < 0xE000))
			out.push_back(0xFFFD);
		else
			out.push_back(static_cast<char16_t>(c));
	}
	return out;
}

// Cuts to at most `maxLength` UTF-16 units without splitting a surrogate pair.
inline void Truncate(std::u16string& s, size_t maxLength)
{
	if (s.size() <= maxLength)
		return;
	size_t length = maxLength;
	if (length > 0 && s[length - 1] >= 0xD800 && s[length - 1] < 0xDC00)
		--length;
	s.resize(length);
}

inline bool IsEnabled()
{
	return detail::Get().enabled.load(std::memory_order_relaxed);
}

// Turning it off while a keyboard is up accepts that keyboard's starting text, so a title
// waiting on it can't hang. An error dialog is simply left to the core's own drawing.
inline void SetEnabled(bool enabled)
{
	auto& s = detail::Get();
	std::lock_guard lock(s.mutex);
	s.enabled.store(enabled, std::memory_order_relaxed);
	if (!enabled)
	{
		if (s.keyboardActive && !s.keyboardAnswered)
		{
			s.resultPending = true;
			s.resultAccepted = true;
			s.resultText = s.keyboard.text;
		}
		s.keyboardAnswered = true;
		s.errorActive = false;
	}
	detail::Refresh(s);
}

// False when the app isn't taking dialogs; the caller then uses its other path.
inline bool PublishKeyboard(KeyboardRequest request)
{
	auto& s = detail::Get();
	std::lock_guard lock(s.mutex);
	if (!s.enabled.load(std::memory_order_relaxed))
		return false;
	Truncate(request.text, request.maxLength);
	s.keyboardId = ++s.nextId;
	s.keyboard = std::move(request);
	s.keyboardActive = true;
	s.keyboardAnswered = false;
	s.resultPending = false;
	detail::Refresh(s);
	return true;
}

inline void WithdrawKeyboard()
{
	auto& s = detail::Get();
	std::lock_guard lock(s.mutex);
	s.keyboardActive = false;
	s.keyboardAnswered = false;
	s.resultPending = false;
	detail::Refresh(s);
}

// Core side: the newest text and whether it was accepted. False when nothing new.
inline bool PollKeyboard(std::u16string& text, bool& accepted)
{
	auto& s = detail::Get();
	if (!s.keyboardResult.load(std::memory_order_relaxed))
		return false;
	std::lock_guard lock(s.mutex);
	if (!s.resultPending)
		return false;
	text = s.resultText;
	accepted = s.resultAccepted;
	s.resultPending = false;
	detail::Refresh(s);
	return true;
}

// App side. Answers for a request that has been replaced or withdrawn are ignored.
inline void AnswerKeyboard(uint64_t id, std::u16string text, KeyboardAnswer answer)
{
	auto& s = detail::Get();
	std::lock_guard lock(s.mutex);
	if (!s.keyboardActive || s.keyboardAnswered || s.keyboardId != id)
		return;
	if (answer == KeyboardAnswer::Cancel)
		text = s.keyboard.text;
	Truncate(text, s.keyboard.maxLength);
	s.resultText = std::move(text);
	s.resultPending = true;
	if (answer != KeyboardAnswer::Update)
	{
		s.resultAccepted = true;
		s.keyboardAnswered = true;
	}
	else
		s.resultAccepted = false;
	detail::Refresh(s);
}

inline bool PublishError(ErrorRequest request)
{
	auto& s = detail::Get();
	std::lock_guard lock(s.mutex);
	if (!s.enabled.load(std::memory_order_relaxed))
		return false;
	s.errorId = ++s.nextId;
	s.error = std::move(request);
	s.errorActive = true;
	s.errorAnswered = false;
	s.errorChoice = -1;
	detail::Refresh(s);
	return true;
}

inline void WithdrawError()
{
	auto& s = detail::Get();
	std::lock_guard lock(s.mutex);
	s.errorActive = false;
	s.errorAnswered = false;
	s.errorChoice = -1;
	detail::Refresh(s);
}

// App side: 0 is the left button, 1 the right one.
inline void AnswerError(uint64_t id, int button)
{
	auto& s = detail::Get();
	std::lock_guard lock(s.mutex);
	if (!s.errorActive || s.errorAnswered || s.errorId != id)
		return;
	s.errorChoice = button == 0 ? 0 : 1;
	s.errorAnswered = true;
	detail::Refresh(s);
}

// Core side: the button the user chose (0 left, 1 right), once; -1 when none yet.
inline int TakeErrorChoice()
{
	auto& s = detail::Get();
	if (!s.visible.load(std::memory_order_relaxed) && !s.errorActive)
		return -1;
	std::lock_guard lock(s.mutex);
	const int choice = s.errorChoice;
	s.errorChoice = -1;
	return choice;
}

// What the app should show, as one UTF-8 string with fields separated by 0x1F. Empty when
// nothing is waiting. A keyboard comes first:
//   "K" id maxLength multiline(0/1) text hint
//   "E" id buttonCount(1/2) title message button1 button2
inline std::string Describe()
{
	auto& s = detail::Get();
	if (!s.visible.load(std::memory_order_relaxed))
		return {};
	std::lock_guard lock(s.mutex);
	std::string out;
	if (s.keyboardActive && !s.keyboardAnswered)
	{
		out = "K\x1F" + std::to_string(s.keyboardId) + "\x1F" + std::to_string(s.keyboard.maxLength) + "\x1F" +
			  (s.keyboard.multiline ? "1" : "0") + "\x1F" + ToUtf8(s.keyboard.text) + "\x1F" + ToUtf8(s.keyboard.hint);
	}
	else if (s.errorActive && !s.errorAnswered)
	{
		out = "E\x1F" + std::to_string(s.errorId) + "\x1F" + (s.error.button2.empty() ? "1" : "2") + "\x1F" + ToUtf8(s.error.title) +
			  "\x1F" + ToUtf8(s.error.message) + "\x1F" + ToUtf8(s.error.button1) + "\x1F" + ToUtf8(s.error.button2);
	}
	return out;
}
} // namespace NativeDialogs
