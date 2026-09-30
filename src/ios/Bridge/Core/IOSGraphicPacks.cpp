// Graphic pack browsing, toggling and preset selection for iOS. GraphicPack2
// (Cafe/GraphicPack/) is the same graphic pack system the desktop app uses, with real consumers
// (LatteShader.cpp, the texture-rule and patch code), so this file is only the plain-C
// surface the Swift screens need: scan, list, describe, enable, pick a preset.
//
// Where packs live: GraphicPack2::LoadAll() walks <user data>/graphicPacks recursively,
// and the user data path on iOS is Documents/mlc. So
//   Documents/mlc/graphicPacks/downloadedGraphicPacks/  the community release (GraphicPackStore.swift)
//   Documents/mlc/graphicPacks/imported/                 packs a player added from Files
// are both found by the core's own scan, and CafeSystem prints
// "------- Activate graphic packs -------" and calls GraphicPack2::ActivateForCurrentTitle()
// for the title being launched.
//
// Persistence is the core's own graphic_pack_entries in config.xml (the same entries the
// desktop app writes): an entry that exists means "enabled" unless it carries the
// "_disabled" marker, and its other keys are <preset category, active preset name>.
//
// The engine is only initialized on the first game launch, and the pack screens have to work
// before that. EnsureEnvironment() gives the core just what the pack scan needs (the user
// data path and the config file) when the engine has not done so yet. CemuInitialize() then
// repeats both and clears and re-scans the packs, so nothing made here survives as a
// duplicate.
#include "Cafe/CafeSystem.h"
#include "Cafe/GraphicPack/GraphicPack2.h"
#include "config/ActiveSettings.h"
#include "config/CemuConfig.h"

#include "IOSGraphicPackBridge.h"

#include <algorithm>
#include <cstdio>
#include <fstream>
#include <set>
#include <sstream>
#include <unordered_map>

// main.cpp
extern "C" bool CemuIsInitialized();

namespace
{
constexpr char kRecordSep = '\x1E';
constexpr char kFieldSep = '\x1F';
constexpr char kGroupSep = '\x1D';

// What a pack's folder says about which renderers it can work with, read from the files
// themselves because GraphicPack2 keeps the renderer and vendor filters private.
struct PackFacts
{
	std::string rendererFilter; // "" (any), "vulkan", "opengl", "metal"
	std::string vendorFilter;   // "" (any), "apple", "amd", ...
	bool glslShaders = false;   // <hash>_<hash>_ps|vs|gs.txt - written for OpenGL/Vulkan
	bool mslShaders = false;    // <hash>_<hash>_ps|vs|gs_msl.txt - written for Metal
	bool outputGlsl = false;    // output.glsl / upscaling.glsl / downscaling.glsl
};

std::unordered_map<std::string, PackFacts> s_facts; // keyed by normalized rules path
bool s_environmentPrepared = false;

std::string Clean(std::string s)
{
	for (char& c : s)
	{
		if (c == kGroupSep || c == kRecordSep || c == kFieldSep)
			c = ' ';
	}
	return s;
}

std::string Lower(std::string s)
{
	for (char& c : s)
		c = (char)tolower((unsigned char)c);
	return s;
}

bool IsHex(const std::string& s, size_t from, size_t to)
{
	if (to <= from)
		return false;
	for (size_t i = from; i < to; i++)
	{
		if (!isxdigit((unsigned char)s[i]))
			return false;
	}
	return true;
}

// <hex>_<hex>_<type>... with type starting ps, vs or gs. Mirrors GraphicPack2::LoadShaders().
// Sets isMsl when the type is followed by "_msl".
bool ParseShaderFileName(const std::string& name, bool& isMsl)
{
	const size_t a = name.find('_');
	if (a == std::string::npos || !IsHex(name, 0, a))
		return false;
	const size_t b = name.find('_', a + 1);
	if (b == std::string::npos || !IsHex(name, a + 1, b))
		return false;
	const std::string type = name.substr(b + 1);
	if (type.size() < 2)
		return false;
	if (!((type[0] == 'p' || type[0] == 'v' || type[0] == 'g') && type[1] == 's'))
		return false;
	isMsl = type.size() >= 6 && type.compare(2, 4, "_msl") == 0;
	return true;
}

PackFacts ScanPack(const fs::path& rulesPath)
{
	PackFacts facts;
	std::error_code ec;

	// [Definition] only: stop at the next section header.
	if (std::ifstream rules{rulesPath})
	{
		std::string line;
		bool inDefinition = false;
		while (std::getline(rules, line))
		{
			const size_t start = line.find_first_not_of(" \t\r\n");
			if (start == std::string::npos)
				continue;
			line = line.substr(start);
			if (line[0] == '[')
			{
				if (inDefinition)
					break;
				inDefinition = Lower(line).rfind("[definition]", 0) == 0;
				continue;
			}
			if (!inDefinition)
				continue;
			const size_t eq = line.find('=');
			if (eq == std::string::npos)
				continue;
			auto trim = [](std::string v) {
				const size_t s = v.find_first_not_of(" \t\r\n\"");
				const size_t e = v.find_last_not_of(" \t\r\n\"");
				return s == std::string::npos ? std::string() : v.substr(s, e - s + 1);
			};
			const std::string key = Lower(trim(line.substr(0, eq)));
			if (key == "rendererfilter")
				facts.rendererFilter = Lower(trim(line.substr(eq + 1)));
			else if (key == "vendorfilter")
				facts.vendorFilter = Lower(trim(line.substr(eq + 1)));
		}
	}

	// Shader files sit next to rules.txt (GraphicPack2::LoadShaders() does not recurse).
	for (fs::directory_iterator it(rulesPath.parent_path(), ec), end; !ec && it != end; it.increment(ec))
	{
		if (!it->is_regular_file(ec))
			continue;
		const std::string name = _pathToUtf8(it->path().filename());
		bool isMsl = false;
		if (ParseShaderFileName(name, isMsl))
		{
			if (isMsl)
				facts.mslShaders = true;
			else
				facts.glslShaders = true;
		}
		else if (name == "output.glsl" || name == "upscaling.glsl" || name == "downscaling.glsl")
			facts.outputGlsl = true;
	}
	return facts;
}

const PackFacts& FactsFor(const GraphicPackPtr& pack)
{
	const std::string key = pack->GetNormalizedPathString();
	auto it = s_facts.find(key);
	if (it == s_facts.end())
		it = s_facts.emplace(key, ScanPack(pack->GetRulesPath())).first;
	return it->second;
}

GraphicPackPtr FindPack(const char* normalizedPath)
{
	if (!normalizedPath)
		return nullptr;
	const std::string wanted(normalizedPath);
	for (const auto& pack : GraphicPack2::GetGraphicPacks())
	{
		if (pack->GetNormalizedPathString() == wanted)
			return pack;
	}
	return nullptr;
}

// Rewrites the pack's config entry from its live state, in the shape LoadGraphicPack()
// reads back: an entry that exists is enabled unless it holds "_disabled", and every other
// key is <category, active preset>. A disabled pack that defaults off and has no chosen
// preset needs no entry at all - absence already means disabled.
void PersistPack(const GraphicPackPtr& pack)
{
	auto& entries = GetConfigHandle().data().graphic_pack_entries;
	entries.erase(pack->GetRulesPath().lexically_normal()); // legacy absolute-path key
	const auto key = _utf8ToPath(pack->GetNormalizedPathString());
	entries.erase(key);

	std::unordered_map<std::string, std::string> entry;
	for (const auto& preset : pack->GetPresets())
	{
		if (preset->active)
			entry[preset->category] = preset->name;
	}

	if (pack->IsEnabled())
	{
		entries[key] = std::move(entry);
	}
	else if (pack->IsDefaultEnabled() || !entry.empty())
	{
		entry["_disabled"] = "true";
		entries[key] = std::move(entry);
	}
	GetConfigHandle().Save();
}

bool EnsureEnvironment(const char* mlcPath)
{
	if (CemuIsInitialized() || s_environmentPrepared)
		return true;
	if (!mlcPath || !mlcPath[0])
		return false;
	const fs::path userData(mlcPath);
	std::set<fs::path> failedAccess;
	ActiveSettings::SetPaths(true, userData / "MuffinEMU", userData, userData, userData / "cache", userData, failedAccess);
	GetConfigHandle().SetFilename(ActiveSettings::GetConfigPath("config.xml").generic_wstring());
	GetConfigHandle().Load();
	s_environmentPrepared = true;
	return true;
}

bool EnvironmentReady()
{
	return CemuIsInitialized() || s_environmentPrepared;
}
} // namespace

// ---------------------------------------------------------------------------
// Older index-based surface, still called from CemuBridge.mm.

// Field separator (0x1F) between a record's fields, record separator (0x1E) between
// packs, title IDs comma-joined within their own field.
std::string IOSGraphicPacks_List()
{
	std::ostringstream out;
	const auto& packs = GraphicPack2::GetGraphicPacks();
	for (size_t i = 0; i < packs.size(); i++)
	{
		if (i != 0)
			out << kRecordSep;
		const auto& pack = packs[i];
		out << i << kFieldSep << Clean(pack->GetName()) << kFieldSep << Clean(pack->GetDescription()) << kFieldSep
			<< (pack->IsEnabled() ? '1' : '0') << kFieldSep;
		const auto& titleIds = pack->GetTitleIds();
		for (size_t j = 0; j < titleIds.size(); j++)
		{
			if (j != 0)
				out << ',';
			char buf[17];
			snprintf(buf, sizeof(buf), "%016llx", (unsigned long long)titleIds[j]);
			out << buf;
		}
	}
	return out.str();
}

// No-op (not an error) while a title is running - GraphicPack2 isn't safe to reload out
// from under an active emulation session.
void IOSGraphicPacks_Refresh()
{
	if (CafeSystem::IsTitleRunning() || !EnvironmentReady())
		return;
	GraphicPack2::ClearGraphicPacks();
	GraphicPack2::LoadAll();
	s_facts.clear();
}

void IOSGraphicPacks_SetEnabled(int index, bool enabled)
{
	const auto& packs = GraphicPack2::GetGraphicPacks();
	if (index < 0 || (size_t)index >= packs.size() || CafeSystem::IsTitleRunning())
		return;
	const auto& pack = packs[(size_t)index];
	pack->SetEnabled(enabled);
	if (enabled)
		pack->ValidatePresetSelections();
	PersistPack(pack);
}

// ---------------------------------------------------------------------------
// Path-keyed surface used by GraphicPackStore.swift and GraphicPacksView.swift.

extern "C"
{

bool muffin_gp_title_running(void)
{
	return CafeSystem::IsTitleRunning();
}

bool muffin_gp_reload(const char* mlcPath)
{
	if (CafeSystem::IsTitleRunning())
		return false;
	if (!EnsureEnvironment(mlcPath))
		return false;
	GraphicPack2::ClearGraphicPacks();
	GraphicPack2::LoadAll();
	s_facts.clear();
	return true;
}

const char* muffin_gp_list(void)
{
	static thread_local std::string result;
	std::ostringstream out;
	if (EnvironmentReady())
	{
		bool first = true;
		for (const auto& pack : GraphicPack2::GetGraphicPacks())
		{
			const PackFacts& facts = FactsFor(pack);
			if (!first)
				out << kRecordSep;
			first = false;
			out << Clean(pack->GetNormalizedPathString()) << kFieldSep
				<< Clean(pack->GetName()) << kFieldSep
				<< Clean(pack->GetVirtualPath()) << kFieldSep
				<< (pack->IsEnabled() ? '1' : '0') << kFieldSep
				<< (pack->IsDefaultEnabled() ? '1' : '0') << kFieldSep
				<< (pack->IsUniversal() ? '1' : '0') << kFieldSep
				<< pack->GetVersion() << kFieldSep;
			const auto& titleIds = pack->GetTitleIds();
			for (size_t j = 0; j < titleIds.size(); j++)
			{
				if (j != 0)
					out << ',';
				char buf[17];
				snprintf(buf, sizeof(buf), "%016llx", (unsigned long long)titleIds[j]);
				out << buf;
			}
			std::string brief = pack->GetDescription();
			std::replace(brief.begin(), brief.end(), '\n', ' ');
			if (brief.size() > 140)
				brief.resize(140);
			out << kFieldSep << Clean(facts.rendererFilter) << kFieldSep << Clean(facts.vendorFilter) << kFieldSep
				<< (facts.glslShaders ? '1' : '0') << kFieldSep
				<< (facts.mslShaders ? '1' : '0') << kFieldSep
				<< (facts.outputGlsl ? '1' : '0') << kFieldSep
				<< pack->GetPresets().size() << kFieldSep
				<< Clean(brief);
		}
	}
	result = out.str();
	return result.c_str();
}

// The full description, then 0x1D, then one record per preset:
// category, name, active, visible, default.
const char* muffin_gp_details(const char* packPath)
{
	static thread_local std::string result;
	std::ostringstream out;
	if (const auto pack = FindPack(packPath))
	{
		out << Clean(pack->GetDescription()) << kGroupSep;
		bool first = true;
		for (const auto& preset : pack->GetPresets())
		{
			if (!first)
				out << kRecordSep;
			first = false;
			out << Clean(preset->category) << kFieldSep << Clean(preset->name) << kFieldSep
				<< (preset->active ? '1' : '0') << kFieldSep << (preset->visible ? '1' : '0') << kFieldSep
				<< (preset->is_default ? '1' : '0');
		}
	}
	result = out.str();
	return result.c_str();
}

// Returns false, changing nothing, while a title is running: the running game was activated
// from these very objects, and the change is for the next launch anyway.
bool muffin_gp_set_enabled(const char* packPath, bool enabled)
{
	if (CafeSystem::IsTitleRunning())
		return false;
	const auto pack = FindPack(packPath);
	if (!pack)
		return false;
	pack->SetEnabled(enabled);
	if (enabled)
		pack->ValidatePresetSelections(); // a pack that is on always has its default presets chosen
	PersistPack(pack);
	return true;
}

bool muffin_gp_set_preset(const char* packPath, const char* category, const char* preset)
{
	if (CafeSystem::IsTitleRunning() || !category || !preset)
		return false;
	const auto pack = FindPack(packPath);
	if (!pack)
		return false;
	const bool ok = pack->SetActivePreset(category, preset); // also refreshes visibility and validates
	PersistPack(pack);
	return ok;
}

// Back to what the pack ships with: default on/off state and default presets.
bool muffin_gp_reset_pack(const char* packPath)
{
	if (CafeSystem::IsTitleRunning())
		return false;
	const auto pack = FindPack(packPath);
	if (!pack)
		return false;
	for (const auto& preset : pack->GetPresets())
		preset->active = false;
	pack->UpdatePresetVisibility();
	pack->ValidatePresetSelections();
	pack->SetEnabled(pack->IsDefaultEnabled());
	auto& entries = GetConfigHandle().data().graphic_pack_entries;
	entries.erase(pack->GetRulesPath().lexically_normal());
	entries.erase(_utf8ToPath(pack->GetNormalizedPathString()));
	GetConfigHandle().Save();
	return true;
}

} // extern "C"
