#include "Cafe/HW/Latte/Renderer/Metal/MetalBinaryArchive.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalCommon.h"

#include "Cemu/Logging/CemuLogging.h"
#include "Common/precompiled.h"
#include "config/ActiveSettings.h"
#include "util/helpers/helpers.h"

#include <CoreFoundation/CoreFoundation.h>
#include <pthread.h>
#include <sys/sysctl.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <thread>

namespace
{
namespace sfs = std::filesystem;
using Clock = std::chrono::steady_clock;

// Bump when the way archives are used changes in a way that makes old files worthless.
constexpr uint32_t kArchiveSchemaVersion = 1;

constexpr uint64_t kMinFreeBytesToUse = 256ull << 20; // below this the archive stays off
constexpr uint64_t kMinFreeBytesToSave = 128ull << 20;
constexpr uint64_t kMinCapBytes = 16ull << 20;
constexpr uint64_t kMaxCapBytes = 384ull << 20;
constexpr size_t kMaxQueuedAdds = 4096; // descriptors are small (functions are shared); bounds RAM
constexpr uint32_t kSaveEveryNAdds = 128;
constexpr auto kSaveMinInterval = std::chrono::seconds(45);
constexpr auto kSaveRetryCooldown = std::chrono::minutes(5);

std::atomic<bool> s_enabledSetting{true};

uint32_t Fnv1a32(const std::string& s)
{
	uint32_t h = 2166136261u;
	for (unsigned char c : s)
	{
		h ^= c;
		h *= 16777619u;
	}
	return h;
}

std::string SanitizeForFilename(std::string s)
{
	for (char& c : s)
		if (!isalnum(static_cast<unsigned char>(c)))
			c = '-';
	return s;
}

std::string GetOsBuild()
{
	char buf[64] = {};
	size_t len = sizeof(buf);
	if (sysctlbyname("kern.osversion", buf, &len, nullptr, 0) != 0)
		return "unknown";
	return SanitizeForFilename(buf);
}

std::string GetAppBuild()
{
	std::string result = "0";
	CFBundleRef bundle = CFBundleGetMainBundle();
	if (!bundle)
		return result;
	CFTypeRef value = CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleVersionKey);
	if (value && CFGetTypeID(value) == CFStringGetTypeID())
	{
		char buf[64] = {};
		if (CFStringGetCString(static_cast<CFStringRef>(value), buf, sizeof(buf), kCFStringEncodingUTF8))
			result = buf;
	}
	return result;
}

// Highest Apple GPU family the device supports (1..9), 0 if none.
int GetAppleGpuFamily(MTL::Device* device)
{
	for (int i = 9; i >= 1; --i)
	{
		if (device->supportsFamily(static_cast<MTL::GPUFamily>(1000 + i)))
			return i;
	}
	return 0;
}

uint64_t FileSizeOrZero(const sfs::path& p)
{
	std::error_code ec;
	auto size = sfs::file_size(p, ec);
	return ec ? 0 : static_cast<uint64_t>(size);
}

void RemoveQuiet(const sfs::path& p)
{
	std::error_code ec;
	sfs::remove(p, ec);
}
} // namespace

struct MetalBinaryArchive::Impl
{
	// Two archives are opened from the same file, so nothing is ever read and written through
	// the same object:
	//  - read archive: attached to pipeline descriptors, never modified, never serialised.
	//    readMutex only guards the pointer, so an in-flight pipeline creation can take its
	//    own reference and is unaffected when Close() drops ours.
	//  - write archive: only the worker thread adds to and serialises it. Descriptors never
	//    reference it. archiveMutex guards it against Release().
	// The next launch opens the saved file as its new read archive.
	std::mutex readMutex;
	MTL::BinaryArchive* readArchive = nullptr;
	NS::Array* readArray = nullptr;
	std::mutex archiveMutex;
	MTL::BinaryArchive* archive = nullptr; // the write archive
	sfs::path path, tmpPath, countPath, markerPath;
	uint64_t capBytes = 0;
	std::atomic<uint64_t> fileBytes{0};
	int64_t entriesAtLoad = -1;
	bool entriesKnown = false;

	// Worker state. queueMutex guards everything below.
	std::mutex queueMutex;
	std::condition_variable cv;
	std::condition_variable doneCv;
	std::deque<MTL::RenderPipelineDescriptor*> queue;
	std::thread worker;
	bool stop = false;
	bool saveRequested = false;
	bool busy = false;
	Clock::time_point drainDeadline{};
	Clock::time_point lastSave = Clock::now();
	Clock::time_point saveBlockedUntil{};
	uint32_t addsSinceSave = 0;

	std::atomic<bool> full{false};
	std::atomic<bool> addsDisabled{false};
	std::atomic<uint32_t> hits{0}, misses{0}, added{0}, dropped{0}, saves{0};

	void WorkerMain();
	bool SaveLocked();
	void QueueAdd(MTL::RenderPipelineDescriptor* desc);
	void Release();
};

MetalBinaryArchive::MetalBinaryArchive() : m_impl(new Impl()) {}

MetalBinaryArchive::~MetalBinaryArchive()
{
	Close();
	delete m_impl;
}

MetalBinaryArchive& MetalBinaryArchive::GetInstance()
{
	static MetalBinaryArchive* s_instance = new MetalBinaryArchive(); // intentionally leaked, lives until process exit
	return *s_instance;
}

void MetalBinaryArchive::SetEnabledSetting(bool enabled)
{
	s_enabledSetting.store(enabled);
}

bool MetalBinaryArchive::GetEnabledSetting()
{
	return s_enabledSetting.load();
}

void MetalBinaryArchive::Open(MTL::Device* device, uint64_t titleId)
{
	if (m_active.load())
		Close();
	if (!device)
		return;
	if (!s_enabledSetting.load())
	{
		cemuLog_log(LogType::Force, "Metal archive: off (Save compiled shaders is disabled)");
		return;
	}
	if (!__builtin_available(iOS 14.0, macOS 11.0, *))
	{
		cemuLog_log(LogType::Force, "Metal archive: unavailable (needs iOS 14)");
		return;
	}
	if (!device->supportsFamily(MTL::GPUFamilyApple3))
	{
		cemuLog_log(LogType::Force, "Metal archive: unavailable (GPU family below Apple3)");
		return;
	}

	NS_STACK_SCOPED NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
	Impl& d = *m_impl;

	// Budget from free storage
	std::error_code ec;
	sfs::path dir = ActiveSettings::GetCachePath("shaderCache/metal");
	sfs::create_directories(dir, ec);
	const uint64_t avail = static_cast<uint64_t>(sfs::space(dir, ec).available);
	if (ec || avail < kMinFreeBytesToUse)
	{
		cemuLog_log(LogType::Force, "Metal archive: off (only {} MB free)", ec ? 0 : avail >> 20);
		return;
	}
	d.capBytes = std::clamp<uint64_t>(avail / 8, kMinCapBytes, kMaxCapBytes);

	// Key: title, GPU (family + name), OS build, app build
	const int family = GetAppleGpuFamily(device);
	const std::string deviceName = device->name() ? device->name()->utf8String() : "";
	const std::string osBuild = GetOsBuild();
	const uint32_t keyHash = Fnv1a32(deviceName + "|" + GetAppBuild() + "|" + std::to_string(kArchiveSchemaVersion));
	const std::string stem = fmt::format("{:016x}_a{}_{}_{:08x}", titleId, family, osBuild, keyHash);
	d.path = dir / (stem + ".metallib");
	d.tmpPath = dir / (stem + ".metallib.tmp");
	d.countPath = dir / (stem + ".count");
	d.markerPath = dir / (stem + ".loading");

	// Delete this title's archives made for another GPU, OS or app build
	{
		const std::string titlePrefix = fmt::format("{:016x}_", titleId);
		for (auto& entry : sfs::directory_iterator(dir, ec))
		{
			const std::string name = entry.path().filename().string();
			if (name.rfind(titlePrefix, 0) == 0 && name.rfind(stem, 0) != 0)
			{
				cemuLog_log(LogType::Force, "Metal archive: removing stale file {}", name);
				RemoveQuiet(entry.path());
			}
		}
	}

	// A marker left behind means the previous session died while this archive was loading or
	// being filled during "loading shaders". Distrust the file rather than crash-loop on it.
	if (sfs::exists(d.markerPath, ec))
	{
		cemuLog_log(LogType::Force, "Metal archive: previous session did not finish loading, discarding archive");
		RemoveQuiet(d.path);
		RemoveQuiet(d.countPath);
		RemoveQuiet(d.markerPath);
	}
	RemoveQuiet(d.tmpPath);
	{
		std::ofstream marker(d.markerPath);
	}

	// Load the read and write archives from the existing file, or start empty
	d.entriesAtLoad = 0;
	d.entriesKnown = true;
	d.fileBytes = 0;
	bool writeUnavailable = false;
	auto openFromFile = [&](NS::Error** error) -> MTL::BinaryArchive* {
		NS_STACK_SCOPED MTL::BinaryArchiveDescriptor* desc = MTL::BinaryArchiveDescriptor::alloc()->init();
		desc->setUrl(ToNSURL(d.path.string()));
		return device->newBinaryArchive(desc, error);
	};
	if (sfs::exists(d.path, ec))
	{
		const uint64_t size = FileSizeOrZero(d.path);
		NS::Error* error = nullptr;
		MTL::BinaryArchive* readArchive = openFromFile(&error);
		if (readArchive)
		{
			d.readArchive = readArchive;
			d.archive = openFromFile(&error);
			writeUnavailable = (d.archive == nullptr); // never write through the read archive
			d.fileBytes = size;
			std::ifstream in(d.countPath);
			int64_t count = -1;
			if (in >> count)
				d.entriesAtLoad = count;
			else
				d.entriesKnown = false;
		}
		else
		{
			cemuLog_log(LogType::Force, "Metal archive: could not load existing archive ({}), starting fresh", error ? error->localizedDescription()->utf8String() : "unknown error");
			RemoveQuiet(d.path);
			RemoveQuiet(d.countPath);
		}
	}
	if (!d.readArchive)
	{
		NS_STACK_SCOPED MTL::BinaryArchiveDescriptor* desc = MTL::BinaryArchiveDescriptor::alloc()->init();
		NS::Error* error = nullptr;
		d.archive = device->newBinaryArchive(desc, &error);
		d.entriesAtLoad = 0;
		d.entriesKnown = true;
		if (!d.archive)
		{
			cemuLog_log(LogType::Force, "Metal archive: off (could not create archive: {})", error ? error->localizedDescription()->utf8String() : "unknown error");
			RemoveQuiet(d.markerPath);
			return;
		}
	}
	if (d.readArchive)
		d.readArray = NS::Array::array(d.readArchive)->retain();

	d.hits = d.misses = d.added = d.dropped = d.saves = 0;
	d.full = writeUnavailable || d.fileBytes.load() >= d.capBytes;
	d.addsDisabled = false;
	d.addsSinceSave = 0;
	d.lastSave = Clock::now();
	d.saveBlockedUntil = Clock::time_point{};
	d.stop = false;
	d.saveRequested = false;
	d.worker = std::thread(&Impl::WorkerMain, &d);

	m_active.store(true, std::memory_order_release);
	cemuLog_log(LogType::Force, "Metal archive: {} read archive {} ({:.1f} MB, {} entries), separate write archive {}, cap {} MB, GPU family Apple{}", d.readArchive ? "opened" : "no existing file, no", stem, d.fileBytes.load() / 1048576.0,
				d.entriesKnown ? std::to_string(d.entriesAtLoad) : std::string("unknown"), writeUnavailable ? "unavailable (read only)" : "ready", d.capBytes >> 20, family);
}

void MetalBinaryArchive::OnLoadingFinished()
{
	if (!IsActive())
		return;
	Impl& d = *m_impl;
	RemoveQuiet(d.markerPath); // made it through "loading shaders"
	{
		std::lock_guard lock(d.queueMutex);
		d.saveRequested = true;
		d.drainDeadline = Clock::time_point::max(); // not urgent: let queued adds finish first
	}
	d.cv.notify_all();
	cemuLog_log(LogType::Force, "Metal archive: {}", FormatStatsLine());
}

void MetalBinaryArchive::Flush(uint32_t timeoutMs)
{
	if (!IsActive())
		return;
	Impl& d = *m_impl;
	std::unique_lock lock(d.queueMutex);
	d.saveRequested = true;
	d.drainDeadline = Clock::now() + std::chrono::milliseconds(timeoutMs);
	d.cv.notify_all();
	d.doneCv.wait_for(lock, std::chrono::milliseconds(timeoutMs + 1500), [&] { return !d.saveRequested && !d.busy; });
}

void MetalBinaryArchive::Close()
{
	if (!m_active.load())
		return;
	Impl& d = *m_impl;
	Flush(3000);
	m_active.store(false, std::memory_order_release);
	{
		std::lock_guard lock(d.queueMutex);
		d.stop = true;
	}
	d.cv.notify_all();
	if (d.worker.joinable())
		d.worker.join();
	cemuLog_log(LogType::Force, "Metal archive: closed, {}", FormatStatsLine());
	RemoveQuiet(d.markerPath); // clean exit
	d.Release();
}

void MetalBinaryArchive::Impl::Release()
{
	{
		std::lock_guard lock(queueMutex);
		for (auto* desc : queue)
			desc->release();
		queue.clear();
	}
	{
		std::lock_guard readLock(readMutex);
		if (readArray)
		{
			readArray->release();
			readArray = nullptr;
		}
		if (readArchive)
		{
			readArchive->release();
			readArchive = nullptr;
		}
	}
	std::lock_guard lock(archiveMutex);
	if (archive)
	{
		archive->release();
		archive = nullptr;
	}
}

MTL::RenderPipelineState* MetalBinaryArchive::CreateRenderPipeline(MTL::Device* device, MTL::RenderPipelineDescriptor* desc, NS::Error** error)
{
	if (!IsActive())
		return device->newRenderPipelineState(desc, error);

	Impl& d = *m_impl;

	// Take our own reference to the read archive for the duration of this call, so Close()
	// releasing the shared one cannot pull it out from under a creation in progress.
	NS::Array* readArray = nullptr;
	{
		std::lock_guard lock(d.readMutex);
		if (d.readArray)
			readArray = d.readArray->retain();
	}

	MTL::RenderPipelineState* pipeline = nullptr;
	uint32_t missCount = 0;
	if (readArray)
	{
		desc->setBinaryArchives(readArray);
		// Probe: is it already in the read archive? This only detects hits, a miss falls
		// through to a normal compile below and never fails the pipeline.
		NS::Error* probeError = nullptr;
		pipeline = device->newRenderPipelineState(desc, MTL::PipelineOptionFailOnBinaryArchiveMiss, nullptr, &probeError);
		if (pipeline)
			++d.hits;
		else
			missCount = ++d.misses;
	}
	else
		missCount = ++d.misses; // nothing to read from yet (first play of this title)
	if (pipeline)
	{
		readArray->release();
		return pipeline;
	}

	pipeline = device->newRenderPipelineState(desc, MTL::PipelineOptionNone, nullptr, error);
	if (readArray)
		readArray->release();
	if (!pipeline)
		return nullptr;

	// An archive that was loaded with entries but never matches means the keys are not stable
	// for this kind of function. Stop growing it instead of filling storage with duplicates.
	if (d.entriesKnown && d.entriesAtLoad > 0 && d.hits.load() == 0 && missCount >= 64 && !d.addsDisabled.exchange(true))
		cemuLog_log(LogType::Force, "Metal archive: {} pipelines missed and none hit an archive with {} entries, no longer adding", missCount, d.entriesAtLoad);

	d.QueueAdd(desc);
	return pipeline;
}

void MetalBinaryArchive::Impl::QueueAdd(MTL::RenderPipelineDescriptor* desc)
{
	if (full.load() || addsDisabled.load())
	{
		++dropped;
		return;
	}
	MTL::RenderPipelineDescriptor* copy = desc->copy();
	copy->setBinaryArchives(nullptr); // queued copies hold no archive at all
	{
		std::lock_guard lock(queueMutex);
		if (stop || queue.size() >= kMaxQueuedAdds)
		{
			copy->release();
			++dropped;
			return;
		}
		queue.push_back(copy);
	}
	cv.notify_one();
}

void MetalBinaryArchive::Impl::WorkerMain()
{
	SetThreadName("mtlArchive");
	pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);
	std::unique_lock lock(queueMutex);
	while (true)
	{
		cv.wait_for(lock, std::chrono::seconds(5), [&] { return stop || !queue.empty() || saveRequested; });

		const auto now = Clock::now();
		const bool drainFirst = !queue.empty() && (!saveRequested || now < drainDeadline) && !stop;
		if (drainFirst)
		{
			MTL::RenderPipelineDescriptor* desc = queue.front();
			queue.pop_front();
			busy = true;
			lock.unlock();
			{
				NS_STACK_SCOPED NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
				std::lock_guard archiveLock(archiveMutex);
				if (archive && !full.load())
				{
					NS::Error* error = nullptr;
					if (archive->addRenderPipelineFunctions(desc, &error))
					{
						++added;
						++addsSinceSave;
					}
					else
					{
						++dropped;
						cemuLog_log(LogType::Force, "Metal archive: add failed: {}", error ? error->localizedDescription()->utf8String() : "unknown error");
					}
				}
				else
					++dropped;
			}
			desc->release();
			lock.lock();
			busy = false;
		}

		const bool periodic = addsSinceSave >= kSaveEveryNAdds && (now - lastSave) >= kSaveMinInterval;
		const bool doSave = (saveRequested && (queue.empty() || now >= drainDeadline || stop)) || (periodic && !saveRequested);
		if (doSave)
		{
			const bool wasRequested = saveRequested;
			busy = true;
			lock.unlock();
			bool ok = true;
			if (now >= saveBlockedUntil || wasRequested)
			{
				NS_STACK_SCOPED NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
				std::lock_guard archiveLock(archiveMutex);
				ok = SaveLocked();
			}
			lock.lock();
			busy = false;
			saveRequested = false;
			lastSave = Clock::now();
			if (!ok)
				saveBlockedUntil = Clock::now() + kSaveRetryCooldown;
			doneCv.notify_all();
		}
		else if (queue.empty() && !saveRequested)
			doneCv.notify_all();

		if (stop && !saveRequested)
			break; // anything still queued is released by Release()
	}
	doneCv.notify_all();
}

// Called with archiveMutex held, off the render and pipeline threads.
bool MetalBinaryArchive::Impl::SaveLocked()
{
	if (!archive)
		return false;
	if (addsSinceSave == 0)
		return true; // nothing new

	std::error_code ec;
	const uint64_t avail = static_cast<uint64_t>(sfs::space(path.parent_path(), ec).available);
	if (ec || avail < kMinFreeBytesToSave)
	{
		cemuLog_log(LogType::Force, "Metal archive: not saving, only {} MB free", ec ? 0 : avail >> 20);
		full = true;
		return false;
	}

	RemoveQuiet(tmpPath);
	NS::Error* error = nullptr;
	if (!archive->serializeToURL(ToNSURL(tmpPath.string()), &error))
	{
		cemuLog_log(LogType::Force, "Metal archive: save failed: {}", error ? error->localizedDescription()->utf8String() : "unknown error");
		RemoveQuiet(tmpPath);
		return false;
	}
	sfs::rename(tmpPath, path, ec); // atomic on the same volume
	if (ec)
	{
		cemuLog_log(LogType::Force, "Metal archive: could not move the saved archive into place: {}", ec.message());
		RemoveQuiet(tmpPath);
		return false;
	}

	const uint64_t size = FileSizeOrZero(path);
	fileBytes = size;
	addsSinceSave = 0;
	++saves;
	if (entriesKnown)
	{
		const sfs::path countTmp = countPath.string() + ".tmp";
		{
			std::ofstream out(countTmp);
			out << (entriesAtLoad + static_cast<int64_t>(added.load())) << "\n";
		}
		sfs::rename(countTmp, countPath, ec);
	}
	if (size >= capBytes && !full.exchange(true))
		cemuLog_log(LogType::Force, "Metal archive: reached its {} MB cap, no longer adding", capBytes >> 20);
	return true;
}

MetalBinaryArchive::Stats MetalBinaryArchive::GetStats() const
{
	Stats s;
	const Impl& d = *m_impl;
	s.active = IsActive();
	s.fileBytes = d.fileBytes.load();
	s.entriesAtLoad = d.entriesKnown ? d.entriesAtLoad : -1;
	s.hits = d.hits;
	s.misses = d.misses;
	s.added = d.added;
	s.dropped = d.dropped;
	s.saves = d.saves;
	return s;
}

std::string MetalBinaryArchive::FormatStatsLine() const
{
	const Stats s = GetStats();
	if (!s.active)
		return "archive off";
	return fmt::format("archive read hit {} miss {} | write add {} dropped {} saves {} | file {:.1f} MB", s.hits, s.misses, s.added, s.dropped, s.saves, s.fileBytes / 1048576.0);
}
