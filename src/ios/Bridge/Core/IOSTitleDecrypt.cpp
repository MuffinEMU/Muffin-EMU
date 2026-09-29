// Decrypt-to-Files for iOS: take a WUD/WUX the user already owns the
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
#include "Cafe/Filesystem/fsc.h"
#include "Cafe/TitleList/TitleInfo.h"
#include "Cemu/Logging/CemuLogging.h"

#include <zarchive/zarchivereader.h>
#include <zarchive/zarchivewriter.h>

#include <atomic>
#include <filesystem>
#include <fstream>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include <fcntl.h>
#include <unistd.h>

// fs is the core's own namespace, from precompiled.h.

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

// Decrypt-to-WUA. Same source, same underlying decrypt (nothing here does crypto
// either), different output shape: a single-file .wua archive instead of a loose
// code/, content/, meta/ tree.
//
// This is a from-scratch iOS port of the Android app's WuaConverter.cpp
// (src/android/app/src/main/cpp/), not a fresh design - that file already does exactly
// this (TitleInfo::Mount + the fsc_* virtual filesystem walk + ZArchiveWriter) and is
// almost entirely platform-agnostic C++. The only Android-specific piece was
// CompressTitleCallbacks, a thin wrapper around a JNI jobject/jmethodID pair used
// purely to call back into Java - it carries no conversion logic of its own, so it is
// simply not needed here: this function reports success/failure through the same
// int return + progressCallback convention IOSTitleDecrypt_ExtractToFolder already
// uses, with no callback-object indirection at all.
//
// TitleInfo(path) is used here instead of FSTVolume::OpenFromDiscImage (as the
// raw-source path above does) because it is what actually knows how to write the
// archive's internal layout - {titleId}_v{version}/... - via GetAppTitleId() /
// GetAppTitleVersion(), and because it means this function works unmodified on any
// source TitleInfo::DetectFormat already recognizes (WUD/WUX disc image, a folder
// dump, or an NUS dump pointed at its title.tmd), not just WUD/WUX.
namespace
{
struct WuaWriterContext
{
	int fd;

	static void NewOutputFile(const int32_t /*partIndex*/, void* /*ctx*/)
	{
		// ZArchive only asks for a new output "part" when a single archive is split
		// across multiple files - never the case here, one fd for the whole .wua.
	}

	static void WriteOutputData(const void* data, size_t length, void* ctx)
	{
		WuaWriterContext* self = (WuaWriterContext*)ctx;
		size_t written = 0;
		const uint8* p = (const uint8*)data;
		while (written < length)
		{
			ssize_t n = write(self->fd, p + written, length - written);
			if (n <= 0)
				break; // disk full or similar - AppendData/Finalize have no return value
			           // to propagate this through, so the truncated .wua is caught by
			           // the ZArchiveReader verification pass after Finalize() instead.
			written += (size_t)n;
		}
	}
};

// Mirrors WuaConverter.cpp's RecursivelyAddFiles: walks the fsc_* virtual filesystem
// tree TitleInfo::Mount() exposes and copies every file straight into the archive
// writer, one file at a time, never materializing anything on real disk in between.
bool WuaWalkDirectory(ZArchiveWriter& writer, const std::string& archivePath, const std::string& fscPath,
	std::atomic_bool& cancelRequested, uint64& bytesWritten, uint32& filesWritten,
	const std::function<void(uint64 bytesWritten, uint32 filesWritten)>& progressCallback,
	std::vector<uint8>& scratchBuffer)
{
	sint32 fscStatus;
	std::unique_ptr<FSCVirtualFile, void(*)(FSCVirtualFile*)> dirIterator(
		fsc_openDirIterator(fscPath.c_str(), &fscStatus), fsc_close);
	if (!dirIterator)
	{
		cemuLog_log(LogType::Force, "Decrypt-to-WUA: could not open directory '{}', skipping it", fscPath);
		return true; // same skip-not-abort policy as DecryptWalkDirectory above
	}

	writer.MakeDir(archivePath.c_str(), false);

	FSCDirEntry dirEntry;
	while (fsc_nextDir(dirIterator.get(), &dirEntry))
	{
		if (cancelRequested.load())
			return false;

		std::string name(dirEntry.GetPath());
		if (name.empty())
			continue;

		if (dirEntry.isDirectory)
		{
			if (!WuaWalkDirectory(writer, archivePath + name + "/", fscPath + name + "/",
					cancelRequested, bytesWritten, filesWritten, progressCallback, scratchBuffer))
				return false;
			continue;
		}

		if (!dirEntry.isFile)
			continue;

		sint32 openStatus;
		std::unique_ptr<FSCVirtualFile, void(*)(FSCVirtualFile*)> file(
			fsc_open((fscPath + name).c_str(), FSC_ACCESS_FLAG::OPEN_FILE | FSC_ACCESS_FLAG::READ_PERMISSION, &openStatus),
			fsc_close);
		if (!file)
		{
			cemuLog_log(LogType::Force, "Decrypt-to-WUA: could not open '{}', skipping it", fscPath + name);
			continue;
		}

		writer.StartNewFile((archivePath + name).c_str());
		if (scratchBuffer.size() < kDecryptChunkSize)
			scratchBuffer.resize(kDecryptChunkSize);

		uint32 got;
		while ((got = file->fscReadData(scratchBuffer.data(), (uint32)scratchBuffer.size())) != 0)
		{
			if (cancelRequested.load())
				return false;
			writer.AppendData(scratchBuffer.data(), got);
			bytesWritten += got;
		}
		filesWritten++;
		if (progressCallback)
			progressCallback(bytesWritten, filesWritten);
	}
	return true;
}
} // namespace

int IOSTitleDecrypt_ExtractToWua(const char* srcPath, const char* destWuaPath,
	std::atomic_bool& cancelRequested,
	const std::function<void(uint64 bytesWritten, uint32 filesWritten)>& progressCallback)
{
	if (!srcPath || srcPath[0] == '\0' || !destWuaPath || destWuaPath[0] == '\0')
		return IOS_DECRYPT_UNABLE_TO_MOUNT;

	fs::path dest(destWuaPath);
	std::error_code ec;
	fs::create_directories(dest.parent_path(), ec);

	TitleInfo titleInfo{fs::path(srcPath)};
	if (!titleInfo.IsValid())
	{
		cemuLog_log(LogType::Force, "Decrypt-to-WUA: could not recognize '{}' as a title", srcPath);
		return IOS_DECRYPT_UNABLE_TO_MOUNT;
	}

	int fd = open(destWuaPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd < 0)
	{
		cemuLog_log(LogType::Force, "Decrypt-to-WUA: destination '{}' is not writable", dest.string());
		return IOS_DECRYPT_DEST_NOT_WRITABLE;
	}

	WuaWriterContext writerCtx{fd};
	ZArchiveWriter archiveWriter(&WuaWriterContext::NewOutputFile, &WuaWriterContext::WriteOutputData, &writerCtx);

	std::string mountPath = TitleInfo::GetUniqueTempMountingPath();
	if (!titleInfo.Mount(mountPath, "", FSC_PRIORITY_BASE))
	{
		// Previously ignored: a mount failure here silently produced a well-formed but
		// empty .wua, reported as success, instead of the real failure.
		cemuLog_log(LogType::Force, "Decrypt-to-WUA: failed to mount '{}' for reading", srcPath);
		close(fd);
		return IOS_DECRYPT_UNABLE_TO_MOUNT;
	}

	std::string archiveRoot = fmt::format("{:016x}_v{}/", titleInfo.GetAppTitleId(), titleInfo.GetAppTitleVersion());

	uint64 bytesWritten = 0;
	uint32 filesWritten = 0;
	std::vector<uint8> scratchBuffer;
	bool completed = WuaWalkDirectory(archiveWriter, archiveRoot, mountPath, cancelRequested,
		bytesWritten, filesWritten, progressCallback, scratchBuffer);

	titleInfo.Unmount(mountPath);

	if (!completed)
	{
		close(fd);
		std::error_code rmEc;
		fs::remove(dest, rmEc); // a cancelled .wua is not a valid archive - don't leave it behind
		cemuLog_log(LogType::Force, "Decrypt-to-WUA: cancelled - '{}' removed", dest.string());
		return IOS_DECRYPT_CANCELLED;
	}

	archiveWriter.Finalize();
	close(fd);

	// Same verification WuaConverter.cpp does on Android: open what was just written
	// back up as a reader before calling it done, so a truncated or corrupt .wua is
	// caught here rather than surfacing later as an unbootable file the user has to
	// debug on their own.
	ZArchiveReader* verify = ZArchiveReader::OpenFromFile(dest);
	if (!verify)
	{
		cemuLog_log(LogType::Force, "Decrypt-to-WUA: '{}' failed verification after writing", dest.string());
		return IOS_DECRYPT_DEST_NOT_WRITABLE;
	}
	delete verify;

	cemuLog_log(LogType::Force, "Decrypt-to-WUA: finished - {} files, {} bytes written to '{}'",
		filesWritten, bytesWritten, dest.string());

	return IOS_DECRYPT_OK;
}
