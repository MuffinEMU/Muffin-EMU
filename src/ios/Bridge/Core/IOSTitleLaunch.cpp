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
// Kept in its own file rather than inside CemuBridge.mm so the launch decision tree reads
// on its own; both are compiled into Cemu.framework by CMake, next to the core.
#include "Cafe/CafeSystem.h"
#include "Cafe/TitleList/TitleInfo.h"
#include "Cafe/TitleList/TitleList.h"
#include "Cafe/Filesystem/FST/KeyCache.h"
#include "Cafe/Filesystem/FST/FST.h"
#include <cctype>
#include <fstream>
#include <thread>
#include <chrono>
#include "Cafe/GraphicPack/GraphicPack2.h"
#include "config/ActiveSettings.h"
#include "Cemu/Logging/CemuLogging.h"

#include <atomic>
#include <filesystem>
#include <iterator>
#include <string>
#include <vector>

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
	// Encrypted game folder (title.tmd, title.tik and .app files) that could not be opened
	IOS_TITLE_LAUNCH_BAD_TITLE_TMD = 7,
	IOS_TITLE_LAUNCH_BAD_TITLE_TIK = 8,
	IOS_TITLE_LAUNCH_TITLE_KEY_INVALID = 9,
	IOS_TITLE_LAUNCH_MISSING_CONTENT_FILE = 10,
	IOS_TITLE_LAUNCH_TITLE_NOT_INSTALLED = 11,
};

// Extra detail for the last failure, e.g. the name of the missing .app file. Read by the
// bridge right after IOSTitleLaunch_PrepareForegroundTitle() returns, on the same thread.
static thread_local std::string sLastLaunchDetail;

const char* IOSTitleLaunch_LastErrorDetail()
{
	return sLastLaunchDetail.c_str();
}

// Defined in IOSDlcUpdateImport.cpp
bool IOSDlcUpdateImport_ReadTmdTitleId(const char* tmdPath, uint64* titleIdOut);
uint64 IOSDlcUpdateImport_DeriveBaseTitleId(uint64 titleId);

// Defined below, next to the rest of the key handling. Declared here because the
// launch path above it calls it too.
static void IOSTitleLaunch_AdoptDroppedKeys();

static std::atomic_bool sTitleListInitialized{false};

void IOSTitleLaunch_InitializeTitleList()
{
	if (sTitleListInitialized.exchange(true))
		return;
	// The core's CemuInitialize() already runs CafeTitleList::Initialize(), SetMLCPath(),
	// Refresh() and GraphicPack2::LoadAll(), in that order, before any launch can reach
	// this file. Initializing the title list a second time would reset it under the scan
	// that call started, so this only records where the list is rooted.
	cemuLog_log(LogType::Force, "iOS: title list already initialized by the core (mlc: {})", _pathToUtf8(ActiveSettings::GetMlcPath()));
}

// The core has no MLC-only rescan, so this is a full CafeTitleList::Refresh() with a
// bounded wait. Refresh() is asynchronous; waiting for it here is what makes an update or
// DLC that DlcUpdateImport.swift installed moments ago part of the GameInfo that
// PrepareForegroundTitle() builds. The cap keeps a huge library from holding a launch
// hostage: past it the title boots with whatever the scan has found so far and says so.
static void IOSTitleLaunch_RescanInstalledContent(int maxSeconds = 10)
{
	CafeTitleList::Refresh();
	const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(maxSeconds);
	while (CafeTitleList::IsScanning())
	{
		if (std::chrono::steady_clock::now() >= deadline)
		{
			cemuLog_log(LogType::Force, "iOS: title rescan still running after {}s - launching with the titles found so far", maxSeconds);
			return;
		}
		std::this_thread::sleep_for(std::chrono::milliseconds(50));
	}
}

// ---------------------------------------------------------------------------
// Wii U Menu
//
// The Menu (0005001010040000 JPN / ...0100 USA / ...0200 EUR) is a system title. It lives
// in the MLC (Documents/mlc/mlc01/sys/title/00050010/10040X00), which CafeTitleList's own
// scan already covers, and it starts games by title id through coreinit rather than by
// path. The pieces it needs beside the title itself: the shared data in
// sys/title/0005001b (fonts, Mii data), and the console's cafeLibs (Documents/mlc/cafeLibs,
// read by rpl.cpp). otp.bin and seeprom.bin are only needed for online features. All of
// them come from the user's own console; none is bundled or fetched.
static bool IOSTitleLaunch_IsWiiUMenuTitleId(uint64 titleId)
{
	return titleId == 0x0005001010040000ull || titleId == 0x0005001010040100ull || titleId == 0x0005001010040200ull;
}

// Games the Menu can launch are the titles in the core's list. On iOS the list is built from
// the MLC only (CemuInitialize adds no game paths), so a game living in Documents/Roms - which
// is where every imported game lives - would be invisible to the Menu. While the Menu is what
// the user launched, Documents/Roms is a scan path; it is dropped again when an ordinary
// title launches, so the rescan that launch does stays as cheap as it was.
static bool sMenuScanPathActive{false};

static void IOSTitleLaunch_ExposeRomsToTheMenu()
{
	if (sMenuScanPathActive)
		return;
	const fs::path userData = ActiveSettings::GetUserDataPath();
	if (userData.empty())
		return;
	const fs::path roms = userData.parent_path() / "Roms";
	CafeTitleList::AddScanPath(roms);
	sMenuScanPathActive = true;
	cemuLog_log(LogType::Force, "iOS: Wii U Menu - {} added to the title list scan, so the Menu can list and launch those games", _pathToUtf8(roms));
}

static void IOSTitleLaunch_DropMenuScanPath()
{
	if (!sMenuScanPathActive)
		return;
	CafeTitleList::ClearScanPaths();
	sMenuScanPathActive = false;
}

// Says, in the log, what the Menu is going to be missing. It may still boot without any of
// these - the log is what turns a null-pointer crash seven seconds in into a known cause.
static void IOSTitleLaunch_LogMenuPreflight()
{
	std::error_code ec;
	const fs::path mlc = ActiveSettings::GetMlcPath();
	const fs::path userData = ActiveSettings::GetUserDataPath();
	if (!fs::exists(userData / "otp.bin", ec))
		cemuLog_log(LogType::Force, "iOS: Wii U Menu - otp.bin is missing (Documents/mlc/otp.bin); online features will not work, the Menu may still start");
	if (!fs::exists(userData / "seeprom.bin", ec))
		cemuLog_log(LogType::Force, "iOS: Wii U Menu - seeprom.bin is missing (Documents/mlc/seeprom.bin); online features will not work, the Menu may still start");
	if (!fs::is_directory(mlc / "sys/title/0005001b", ec))
		cemuLog_log(LogType::Force, "iOS: Wii U Menu - sys/title/0005001b (shared data: fonts, Mii) is missing from the MLC; the Menu is likely to crash without it");
	static const char* const cafeLibs[] = {"drmapp", "erreula", "nn_sl", "nsyskbd", "snd_user", "snduser2", "swkbd"};
	int missingLibs = 0;
	for (const char* lib : cafeLibs)
	{
		if (!fs::exists(userData / "cafeLibs" / (std::string(lib) + ".rpl"), ec))
			missingLibs++;
	}
	// Titles in sys/title that have code/content/meta folders but lack the XML files the core reads. The
	// core only warns ("Title has missing meta .xml files"); naming them here says which dump is bad.
	int incomplete = 0;
	for (auto& group : fs::directory_iterator(mlc / "sys/title", ec))
	{
		for (auto& title : fs::directory_iterator(group.path(), ec))
		{
			const fs::path dir = title.path();
			if (!fs::is_directory(dir / "code", ec) || !fs::is_directory(dir / "meta", ec))
				continue;
			if (fs::exists(dir / "code/app.xml", ec) && fs::exists(dir / "code/cos.xml", ec) && fs::exists(dir / "meta/meta.xml", ec))
				continue;
			if (++incomplete <= 8)
				cemuLog_log(LogType::Force, "iOS: Wii U Menu - system title {} is missing app.xml, cos.xml or meta.xml", _pathToUtf8(dir.lexically_relative(mlc)));
		}
	}
	if (incomplete > 8)
		cemuLog_log(LogType::Force, "iOS: Wii U Menu - and {} more incomplete system titles", incomplete - 8);
	if (missingLibs > 0)
		cemuLog_log(LogType::Force, "iOS: Wii U Menu - {} of {} cafeLibs .rpl files are missing from Documents/mlc/cafeLibs; the Menu will not work without them", missingLibs, (int)std::size(cafeLibs));
}

// Launches a title that is installed in the MLC by its title id - the Wii U Menu, mainly.
// Same contract as IOSTitleLaunch_PrepareForegroundTitle: prepares, does not launch.
int IOSTitleLaunch_PrepareForegroundTitleById(uint64 titleId)
{
	IOSTitleLaunch_AdoptDroppedKeys();
	KeyCache_Prepare();
	IOSTitleLaunch_InitializeTitleList();

	const bool isMenu = IOSTitleLaunch_IsWiiUMenuTitleId(titleId);
	if (isMenu)
	{
		IOSTitleLaunch_LogMenuPreflight();
		IOSTitleLaunch_ExposeRomsToTheMenu();
	}
	else
		IOSTitleLaunch_DropMenuScanPath();

	// sys/title first (system titles), then usr/title. Directory names are the two halves
	// of the title id in lower-case hex, the same layout the core's MLC scan expects.
	const std::string high = fmt::format("{:08x}", (uint32)(titleId >> 32));
	const std::string low = fmt::format("{:08x}", (uint32)(titleId & 0xFFFFFFFFull));
	const fs::path mlc = ActiveSettings::GetMlcPath();
	std::error_code ec;
	fs::path titleDir;
	for (const char* group : {"sys/title", "usr/title"})
	{
		const fs::path candidate = mlc / group / high / low;
		if (fs::is_directory(candidate / "code", ec))
		{
			titleDir = candidate;
			break;
		}
	}
	if (titleDir.empty())
	{
		cemuLog_log(LogType::Force, "iOS: title {:016x} is not installed in the MLC ({}/{{sys,usr}}/title/{}/{})", titleId, _pathToUtf8(mlc), high, low);
		return IOS_TITLE_LAUNCH_TITLE_NOT_INSTALLED;
	}

	// Ensure the list has it before anything depends on it: added explicitly, then a bounded
	// rescan (which also picks up the Roms scan path and anything imported a moment ago),
	// then added again in case the rescan dropped an entry it did not rediscover.
	CafeTitleList::AddTitleFromPath(titleDir);
	IOSTitleLaunch_RescanInstalledContent(isMenu ? 30 : 10);
	CafeTitleList::AddTitleFromPath(titleDir);

	TitleId baseTitleId;
	if (!CafeTitleList::FindBaseTitleId(titleId, baseTitleId))
		return IOS_TITLE_LAUNCH_BASE_NOT_FOUND;
	for (const fs::path& wua : IOSTitleLaunch_FindWuaCompanions(baseTitleId))
		CafeTitleList::AddTitleFromPath(wua);
	cemuLog_log(LogType::Force, "iOS: launching installed title {:016x} from {}", (uint64)baseTitleId, _pathToUtf8(titleDir));
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

// An update or DLC imported from a .wua is kept whole at <mlc>/wua-content/<base id>/, one file
// per kind. The core adds every title inside a .wua when the file is added by path, so they
// are added here next to the game, the same way the folder companions below are.
static std::vector<fs::path> IOSTitleLaunch_FindWuaCompanions(TitleId baseTitleId)
{
	std::vector<fs::path> found;
	const fs::path dir = ActiveSettings::GetMlcPath() / "wua-content" / fmt::format("{:016x}", (uint64)baseTitleId);
	std::error_code ec;
	for (const char* name : {"update.wua", "dlc.wua"})
	{
		const fs::path candidate = dir / name;
		if (fs::is_regular_file(candidate, ec))
			found.push_back(candidate);
	}
	return found;
}

// Encrypted game folders often come as a parent folder holding one subfolder each for the
// game, its update and its DLC, every one with its own title.tmd. The update and DLC are
// not in the MLC, so nothing would ever tell the core about them. They are found here by
// their title.tmd (title ID high word 0005000E update, 0005000C DLC, base ID must match) in
// the folders next to the game's folder and inside it, and added to the title list next to
// the game so PrepareForegroundTitle() builds its GameInfo with them.
static std::vector<fs::path> IOSTitleLaunch_FindCompanionTitles(const TitleInfo& base, TitleId baseTitleId)
{
	std::vector<fs::path> found;
	if (base.GetFormat() != TitleInfo::TitleDataFormat::NUS)
		return found;
	const fs::path baseFolder = base.GetPath().parent_path();
	std::vector<fs::path> searchRoots{baseFolder};
	if (baseFolder.has_parent_path() && baseFolder.parent_path() != baseFolder)
		searchRoots.push_back(baseFolder.parent_path());
	std::error_code ec;
	for (const fs::path& root : searchRoots)
	{
		for (auto& dir : fs::directory_iterator(root, ec))
		{
			if (!dir.is_directory(ec) || dir.path() == baseFolder)
				continue;
			fs::path tmdPath;
			for (auto& file : fs::directory_iterator(dir.path(), ec))
			{
				std::string name = _pathToUtf8(file.path().filename());
				for (auto& c : name)
					c = (char)std::tolower((unsigned char)c);
				if (name == "title.tmd")
				{
					tmdPath = file.path();
					break;
				}
			}
			if (tmdPath.empty())
				continue;
			uint64 tmdTitleId = 0;
			if (!IOSDlcUpdateImport_ReadTmdTitleId(_pathToUtf8(tmdPath).c_str(), &tmdTitleId))
				continue;
			const uint32 high = (uint32)(tmdTitleId >> 32);
			if (high != 0x0005000E && high != 0x0005000C)
				continue;
			if (IOSDlcUpdateImport_DeriveBaseTitleId(tmdTitleId) != (uint64)baseTitleId)
				continue;
			found.push_back(tmdPath);
		}
	}
	return found;
}

// Prepares whatever the user actually picked, mirroring the same decision tree the
// desktop GUI uses (MainWindow.cpp), rather than assuming everything is a standalone RPX.
//
// Does NOT launch - the caller does that, so it can log around it and so a failure here
// is reported before a title thread exists.
int IOSTitleLaunch_PrepareForegroundTitle(const char* pathStr)
{
	sLastLaunchDetail.clear();
	if (!pathStr || pathStr[0] == '\0')
		return IOS_TITLE_LAUNCH_UNSUPPORTED_FORMAT;
	fs::path launchPath = fs::path(pathStr);

	// Adopt a keys.txt dropped into Documents/keys/ before the key cache first reads it.
	IOSTitleLaunch_AdoptDroppedKeys();
	// The core's key cache is load-once (KeyCache_Prepare() latches after its first
	// read), so a keys.txt imported after the first launch attempt of a session is picked
	// up on the next app launch rather than this one. IOSTitleLaunch_ReloadAndCountKeys()
	// is what tells the user that, from the file itself.
	KeyCache_Prepare();
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
		// A Wii U Menu launched from a folder in Documents/Roms is still the Menu: it has to be
		// able to see the other games. An ordinary title drops that scan path again.
		if (IOSTitleLaunch_IsWiiUMenuTitleId((uint64)baseTitleId))
		{
			IOSTitleLaunch_LogMenuPreflight();
			IOSTitleLaunch_ExposeRomsToTheMenu();
		}
		else
			IOSTitleLaunch_DropMenuScanPath();
		std::vector<fs::path> companionTitles = IOSTitleLaunch_FindCompanionTitles(launchTitle, baseTitleId);
		for (const fs::path& wua : IOSTitleLaunch_FindWuaCompanions(baseTitleId))
			companionTitles.push_back(wua);
		for (const fs::path& companion : companionTitles)
		{
			cemuLog_log(LogType::Force, "iOS: adding update/DLC folder {} next to the game", _pathToUtf8(companion));
			CafeTitleList::AddTitleFromPath(companion);
		}
		// Picks up anything DlcUpdateImport.swift has installed into Documents/mlc since
		// the title list was last populated. Without it PrepareForegroundTitle below builds
		// its GameInfo2 from the base game alone and boots unpatched.
		IOSTitleLaunch_RescanInstalledContent();
		// The rescan drops every title it did not rediscover under the game paths or the MLC,
		// and a title launched from Documents/Roms is under neither, so the entry added above
		// is gone by now. Without adding it back, PrepareForegroundTitle finds no base title
		// and fails with "Game meta information is either missing...". Re-adding is
		// synchronous and deduplicated by location.
		CafeTitleList::AddTitleFromPath(launchPath);
		for (const fs::path& companion : companionTitles)
			CafeTitleList::AddTitleFromPath(companion);
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
	case TitleInfo::InvalidReason::BAD_TITLE_TMD:
		cemuLog_log(LogType::Force, "iOS: {} has a title.tmd that could not be read", _pathToUtf8(launchPath));
		return IOS_TITLE_LAUNCH_BAD_TITLE_TMD;
	case TitleInfo::InvalidReason::BAD_TITLE_TIK:
		cemuLog_log(LogType::Force, "iOS: {} has a title.tik that could not be read", _pathToUtf8(launchPath));
		return IOS_TITLE_LAUNCH_BAD_TITLE_TIK;
	case TitleInfo::InvalidReason::TITLE_KEY_INVALID:
		cemuLog_log(LogType::Force, "iOS: {} could not be decrypted with its ticket or any key in keys.txt", _pathToUtf8(launchPath));
		return IOS_TITLE_LAUNCH_TITLE_KEY_INVALID;
	case TitleInfo::InvalidReason::MISSING_CONTENT_FILE:
		sLastLaunchDetail = FSTVolume::GetLastMissingContentFile();
		cemuLog_log(LogType::Force, "iOS: {} is missing content file {}", _pathToUtf8(launchPath), sLastLaunchDetail);
		return IOS_TITLE_LAUNCH_MISSING_CONTENT_FILE;
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
// bytes. Doing it immediately before every key read keeps the drop folder and the engine
// copy in sync. The engine's key cache itself is read once per app launch, so keys added
// mid-session are used after the app is relaunched.
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
	KeyCache_Prepare();
	sint32 cached = 0;
	while (KeyCache_GetAES128(cached) != nullptr)
		cached++;

	// Counted from the file, not only from the cache. The core's cache is load-once, so
	// after an import mid-session the cache still holds the old set; the file is the
	// answer to "did my import work". Same acceptance rule as KeyCache_Prepare(): 32 hex
	// digits at the start of a line, anything after '#' ignored.
	sint32 inFile = 0;
	std::ifstream keys(ActiveSettings::GetUserDataPath("keys.txt"));
	for (std::string line; std::getline(keys, line);)
	{
		size_t hex = 0;
		while (hex < line.size() && std::isxdigit((unsigned char)line[hex]))
			hex++;
		if (hex >= 32)
			inFile++;
	}
	if (inFile != cached)
		cemuLog_log(LogType::Force, "iOS: keys.txt has {} key(s), {} loaded this session - relaunch MuffinEMU to use the new ones", inFile, cached);
	else
		cemuLog_log(LogType::Force, "iOS: keys.txt checked, {} key(s) available", inFile);
	return (int)inFile;
}
