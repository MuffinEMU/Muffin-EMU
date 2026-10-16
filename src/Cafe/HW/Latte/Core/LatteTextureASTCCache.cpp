// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

#include "Cafe/HW/Latte/Core/LatteTextureASTCCache.h"
#include "Cafe/CafeSystem.h"
#include "config/ActiveSettings.h"
#include <cstdio>
#include <unistd.h>
#include <mutex>
#include <unordered_map>

// One pack file per title: a header, then records of {key, size, ASTC bytes}, appended as textures are
// encoded. The index of where each record sits is rebuilt by reading the record headers on first use.
// A file from another format version, or one cut short by a crash, is read up to its last whole record.

namespace
{
	constexpr uint32 kMagic = 0x43545341; // "ASTC"
	// Bump when the encoder settings or the decoders change, so an old file is never mixed with new output.
	constexpr uint32 kVersion = 2;

	struct FileHeader
	{
		uint32 magic;
		uint32 version;
	};

	struct RecordHeader
	{
		uint64 hashA;
		uint64 hashB;
		uint32 width;
		uint32 height;
		uint32 kind;
		uint32 size;
	};

	struct KeyHash
	{
		size_t operator()(const ASTCCacheKey& k) const { return (size_t)(k.hashA ^ (k.hashB * 0x9E3779B97F4A7C15ull)); }
	};
	struct KeyEq
	{
		bool operator()(const ASTCCacheKey& a, const ASTCCacheKey& b) const
		{
			return a.hashA == b.hashA && a.hashB == b.hashB && a.width == b.width && a.height == b.height && a.kind == b.kind;
		}
	};

	struct Entry
	{
		uint64 offset; // of the ASTC bytes
		uint32 size;
	};

	struct Cache
	{
		std::mutex mutex;
		uint64 titleId = 0;
		bool opened = false;
		FILE* file = nullptr;
		uint64 fileSize = 0;
		std::unordered_map<ASTCCacheKey, Entry, KeyHash, KeyEq> index;
		bool full = false;
		bool logged = false;
	};

	Cache& Get()
	{
		static Cache cache;
		return cache;
	}

	// A cap on one title's pack, so a game with thousands of textures cannot fill the device. 1 GB holds every
	// track of a racing game several times over at 1 byte per texel.
	uint64 MaxBytes() { return 1024ull * 1024 * 1024; }

	void Close(Cache& c)
	{
		if (c.file)
			fclose(c.file);
		c.file = nullptr;
		c.index.clear();
		c.fileSize = 0;
		c.full = false;
		c.opened = false;
		c.logged = false;
	}

	// Opens (or creates) the pack for the running title. Called with the mutex held.
	bool Open(Cache& c)
	{
		const uint64 titleId = CafeSystem::GetForegroundTitleId();
		if (c.opened && c.titleId == titleId)
			return c.file != nullptr;
		Close(c);
		c.opened = true;
		c.titleId = titleId;
		if (titleId == 0)
			return false;

		std::error_code ec;
		fs::create_directories(ActiveSettings::GetCachePath("textureCache"), ec);
		const fs::path path = ActiveSettings::GetCachePath("textureCache/{:016x}_astc4x4.bin", titleId);
		FILE* f = fopen(_pathToUtf8(path).c_str(), "r+b");
		bool fresh = false;
		if (f)
		{
			FileHeader h{};
			if (fread(&h, sizeof(h), 1, f) != 1 || h.magic != kMagic || h.version != kVersion)
			{
				fclose(f);
				f = nullptr;
				fresh = true;
			}
		}
		else
			fresh = true;
		if (fresh)
		{
			f = fopen(_pathToUtf8(path).c_str(), "w+b");
			if (!f)
				return false;
			const FileHeader h{kMagic, kVersion};
			if (fwrite(&h, sizeof(h), 1, f) != 1)
			{
				fclose(f);
				return false;
			}
			fflush(f);
		}
		c.file = f;

		// Index every whole record; a torn tail (the app was killed mid-write) is cut off.
		// Records are checked against the real file size: seeking past the end of a file succeeds, so a record whose
		// header made it to disk but whose data did not used to be accepted, and the truncate below then grew the file
		// to fit it with zeros. All-zero ASTC blocks are invalid and sample as the error colour, so that texture stayed
		// broken on every later launch.
		fseeko(f, 0, SEEK_END);
		const uint64 actualSize = (uint64)ftello(f);
		uint64 pos = sizeof(FileHeader);
		fseeko(f, (off_t)pos, SEEK_SET);
		RecordHeader r{};
		while (pos + sizeof(r) <= actualSize && fread(&r, sizeof(r), 1, f) == 1)
		{
			const uint64 dataPos = pos + sizeof(r);
			// a record always holds one whole 4x4 ASTC image of its size; anything else is a damaged header
			const uint64 expectedSize = (uint64)((r.width + 3) / 4) * (uint64)((r.height + 3) / 4) * 16u;
			if (r.size == 0 || r.size != expectedSize || r.size > actualSize - dataPos)
				break;
			if (fseeko(f, (off_t)r.size, SEEK_CUR) != 0)
				break;
			c.index[ASTCCacheKey{r.hashA, r.hashB, r.width, r.height, r.kind}] = Entry{dataPos, r.size};
			pos = dataPos + r.size;
		}
		c.fileSize = pos;
		if (actualSize != pos)
		{
			// pos <= actualSize here, so this only ever cuts the damaged tail off
			fflush(f);
			ftruncate(fileno(f), (off_t)pos);
		}
		c.full = c.fileSize >= MaxBytes();
		cemuLog_log(LogType::Force, "BC->ASTC texture cache: {} textures, {} MB for this title{}", c.index.size(), c.fileSize / (1024 * 1024),
			c.full ? " (full, not adding more)" : "");
		return true;
	}
}

bool LatteTextureASTCCache_Lookup(const ASTCCacheKey& key, uint8* outputData, size_t outputSize)
{
	Cache& c = Get();
	std::lock_guard lock(c.mutex);
	if (!Open(c))
		return false;
	auto it = c.index.find(key);
	if (it == c.index.end() || it->second.size != outputSize)
		return false;
	if (pread(fileno(c.file), outputData, outputSize, (off_t)it->second.offset) != (ssize_t)outputSize)
	{
		c.index.erase(it);
		return false;
	}
	// Neither the encoder nor the direct transcoder ever writes an all-zero block (block mode 0 is reserved), so one at the
	// end of the image means its record was cut short and zero-filled (files written before the size check in Open()).
	// Encode it again instead; the fresh result is appended and replaces this record from the next launch on.
	if (outputSize >= 16)
	{
		const uint8* lastBlock = outputData + outputSize - 16;
		bool allZero = true;
		for (size_t i = 0; i < 16 && allZero; i++)
			allZero = lastBlock[i] == 0;
		if (allZero)
		{
			c.index.erase(it);
			return false;
		}
	}
	return true;
}

void LatteTextureASTCCache_Store(const ASTCCacheKey& key, const uint8* data, size_t size)
{
	Cache& c = Get();
	std::lock_guard lock(c.mutex);
	if (!Open(c) || c.full || size == 0 || size > 0xFFFFFFFFu)
		return;
	if (c.index.find(key) != c.index.end())
		return;
	const RecordHeader r{key.hashA, key.hashB, key.width, key.height, key.kind, (uint32)size};
	fseeko(c.file, (off_t)c.fileSize, SEEK_SET);
	if (fwrite(&r, sizeof(r), 1, c.file) != 1 || fwrite(data, 1, size, c.file) != size)
	{
		// Out of space or an I/O error: stop adding for this title and leave the file at its last whole record.
		fflush(c.file);
		ftruncate(fileno(c.file), (off_t)c.fileSize);
		c.full = true;
		return;
	}
	fflush(c.file);
	c.index[key] = Entry{c.fileSize + sizeof(r), (uint32)size};
	c.fileSize += sizeof(r) + size;
	if (c.fileSize >= MaxBytes())
	{
		c.full = true;
		cemuLog_log(LogType::Force, "BC->ASTC texture cache: {} MB for this title, not adding more", c.fileSize / (1024 * 1024));
	}
}
