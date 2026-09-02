// Decrypt-to-Files for iOS. Void's ask: take a WUD/WUX the user already owns the
// keys for and produce a plain, decrypted copy - either to keep using instead of the
// encrypted original, or to hand to another app via the Files share sheet.
//
// Deliberately NOT a from-scratch crypto implementation. FSTVolume already has to do
// full AES-128/hash-tree decryption for every single read during ordinary emulation
// (see FST.cpp's GetDecryptedRawBlock/GetDecryptedHashedBlock) - that code is already
// exercised on every boot and is what tonight's AES128_init fix made work at all. This
// file only walks the FST's own directory tree (OpenDirectoryIterator/Next, the same
// API fscDeviceWud.cpp already uses to serve the emulated OS live reads) and writes out
// whatever ReadFile() hands back - it never touches a key or a cipher itself.
//
// The output lands as a plain folder tree, not a repackaged WUD: FSTVolume::GetPath()
// carries its own `cemu_assert_debug(parentChain.size() <= 1); // test this case`,
// which is the original author's own admission that path reconstruction below one
// level of nesting isn't trusted - a real disc easily nests deeper than that (content/
// alone commonly does), so this builds the path itself while walking instead of ever
// calling GetPath(). The result is exactly the code/, content/, meta/ layout a folder
// dump already has - GameManager.swift's own error text says as much - so nothing
// downstream (TitleInfo::Mount's HOST_FS path, already used for folder dumps for a
// while) needs to change to import and boot what this produces.
//
// Why this lives here and not in CemuBridge.mm: same reasoning as IOSTitleLaunch.cpp -
// the bridge is compiled by Xcode directly and FST.h pulls in the ncrypto/config stack,
// so anything header-heavy stays on the CMake side and exposes a flat function.
#include "Cafe/Filesystem/FST/FST.h"
#include "Cemu/Logging/CemuLogging.h"

#include <atomic>
#include <filesystem>
#include <fstream>
#include <functional>
#include <string>
#include <vector>

namespace fs = std::filesystem;

// Mirrored 1:1 by CemuBridgeStatus-style ints in the bridge, same convention as
// IOSTitleLaunch.cpp's IOS_TITLE_LAUNCH_* enum.
enum
{
	IOS_DECRYPT_OK = 0,
	IOS_DECRYPT_UNABLE_TO_MOUNT = 1,
	IOS_DECRYPT_NO_DISC_KEY = 2,
	IOS_DECRYPT_DEST_NOT_WRITABLE = 3,
	IOS_DECRYPT_CANCELLED = 4,
};

// One 4MB buffer reused for every file rather than one allocation per file - a real
// disc easily has several thousand files, and this runs on a background thread where
// there is no benefit to letting the allocator churn on every single one.
constexpr uint32 kDecryptChunkSize = 4 * 1024 * 1024;

static bool DecryptWalkDirectory(FSTVolume* volume, const std::string& fstPath, const fs::path& destPath,
	uint64& bytesWritten, uint32& filesWritten, std::atomic_bool& cancelRequested,
	const std::function<void(uint64 bytesWritten, uint32 filesWritten)>& progressCallback,
	std::vector<uint8>& scratchBuffer)
{
	FSTDirectoryIterator dirIterator;
	if (!volume->OpenDirectoryIterator(fstPath, dirIterator))
	{
		// Not every directory in the FST necessarily resolves (link entries, tik-gated
		// partitions without a key) - skip it rather than abort the whole extraction
		// over one subtree. The caller only fails the overall operation on the
		// top-level mount itself failing.
		cemuLog_log(LogType::Force, "Decrypt: could not open directory '{}', skipping it", fstPath);
		return true;
	}

	FSTFileHandle entry;
	while (volume->Next(dirIterator, entry))
	{
		if (cancelRequested.load())
			return false;

		std::string name(volume->GetName(entry));
		if (name.empty())
			continue;
		std::string childFstPath = fstPath.empty() ? name : (fstPath + "/" + name);
		fs::path childDestPath = destPath / name;

		if (volume->IsDirectory(entry))
		{
			std::error_code ec;
			fs::create_directories(childDestPath, ec);
			if (ec)
			{
				cemuLog_log(LogType::Force, "Decrypt: could not create directory '{}' ({})", childDestPath.string(), ec.message());
				continue;
			}
			if (!DecryptWalkDirectory(volume, childFstPath, childDestPath, bytesWritten, filesWritten, cancelRequested, progressCallback, scratchBuffer))
				return false;
			continue;
		}

		if (!volume->IsFile(entry))
			continue; // link entries and anything else not directly readable

		FSTFileHandle fileHandle;
		if (!volume->OpenFile(childFstPath, fileHandle, true))
		{
			cemuLog_log(LogType::Force, "Decrypt: could not open '{}' for reading, skipping it", childFstPath);
			continue;
		}
		uint32 fileSize = volume->GetFileSize(fileHandle);

		std::ofstream out(childDestPath, std::ios::binary | std::ios::trunc);
		if (!out.is_open())
		{
			cemuLog_log(LogType::Force, "Decrypt: could not create output file '{}'", childDestPath.string());
			continue;
		}

		if (scratchBuffer.size() < std::min(fileSize, kDecryptChunkSize))
			scratchBuffer.resize(std::min(fileSize, kDecryptChunkSize));

		uint32 offset = 0;
		while (offset < fileSize)
		{
			if (cancelRequested.load())
				return false;
			uint32 toRead = std::min((uint32)scratchBuffer.size(), fileSize - offset);
			uint32 got = volume->ReadFile(fileHandle, offset, toRead, scratchBuffer.data());
			if (got == 0)
				break; // real disc read failure (bad key, corrupt data) - stop this file, move on to the next
			out.write((const char*)scratchBuffer.data(), got);
			offset += got;
			bytesWritten += got;
		}
		out.close();
		filesWritten++;
		if (progressCallback)
			progressCallback(bytesWritten, filesWritten);
	}
	return true;
}

// Opens srcPath (WUD/WUX) and writes a fully decrypted copy of its file tree under
// destFolderPath, preserving the FST's own directory structure - a plain code/,
// content/, meta/ tree the app can already import and boot as a folder dump. The
// original file at srcPath is never opened for writing and never touched.
//
// progressCallback is invoked from this thread (the caller's background thread, never
// the main thread) after every file completes - the Swift side polls a snapshot
// instead of marshalling this across the bridge live, same pattern as the boot
// progress struct already uses.
int IOSTitleDecrypt_ExtractToFolder(const char* srcPath, const char* destFolderPath,
	std::atomic_bool& cancelRequested,
	const std::function<void(uint64 bytesWritten, uint32 filesWritten)>& progressCallback)
{
	if (!srcPath || srcPath[0] == '\0' || !destFolderPath || destFolderPath[0] == '\0')
		return IOS_DECRYPT_UNABLE_TO_MOUNT;

	fs::path dest(destFolderPath);
	std::error_code ec;
	fs::create_directories(dest, ec);
	if (ec)
	{
		cemuLog_log(LogType::Force, "Decrypt: destination '{}' is not writable ({})", dest.string(), ec.message());
		return IOS_DECRYPT_DEST_NOT_WRITABLE;
	}

	FSTVolume::ErrorCode fstError;
	FSTVolume* volume = FSTVolume::OpenFromDiscImage(fs::path(srcPath), &fstError);
	if (!volume)
	{
		cemuLog_log(LogType::Force, "Decrypt: could not open '{}' ({})", srcPath, (sint32)fstError);
		return fstError == FSTVolume::ErrorCode::DISC_KEY_MISSING ? IOS_DECRYPT_NO_DISC_KEY : IOS_DECRYPT_UNABLE_TO_MOUNT;
	}

	uint64 bytesWritten = 0;
	uint32 filesWritten = 0;
	std::vector<uint8> scratchBuffer;
	bool completed = DecryptWalkDirectory(volume, "", dest, bytesWritten, filesWritten, cancelRequested, progressCallback, scratchBuffer);
	delete volume;

	cemuLog_log(LogType::Force, "Decrypt: {} - {} files, {} bytes written to '{}'",
		completed ? "finished" : "cancelled", filesWritten, bytesWritten, dest.string());

	return completed ? IOS_DECRYPT_OK : IOS_DECRYPT_CANCELLED;
}
