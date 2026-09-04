// Title-ID identification and base-game matching for DLC/update import.
//
// Every piece of this is already correct and working in the shared engine -
// TitleIdParser's type byte, CafeTitleList::FindBaseTitleId's base-title derivation for
// both update and AOC, the code/content/meta MLC layout CafeTitleList::ScanMLCPath
// already scans for. Nothing here reimplements that; it only exposes the three pieces
// of it the iOS import UI needs to answer "what is this file, and which of my installed
// games does it belong to":
//
//   1. What title ID does this dump actually have? (IOSDlcUpdateImport_DeriveTitleId)
//   2. What base title ID does that resolve to? (IOSDlcUpdateImport_DeriveBaseTitleId,
//      a thin wrapper over CafeTitleList::FindBaseTitleId - pure title-ID math, no
//      scanning, so it's safe to call before CafeTitleList::Initialize() has run)
//   3. What TYPE of title is this - actually a DLC, actually an update, or something
//      else entirely? (IOSDlcUpdateImport_GetTitleType) - this is what lets the import
//      flow say "that's an update, not DLC" instead of silently accepting anything.
#include "Cafe/TitleList/TitleInfo.h"
#include "Cafe/TitleList/TitleList.h"
#include "Cafe/TitleList/TitleId.h"

#include <cstdio>

bool IOSDlcUpdateImport_DeriveTitleId(const char* romPath, uint64* titleIdOut)
{
	if (!romPath || romPath[0] == '\0' || !titleIdOut)
		return false;

	TitleInfo titleInfo{fs::path(romPath)};
	if (!titleInfo.IsValid() || !titleInfo.HasValidXmlInfo())
		return false;

	*titleIdOut = (uint64)titleInfo.GetAppTitleId();
	return true;
}

uint64 IOSDlcUpdateImport_DeriveBaseTitleId(uint64 titleId)
{
	TitleId baseTitleId;
	// FindBaseTitleId currently always returns true (see its own implementation) - the
	// bool is there for a scanning-based lookup it doesn't do yet, not a real failure
	// mode. Falling back to the input unchanged if that ever stops being true is safer
	// than propagating an uninitialized baseTitleId.
	if (!CafeTitleList::FindBaseTitleId((TitleId)titleId, baseTitleId))
		return titleId;
	return (uint64)baseTitleId;
}

// Writes the two path components CafeTitleList::ScanMLCPath expects under
// <mlc>/usr/title/ - the upper 32 bits of titleId as 8 lowercase hex chars (the
// type-prefix directory, e.g. "0005000c" for AOC), then the lower 32 bits the same
// way (the title's own directory, holding code/content/meta). Both buffers must be at
// least 9 bytes (8 chars plus the null terminator). ScanMLCPath's own hex check is
// case-insensitive, but lowercase matches how real Wii U dumps are named.
void IOSDlcUpdateImport_GetMlcTitlePathComponents(uint64 titleId, char* outUpperHex, char* outLowerHex)
{
	uint32 upper = (uint32)(titleId >> 32);
	uint32 lower = (uint32)(titleId & 0xFFFFFFFFu);
	snprintf(outUpperHex, 9, "%08x", upper);
	snprintf(outLowerHex, 9, "%08x", lower);
}

// Returns the raw TitleIdParser::TITLE_TYPE byte value directly (0x00 base, 0x0E
// update, 0x0C AOC/DLC, 0xFF unknown, etc.) rather than translating it into a separate
// iOS-side enum - TitleId.h's own enum is already the single source of truth for what
// these values mean, and re-encoding it here would just be a second place for the two
// to drift apart.
int IOSDlcUpdateImport_GetTitleType(uint64 titleId)
{
	TitleIdParser parser((TitleId)titleId);
	return (int)parser.GetType();
}
