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

static std::atomic_bool sTitleListInitialized{false};

// Desktop Cemu does this in src/main.cpp's CemuCommonInit(), which the iOS app never
// runs - so the title list was simply never initialized here, and any launch path that
// resolves a title id had nothing to resolve against.
//
// No CafeTitleList::Refresh() on purpose. A refresh scans the MLC and any configured
// game paths on a background thread and writes title_list_cache.xml; the launch path
// below adds the one title being launched explicitly, so a scan buys nothing for a
// plain "boot this file" and would put an unbounded directory walk in front of every
// first launch. The cost is that updates and DLC already installed into Documents/mlc
// are not discovered, so a base game boots unpatched. That is a real limitation and it
// is deliberate for now, not an oversight.
void IOSTitleLaunch_InitializeTitleList()
{
	if (sTitleListInitialized.exchange(true))
		return;
	CafeTitleList::Initialize(ActiveSettings::GetUserDataPath("title_list_cache.xml"));
	fs::path mlcPath = ActiveSettings::GetMlcPath();
	if (!mlcPath.empty())
		CafeTitleList::SetMLCPath(mlcPath);
	cemuLog_log(LogType::Force, "iOS: title list initialized (mlc: {})", _pathToUtf8(mlcPath));
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

// Number of 128-bit keys currently readable from keys.txt, re-read on every call.
// Shown in Settings so an import is confirmed by the engine's own parser rather than by
// the file having been copied somewhere. KeyCache_GetAES128() returns nullptr past the
// end of the cache, which is the only count the key cache exposes.
int IOSTitleLaunch_ReloadAndCountKeys()
{
	KeyCache_Reload();
	sint32 count = 0;
	while (KeyCache_GetAES128(count) != nullptr)
		count++;
	cemuLog_log(LogType::Force, "iOS: keys.txt reloaded, {} key(s) available", count);
	return (int)count;
}
