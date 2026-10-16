#pragma once

#include <mutex>
#include <functional>

class FileCache
{
public:
	struct FileName 
	{
		FileName(uint64 name1, uint64 name2) : name1(name1), name2(name2) {};
		FileName(std::string_view filePath)
		{
			// name from string hash
			uint64 h1 = 0xa2cc2c49386a75fdull;
			uint64 h2 = 0x5182d367734c2ce8ull;
			const char* c = filePath.data();
			const char* cEnd = filePath.data() + filePath.size();
			while (c < cEnd)
			{
				uint64 t = (uint64)*c;
				c++;
				h1 = (h1 << 7) | (h1 >> (64 - 7));
				h1 += t;
				h2 = h2 * 7841u + t;
			}
			name1 = h1;
			name2 = h2;
		};

		FileName(const std::string& filePath) : FileName(std::basic_string_view(filePath.data(), filePath.size())) {};

		uint64 name1;
		uint64 name2;
	};

	~FileCache();

	static FileCache* Create(const fs::path& path, uint32 extraVersion = 0);
	// A readable file with another version stamp is set aside as ".unreadable" like an unreadable one, so learned shaders and
	// pipelines survive a stamp change. replaceOnVersionChange is for caches that are rebuilt when their stamp changes (the
	// precompiled SPIR-V / program binary caches, stamped per app version): there the old file is simply overwritten.
	static FileCache* Open(const fs::path& path, bool allowCreate, uint32 extraVersion = 0, bool replaceOnVersionChange = false);
	static FileCache* Open(const fs::path& path); // open without extraVersion check
	// For files that belong to someone else (cache import sources): opened read-only, and a damaged entry is just reported as
	// unreadable. Nothing is ever deleted, rewritten or restored from the backup directory, and no write method does anything.
	static FileCache* OpenReadOnly(const fs::path& path);
	// Health check without changing anything: header and file table readable and the file table's own
	// entry in order. With checkEntries also every entry inside the file and not overlapping another, and
	// every checksummed entry intact (checksum of the stored bytes; nothing is decompressed). Without it, a
	// single cut-short entry doesn't fail the file: that one is repaired when it's read.
	static bool Verify(const fs::path& path, bool checkEntries = true);
	// Where known-good copies of cache files live (same file names). A damaged entry is repaired from
	// there the moment it's read, or deleted if no good copy exists; every other entry stays.
	static void SetBackupDirectory(const fs::path& dir);
	// Damaged entries found (and repaired or deleted) since this file was opened.
	uint32 GetDamagedEntryCount() const { return damagedEntryCount; }
	// The same across every cache file in the process (backup copies excluded), so a caller can tell whether
	// anything at all was damaged between two points, whichever files it touched.
	static uint32 GetDamagedEntryTotal();
	// The version stamp from the header (for the caches here: derived from the title, or a legacy constant).
	uint32 GetExtraVersion() const { return extraVersion; }

	void UseCompression(bool enable) { enableCompression = enable; };

	// false if the entry could not be written (e.g. the disk is full); the file table then still describes what was there before
	bool AddFile(const FileName&& name, const uint8* fileData, sint32 fileSize);
	void AddFileAsync(const FileName& name, const uint8* fileData, sint32 fileSize);
	bool DeleteFile(const FileName&& name);
	bool GetFile(const FileName&& name, std::vector<uint8>& dataOut);
	bool GetFileByIndex(sint32 index, uint64* name1, uint64* name2, std::vector<uint8>& dataOut);
	bool HasFile(const FileName&& name);

	// Moves entries to new names in one batch. Each entry's data is read, passed through patch (if set) and written under
	// the new name; every new entry is read back and compared, the file is flushed once, and only then are the old
	// names deleted (and flushed once more). A crash in between leaves both names, never neither. If the new name is
	// already there the entry is the same one and the old name is just deleted. Returns the number of entries moved.
	struct RekeyJob
	{
		FileName from;
		FileName to;
		std::function<void(std::vector<uint8>&)> patch;
	};
	uint32 RekeyEntries(const std::vector<RekeyJob>& jobs);

	sint32 GetFileCount();

	sint32 GetMaximumFileIndex();

private:
	struct FileTableEntry
	{
		enum FLAGS : uint8
		{
			FLAG_NONE = 0x00,
			FLAG_COMPRESSED = (1 << 0), // zLib compressed
			// extraReserved1/2 hold a 16-bit checksum of the stored bytes (folded CRC32). Older
			// entries and older builds leave the bit clear and are read as before.
			FLAG_CHECKSUM = (1 << 1),
		};
		uint64 name1;
		uint64 name2;
		uint64 fileOffset;
		uint32 fileSize;
		FLAGS flags;
		uint8 extraReserved1;
		uint8 extraReserved2;
		uint8 extraReserved3;
	};

	static_assert(sizeof(FileTableEntry) == 0x20);

	FileCache() {};

	static FileCache* _OpenExisting(const fs::path& path, bool compareExtraVersion, uint32 extraVersion = 0, bool readOnly = false);

	bool fileCache_updateFiletable(sint32 extraEntriesToAllocate);
	bool _flushStream();
	bool _addFileInternal(uint64 name1, uint64 name2, const uint8* fileData, sint32 fileSize, bool noCompression);
	bool _readEntryRaw(const FileTableEntry* entry, std::vector<uint8>& rawOut);
	bool _getFileDataInternal(const FileTableEntry* entry, std::vector<uint8>& dataOut);

	class FileStream* fileStream{};
	uint64 dataOffset{};
	uint32 extraVersion{};
	// file table
	FileTableEntry* fileTableEntries{};
	sint32 fileTableEntryCount{};
	// file table (as stored in file)
	uint64 fileTableOffset{};
	uint32 fileTableSize{};
	// options
	bool enableCompression{true};
	bool readOnly{false};
	bool deferFlush{false}; // set while a batch is applied: the batch flushes itself
	fs::path filePath;
	uint32 damagedEntryCount{};
	bool _handleDamagedEntry(FileTableEntry* entry, std::vector<uint8>& dataOut);

	std::recursive_mutex mutex;
};
