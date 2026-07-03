#pragma once
// iOS Phase 0: Configuration stubs
// Provides minimal config system without Boost/XMLConfig

#if defined(CEMU_PLATFORM_IOS)

#include <string>
#include <vector>

// Minimal CemuConfig stub
namespace CemuConfig {
    inline bool GetBool(const char* key, bool default_val) { return default_val; }
    inline int GetInt(const char* key, int default_val) { return default_val; }
    inline std::string GetString(const char* key, const std::string& default_val) { return default_val; }
}

// Minimal ActiveSettings stub
namespace ActiveSettings {
    inline void SetValue(const char* key, const char* value) {}
    inline std::string GetValue(const char* key, const std::string& default_val) { return default_val; }
}

// CrashDump stub
struct CrashDump {
    static void Generate() {}
};

#endif // CEMU_PLATFORM_IOS
