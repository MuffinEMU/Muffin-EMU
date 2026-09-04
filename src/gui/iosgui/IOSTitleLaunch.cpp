// Real-title launch path for iOS.
//
// Until now the iOS bridge had exactly one way to start anything:
// CafeSystem::PrepareForegroundTitleFromStandaloneRPX(). That is the fallback path
// upstream Cemu uses for a loose executable with "incorrect layout or missing meta
// files" - fine for helloworld.rpx, and incapable of booting a real game. A .wux/.wud
// is an encrypted disc image: it has to be opened through FSTVolume (which finds the
// right AES-128 key in the key cache), registered as a title, and launched by title id
// via CafeSystem::PrepareForegroundTitle(). The picker and the importer have accepted
// .wux/.wud/.wua/.iso for a while; this is the part that was missing behind them.
//
// Keys are the user's own and are never shipped, derived or guessed. Cemu reads them
// from keys.txt in the user data directory (Documents/mlc/keys.txt on iOS) - dumped
// from the console the user owns - and FSTVolume::FindDiscKey() simply tries each one
// against the disc header until a decrypt comes out as zeroes. With no keys.txt, or
// with keys that do not match, nothing here can open a disc image, and the boot fails
// with a reason that says exactly that instead of a black screen. Homebrew (.rpx) is
// unaffected and still needs no keys at all.
//
// Why this lives here and not in CemuBridge.mm: the bridge is compiled by Xcode
// directly, and TitleInfo.h/TitleList.h pull in pugixml, ZArchive and the config stack.
// The same reasoning already applied to IOSInput_* and IOSWindowSystem_GetLastFPS() -
// keep anything header-heavy inside the CMake build, which already has those include
// paths and the precompiled header, and expose a flat function the bridge can declare
// in one line.
#include "Cafe/CafeSystem.h"
#include "Cafe/TitleList/TitleInfo.h"
#include "Cafe/TitleList/TitleList.h"
#include "Cafe/Filesystem/FST/KeyCache.h"
#include "Cafe/GraphicPack/GraphicPack2.h"
#include "config/ActiveSettings.h"
#include "Cemu/Logging/CemuLogging.h"

#include <atomic>
#include <filesystem>
#include <string>

// Mirrored 1:1 by CemuBridgeStatus in src/ios/Bridge/CemuBridge.h. Plain ints across
// the boundary so neither side has to include the other's header.
enum
{
	IOS_TITLE_LAUNCH_OK = 0,
	IOS_TITLE_LAUNCH_INVALID_RPX = 1,
	IOS_TITLE_LAUNCH_UNABLE_TO_MOUNT = 2,
	IOS_TITLE_LAUNCH_NO_DISC_KEY = 3,
	IOS_TITLE_LAUNCH_NO_TITLE_TIK = 4,
	IOS_TITLE_LAUNCH_UNSUPPORTED_FORMAT = 5,
	IOS_TITLE_LAUNCH_BASE_NOT_FOUND = 6,
};

// Defined below, next to the rest of the key handling. Declared here because the
// launch path above it calls it too.
static void IOSTitleLaunch_AdoptDroppedKeys();

static std::atomic_bool sTitleListInitialized{false};

// Desktop Cemu does this in src/main.cpp's CemuCommonInit(), which the iOS app never
// runs - so the title list was simply never initialized here, and any launch path that
// resolves a title id had nothing to resolve against.
//
// No CafeTitleList::Refresh() on purpose. A refresh scans the MLC and any configured
// game paths on a background thread and writes title_list_cache.xml; the launch path
// below adds the one title being launched explicitly, so a full scan buys nothing for a
// plain "boot this file" and would put an unbounded directory walk (over every configured
// ROM path) in front of every first launch. Updates and DLC installed into Documents/mlc
// ARE discovered despite that - see CafeTitleList::ScanMLCUsrTitleOnly(), called below
// right before the title launches, which is the one part of a full Refresh() that stays
// cheap regardless of how large the ROM library is (it only walks usr/title, which holds
// just the user's own installed titles).
void IOSTitleLaunch_InitializeTitleList()
{
	if (sTitleListInitialized.exchange(true))
		return;
	CafeTitleList::Initialize(ActiveSettings::GetUserDataPath("title_list_cache.xml"));
	fs::path mlcPath = ActiveSettings::GetMlcPath();
	if (!mlcPath.empty())
		CafeTitleList::SetMLCPath(mlcPath);
	cemuLog_log(LogType::Force, "iOS: title list initialized (mlc: {})", _pathToUtf8(mlcPath));

	// Nothing on iOS ever called this before - GraphicPack2::ActivateForCurrentTitle()
	// further down CafeSystem's own (shared, unconditional) boot path has always run
	// here too, it just always found an empty list, since GetGraphicPacks() has nothing
	// in it until LoadAll() has scanned Documents/mlc/graphicPacks/ at least once.
	GraphicPack2::LoadAll();
}

// Prepares whatever the user actually picked, mirroring the same decision tree the
// Android port uses (NativeEmulation.cpp prepareTitle) and the desktop GUI uses
// (MainWindow.cpp), rather than assuming everything is a standalone RPX.
//
// Does NOT launch - the caller does that, so it can log around it and so a failure here
// is reported before a title thread exists.
int IOSTitleLaunch_PrepareForegroundTitle(const char* pathStr)
{
	if (!pathStr || pathStr[0] == '\0')
		return IOS_TITLE_LAUNCH_UNSUPPORTED_FORMAT;
	fs::path launchPath = fs::path(pathStr);

	// Re-read keys.txt before touching the file. The key cache is one-shot, and on iOS
	// the user can import keys.txt from the Files app at any point - including after a
	// failed boot in this same session, which is precisely when they are most likely to.
	// The adopt step ahead of it is what makes a file dropped into Documents/keys/ count
	// as such an import, with no app relaunch in between.
	IOSTitleLaunch_AdoptDroppedKeys();
	KeyCache_Reload();
	IOSTitleLaunch_InitializeTitleList();

	TitleInfo launchTitle{launchPath};
	if (launchTitle.IsValid())
	{
		// The title is not in the list (nothing scans for it), so add it as a temporary
		// entry, then launch by base title id.
		CafeTitleList::AddTitleFromPath(launchPath);
		TitleId baseTitleId;
		if (!CafeTitleList::FindBaseTitleId(launchTitle.GetAppTitleId(), baseTitleId))
		{
			cemuLog_log(LogType::Force, "iOS: no base title found for {:016x} - an update or DLC was launched without its base game", (uint64)launchTitle.GetAppTitleId());
			return IOS_TITLE_LAUNCH_BASE_NOT_FOUND;
		}
		// Picks up anything DlcUpdateImport.swift has installed into Documents/mlc since
		// the title list was last populated - bounded to usr/title alone (see
		// ScanMLCUsrTitleOnly's own comment), so this is the one piece of the Refresh()
		// this file otherwise deliberately skips that is cheap enough to always do. Without
		// this, CafeSystem::PrepareForegroundTitle below builds its GameInfo2 from
		// whatever CafeTitleList::AddTitleFromPath just added above (the base game only)
		// and boots unpatched even when an update/DLC is sitting right there on disk.
		CafeTitleList::ScanMLCUsrTitleOnly();
		cemuLog_log(LogType::Force, "iOS: launching real title {:016x} from {}", (uint64)baseTitleId, _pathToUtf8(launchPath));
		CafeSystem::PREPARE_STATUS_CODE r = CafeSystem::PrepareForegroundTitle(baseTitleId);
		switch (r)
		{
		case CafeSystem::PREPARE_STATUS_CODE::SUCCESS:
			return IOS_TITLE_LAUNCH_OK;
		case CafeSystem::PREPARE_STATUS_CODE::INVALID_RPX:
			return IOS_TITLE_LAUNCH_INVALID_RPX;
		default:
			return IOS_TITLE_LAUNCH_UNABLE_TO_MOUNT;
		}
	}

	// Not a title. An RPX/ELF is still launchable on its own - that is the homebrew
	// path, and helloworld.rpx goes through here exactly as it always has. Anything else
	// is an error, and the invalid reason is the only thing that can tell the user
	// whether the file is unreadable, unrecognised, or simply locked without their keys.
	CafeTitleFileType fileType = DetermineCafeSystemFileType(launchPath);
	if (fileType == CafeTitleFileType::RPX || fileType == CafeTitleFileType::ELF)
	{
		cemuLog_log(LogType::Force, "iOS: launching standalone executable {}", _pathToUtf8(launchPath));
		CafeSystem::PREPARE_STATUS_CODE r = CafeSystem::PrepareForegroundTitleFromStandaloneRPX(launchPath);
		switch (r)
		{
		case CafeSystem::PREPARE_STATUS_CODE::SUCCESS:
			return IOS_TITLE_LAUNCH_OK;
		case CafeSystem::PREPARE_STATUS_CODE::INVALID_RPX:
			return IOS_TITLE_LAUNCH_INVALID_RPX;
		default:
			return IOS_TITLE_LAUNCH_UNABLE_TO_MOUNT;
		}
	}

	switch (launchTitle.GetInvalidReason())
	{
	case TitleInfo::InvalidReason::NO_DISC_KEY:
		cemuLog_log(LogType::Force, "iOS: {} is an encrypted disc image and no key in keys.txt decrypts it", _pathToUtf8(launchPath));
		return IOS_TITLE_LAUNCH_NO_DISC_KEY;
	case TitleInfo::InvalidReason::NO_TITLE_TIK:
		cemuLog_log(LogType::Force, "iOS: {} has no usable title.tik", _pathToUtf8(launchPath));
		return IOS_TITLE_LAUNCH_NO_TITLE_TIK;
	default:
		cemuLog_log(LogType::Force, "iOS: {} is not a title this build can launch (invalid reason {})", _pathToUtf8(launchPath), (int)launchTitle.GetInvalidReason());
		return IOS_TITLE_LAUNCH_UNSUPPORTED_FORMAT;
	}
}

// Adopt a keys.txt the user dropped into Documents/keys/.
//
// The engine reads keys from ActiveSettings::GetUserDataPath("keys.txt"), which on iOS
// resolves to Documents/mlc/keys.txt. That path is correct for the engine and useless
// as an instruction to a person: mlc is the emulated console's storage and is full of
// engine state, so "put your keys in there" means picking the right directory out of a
// pile. Documents/keys/ exists so there is exactly one plainly named folder, visible in
// Files.app via UIFileSharingEnabled, whose only job is to receive keys.txt.
//
// Adopted by copying rather than by repointing the engine, because KeyCache_Prepare()
// builds its path from GetUserDataPath() in code shared with every other platform.
// Copying keeps that untouched and is free in practice - a keys.txt is a few hundred
// bytes. Doing it immediately before every key read (rather than once at startup) is
// what makes a file dropped mid-session work without relaunching the app, which is the
// same reason KeyCache_Reload() is called on every launch attempt.
//
// The drop folder wins when both files exist: it is the one the user can see and edit,
// so it is the one their last action was performed on. When only the engine copy exists
// - a keys.txt imported through Settings before this folder existed - it is seeded into
// the drop folder instead, so those keys become visible rather than silently staying in
// mlc. After that first seed the drop file always exists and the drop folder wins from
// then on, so the two rules cannot ping-pong.
static void IOSTitleLaunch_AdoptDroppedKeys()
{
	std::error_code ec;

	const fs::path engineKeys = ActiveSettings::GetUserDataPath("keys.txt");
	// Documents/mlc -> Documents. cemu_bridge_initialize() sets the user data path to
	// the app's Documents/mlc, so its parent is the Documents root Files.app exposes.
	const fs::path userDataRoot = ActiveSettings::GetUserDataPath();
	if (userDataRoot.empty())
		return;
	const fs::path dropDir = userDataRoot.parent_path() / "keys";
	const fs::path dropKeys = dropDir / "keys.txt";

	// Created even while empty, and on every call rather than once: an empty folder in
	// Files.app is itself the instruction for how to install keys, a folder that only
	// appears once keys exist is one nobody can drop keys into, and a user who deletes
	// it from Files.app should get it back rather than lose the mechanism.
	fs::create_directories(dropDir, ec);
	if (ec)
	{
		cemuLog_log(LogType::Force, "iOS: could not create the keys drop folder ({})", ec.message());
		return;
	}

	std::error_code dropEc, engineEc;
	const bool haveDrop = fs::is_regular_file(dropKeys, dropEc);
	const bool haveEngine = fs::is_regular_file(engineKeys, engineEc);
	if (!haveDrop && !haveEngine)
		return; // nothing to adopt yet - but the folder now exists to be dropped into

	const fs::path& from = haveDrop ? dropKeys : engineKeys;
	const fs::path& to = haveDrop ? engineKeys : dropKeys;

	// Skip a copy that would change nothing. Not a micro-optimisation: this runs before
	// every launch attempt, and rewriting the file the engine is about to read - and its
	// mtime with it - on every boot is worth not doing. Separate error_codes because a
	// later successful call clears a shared one, which would hide the earlier failure.
	if (haveDrop && haveEngine)
	{
		std::error_code fromSizeEc, toSizeEc, fromTimeEc, toTimeEc;
		const auto fromSize = fs::file_size(from, fromSizeEc);
		const auto toSize = fs::file_size(to, toSizeEc);
		const auto fromTime = fs::last_write_time(from, fromTimeEc);
		const auto toTime = fs::last_write_time(to, toTimeEc);
		if (!fromSizeEc && !toSizeEc && !fromTimeEc && !toTimeEc
			&& fromSize == toSize && fromTime <= toTime)
			return;
	}

	ec.clear();
	fs::copy_file(from, to, fs::copy_options::overwrite_existing, ec);
	if (ec)
		cemuLog_log(LogType::Force, "iOS: could not adopt keys.txt from {} ({})", _pathToUtf8(from), ec.message());
	else
		cemuLog_log(LogType::Force, "iOS: adopted keys.txt from {}", _pathToUtf8(from));
}

// Number of 128-bit keys currently readable from keys.txt, re-read on every call.
// Shown in Settings so an import is confirmed by the engine's own parser rather than by
// the file having been copied somewhere. KeyCache_GetAES128() returns nullptr past the
// end of the cache, which is the only count the key cache exposes.
int IOSTitleLaunch_ReloadAndCountKeys()
{
	IOSTitleLaunch_AdoptDroppedKeys();
	KeyCache_Reload();
	sint32 count = 0;
	while (KeyCache_GetAES128(count) != nullptr)
		count++;
	cemuLog_log(LogType::Force, "iOS: keys.txt reloaded, {} key(s) available", count);
	return (int)count;
}
