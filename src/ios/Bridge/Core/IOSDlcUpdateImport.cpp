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
//   4. Is this actually a valid, complete title at all - and if not, specifically why
//      not, plus (when it is) its version and region for comparing against what's
//      already installed? (IOSDlcUpdateImport_Inspect)
#include "Cafe/TitleList/TitleInfo.h"
#include "Cafe/TitleList/TitleList.h"
#include "Cafe/TitleList/TitleId.h"
#include "Cemu/ncrypto/ncrypto.h"
#include "Common/FileStream.h"

#include <cstdio>
#include <memory>
#include <vector>

// Title ID straight out of a title.tmd, without decrypting anything. An encrypted game folder
// (title.tmd, title.tik and .app files) can be classified by it - high word 00050000 base,
// 0005000E update, 0005000C DLC - even when its ticket or keys are missing, which
// IOSDlcUpdateImport_DeriveTitleId (it has to mount the title) cannot do.
bool IOSDlcUpdateImport_ReadTmdTitleId(const char* tmdPath, uint64* titleIdOut)
{
	if (!tmdPath || tmdPath[0] == '\0' || !titleIdOut)
		return false;
	std::unique_ptr<FileStream> tmdFile(FileStream::openFile2(fs::path(tmdPath)));
	if (!tmdFile)
		return false;
	std::vector<uint8> tmdData;
	tmdFile->extract(tmdData);
	NCrypto::TMDParser parser;
	if (!parser.parse(tmdData.data(), tmdData.size()))
		return false;
	*titleIdOut = parser.getTitleId();
	return true;
}

static bool IOSDlcUpdateImport_DeriveTitleId_Impl(const char* romPath, uint64* titleIdOut)
{
	if (!romPath || romPath[0] == '\0' || !titleIdOut)
		return false;

	TitleInfo titleInfo{fs::path(romPath)};
	if (!titleInfo.IsValid() || !titleInfo.HasValidXmlInfo())
		return false;

	*titleIdOut = (uint64)titleInfo.GetAppTitleId();
	return true;
}

// One TitleInfo construction (real disk I/O + XML parsing) covering everything the
// import flow needs to either accept a candidate DLC/update or explain specifically
// why not - TitleInfo::InvalidReason already distinguishes "not a real Wii U title
// structure" from "the ticket is missing" from "the XML itself is unreadable", which
// gives a specific reason rather than a generic failure; nothing here invents new
// categories on top of what the engine already determined while parsing.
// Returns false (and only outInvalidReason) for an invalid title; true (and
// everything else, outInvalidReason left at NONE) for a valid one.
static bool IOSDlcUpdateImport_Inspect_Impl(const char* romPath, uint64* outTitleId, uint16* outVersion,
	int* outRegion, int* outInvalidReason)
{
	if (outInvalidReason)
		*outInvalidReason = 0; // TitleInfo::InvalidReason::NONE

	if (!romPath || romPath[0] == '\0')
	{
		if (outInvalidReason)
			*outInvalidReason = 1; // BAD_PATH_OR_INACCESSIBLE
		return false;
	}

	TitleInfo titleInfo{fs::path(romPath)};
	if (!titleInfo.IsValid())
	{
		if (outInvalidReason)
			*outInvalidReason = (int)titleInfo.GetInvalidReason();
		return false;
	}
	if (!titleInfo.HasValidXmlInfo())
	{
		if (outInvalidReason)
			*outInvalidReason = (int)TitleInfo::InvalidReason::MISSING_XML_FILES;
		return false;
	}

	if (outTitleId)
		*outTitleId = (uint64)titleInfo.GetAppTitleId();
	if (outVersion)
		*outVersion = titleInfo.GetAppTitleVersion();
	if (outRegion)
		*outRegion = (int)titleInfo.GetMetaRegion();
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

// The reverse direction of IOSDlcUpdateImport_DeriveBaseTitleId - what would this
// base game's update or AOC title ID be, so removal can find it on disk without
// re-deriving it from a file that may no longer exist. Returns 0 (never a real Wii U
// title ID) if baseTitleId can't have the requested kind at all.
uint64 IOSDlcUpdateImport_DeriveContentTitleId(uint64 baseTitleId, bool isUpdate)
{
	TitleIdParser tip((TitleId)baseTitleId);
	if (isUpdate)
	{
		if (!tip.CanHaveSeparateUpdateTitleId())
			return 0;
		return (uint64)tip.GetSeparateUpdateTitleId();
	}
	// AOC/DLC - TitleIdParser only has a public helper for base->update, not base->AOC,
	// so this mirrors the one place engine code already computes that direction:
	// CafeTitleList::GetGameInfo()'s own "for now we assume there is a direct match of
	// ids" AOC lookup in TitleList.cpp.
	return baseTitleId | 0xC00000000ull;
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

// Same reason as IOSCoverArt.cpp: called from Swift, where an escaping exception ends the app.
bool IOSDlcUpdateImport_DeriveTitleId(const char* romPath, uint64* titleIdOut)
{
	try
	{
		return IOSDlcUpdateImport_DeriveTitleId_Impl(romPath, titleIdOut);
	}
	catch (...)
	{
		return false;
	}
}

bool IOSDlcUpdateImport_Inspect(const char* romPath, uint64* outTitleId, uint16* outVersion,
	int* outRegion, int* outInvalidReason)
{
	try
	{
		return IOSDlcUpdateImport_Inspect_Impl(romPath, outTitleId, outVersion, outRegion, outInvalidReason);
	}
	catch (...)
	{
		if (outInvalidReason)
			*outInvalidReason = (int)TitleInfo::InvalidReason::UNKNOWN_FORMAT;
		return false;
	}
}
