#pragma once
// iOS Phase 0: fmt + type stubs
// Prevents compilation errors when fmt is not available and when key types are missing

#if defined(CEMU_PLATFORM_IOS)

// Minimal address type stubs (MemPtr.h disabled for iOS Phase 0)
using MPTR = uint32_t;
using VAddr = uint32_t;
using PAddr = uint32_t;

namespace fmt {
    // Minimal formatter stub - allows specializations to compile
    template <typename T>
    struct formatter {
        auto parse(auto& ctx) { return ctx.begin(); }
        auto format(const T& val, auto& ctx) {
            return ctx.out();
        }
    };

    // format_string stub for logging
    template <typename... Args>
    class format_string {
    public:
        format_string(const char* str) : m_str(str) {}
        const char* data() const { return m_str; }
        size_t size() const { return strlen(m_str); }
    private:
        const char* m_str;
    };

    // format stub - just returns empty string
    template <typename... Args>
    inline std::string format(const fmt::format_string<Args...>&, Args&&...) {
        return {};
    }

    template <typename... Args>
    inline std::string format(const fmt::format_string<Args...>&) {
        return {};
    }
}

#endif // CEMU_PLATFORM_IOS
