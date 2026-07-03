#pragma once

#if defined(CEMU_PLATFORM_IOS)

#include <string>
#include <string_view>
#include <charconv>
#include <vector>
#include <cstdint>

// Big-endian 16-bit type
using uint16be = uint16_t;

namespace nowide {
    inline std::string narrow(const std::wstring& str) {
        std::string result;
        result.reserve(str.size());
        for (wchar_t c : str) {
            if (c < 256) {
                result += static_cast<char>(c);
            }
        }
        return result;
    }

    inline std::wstring widen(const std::string& str) {
        std::wstring result;
        result.reserve(str.size());
        for (unsigned char c : str) {
            result += static_cast<wchar_t>(c);
        }
        return result;
    }

    inline std::wstring widen(const char* str, size_t len) {
        std::wstring result;
        result.reserve(len);
        for (size_t i = 0; i < len; i++) {
            result += static_cast<wchar_t>(static_cast<unsigned char>(str[i]));
        }
        return result;
    }
}

namespace StringHelpers {
    // Convert big-endian UTF-16 to UTF-8
    static std::string ToUtf8(const uint16be* ptr, size_t maxLength) {
        std::string result;
        while (ptr && *ptr != 0 && maxLength > 0) {
            uint16_t c = *ptr;
            if (c < 128) {
                result += static_cast<char>(c);
            } else if (c < 2048) {
                result += static_cast<char>(0xC0 | (c >> 6));
                result += static_cast<char>(0x80 | (c & 0x3F));
            } else {
                result += static_cast<char>(0xE0 | (c >> 12));
                result += static_cast<char>(0x80 | ((c >> 6) & 0x3F));
                result += static_cast<char>(0x80 | (c & 0x3F));
            }
            ptr++;
            maxLength--;
        }
        return result;
    }

    static std::string ToUtf8(std::span<uint16be> input) {
        return ToUtf8(input.data(), input.size());
    }

    // Convert UTF-8 to big-endian UTF-16
    static std::vector<uint16be> FromUtf8(std::string_view str) {
        std::vector<uint16be> result;
        for (size_t i = 0; i < str.size(); ) {
            unsigned char c = str[i++];
            uint16_t code = 0;

            if ((c & 0x80) == 0) {
                code = c;
            } else if ((c & 0xE0) == 0xC0 && i < str.size()) {
                code = ((c & 0x1F) << 6) | (str[i++] & 0x3F);
            } else if ((c & 0xF0) == 0xE0 && i + 1 < str.size()) {
                code = ((c & 0x0F) << 12) | ((str[i++] & 0x3F) << 6) | (str[i++] & 0x3F);
            }

            if (code > 0) {
                result.push_back(static_cast<uint16be>(code));
            }
        }
        result.push_back(0);
        return result;
    }

    static int32_t ToInt(const std::string_view& input, int32_t defaultValue = 0) {
        int32_t value = defaultValue;
        if (input.size() >= 2 && (input[0] == '0' && (input[1] == 'x' || input[1] == 'X'))) {
            auto result = std::from_chars(input.data() + 2, input.data() + input.size(), value, 16);
            if (result.ec != std::errc()) return defaultValue;
        } else {
            auto result = std::from_chars(input.data(), input.data() + input.size(), value);
            if (result.ec != std::errc()) return defaultValue;
        }
        return value;
    }

    static int64_t ToInt64(const std::string_view& input, int64_t defaultValue = 0) {
        int64_t value = defaultValue;
        if (input.size() >= 2 && (input[0] == '0' && (input[1] == 'x' || input[1] == 'X'))) {
            auto result = std::from_chars(input.data() + 2, input.data() + input.size(), value, 16);
            if (result.ec != std::errc()) return defaultValue;
        } else {
            auto result = std::from_chars(input.data(), input.data() + input.size(), value);
            if (result.ec != std::errc()) return defaultValue;
        }
        return value;
    }

    static uint32_t ToUInt(const std::string_view& input, uint32_t defaultValue = 0) {
        uint32_t value = defaultValue;
        if (input.size() >= 2 && (input[0] == '0' && (input[1] == 'x' || input[1] == 'X'))) {
            auto result = std::from_chars(input.data() + 2, input.data() + input.size(), value, 16);
            if (result.ec != std::errc()) return defaultValue;
        } else {
            auto result = std::from_chars(input.data(), input.data() + input.size(), value);
            if (result.ec != std::errc()) return defaultValue;
        }
        return value;
    }

    static uint64_t ToUInt64(const std::string_view& input, uint64_t defaultValue = 0) {
        uint64_t value = defaultValue;
        if (input.size() >= 2 && (input[0] == '0' && (input[1] == 'x' || input[1] == 'X'))) {
            auto result = std::from_chars(input.data() + 2, input.data() + input.size(), value, 16);
            if (result.ec != std::errc()) return defaultValue;
        } else {
            auto result = std::from_chars(input.data(), input.data() + input.size(), value);
            if (result.ec != std::errc()) return defaultValue;
        }
        return value;
    }
}

#endif // CEMU_PLATFORM_IOS
