#pragma once

// CemuLogging.cpp always defines this with real linkage (a genuine mask computed
// from cemuLog_getFlag), regardless of platform. An earlier "iOS Phase 0: Stub
// logging" era had this as `static uint64 = 0` here instead, which conflicted with
// the .cpp's own non-static definition the moment CEMU_PLATFORM_IOS was actually
// defined for a real build (as opposed to never being exercised).
extern uint64 s_loggingFlagMask;

enum class LogType : sint32
{
	// note: IDs must be in range 1-64
	Force = 63, // always enabled
	Placeholder = 62, // always disabled
	APIErrors = 61, // Logs bad parameters or other API usage mistakes or unintended errors in OS libs. Intended for homebrew developers

	CoreinitFile = 0,
	GX2 = 1,
	UnsupportedAPI = 2,
	SoundAPI = 4, // any audio related API
	InputAPI = 5, // any input related API
	Socket = 6,
	Save = 7,
	H264 = 9,
	OpenGLLogging = 10, // OpenGL debug logging
	TextureCache = 11, // texture cache warnings and info
	VulkanValidation = 12, // Vulkan validation layer
	Patches = 14,
	CoreinitMem = 8, // coreinit memory functions
	CoreinitMP = 15,
	CoreinitThread = 16,
	CoreinitLogging = 17, // OSReport, OSConsoleWrite etc.
	CoreinitMemoryMapping = 18, // OSGetAvailPhysAddrRange, OSAllocVirtAddr, OSMapMemory etc.
	CoreinitAlarm = 22,
	CoreinitThreadSync = 3,

	PPC_IPC = 19,
	NN_AOC = 20,
	NN_PDM = 21,
	NN_OLV = 23,
	NN_NFP = 13,
	NN_FP = 24,
	NN_BOSS = 25,
	NN_SL = 26,

	TextureReadback = 29,
	ProcUi = 39,
	nlibcurl = 41,

	PRUDP = 40,

	NFC	= 41,
	NTAG = 42,
	Recompiler = 60,
};

#if !defined(CEMU_PLATFORM_IOS)
template <>
struct fmt::formatter<std::u8string_view> : formatter<string_view> {
	template <typename FormatContext>
	auto format(std::u8string_view v, FormatContext& ctx)
	{
		string_view s((char*)v.data(), v.size());
		return formatter<string_view>::format(s, ctx);
	}
};
#endif

void cemuLog_writeLineToLog(std::string_view text, bool date = true, bool new_line = true);
inline void cemuLog_writePlainToLog(std::string_view text) { cemuLog_writeLineToLog(text, false, false); }

void cemuLog_setActiveLoggingFlags(uint64 flagMask);

inline uint64 cemuLog_getFlag(LogType type)
{
	return 1ULL << (uint64)type;
}

inline bool cemuLog_isLoggingEnabled(LogType type)
{
	return (s_loggingFlagMask & cemuLog_getFlag(type)) != 0;
}

bool cemuLog_log(LogType type, std::string_view text);
bool cemuLog_log(LogType type, std::u8string_view text);
void cemuLog_waitForFlush(); // wait until all log lines are written

#if !defined(CEMU_PLATFORM_IOS)
template<typename... TArgs>
bool cemuLog_log(LogType type, fmt::format_string<TArgs...> formatStr, TArgs&&... args)
{
	if (!cemuLog_isLoggingEnabled(type))
		return false;

	cemuLog_log(type, fmt::format(formatStr, std::forward<TArgs>(args)...));

	return true;
}

// same as cemuLog_log, but only outputs in debug mode
template<typename ... TArgs>
bool cemuLog_logDebug(LogType type, fmt::format_string<TArgs...> format, TArgs&&... args)
{
#ifdef CEMU_DEBUG_ASSERT
	return cemuLog_log(type, format, std::forward<TArgs>(args)...);
#else
	return false;
#endif
}
#else
// iOS overloads. These templates exact-match ANY cemuLog_log(type, "string literal",
// ...) call (a `const char*`/`const char[N]` argument binds directly to `const char*`
// with no conversion needed - whereas the real non-template overloads take
// std::string_view/std::u8string_view, which require one), so whatever these do IS
// what iOS logging does for the overwhelming majority of the engine's log calls.
//
// They used to `return false` for every call with format arguments, and the
// accompanying `#define cemuLog_logOnce(...) {}` expanded logOnce to nothing at all.
// That made the iOS log actively deceptive rather than merely sparse: every line that
// survived was a zero-argument call, and every formatted line - `RPL link time: {}ms`,
// the whole `Active settings` block, `Generated placeholder TitleId: {:016x}`,
// MetalLayerHandle's `layer {} failed to acquire next drawable` - vanished with no
// trace, as did the always-on GX2SwapScanBuffers() marker (GX2.cpp), which is a
// cemuLog_logOnce call. Debugging the black screen off that log meant reading the
// absence of lines that could never have been printed in the first place, and
// concluding things about the emulator that the log had no ability to report.
//
// fmt is available and working in this target (CemuLogging.cpp builds every log
// timestamp with fmt::format), so there was never a real capability gap here. Use
// the runtime-format entry point, fmt::vformat + fmt::make_format_args, rather than
// the compile-time-checked fmt::format_string<TArgs...> path the desktop branch above
// uses: format_string is a consteval-constructed type, and its strictness is what
// made these calls awkward to support here in the first place. Runtime formatting
// gives identical output.
template<typename... TArgs>
bool cemuLog_log(LogType type, const char* formatStr, TArgs&&... args)
{
	if constexpr (sizeof...(TArgs) == 0)
		return cemuLog_log(type, std::string_view(formatStr));
	else
	{
		if (!cemuLog_isLoggingEnabled(type))
			return false;
		const std::string formatted = fmt::vformat(fmt::string_view(formatStr), fmt::make_format_args(args...));
		cemuLog_log(type, std::string_view(formatted));
		return true;
	}
}
template<typename ... TArgs>
bool cemuLog_logDebug(LogType type, const char* format, TArgs&&... args)
{
	// Deliberately calls cemuLog_log (the template directly above) rather than the
	// cemuLog_logDebug(LogType, std::string_view) overload declared further down in
	// this same header: this call has non-dependent arguments, so two-phase lookup
	// would resolve it at THIS definition point, before that overload is visible.
	// Same CEMU_DEBUG_ASSERT gate, inlined.
#ifdef CEMU_DEBUG_ASSERT
	return cemuLog_log(type, format, std::forward<TArgs>(args)...);
#else
	return false;
#endif
}
#endif

// Platform-independent: this used to live inside the desktop-only branch above, with
// the iOS branch defining it as `{}` - i.e. cemuLog_logOnce() compiled to nothing at
// all on iOS, silently discarding every one-shot diagnostic in the engine including
// the always-on GX2SwapScanBuffers() marker added specifically to debug the iOS
// black screen.
#define cemuLog_logOnce(...) { static bool _not_first_call = false; if (!_not_first_call) { _not_first_call = true; cemuLog_log(__VA_ARGS__); } }

inline bool cemuLog_logDebug(LogType type, std::string_view message)
{
#ifdef CEMU_DEBUG_ASSERT
	return cemuLog_log(type, message);
#else
	return false;
#endif
}

#define cemuLog_logDebugOnce(...) { static bool _not_first_call = false; if (!_not_first_call) { _not_first_call = true; cemuLog_logDebug(__VA_ARGS__); } }

// utility function for logging binary data as a hex dump
void cemuLog_logHexDump(LogType type, const void* data, size_t size, size_t lineSize = 16);

// cafe lib calls
bool cemuLog_advancedPPCLoggingEnabled();

uint64 cemuLog_getFlag(LogType type);

fs::path cemuLog_GetLogFilePath();
void cemuLog_createLogFile(bool triggeredByCrash);
[[nodiscard]] std::unique_lock<std::recursive_mutex> cemuLog_acquire(); // used for logging multiple lines at once

class LoggingCallbacks
{
  public:
	virtual void Log(std::string_view filter, std::string_view message) {};
	virtual void Log(std::string_view filter, std::wstring_view message) {};
	virtual ~LoggingCallbacks() = default;
};

void cemuLog_setCallbacks(LoggingCallbacks* loggingCallbacks);
void cemuLog_clearCallbacks();
