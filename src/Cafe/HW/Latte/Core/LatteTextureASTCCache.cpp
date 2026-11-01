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

// Two pack files per title, the current generation and the previous one. Each is a header, then records of
// {key, size, ASTC bytes}, appended as textures are encoded. The index of where each record sits is rebuilt by
// reading the record headers on first use. A file from another format version, or one cut short by a crash, is
// read up to its last whole record.
//
// When the current pack reaches its cap it becomes the previous one (replacing the older previous) and a new
// current pack starts. A texture found only in the previous pack is copied into the current one, so whatever
// the game still uses moves forward and only what it stopped using ages out. A single pack that simply stopped
// growing at its cap kept the textures of the first hours of play for good and re-encoded everything newer on
// every load, which turned loading in a long game (Breath of the Wild menus, the album, resting) slow for good.

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

	struct Pack
	{
		FILE* file = nullptr;
		uint64 fileSize = 0;
		std::unordered_map<ASTCCacheKey, Entry, KeyHash, KeyEq> index;
	};

	struct Cache
	{
		std::mutex mutex;
		uint64 titleId = 0;
		bool opened = false;
		fs::path currentPath;
		fs::path previousPath;
		Pack current;
		Pack previous;
		bool full = false; // the current pack cannot be written (I/O error, out of space, or it could not be rotated)
	};

	Cache& Get()
	{
		static Cache cache;
		return cache;
	}

	// A cap on one generation, so a game with thousands of textures cannot fill the device: the two packs of a
	// title stay near 1 GB together, the size the single pack used to stop at. 512 MB holds every track of a
	// racing game at 1 byte per texel.
	uint64 MaxBytes() { return 512ull * 1024 * 1024; }

	void ClosePack(Pack& p)
	{
		if (p.file)
			fclose(p.file);
		p.file = nullptr;
		p.index.clear();
		p.fileSize = 0;
	}

	void Close(Cache& c)
	{
		ClosePack(c.current);
		ClosePack(c.previous);
		c.full = false;
		c.opened = false;
	}

	// Opens a pack and indexes every whole record; a torn tail (the app was killed mid-write) is cut off. A missing
	// file, or one from another format version, is started fresh when create is set and left closed otherwise.
	bool OpenPack(Pack& p, const fs::path& path, bool create)
	{
		ClosePack(p);
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
			if (!create)
			{
				std::error_code ec;
				fs::remove(path, ec);
				return false;
			}
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
		p.file = f;

		uint64 pos = sizeof(FileHeader);
		fseeko(f, (off_t)pos, SEEK_SET);
		RecordHeader r{};
		while (fread(&r, sizeof(r), 1, f) == 1)
		{
			const uint64 dataPos = pos + sizeof(r);
			if (r.size == 0 || fseeko(f, (off_t)r.size, SEEK_CUR) != 0)
				break;
			if ((uint64)ftello(f) != dataPos + r.size)
				break;
			p.index[ASTCCacheKey{r.hashA, r.hashB, r.width, r.height, r.kind}] = Entry{dataPos, r.size};
			pos = dataPos + r.size;
		}
		p.fileSize = pos;
		fseeko(f, 0, SEEK_END);
		if ((uint64)ftello(f) != pos)
		{
			fflush(f);
			ftruncate(fileno(f), (off_t)pos);
		}
		return true;
	}

	// The current pack becomes the previous one and an empty current pack starts. Called with the mutex held.
	// Every step leaves whole pack files behind, so a crash part way loses cached textures, never correctness.
	void Rotate(Cache& c)
	{
		ClosePack(c.previous);
		std::error_code ec;
		fs::remove(c.previousPath, ec);
		fflush(c.current.file);
		fclose(c.current.file);
		c.current.file = nullptr;
		fs::rename(c.currentPath, c.previousPath, ec);
		if (ec)
		{
			// The pack keeps its name: carry on with it as before, read-only from here on.
			cemuLog_log(LogType::Force, "BC->ASTC texture cache: could not start a new pack ({}), not adding more", ec.message());
			c.current.file = fopen(_pathToUtf8(c.currentPath).c_str(), "r+b");
			if (!c.current.file)
				c.current.index.clear();
			c.full = true;
			return;
		}
		// Same bytes under a new name, so the index is still right.
		c.previous.index = std::move(c.current.index);
		c.previous.fileSize = c.current.fileSize;
		c.previous.file = fopen(_pathToUtf8(c.previousPath).c_str(), "rb");
		if (!c.previous.file)
			ClosePack(c.previous);
		ClosePack(c.current);
		if (!OpenPack(c.current, c.currentPath, true))
			c.full = true;
		cemuLog_log(LogType::Force, "BC->ASTC texture cache: started a new pack; {} textures, {} MB kept from the last one",
			c.previous.index.size(), c.previous.fileSize / (1024 * 1024));
	}

	// Opens (or creates) the packs for the running title. Called with the mutex held.
	bool Open(Cache& c)
	{
		const uint64 titleId = CafeSystem::GetForegroundTitleId();
		if (c.opened && c.titleId == titleId)
			return c.current.file != nullptr || c.previous.file != nullptr;
		Close(c);
		c.opened = true;
		c.titleId = titleId;
		if (titleId == 0)
			return false;

		std::error_code ec;
		fs::create_directories(ActiveSettings::GetCachePath("textureCache"), ec);
		c.currentPath = ActiveSettings::GetCachePath("textureCache/{:016x}_astc4x4.bin", titleId);
		c.previousPath = ActiveSettings::GetCachePath("textureCache/{:016x}_astc4x4.previous.bin", titleId);
		if (!OpenPack(c.current, c.currentPath, true))
			return false;
		OpenPack(c.previous, c.previousPath, false);
		// A pack at its cap (or one from the single-pack builds, which stopped at 1 GB) moves aside now.
		if (c.current.fileSize >= MaxBytes())
			Rotate(c);
		cemuLog_log(LogType::Force, "BC->ASTC texture cache: {} textures, {} MB for this title, plus {} textures, {} MB in the previous pack{}",
			c.current.index.size(), c.current.fileSize / (1024 * 1024), c.previous.index.size(), c.previous.fileSize / (1024 * 1024),
			c.full ? " (not adding more)" : "");
		return c.current.file != nullptr || c.previous.file != nullptr;
	}

	// Called with the mutex held.
	void StoreLocked(Cache& c, const ASTCCacheKey& key, const uint8* data, size_t size)
	{
		if (c.full || !c.current.file || size == 0 || size > 0xFFFFFFFFu)
			return;
		if (c.current.index.find(key) != c.current.index.end())
			return;
		Pack& p = c.current;
		const RecordHeader r{key.hashA, key.hashB, key.width, key.height, key.kind, (uint32)size};
		fseeko(p.file, (off_t)p.fileSize, SEEK_SET);
		if (fwrite(&r, sizeof(r), 1, p.file) != 1 || fwrite(data, 1, size, p.file) != size)
		{
			// Out of space or an I/O error: stop adding for this title and leave the file at its last whole record.
			fflush(p.file);
			ftruncate(fileno(p.file), (off_t)p.fileSize);
			c.full = true;
			return;
		}
		fflush(p.file);
		p.index[key] = Entry{p.fileSize + sizeof(r), (uint32)size};
		p.fileSize += sizeof(r) + size;
		if (p.fileSize >= MaxBytes())
			Rotate(c);
	}

	bool ReadEntry(Pack& p, const ASTCCacheKey& key, uint8* outputData, size_t outputSize)
	{
		if (!p.file)
			return false;
		auto it = p.index.find(key);
		if (it == p.index.end() || it->second.size != outputSize)
			return false;
		if (pread(fileno(p.file), outputData, outputSize, (off_t)it->second.offset) != (ssize_t)outputSize)
		{
			p.index.erase(it);
			return false;
		}
		return true;
	}
}

bool LatteTextureASTCCache_Lookup(const ASTCCacheKey& key, uint8* outputData, size_t outputSize)
{
	Cache& c = Get();
	std::lock_guard lock(c.mutex);
	if (!Open(c))
		return false;
	if (ReadEntry(c.current, key, outputData, outputSize))
		return true;
	if (!ReadEntry(c.previous, key, outputData, outputSize))
		return false;
	// Still in use: carry it into the current pack before the previous one is dropped.
	StoreLocked(c, key, outputData, outputSize);
	return true;
}

void LatteTextureASTCCache_Store(const ASTCCacheKey& key, const uint8* data, size_t size)
{
	Cache& c = Get();
	std::lock_guard lock(c.mutex);
	if (!Open(c))
		return;
	StoreLocked(c, key, data, size);
}
