#pragma once

#include <optional>
#include <string>

class LaunchSettings
{
public:
	// winmain
	static bool HandleCommandline(const wchar_t* lpCmdLine);
	// wmain
	static bool HandleCommandline(int argc, wchar_t* argv[]);
	// main (unix)
	static bool HandleCommandline(int argc, char* argv[]);

	static bool HandleCommandline(const std::vector<std::wstring>& args);

	static std::optional<fs::path> GetLoadFile() { return s_load_game_file; }
    static std::optional<uint64> GetLoadTitleID() {return s_load_title_id;}
	static std::optional<fs::path> GetMLCPath() { return s_mlc_path; }

	static std::optional<bool> RenderUpsideDownEnabled() { return s_render_upside_down; }
	static std::optional<bool> FullscreenEnabled() { return s_fullscreen; }

	static bool Verbose() { return s_verbose; }

	static bool GDBStubEnabled() { return s_enable_gdbstub; }
	static bool NSightModeEnabled() { return s_nsight_mode; }

	static bool ForceInterpreter() { return s_force_interpreter; };
	static bool ForceMultiCoreInterpreter() { return s_force_multicore_interpreter; }

    static bool SetInterpreter(bool interpreter) {
        s_force_multicore_interpreter = interpreter;
        return s_force_multicore_interpreter;
    }

	static std::optional<uint32> GetPersistentId() { return s_persistent_id; }

	static uint32 GetPPCRecLowerAddr() { return ppcRec_limitLowerAddr; };
	static uint32 GetPPCRecUpperAddr() { return ppcRec_limitUpperAddr; };

private:
	inline static std::optional<fs::path> s_load_game_file{};
    inline static std::optional<uint64> s_load_title_id{};
	inline static std::optional<fs::path> s_mlc_path{};

	inline static std::optional<bool> s_render_upside_down{};
	inline static std::optional<bool> s_fullscreen{};

	// Off by default: with this on, every cemuLog_log() on every thread does std::cout << text << std::endl, a flushed write()
	// to stdout under the stdio FILE lock. On iOS stdout is a pipe or file nothing reliably drains (and that a backgrounded
	// app can stall on), so one stuck write() kept the FILE lock and every other thread that logged - including the main
	// thread (display resize, Quit) - hung behind it until the watchdog killed the app. The log file already gets every line.
	inline static bool s_verbose = false;

	inline static bool s_enable_gdbstub = false;
	inline static bool s_nsight_mode = false;

	inline static bool s_force_interpreter = false;
	inline static bool s_force_multicore_interpreter = false;

	inline static std::optional<uint32> s_persistent_id{};

	// for recompiler debugging
	inline static uint32 ppcRec_limitLowerAddr{};
	inline static uint32 ppcRec_limitUpperAddr{};

	static bool ExtractorTool(std::wstring_view wud_path, std::string_view output_path, std::wstring_view log_path);
};
