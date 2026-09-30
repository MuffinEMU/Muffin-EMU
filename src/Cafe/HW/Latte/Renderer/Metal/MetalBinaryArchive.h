#pragma once

#include <atomic>
#include <cstdint>
#include <string>

namespace MTL
{
class Device;
class RenderPipelineDescriptor;
class RenderPipelineState;
} // namespace MTL
namespace NS
{
class Error;
}

// Persists compiled GPU code for render pipelines across launches using an MTLBinaryArchive.
//
// One archive per title, keyed on the GPU, the OS build and the app build, because compiled
// binaries are specific to all three. Whatever is left from another key is deleted when the
// archive opens.
//
// Two archive objects are opened from the same file. The READ archive is attached to pipeline
// descriptors and is never modified or serialised. The WRITE archive is touched only by the
// background worker (add, serialise) and is never referenced by a descriptor. A save replaces
// the file; the next launch opens it as its read archive. So no archive object is ever read
// and written at the same time.
//
// Everything here is best effort: any failure (unsupported GPU, corrupt file, full disk)
// drops back to plain pipeline creation and never throws or crashes.
//
// What it does NOT save: the MSL -> AIR step. Shader libraries are still compiled from source
// on every launch (newLibrary(source)); the archive only skips the AIR -> GPU binary step.
class MetalBinaryArchive
{
public:
	struct Stats
	{
		bool active = false;
		uint64_t fileBytes = 0;		// size of the archive on disk (as loaded or last saved)
		int64_t entriesAtLoad = -1; // -1 when unknown
		uint32_t hits = 0;
		uint32_t misses = 0;
		uint32_t added = 0;			// pipelines added this session
		uint32_t dropped = 0;		// adds skipped (queue full, archive full, disabled)
		uint32_t saves = 0;
	};

	static MetalBinaryArchive& GetInstance();

	// User setting ("Save compiled shaders"). Read when a title starts; changing it while a
	// title runs only affects the next launch.
	static void SetEnabledSetting(bool enabled);
	static bool GetEnabledSetting();

	// Title lifecycle. Open() is cheap and safe to call when unsupported or disabled.
	void Open(MTL::Device* device, uint64_t titleId);
	void OnLoadingFinished(); // schedules a save after the "loading shaders" phase
	void Close();			  // saves (bounded wait) and releases

	// Saves now if anything changed. Waits up to timeoutMs for queued adds to drain first.
	// Used when the app moves to the background.
	void Flush(uint32_t timeoutMs);

	// Drop-in for device->newRenderPipelineState(desc, &error). Consults the archive first and
	// queues new pipelines for the archive. Falls back to plain creation when inactive.
	// May modify desc (sets its binaryArchives).
	MTL::RenderPipelineState* CreateRenderPipeline(MTL::Device* device, MTL::RenderPipelineDescriptor* desc, NS::Error** error);

	bool IsActive() const { return m_active.load(std::memory_order_acquire); }
	Stats GetStats() const;
	// One line for the log or the perf overlay, e.g. "archive hit 812 miss 14 add 14 (2.1 MB)".
	std::string FormatStatsLine() const;

private:
	MetalBinaryArchive();
	~MetalBinaryArchive();
	struct Impl;
	Impl* m_impl;
	std::atomic<bool> m_active{false};
};
