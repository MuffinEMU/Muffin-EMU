// Graphic pack browsing and toggling for iOS - GraphicPack2 (Cafe/GraphicPack/) is a
// complete, working feature with real consumers (LatteToMtl.cpp, the shader cache) and
// had precisely zero iOS surface before this: nothing ever called LoadAll() here, so
// Documents/mlc/graphicPacks/ was never even scanned. Mirrors the shape Android's own
// NativeGraphicPacks.cpp already proved out (LoadAll -> list -> per-pack SetEnabled,
// persisted into the same graphic_pack_entries config GraphicPack2::LoadGraphicPack
// already reads back on the next LoadAll) rather than inventing a different one.
//
// Presets are out of scope here - a pack activates with whatever preset was already
// selected/default, but there is no iOS UI yet to change which one. That is a real,
// deliberate gap, not an oversight: presets are a second dimension of complexity this
// pass didn't need to take on to make packs usable at all.
#include "Cafe/CafeSystem.h"
#include "Cafe/GraphicPack/GraphicPack2.h"
#include "config/CemuConfig.h"

#include <cstdio>
#include <sstream>

// Field separator (0x1F) between a record's fields, record separator (0x1E) between
// packs, title IDs comma-joined within their own field - title IDs and pack
// names/descriptions can't contain either control character, so this needs no escaping.
std::string IOSGraphicPacks_List()
{
	std::ostringstream out;
	const auto& packs = GraphicPack2::GetGraphicPacks();
	for (size_t i = 0; i < packs.size(); i++)
	{
		if (i != 0)
			out << '\x1E';
		const auto& pack = packs[i];
		out << i << '\x1F' << pack->GetName() << '\x1F' << pack->GetDescription() << '\x1F'
			<< (pack->IsEnabled() ? '1' : '0') << '\x1F';
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

// No-op (not an error) while a title is running, same guard Android's own refresh uses -
// GraphicPack2 isn't safe to reload out from under an active emulation session, and this
// UI has no reason to be reachable mid-game anyway.
void IOSGraphicPacks_Refresh()
{
	if (CafeSystem::IsTitleRunning())
		return;
	GraphicPack2::ClearGraphicPacks();
	GraphicPack2::LoadAll();
}

void IOSGraphicPacks_SetEnabled(int index, bool enabled)
{
	const auto& packs = GraphicPack2::GetGraphicPacks();
	if (index < 0 || (size_t)index >= packs.size())
		return;
	const auto& pack = packs[(size_t)index];
	pack->SetEnabled(enabled);

	// Same persistence shape GraphicPack2::LoadGraphicPack already reads back: an
	// "_disabled" marker for an off pack that defaults on, an empty entry (present at
	// all = enabled) otherwise, nothing written for an off pack that defaults off -
	// matching Android's SaveGraphicPackStateToConfig exactly, since LoadGraphicPack
	// doesn't distinguish who wrote the entry.
	auto& data = GetConfigHandle().data();
	auto filename = _utf8ToPath(pack->GetNormalizedPathString());
	data.graphic_pack_entries.erase(filename);
	if (enabled)
	{
		data.graphic_pack_entries.try_emplace(filename);
	}
	else if (pack->IsDefaultEnabled())
	{
		auto& entry = data.graphic_pack_entries.try_emplace(filename).first->second;
		entry.try_emplace("_disabled", "false");
	}
	GetConfigHandle().Save();
}
