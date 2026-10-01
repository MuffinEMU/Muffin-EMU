#include <atomic>
#include <memory>
#include <mutex>

#include "Cemu/Logging/CemuLogging.h"
#include "WindowSystem.h"
#include "config/ActiveSettings.h"
#include "util/crypto/aes128.h"
#include "Common/FileStream.h"
#include "util/helpers/StringHelpers.h"

std::mutex mtxKeyCache;

struct KeyCacheEntry
{
	uint8 aes128key[16];
};

// The published key list. Readers (KeyCache_GetAES128 from any thread) never take the lock: a reload builds a new
// list and swaps the pointer, and the list it replaces is kept alive so a pointer a reader already got stays valid.
// A reload only happens when keys.txt really changed, so the retired lists are a few hundred bytes each.
static std::vector<KeyCacheEntry> sEmptyKeyList;
static std::atomic<const std::vector<KeyCacheEntry>*> sKeyList{&sEmptyKeyList};
static std::vector<std::unique_ptr<std::vector<KeyCacheEntry>>> sRetiredKeyLists;

bool strishex(std::string_view str)
{
	for(size_t i=0; i<str.size(); i++)
	{
		char c = str[i];
		if( (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F') )
			continue;
		return false;
	}
	return true;
}

/*
 * Returns AES-128 key from the key cache
 * nullptr is returned if index >= max_keys
 */
uint8* KeyCache_GetAES128(sint32 index)
{
	const std::vector<KeyCacheEntry>* list = sKeyList.load(std::memory_order_acquire);
	if( index < 0 || index >= (sint32)list->size())
		return nullptr;
	return const_cast<uint8*>((*list)[index].aes128key);
}

// A hash of how many keys there are and what they are. Anything that remembers a result that depended on the keys
// (TitleInfo's failed-open memo) stores this next to it, so a different keys.txt can never be answered from the past.
uint64 KeyCache_GetFingerprint()
{
	const std::vector<KeyCacheEntry>* list = sKeyList.load(std::memory_order_acquire);
	uint64 h = 1469598103934665603ull;
	auto mix = [&](uint64 v) { h = (h ^ v) * 1099511628211ull; };
	mix(list->size());
	for (const KeyCacheEntry& entry : *list)
	{
		uint64 a, b;
		memcpy(&a, entry.aes128key, 8);
		memcpy(&b, entry.aes128key + 8, 8);
		mix(a);
		mix(b);
	}
	return h;
}

// What the last load of keys.txt looked like. The cache is re-read when the path or the file changed, not only once:
// a keys.txt that is adopted or replaced after the first read (the iOS app copies the one dropped into Documents/keys
// right before a launch) used to be ignored until the next app start.
static bool sKeyCachePrepared = false;
static fs::path sLoadedKeysPath;
static uint64 sLoadedKeysSize = 0;
static sint64 sLoadedKeysTime = 0;

void KeyCache_ResetForNewPaths()
{
	std::lock_guard lock(mtxKeyCache);
	sKeyCachePrepared = false;
}

// The key files the app named for use before ActiveSettings::SetPaths() has run (see KeyCache.h), in order of preference.
static fs::path sPreInitKeysPaths[2];

void KeyCache_SetPreInitKeyFiles(const fs::path& preferred, const fs::path& fallback)
{
	std::lock_guard lock(mtxKeyCache);
	sPreInitKeysPaths[0] = preferred;
	sPreInitKeysPaths[1] = fallback;
}

static bool KeyCache_StatKeysFile(const fs::path& keysPath, uint64& sizeOut, sint64& timeOut)
{
	std::error_code ec;
	const auto size = fs::file_size(keysPath, ec);
	if (ec)
		return false;
	const auto time = fs::last_write_time(keysPath, ec);
	if (ec)
		return false;
	sizeOut = (uint64)size;
	timeOut = (sint64)time.time_since_epoch().count();
	return true;
}

void KeyCache_Prepare()
{
	std::lock_guard lock(mtxKeyCache);
	fs::path keysPath;
	// True while reading one of the files named by KeyCache_SetPreInitKeyFiles(): nothing is created or latched then.
	bool readingPreInitFile = false;
	// Before ActiveSettings::SetPaths() there is no real keys.txt location, and a read against the empty path finds
	// nothing. That result must not stick: a library scan that runs ahead of CemuInitialize() would otherwise leave
	// the session believing there are no keys. Nothing is latched and the next call tries again.
	// The app can name the file(s) that will become keys.txt (KeyCache_SetPreInitKeyFiles), so that a disc image can
	// be opened before the engine starts: the library scan, DLC/update inspection and Decrypt to Files all do that,
	// and without keys they could not read a .wux/.wud at all.
	// ArePathsSet() rather than reading the path: SetPaths() assigns it on another thread, and an unsynchronised read of a
	// std::filesystem::path that is being assigned can see it half written. Every call used to read it, and the library scan
	// calls this while CemuInitialize() runs.
	if (!ActiveSettings::ArePathsSet())
	{
		for (const fs::path& candidate : sPreInitKeysPaths)
		{
			std::error_code candidateEc;
			if (!candidate.empty() && fs::is_regular_file(candidate, candidateEc))
			{
				keysPath = candidate;
				readingPreInitFile = true;
				break;
			}
		}
		if (!readingPreInitFile)
			return;
	}
	else
		keysPath = ActiveSettings::GetUserDataPath("keys.txt");
	uint64 fileSize = 0;
	sint64 fileTime = 0;
	const bool haveFile = KeyCache_StatKeysFile(keysPath, fileSize, fileTime);
	if (sKeyCachePrepared && keysPath == sLoadedKeysPath && haveFile && fileSize == sLoadedKeysSize && fileTime == sLoadedKeysTime)
		return;
	FileStream* fs_keys = FileStream::openFile2(keysPath);
	if( !fs_keys )
	{
		if (readingPreInitFile)
			return; // unreadable for now: not latched, not created (there is no user data folder yet), tried again next call
		if (sKeyCachePrepared && keysPath == sLoadedKeysPath && !haveFile)
			return; // still missing, already handled
		sKeyCachePrepared = true;
		sLoadedKeysPath = keysPath;
		sLoadedKeysSize = 0;
		sLoadedKeysTime = 0;
		fs_keys = FileStream::createFile2(keysPath);
		if(fs_keys)
		{
			fs_keys->writeString("# this file contains keys needed for decryption of disc file system data (WUD/WUX)\r\n");
			fs_keys->writeString("# 1 key per line, any text after a '#' character is considered a comment\r\n");
			fs_keys->writeString("# the emulator will automatically pick the right key\r\n");
			fs_keys->writeString("541b9889519b27d363cd21604b97c67a # example key (can be deleted)\r\n");
			delete fs_keys;
		}
		else
		{
			WindowSystem::ShowErrorDialog(_tr("Unable to create file keys.txt\nThis can happen if Cemu does not have write permission to its own directory, the disk is full or if anti-virus software is blocking Cemu."), _tr("Error"), WindowSystem::ErrorCategory::KEYS_TXT_CREATION);
		}
		return;
	}
	sKeyCachePrepared = true;
	sLoadedKeysPath = keysPath;
	sLoadedKeysSize = haveFile ? fileSize : 0;
	sLoadedKeysTime = haveFile ? fileTime : 0;
	auto newList = std::make_unique<std::vector<KeyCacheEntry>>();
	sint32 lineNumber = 0;
	std::string line;
	while( fs_keys->readLine(line) )
	{
		lineNumber++;
		// truncate anything after '#' or ';'
		for(size_t i=0; i<line.size(); i++)
		{
			if(line[i] == '#' || line[i] == ';' )
			{
				line.resize(i);
				break;
			}
		}
		// remove whitespaces and other common formatting characters
		auto itr = line.begin();
		while (itr != line.end())
		{
			char c = *itr;
			if (c == ' ' || c == '\t' || c == '-' || c == '_')
				itr = line.erase(itr);
			else
				itr++;
		}
		if (line.empty())
			continue;
		if( strishex(line) == false )
		{
			auto errorMsg = _tr("Error in keys.txt at line {}", lineNumber);
			WindowSystem::ShowErrorDialog(errorMsg, WindowSystem::ErrorCategory::KEYS_TXT_CREATION);
			continue;
		}
		if(line.size() == 32 )
		{
			// 128-bit key
			uint8 keyData128[16];
			StringHelpers::ParseHexString(line, keyData128, 16);
			KeyCacheEntry newEntry = {0};
			memcpy(newEntry.aes128key, keyData128, 16);
			newList->emplace_back(newEntry);
		}
		else
		{
			// invalid key length
		}
	}
	delete fs_keys;
	sKeyList.store(newList.get(), std::memory_order_release);
	sRetiredKeyLists.push_back(std::move(newList)); // kept alive, see sKeyList
}
