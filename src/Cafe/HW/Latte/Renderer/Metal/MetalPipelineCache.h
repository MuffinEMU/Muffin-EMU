#pragma once

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <thread>

#include "Cafe/HW/Latte/Renderer/Metal/MetalPipelineCompiler.h"
#include "util/helpers/ConcurrentQueue.h"
#include "util/helpers/fspinlock.h"
#include "util/math/vector2.h"

// Drops the asynchronous pipeline compiles that are queued and waits for the running ones (see MetalPipelineCache.cpp)
void MetalPipelineCache_DrainAsyncCompiles();
size_t MetalPipelineCache_GetAsyncCompileCount();
// true if a loader thread could not be stopped in time: it may still use the renderer and the cache, which were leaked instead of freed
bool MetalPipelineCache_LoaderAbandoned();

NS::Array* MetalPipelineCache_GetBinaryArchives();
void MetalPipelineCache_NoteArchiveLookup(bool hit);
void MetalPipelineCache_QueueArchiveAdd(MTL::RenderPipelineDescriptor* desc);

class MetalPipelineCache
{
public:
	static MetalPipelineCache& GetInstance();

    MetalPipelineCache(class MetalRenderer* metalRenderer);
    ~MetalPipelineCache();

    PipelineObject* GetRenderPipelineState(const LatteFetchShader* fetchShader, const LatteDecompilerShader* vertexShader, const LatteDecompilerShader* geometryShader, const LatteDecompilerShader* pixelShader, const class MetalAttachmentsInfo& lastUsedAttachmentsInfo, const class MetalAttachmentsInfo& activeAttachmentsInfo, Vector2i extend, uint32 indexCount, const LatteContextRegister& lcr);

    // Cache loading
	uint32 BeginLoading(uint64 cacheTitleId); // returns count of pipelines stored in cache
	bool UpdateLoading(uint32& pipelinesLoadedTotal, uint32& pipelinesMissingShaders);
	void EndLoading();
	void LoadPipelineFromCache(std::span<uint8> fileData);
       void Close(); // called on title exit
	// stops and waits for the background loader threads; false if they are still running after timeoutMs
	bool StopLoading(uint32 timeoutMs);

    NS::Array* GetBinaryArchives() const { return m_binaryArchives; }
    void NoteArchiveLookup(bool hit) { (hit ? m_archiveHits : m_archiveMisses).fetch_add(1, std::memory_order_relaxed); }
    void QueueArchiveAdd(MTL::RenderPipelineDescriptor* desc);

    // Debug
    size_t GetPipelineCacheSize() const { return m_pipelineCache.size(); }

private:
    class MetalRenderer* m_mtlr;

    std::map<uint64, PipelineObject*> m_pipelineCache;
    FSpinlock m_pipelineCacheLock;

	std::thread* m_pipelineCacheStoreThread{nullptr};

	class FileCache* s_cache{nullptr};

	std::atomic_uint32_t m_numCompilationThreads{ 0 };
	std::atomic_uint32_t m_loaderThreadsRunning{ 0 };
	ConcurrentQueue<std::vector<uint8>> m_compilationQueue;
	std::atomic_uint32_t m_compilationCount;

    static uint64 CalculatePipelineHash(const LatteFetchShader* fetchShader, const LatteDecompilerShader* vertexShader, const LatteDecompilerShader* geometryShader, const LatteDecompilerShader* pixelShader, const class MetalAttachmentsInfo& lastUsedAttachmentsInfo, const class MetalAttachmentsInfo& activeAttachmentsInfo, const LatteContextRegister& lcr);

    void AddCurrentStateToCache(uint64 pipelineStateHash, const class MetalAttachmentsInfo& lastUsedAttachmentsInfo);

	// pipeline serialization for file
	bool SerializePipeline(class MemStreamWriter& memWriter, struct CachedPipeline& cachedPipeline);
	bool DeserializePipeline(class MemStreamReader& memReader, struct CachedPipeline& cachedPipeline);

    NS::Array* m_binaryArchives{nullptr};
    std::atomic_uint32_t m_archiveHits{0};
    std::atomic_uint32_t m_archiveMisses{0};
    std::atomic_uint32_t m_pipelinesDeduped{0};
    std::chrono::steady_clock::time_point m_loadStart;
    uint32_t m_loadShaderCompilesAtStart{0};
    uint64_t m_loadShaderCompileNsAtStart{0};
    uint32_t m_loadPipelineCompilesAtStart{0};
    uint64_t m_loadPipelineCompileNsAtStart{0};
    uint32_t m_archiveFilesLoaded{0};

    std::mutex m_archiveMutex;
    std::condition_variable m_archiveCv;
    std::deque<MTL::RenderPipelineDescriptor*> m_archiveQueue;
    std::thread* m_archiveThread{nullptr};
    bool m_archiveStop{false};
    std::atomic<bool> m_archiveWriteEnabled{false};
    std::string m_archiveWritePath;
    uint64_t m_archiveBaseBytes{0};

    void OpenBinaryArchives(uint64 cacheTitleId);
    void CloseBinaryArchives();
    void BinaryArchiveWriterThread();

    int CompilerThread();
	void WorkerThread();
};
