#pragma once

#include <mutex>

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
	static FileCache* Open(const fs::path& path, bool allowCreate, uint32 extraVersion = 0);
	static FileCache* Open(const fs::path& path); // open without extraVersion check
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

	void AddFile(const FileName&& name, const uint8* fileData, sint32 fileSize);
	void AddFileAsync(const FileName& name, const uint8* fileData, sint32 fileSize);
	bool DeleteFile(const FileName&& name);
	bool GetFile(const FileName&& name, std::vector<uint8>& dataOut);
	bool GetFileByIndex(sint32 index, uint64* name1, uint64* name2, std::vector<uint8>& dataOut);
	bool HasFile(const FileName&& name);

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

	static FileCache* _OpenExisting(const fs::path& path, bool compareExtraVersion, uint32 extraVersion = 0);

	void fileCache_updateFiletable(sint32 extraEntriesToAllocate);
	void _addFileInternal(uint64 name1, uint64 name2, const uint8* fileData, sint32 fileSize, bool noCompression);
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
	fs::path filePath;
	uint32 damagedEntryCount{};
	bool _handleDamagedEntry(FileTableEntry* entry, std::vector<uint8>& dataOut);

	std::recursive_mutex mutex;
};
