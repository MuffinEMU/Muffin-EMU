#include "Cafe/HW/Latte/Renderer/Metal/MetalPipelineCache.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalRenderer.h"
#include "Cafe/HW/Latte/Renderer/Metal/LatteToMtl.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalPipelineCompiler.h"

#include "Cafe/HW/Latte/Core/FetchShader.h"
#include "Cafe/HW/Latte/ISA/RegDefines.h"
#include "Cafe/HW/Latte/Core/LatteConst.h"
#include "Cafe/HW/Latte/Common/RegisterSerializer.h"
#include "Cafe/HW/Latte/Core/LatteShaderCache.h"
#include "Cafe/HW/Latte/Core/LatteShader.h"
#include "Cafe/HW/Latte/Core/PerfTelemetry.h"
#include "Cafe/HW/Latte/ISA/LatteReg.h"
#include "Cemu/FileCache/FileCache.h"
#include "Common/precompiled.h"
#include "util/helpers/helpers.h"
#include "config/ActiveSettings.h"

#include <openssl/sha.h>
#include <sys/sysctl.h>
#include <chrono>
#include <deque>

static bool g_compilePipelineThreadInit{false};
static std::mutex g_compilePipelineMutex;
static std::condition_variable g_compilePipelineCondVar;
static std::queue<MetalPipelineCompiler*> g_compilePipelineRequests;
// requests that are queued or being compiled. A compile holds references to the renderer, the pipeline object and the
// shaders of the title that is running, so it must be finished or dropped before those are destroyed
static std::atomic<uint32_t> g_compilePipelineInFlight{0};

static void compileThreadFunc(sint32 threadIndex)
{
	SetThreadName("compilePl");

	// one thread runs at normal priority while the others run at lower priority
	if (threadIndex != 0)
		; // TODO: set thread priority

	while (true)
	{
		std::unique_lock lock(g_compilePipelineMutex);
		while (g_compilePipelineRequests.empty())
			g_compilePipelineCondVar.wait(lock);

		MetalPipelineCompiler* request = g_compilePipelineRequests.front();

		g_compilePipelineRequests.pop();

		lock.unlock();

		request->Compile(true, false, true);
		delete request;
		g_compilePipelineInFlight.fetch_sub(1);
	}
}

// Drops the queued async pipeline compiles and waits for the ones that are running. Runs first when a renderer shuts
// down: the compile threads outlive the renderer (they are detached and shared by every title of the process), and a
// request left over would compile against the destroyed renderer, the freed pipeline cache or shaders that were
// deleted with the title.
void MetalPipelineCache_DrainAsyncCompiles()
{
	{
		std::unique_lock lock(g_compilePipelineMutex);
		while (!g_compilePipelineRequests.empty())
		{
			delete g_compilePipelineRequests.front();
			g_compilePipelineRequests.pop();
			g_compilePipelineInFlight.fetch_sub(1);
		}
	}
	// a compile that is already running finishes on its own; bounded so a hung driver call cannot hold up the stop
	for (int i = 0; i < 1500 && g_compilePipelineInFlight.load() != 0; i++)
		std::this_thread::sleep_for(std::chrono::milliseconds(2));
	if (g_compilePipelineInFlight.load() != 0)
		cemuLog_log(LogType::Force, "Metal: {} pipeline compile(s) were still running after 3 s", g_compilePipelineInFlight.load());
}

size_t MetalPipelineCache_GetAsyncCompileCount()
{
	return g_compilePipelineInFlight.load();
}

static void initCompileThread()
{
	uint32 numCompileThreads;

	uint32 cpuCoreCount = GetPhysicalCoreCount();
	if (cpuCoreCount <= 2)
		numCompileThreads = 1;
	else
		numCompileThreads = 2 + (cpuCoreCount - 3); // 2 plus one additionally for every extra core above 3

	numCompileThreads = std::min(numCompileThreads, 8u); // cap at 8

	for (uint32 i = 0; i < numCompileThreads; i++)
	{
		std::thread compileThread(compileThreadFunc, i);
		compileThread.detach();
	}
}

static void queuePipeline(MetalPipelineCompiler* v)
{
	g_compilePipelineInFlight.fetch_add(1);
	std::unique_lock lock(g_compilePipelineMutex);
	g_compilePipelineRequests.push(std::move(v));
	lock.unlock();
	g_compilePipelineCondVar.notify_one();
}

// make a guess if a pipeline is not essential
// non-essential means that skipping these drawcalls shouldn't lead to permanently corrupted graphics
bool IsAsyncPipelineAllowed(const MetalAttachmentsInfo& attachmentsInfo, Vector2i extend, uint32 indexCount)
{
	if (extend.x == 1600 && extend.y == 1600)
		return false; // Splatoon ink mechanics use 1600x1600 R8 and R8G8 framebuffers, this resolution is rare enough that we can just blacklist it globally

	if (attachmentsInfo.depthFormat != Latte::E_GX2SURFFMT::INVALID_FORMAT)
		return true; // aggressive filter but seems to work well so far

	// small index count (3,4,5,6) is often associated with full-viewport quads (which are considered essential due to often being used to generate persistent textures)
	if (indexCount <= 6)
		return false;

	return true;
}

MetalPipelineCache* g_mtlPipelineCache = nullptr;
static std::mutex g_mtlPipelineCacheLifeMutex; // keeps the cache alive while MetalPipelineCache_FlushArchive uses it

MetalPipelineCache& MetalPipelineCache::GetInstance()
{
    return *g_mtlPipelineCache;
}

MetalPipelineCache::MetalPipelineCache(class MetalRenderer* metalRenderer) : m_mtlr{metalRenderer}
{
    g_mtlPipelineCache = this;
}

MetalPipelineCache::~MetalPipelineCache()
{
    std::lock_guard<std::mutex> lifeLock(g_mtlPipelineCacheLifeMutex);
    EndLoading(); // no-op if loading already ended: stops the background loader threads, which hold this pointer
    Close();      // stops the cache writer thread, which also holds it, and drops what it had not written yet
    for (auto& [key, pipelineObj] : m_pipelineCache)
    {
        if (pipelineObj->m_pipeline)
            pipelineObj->m_pipeline->release();
        delete pipelineObj;
    }
    if (g_mtlPipelineCache == this)
        g_mtlPipelineCache = nullptr;
}

PipelineObject* MetalPipelineCache::GetRenderPipelineState(const LatteFetchShader* fetchShader, const LatteDecompilerShader* vertexShader, const LatteDecompilerShader* geometryShader, const LatteDecompilerShader* pixelShader, const MetalAttachmentsInfo& lastUsedAttachmentsInfo, const MetalAttachmentsInfo& activeAttachmentsInfo, Vector2i extend, uint32 indexCount, const LatteContextRegister& lcr)
{
    uint64 hash = CalculatePipelineHash(fetchShader, vertexShader, geometryShader, pixelShader, lastUsedAttachmentsInfo, activeAttachmentsInfo, lcr);
    PipelineObject*& pipelineObj = m_pipelineCache[hash];
    if (pipelineObj)
        return pipelineObj;

    pipelineObj = new PipelineObject();

    MetalPipelineCompiler* compiler = new MetalPipelineCompiler(m_mtlr, *pipelineObj);
    compiler->InitFromState(fetchShader, vertexShader, geometryShader, pixelShader, lastUsedAttachmentsInfo, activeAttachmentsInfo, lcr);

    bool allowAsyncCompile = false;
    if (GetConfig().async_compile)
		allowAsyncCompile = IsAsyncPipelineAllowed(activeAttachmentsInfo, extend, indexCount);

	if (allowAsyncCompile)
	{
	    if (!g_compilePipelineThreadInit)
		{
			initCompileThread();
			g_compilePipelineThreadInit = true;
		}

		queuePipeline(compiler);
	}
	else
	{
	    // Also force compile to ensure that the pipeline is ready
        PerfTelemetry::Get().pipelineSyncCompiles.fetch_add(1, std::memory_order_relaxed);
        cemu_assert_debug(compiler->Compile(true, true, true));
        delete compiler;
	}

	// Save to cache
    AddCurrentStateToCache(hash, lastUsedAttachmentsInfo);

    return pipelineObj;
}

uint64 MetalPipelineCache::CalculatePipelineHash(const LatteFetchShader* fetchShader, const LatteDecompilerShader* vertexShader, const LatteDecompilerShader* geometryShader, const LatteDecompilerShader* pixelShader, const MetalAttachmentsInfo& lastUsedAttachmentsInfo, const MetalAttachmentsInfo& activeAttachmentsInfo, const LatteContextRegister& lcr)
{
    // Hash
    uint64 stateHash = 0;
    for (int i = 0; i < Latte::GPU_LIMITS::NUM_COLOR_ATTACHMENTS; ++i)
	{
	    Latte::E_GX2SURFFMT format = lastUsedAttachmentsInfo.colorFormats[i];
		if (format == Latte::E_GX2SURFFMT::INVALID_FORMAT)
            continue;

		stateHash += GetMtlPixelFormat(format, false) + i * 31;
		stateHash = std::rotl<uint64>(stateHash, 7);

		if (activeAttachmentsInfo.colorFormats[i] == Latte::E_GX2SURFFMT::INVALID_FORMAT)
		{
            stateHash += 1;
		    stateHash = std::rotl<uint64>(stateHash, 1);
		}
	}

	if (lastUsedAttachmentsInfo.depthFormat != Latte::E_GX2SURFFMT::INVALID_FORMAT)
	{
		stateHash += GetMtlPixelFormat(lastUsedAttachmentsInfo.depthFormat, true);
		stateHash = std::rotl<uint64>(stateHash, 7);
		stateHash += lastUsedAttachmentsInfo.hasStencil ? 1 : 0;
		stateHash = std::rotl<uint64>(stateHash, 1);

		if (activeAttachmentsInfo.depthFormat == Latte::E_GX2SURFFMT::INVALID_FORMAT)
		{
            stateHash += 1;
		    stateHash = std::rotl<uint64>(stateHash, 1);
		}
	}

	for (auto& group : fetchShader->bufferGroups)
	{
		uint32 bufferStride = group.getCurrentBufferStride(lcr.GetRawView());
		stateHash = std::rotl<uint64>(stateHash, 7);
		stateHash += bufferStride * 3;
	}

	stateHash += fetchShader->getVkPipelineHashFragment();
	stateHash = std::rotl<uint64>(stateHash, 7);

	stateHash += lcr.GetRawView()[mmVGT_STRMOUT_EN];
	stateHash = std::rotl<uint64>(stateHash, 7);

	if(lcr.PA_CL_CLIP_CNTL.get_DX_RASTERIZATION_KILL())
		stateHash += 0x333333;

	stateHash = (stateHash >> 8) + (stateHash * 0x370531ull) % 0x7F980D3BF9B4639Dull;

	uint32* ctxRegister = lcr.GetRawView();

	if (vertexShader)
		stateHash += vertexShader->baseHash + std::rotl<uint64>(vertexShader->auxHash, 17);
    
	stateHash = std::rotl<uint64>(stateHash, 13);
    
	if (geometryShader)
		stateHash += geometryShader->baseHash + std::rotl<uint64>(geometryShader->auxHash, 29);

	stateHash = std::rotl<uint64>(stateHash, 13);

	if (pixelShader)
		stateHash += pixelShader->baseHash + std::rotl<uint64>(pixelShader->auxHash, 41);

	stateHash = std::rotl<uint64>(stateHash, 13);

	uint32 polygonCtrl = lcr.PA_SU_SC_MODE_CNTL.getRawValue();
	stateHash += polygonCtrl;
	stateHash = std::rotl<uint64>(stateHash, 7);

	stateHash += ctxRegister[Latte::REGADDR::PA_CL_CLIP_CNTL];
	stateHash = std::rotl<uint64>(stateHash, 7);

	const auto colorControlReg = ctxRegister[Latte::REGADDR::CB_COLOR_CONTROL];
	stateHash += colorControlReg;

	stateHash += ctxRegister[Latte::REGADDR::CB_TARGET_MASK];

	const uint32 blendEnableMask = (colorControlReg >> 8) & 0xFF;
	if (blendEnableMask)
	{
		for (auto i = 0; i < 8; ++i)
		{
			if (((blendEnableMask & (1 << i))) == 0)
				continue;
			stateHash = std::rotl<uint64>(stateHash, 7);
			stateHash += ctxRegister[Latte::REGADDR::CB_BLEND0_CONTROL + i];
		}
	}

	// Mesh pipeline
	const LattePrimitiveMode primitiveMode = static_cast<LattePrimitiveMode>(lcr.GetRawView()[mmVGT_PRIMITIVE_TYPE]);
    bool isPrimitiveRect = (primitiveMode == Latte::LATTE_VGT_PRIMITIVE_TYPE::E_PRIMITIVE_TYPE::RECTS);

    bool usesGeometryShader = (geometryShader != nullptr || isPrimitiveRect);

    if (usesGeometryShader)
    {
        stateHash += lcr.GetRawView()[mmVGT_PRIMITIVE_TYPE];
        stateHash = std::rotl<uint64>(stateHash, 7);
    }

	return stateHash;
}

struct
{
	uint32 pipelineLoadIndex;
	uint32 pipelineMaxFileIndex;

	std::atomic_uint32_t pipelinesQueued;
	std::atomic_uint32_t pipelinesLoaded;
} g_mtlCacheState;

// Entries whose shader hashes were translated while loading; rewritten under their new names once loading is done
static std::vector<LatteShaderCachePipelineRekey> s_pendingRekeys;

uint32 MetalPipelineCache::BeginLoading(uint64 cacheTitleId)
{
	std::error_code ec;
	fs::create_directories(ActiveSettings::GetCachePath("shaderCache/transferable"), ec);
	const auto pathCacheFile = ActiveSettings::GetCachePath("shaderCache/transferable/{:016x}_mtlpipeline.bin", cacheTitleId);

	// init cache loader state
	g_mtlCacheState.pipelineLoadIndex = 0;
	g_mtlCacheState.pipelineMaxFileIndex = 0;
	g_mtlCacheState.pipelinesLoaded = 0;
	g_mtlCacheState.pipelinesQueued = 0;
	s_pendingRekeys.clear();

	m_loadStart = std::chrono::steady_clock::now();
	m_loadShaderCompilesAtStart = PerfTelemetry::Get().shaderCompiles.load(std::memory_order_relaxed);
	m_loadShaderCompileNsAtStart = PerfTelemetry::Get().shaderCompileNs.load(std::memory_order_relaxed);
	m_loadPipelineCompilesAtStart = PerfTelemetry::Get().pipelineCompiles.load(std::memory_order_relaxed);
	m_loadPipelineCompileNsAtStart = PerfTelemetry::Get().pipelineCompileNs.load(std::memory_order_relaxed);
	m_archiveHits = 0;
	m_archiveMisses = 0;
	m_pipelinesDeduped = 0;
	OpenBinaryArchives(cacheTitleId);

	// start async compilation threads
	m_compilationCount.store(0);
	m_compilationQueue.clear();

	// get core count
	uint32 cpuCoreCount = GetPhysicalCoreCount();
	m_numCompilationThreads = std::clamp(cpuCoreCount, 1u, 8u);
	// TODO: uncomment?
	//if (VulkanRenderer::GetInstance()->GetDisableMultithreadedCompilation())
	//	m_numCompilationThreads = 1;

	for (uint32 i = 0; i < m_numCompilationThreads; i++)
	{
		m_loaderThreadsRunning.fetch_add(1);
		std::thread compileThread(&MetalPipelineCache::CompilerThread, this);
		compileThread.detach();
	}

	// open cache file or create it
	cemu_assert_debug(s_cache == nullptr);
	s_cache = FileCache::Open(pathCacheFile, true, LatteShaderCache_getPipelineCacheExtraVersion(cacheTitleId));
	if (!s_cache)
	{
		cemuLog_log(LogType::Force, "Failed to open or create Metal pipeline cache file: {}", _pathToUtf8(pathCacheFile));
		return 0;
	}
	else
	{
		s_cache->UseCompression(false);
		g_mtlCacheState.pipelineMaxFileIndex = s_cache->GetMaximumFileIndex();
	}
	return s_cache->GetFileCount();
}

bool MetalPipelineCache::UpdateLoading(uint32& pipelinesLoadedTotal, uint32& pipelinesMissingShaders)
{
	pipelinesLoadedTotal = g_mtlCacheState.pipelinesLoaded;
	pipelinesMissingShaders = 0;
	while (g_mtlCacheState.pipelineLoadIndex <= g_mtlCacheState.pipelineMaxFileIndex)
	{
		if (m_compilationQueue.size() >= 50)
		{
			std::this_thread::sleep_for(std::chrono::milliseconds(10));
			return true; // queue up to 50 entries at a time
		}

		uint64 fileNameA, fileNameB;
		std::vector<uint8> fileData;
		if (s_cache->GetFileByIndex(g_mtlCacheState.pipelineLoadIndex, &fileNameA, &fileNameB, fileData))
		{
			// the entry names its shaders by the hash they were stored with; the shader loader may have re-keyed them
			LatteShaderCache_TranslatePipelineEntry(fileNameA, fileNameB, fileData, s_pendingRekeys);
			// queue for async compilation
			g_mtlCacheState.pipelinesQueued++;
			m_compilationQueue.push(std::move(fileData));
			g_mtlCacheState.pipelineLoadIndex++;
			return true;
		}
		g_mtlCacheState.pipelineLoadIndex++;
	}
	if (g_mtlCacheState.pipelinesLoaded != g_mtlCacheState.pipelinesQueued)
	{
		std::this_thread::sleep_for(std::chrono::milliseconds(10));
		return true; // pipelines still compiling
	}
	LatteShaderCache_ApplyPipelineRekeys(s_cache, s_pendingRekeys);
	{
		const auto wallMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - m_loadStart).count();
		const uint32 pipelineCompiles = PerfTelemetry::Get().pipelineCompiles.load(std::memory_order_relaxed) - m_loadPipelineCompilesAtStart;
		const uint64 pipelineMs = (PerfTelemetry::Get().pipelineCompileNs.load(std::memory_order_relaxed) - m_loadPipelineCompileNsAtStart) / 1000000;
		const uint32 shaderCompiles = PerfTelemetry::Get().shaderCompiles.load(std::memory_order_relaxed) - m_loadShaderCompilesAtStart;
		cemuLog_log(LogType::Force, "Metal pipeline load: {} cache entries, {} pipelines built in {} ms summed ({} ms avg), {} duplicate entries skipped, binary archive {} hits / {} misses from {} file(s), {} shaders compiled on demand, {} ms wall for the pipeline stage",
			g_mtlCacheState.pipelinesQueued.load(), pipelineCompiles, pipelineMs, pipelineCompiles ? pipelineMs / pipelineCompiles : 0, m_pipelinesDeduped.load(), m_archiveHits.load(), m_archiveMisses.load(), m_archiveFilesLoaded, shaderCompiles, wallMs);
	}
	return false; // done
}

void MetalPipelineCache::EndLoading()
{
	// shut down compilation threads
	uint32 threadCount = m_numCompilationThreads;
	m_numCompilationThreads = 0; // signal thread shutdown
	for (uint32 i = 0; i < threadCount; i++)
	{
		m_compilationQueue.push({}); // push empty workload for every thread. Threads then will shutdown after checking for m_numCompilationThreads == 0
	}
	// keep cache file open for writing of new pipelines
}

struct CachedPipeline
{
	struct ShaderHash
	{
		uint64 baseHash;
		uint64 auxHash;
		bool isPresent{};

		void set(uint64 baseHash, uint64 auxHash)
		{
			this->baseHash = baseHash;
			this->auxHash = auxHash;
			this->isPresent = true;
		}
	};

	ShaderHash vsHash; // includes fetch shader
	ShaderHash gsHash;
	ShaderHash psHash;

	MetalAttachmentsInfo lastUsedAttachmentsInfo;

	Latte::GPUCompactedRegisterState gpuState;
};

void MetalPipelineCache::LoadPipelineFromCache(std::span<uint8> fileData)
{
	static FSpinlock s_spinlockSharedInternal;

	// deserialize file
	LatteContextRegister* lcr = new LatteContextRegister();
	s_spinlockSharedInternal.lock();
	CachedPipeline* cachedPipeline = new CachedPipeline();
	s_spinlockSharedInternal.unlock();

	MemStreamReader streamReader(fileData.data(), fileData.size());
	if (!DeserializePipeline(streamReader, *cachedPipeline))
	{
		// failed to deserialize
		s_spinlockSharedInternal.lock();
		delete lcr;
		delete cachedPipeline;
		s_spinlockSharedInternal.unlock();
		return;
	}
	// restored register view from compacted state
	Latte::LoadGPURegisterState(*lcr, cachedPipeline->gpuState);

	LatteDecompilerShader* vertexShader = nullptr;
	LatteDecompilerShader* geometryShader = nullptr;
	LatteDecompilerShader* pixelShader = nullptr;
	// find vertex shader
	if (cachedPipeline->vsHash.isPresent)
	{
		vertexShader = LatteSHRC_FindVertexShader(cachedPipeline->vsHash.baseHash, cachedPipeline->vsHash.auxHash);
		if (!vertexShader)
		{
			cemuLog_log(LogType::Force, "Vertex shader not found in cache");
			return;
		}
	}
	// find geometry shader
	if (cachedPipeline->gsHash.isPresent)
	{
		geometryShader = LatteSHRC_FindGeometryShader(cachedPipeline->gsHash.baseHash, cachedPipeline->gsHash.auxHash);
		if (!geometryShader)
		{
			cemuLog_log(LogType::Force, "Geometry shader not found in cache");
			return;
		}
	}
	// find pixel shader
	if (cachedPipeline->psHash.isPresent)
	{
		pixelShader = LatteSHRC_FindPixelShader(cachedPipeline->psHash.baseHash, cachedPipeline->psHash.auxHash);
		if (!pixelShader)
		{
			cemuLog_log(LogType::Force, "Pixel shader not found in cache");
			return;
		}
	}

	if (!pixelShader)
	{
		cemu_assert_debug(false);
		return;
	}

	MetalAttachmentsInfo attachmentsInfo(*lcr, pixelShader);

	uint64 pipelineStateHash = CalculatePipelineHash(vertexShader->compatibleFetchShader, vertexShader, geometryShader, pixelShader, cachedPipeline->lastUsedAttachmentsInfo, attachmentsInfo, *lcr);
	PipelineObject* pipelineObject = new PipelineObject();
	m_pipelineCacheLock.lock();
	const bool claimed = m_pipelineCache.try_emplace(pipelineStateHash, pipelineObject).second;
	m_pipelineCacheLock.unlock();
	if (!claimed)
	{
		// another entry with the same pipeline hash is already built or being built; the runtime would use that one anyway
		delete pipelineObject;
		m_pipelinesDeduped.fetch_add(1, std::memory_order_relaxed);
		s_spinlockSharedInternal.lock();
		delete lcr;
		delete cachedPipeline;
		s_spinlockSharedInternal.unlock();
		return;
	}

	// compile
	{
		MetalPipelineCompiler pp(m_mtlr, *pipelineObject);
		pp.InitFromState(vertexShader->compatibleFetchShader, vertexShader, geometryShader, pixelShader, cachedPipeline->lastUsedAttachmentsInfo, attachmentsInfo, *lcr);
		pp.Compile(true, true, false);
		// destroy pp early
	}

	// clean up
	s_spinlockSharedInternal.lock();
	delete lcr;
	delete cachedPipeline;
	s_spinlockSharedInternal.unlock();
}

ConcurrentQueue<CachedPipeline*> g_mtlPipelineCachingQueue;

void MetalPipelineCache::Close()
{
    // The writer thread reads s_cache, so it is stopped (a null job is its stop signal) before the cache is deleted. It used
    // to be detached, which left it blocked on the queue after this object was destroyed, and the next pipeline any title
    // queued woke it up to run on freed memory.
    if (m_pipelineCacheStoreThread)
    {
        CachedPipeline* stopJob = nullptr;
        g_mtlPipelineCachingQueue.push(stopJob);
        m_pipelineCacheStoreThread->join();
        delete m_pipelineCacheStoreThread;
        m_pipelineCacheStoreThread = nullptr;
    }
    // jobs that were queued but not written describe this title's pipelines; they must not end up in the next title's file
    CachedPipeline* leftover = nullptr;
    while (g_mtlPipelineCachingQueue.peek2(leftover))
        delete leftover;
    if(s_cache)
    {
        delete s_cache;
        s_cache = nullptr;
    }
    CloseBinaryArchives();
}

void MetalPipelineCache::AddCurrentStateToCache(uint64 pipelineStateHash, const MetalAttachmentsInfo& lastUsedAttachmentsInfo)
{
	if (!m_pipelineCacheStoreThread)
	{
		m_pipelineCacheStoreThread = new std::thread(&MetalPipelineCache::WorkerThread, this);
	}
	// fill job structure with cached GPU state
	// for each cached pipeline we store:
	// - Active shaders (referenced by hash)
	// - An almost-complete register state of the GPU (minus some ALU uniform constants which aren't relevant)
	CachedPipeline* job = new CachedPipeline();
	auto vs = LatteSHRC_GetActiveVertexShader();
	auto gs = LatteSHRC_GetActiveGeometryShader();
	auto ps = LatteSHRC_GetActivePixelShader();
	if (vs)
		job->vsHash.set(vs->baseHash, vs->auxHash);
	if (gs)
		job->gsHash.set(gs->baseHash, gs->auxHash);
	if (ps)
		job->psHash.set(ps->baseHash, ps->auxHash);
	job->lastUsedAttachmentsInfo = lastUsedAttachmentsInfo;
	Latte::StoreGPURegisterState(LatteGPUState.contextNew, job->gpuState);
	// queue job
	g_mtlPipelineCachingQueue.push(job);
}

bool MetalPipelineCache::SerializePipeline(MemStreamWriter& memWriter, CachedPipeline& cachedPipeline)
{
	memWriter.writeBE<uint8>(0x01); // version
	uint8 presentMask = 0;
	if (cachedPipeline.vsHash.isPresent)
		presentMask |= 1;
	if (cachedPipeline.gsHash.isPresent)
		presentMask |= 2;
	if (cachedPipeline.psHash.isPresent)
		presentMask |= 4;
	memWriter.writeBE<uint8>(presentMask);
	if (cachedPipeline.vsHash.isPresent)
	{
		memWriter.writeBE<uint64>(cachedPipeline.vsHash.baseHash);
		memWriter.writeBE<uint64>(cachedPipeline.vsHash.auxHash);
	}
	if (cachedPipeline.gsHash.isPresent)
	{
		memWriter.writeBE<uint64>(cachedPipeline.gsHash.baseHash);
		memWriter.writeBE<uint64>(cachedPipeline.gsHash.auxHash);
	}
	if (cachedPipeline.psHash.isPresent)
	{
		memWriter.writeBE<uint64>(cachedPipeline.psHash.baseHash);
		memWriter.writeBE<uint64>(cachedPipeline.psHash.auxHash);
	}

	for (uint8 i = 0; i < LATTE_NUM_COLOR_TARGET; i++)
	    memWriter.writeBE<uint16>((uint16)cachedPipeline.lastUsedAttachmentsInfo.colorFormats[i]);
	memWriter.writeBE<uint16>((uint16)cachedPipeline.lastUsedAttachmentsInfo.depthFormat);
    memWriter.writeBE<uint8>(cachedPipeline.lastUsedAttachmentsInfo.hasStencil ? 1 : 0);

	Latte::SerializeRegisterState(cachedPipeline.gpuState, memWriter);

	return true;
}

bool MetalPipelineCache::DeserializePipeline(MemStreamReader& memReader, CachedPipeline& cachedPipeline)
{
	// version
	if (memReader.readBE<uint8>() != 1)
	{
		cemuLog_log(LogType::Force, "Cached Metal pipeline corrupted or has unknown version");
		return false;
	}
	// shader hashes
	uint8 presentMask = memReader.readBE<uint8>();
	if (presentMask & 1)
	{
		uint64 baseHash = memReader.readBE<uint64>();
		uint64 auxHash = memReader.readBE<uint64>();
		cachedPipeline.vsHash.set(baseHash, auxHash);
	}
	if (presentMask & 2)
	{
		uint64 baseHash = memReader.readBE<uint64>();
		uint64 auxHash = memReader.readBE<uint64>();
		cachedPipeline.gsHash.set(baseHash, auxHash);
	}
	if (presentMask & 4)
	{
		uint64 baseHash = memReader.readBE<uint64>();
		uint64 auxHash = memReader.readBE<uint64>();
		cachedPipeline.psHash.set(baseHash, auxHash);
	}

	for (uint8 i = 0; i < LATTE_NUM_COLOR_TARGET; i++)
	    cachedPipeline.lastUsedAttachmentsInfo.colorFormats[i] = (Latte::E_GX2SURFFMT)memReader.readBE<uint16>();
	cachedPipeline.lastUsedAttachmentsInfo.depthFormat = (Latte::E_GX2SURFFMT)memReader.readBE<uint16>();
    cachedPipeline.lastUsedAttachmentsInfo.hasStencil = memReader.readBE<uint8>() != 0;

	// deserialize GPU state
	if (!Latte::DeserializeRegisterState(cachedPipeline.gpuState, memReader))
	{
		return false;
	}
	cemu_assert_debug(!memReader.hasError());

	return true;
}

int MetalPipelineCache::CompilerThread()
{
	SetThreadName("plCacheCompiler");
	while (m_numCompilationThreads != 0)
	{
		std::vector<uint8> pipelineData = m_compilationQueue.pop();
		if(pipelineData.empty())
			continue;
		LoadPipelineFromCache(pipelineData);
		++g_mtlCacheState.pipelinesLoaded;
	}
	m_loaderThreadsRunning.fetch_sub(1); // last access to this object
	return 0;
}

static std::atomic<bool> g_mtlLoaderAbandoned{false};

bool MetalPipelineCache_LoaderAbandoned()
{
	return g_mtlLoaderAbandoned.load();
}

// Stops the threads that load the pipeline cache in the background and waits for them. They hold this object, the renderer and
// the title's shaders, so a stop that arrives while a cache is still loading has to wait until they are done.
bool MetalPipelineCache::StopLoading(uint32 timeoutMs)
{
	EndLoading(); // signals every thread to stop after the pipeline it is on
	for (uint32 waited = 0; m_loaderThreadsRunning.load() != 0 && waited < timeoutMs; waited += 2)
		std::this_thread::sleep_for(std::chrono::milliseconds(2));
	if (m_loaderThreadsRunning.load() == 0)
		return true;
	cemuLog_log(LogType::Force, "Metal: {} pipeline cache loader thread(s) did not stop within {} ms", m_loaderThreadsRunning.load(), timeoutMs);
	g_mtlLoaderAbandoned.store(true);
	return false;
}

void MetalPipelineCache::WorkerThread()
{
	SetThreadName("plCacheWriter");
	while (true)
	{
		CachedPipeline* job;
		g_mtlPipelineCachingQueue.pop(job);
		if (!job)
			return; // stop signal from Close()
		if (!s_cache)
		{
			delete job;
			continue;
		}
		// serialize
		MemStreamWriter memWriter(1024 * 4);
		SerializePipeline(memWriter, *job);
		auto blob = memWriter.getResult();
		// file name is derived from data hash
		uint8 hash[SHA256_DIGEST_LENGTH];
		SHA256(blob.data(), blob.size(), hash);
		uint64 nameA = *(uint64be*)(hash + 0);
		uint64 nameB = *(uint64be*)(hash + 8);
		s_cache->AddFileAsync({ nameA, nameB }, blob.data(), blob.size());
		delete job;
	}
}

bool MetalPipelineCache_FlushArchive(uint32 timeoutMs)
{
	std::lock_guard<std::mutex> lifeLock(g_mtlPipelineCacheLifeMutex);
	return g_mtlPipelineCache ? g_mtlPipelineCache->FlushBinaryArchive(timeoutMs) : true;
}

NS::Array* MetalPipelineCache_GetBinaryArchives()
{
	return g_mtlPipelineCache ? g_mtlPipelineCache->GetBinaryArchives() : nullptr;
}

void MetalPipelineCache_NoteArchiveLookup(bool hit)
{
	if (g_mtlPipelineCache)
		g_mtlPipelineCache->NoteArchiveLookup(hit);
}

void MetalPipelineCache_QueueArchiveAdd(MTL::RenderPipelineDescriptor* desc)
{
	if (g_mtlPipelineCache)
		g_mtlPipelineCache->QueueArchiveAdd(desc);
}

// Compiled pipelines are kept in MTLBinaryArchive files next to the transferable cache, so that a launch after the system has
// dropped its own compiled-code cache does not have to build every pipeline again. Archives that were loaded from disk are only
// read during a session. Pipelines that missed are added to a separate archive by one writer thread and saved as one more file,
// which means no archive is ever read and written at the same time. The file name carries the OS build and GPU the archive was
// built on; files for another build are deleted.
static constexpr uint32 ARCHIVE_MAX_FILES = 8;
static constexpr uint64 ARCHIVE_MAX_BYTES = 768ull * 1024 * 1024;
static constexpr size_t ARCHIVE_MAX_QUEUE = 20000;
static constexpr uint32 ARCHIVE_SAVE_EVERY = 2000;

static std::string GetBinaryArchiveKey(MTL::Device* device)
{
	char osBuild[64] = {};
	size_t osBuildLen = sizeof(osBuild) - 1;
	sysctlbyname("kern.osversion", osBuild, &osBuildLen, nullptr, 0);
	const std::string id = fmt::format("{}|{}|v1", osBuild, device->name()->utf8String());
	uint64 h = 1469598103934665603ull;
	for (unsigned char c : id)
	{
		h ^= c;
		h *= 1099511628211ull;
	}
	return fmt::format("{:016x}", h);
}

void MetalPipelineCache::OpenBinaryArchives(uint64 cacheTitleId)
{
	NS_STACK_SCOPED NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
	CloseBinaryArchives();

	std::error_code ec;
	const fs::path dir = ActiveSettings::GetCachePath("shaderCache/precompiled");
	fs::create_directories(dir, ec);
	const std::string titlePrefix = fmt::format("{:016x}_mtlbin_", cacheTitleId);
	const std::string keyPrefix = titlePrefix + GetBinaryArchiveKey(m_mtlr->GetDevice()) + "_";

	std::vector<fs::path> files;
	std::vector<bool> used(ARCHIVE_MAX_FILES, false);
	for (fs::directory_iterator it(dir, ec), end; !ec && it != end; it.increment(ec))
	{
		const std::string name = it->path().filename().string();
		if (name.compare(0, titlePrefix.size(), titlePrefix) != 0)
			continue;
		std::error_code rmEc;
		if (name.compare(0, keyPrefix.size(), keyPrefix) != 0 || name.size() < 4 || name.compare(name.size() - 4, 4, ".bin") != 0)
		{
			fs::remove(it->path(), rmEc); // built on another OS build or GPU, or a leftover temp file
			continue;
		}
		files.push_back(it->path());
	}
	std::sort(files.begin(), files.end());

	std::vector<NS::Object*> loaded;
	uint64 bytes = 0;
	for (const fs::path& file : files)
	{
		std::error_code sizeEc;
		const uint64 size = fs::file_size(file, sizeEc);
		NS_STACK_SCOPED MTL::BinaryArchiveDescriptor* desc = MTL::BinaryArchiveDescriptor::alloc()->init();
		desc->setUrl(ToNSURL(_pathToUtf8(file)));
		NS::Error* error = nullptr;
		MTL::BinaryArchive* archive = m_mtlr->GetDevice()->newBinaryArchive(desc, &error);
		if (!archive)
		{
			cemuLog_log(LogType::Force, "Metal binary archive {} could not be loaded ({}), deleting it", _pathToUtf8(file.filename()), error ? error->localizedDescription()->utf8String() : "unknown error");
			std::error_code rmEc;
			fs::remove(file, rmEc);
			continue;
		}
		loaded.push_back(archive);
		if (!sizeEc)
			bytes += size;
		const std::string name = file.filename().string();
		const size_t idxPos = keyPrefix.size();
		const size_t idx = (size_t)strtoul(name.c_str() + idxPos, nullptr, 10);
		if (idx < used.size())
			used[idx] = true;
	}
	if (!loaded.empty())
	{
		m_binaryArchives = NS::Array::alloc()->init(loaded.data(), loaded.size());
		for (NS::Object* o : loaded)
			o->release();
	}
	m_archiveFilesLoaded = (uint32)loaded.size();
	m_archiveBaseBytes = bytes;

	uint32 nextIndex = 0;
	while (nextIndex < ARCHIVE_MAX_FILES && used[nextIndex])
		nextIndex++;
	m_archiveWriteEnabled = nextIndex < ARCHIVE_MAX_FILES && bytes < ARCHIVE_MAX_BYTES;
	if (m_archiveWriteEnabled)
		m_archiveWritePath = _pathToUtf8(dir / fmt::format("{}{}.bin", keyPrefix, nextIndex));
	else
		cemuLog_log(LogType::Force, "Metal binary archive: not adding more pipelines ({} file(s), {} MB)", loaded.size(), bytes / (1024 * 1024));
}

bool MetalPipelineCache::FlushBinaryArchive(uint32 timeoutMs)
{
	std::unique_lock<std::mutex> lock(m_archiveMutex);
	if (!m_archiveThreadAlive || m_archiveStop)
		return true;
	const uint64_t generation = ++m_archiveFlushGen;
	m_archiveFlushRequested = true;
	m_archiveCv.notify_all();
	return m_archiveFlushCv.wait_for(lock, std::chrono::milliseconds(timeoutMs), [&] { return m_archiveFlushDoneGen >= generation || !m_archiveThreadAlive; });
}

void MetalPipelineCache::CloseBinaryArchives()
{
	FlushBinaryArchive(3000); // saves what is still queued; the writer only saves what it already added when it is stopped
	if (m_archiveThread)
	{
		{
			std::lock_guard<std::mutex> lock(m_archiveMutex);
			m_archiveStop = true;
		}
		m_archiveCv.notify_all();
		m_archiveThread->join();
		delete m_archiveThread;
		m_archiveThread = nullptr;
		std::lock_guard<std::mutex> lock(m_archiveMutex);
		m_archiveThreadAlive = false;
		m_archiveFlushRequested = false;
		m_archiveFlushCv.notify_all();
	}
	{
		std::lock_guard<std::mutex> lock(m_archiveMutex);
		for (auto* desc : m_archiveQueue)
			desc->release();
		m_archiveQueue.clear();
		m_archiveStop = false;
	}
	m_archiveWriteEnabled = false;
	m_archiveFilesLoaded = 0;
	if (m_binaryArchives)
	{
		m_binaryArchives->release();
		m_binaryArchives = nullptr;
	}
}

void MetalPipelineCache::QueueArchiveAdd(MTL::RenderPipelineDescriptor* desc)
{
	if (!m_archiveWriteEnabled)
		return;
	std::lock_guard<std::mutex> lock(m_archiveMutex);
	if (m_archiveStop || m_archiveQueue.size() >= ARCHIVE_MAX_QUEUE)
		return;
	MTL::RenderPipelineDescriptor* copy = desc->copy();
	copy->setBinaryArchives(nullptr);
	m_archiveQueue.push_back(copy);
	if (!m_archiveThread)
	{
		m_archiveThread = new std::thread(&MetalPipelineCache::BinaryArchiveWriterThread, this);
		m_archiveThreadAlive = true;
	}
	m_archiveCv.notify_one();
}

void MetalPipelineCache::BinaryArchiveWriterThread()
{
	SetThreadName("mtlArchive");
	MTL::BinaryArchive* archive = nullptr;
	uint32 pending = 0;
	uint32 added = 0;
	auto lastSave = std::chrono::steady_clock::now();
	for (;;)
	{
		MTL::RenderPipelineDescriptor* desc = nullptr;
		bool stopping;
		bool flushing;
		uint64_t flushGeneration;
		bool queueEmpty;
		{
			std::unique_lock<std::mutex> lock(m_archiveMutex);
			if (m_archiveQueue.empty() && !m_archiveStop && !m_archiveFlushRequested)
			{
				if (pending == 0)
					m_archiveCv.wait(lock, [&] { return !m_archiveQueue.empty() || m_archiveStop || m_archiveFlushRequested; });
				else
					m_archiveCv.wait_for(lock, std::chrono::seconds(20), [&] { return !m_archiveQueue.empty() || m_archiveStop || m_archiveFlushRequested; });
			}
			stopping = m_archiveStop;
			flushing = m_archiveFlushRequested;
			flushGeneration = m_archiveFlushGen;
			if (stopping)
			{
				for (auto* d : m_archiveQueue)
					d->release();
				m_archiveQueue.clear();
			}
			else if (!m_archiveQueue.empty())
			{
				desc = m_archiveQueue.front();
				m_archiveQueue.pop_front();
			}
			queueEmpty = m_archiveQueue.empty();
		}
		NS_STACK_SCOPED NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
		if (desc)
		{
			if (!archive)
			{
				NS_STACK_SCOPED MTL::BinaryArchiveDescriptor* archiveDesc = MTL::BinaryArchiveDescriptor::alloc()->init();
				NS::Error* error = nullptr;
				archive = m_mtlr->GetDevice()->newBinaryArchive(archiveDesc, &error);
				if (!archive)
					cemuLog_log(LogType::Force, "Metal binary archive could not be created: {}", error ? error->localizedDescription()->utf8String() : "unknown error");
			}
			if (archive)
			{
				NS::Error* error = nullptr;
				if (archive->addRenderPipelineFunctions(desc, &error))
				{
					pending++;
					added++;
				}
			}
			desc->release();
		}
		if (archive && pending > 0 && (pending >= ARCHIVE_SAVE_EVERY || stopping || (flushing && queueEmpty) || (queueEmpty && std::chrono::steady_clock::now() - lastSave >= std::chrono::seconds(20))))
		{
			const auto start = std::chrono::steady_clock::now();
			const std::string tmpPath = m_archiveWritePath + ".tmp";
			NS::Error* error = nullptr;
			bool saved = archive->serializeToURL(ToNSURL(tmpPath), &error);
			std::error_code ec;
			if (saved)
			{
				fs::rename(fs::path(m_archiveWritePath + ".tmp"), fs::path(m_archiveWritePath), ec);
				saved = !ec;
			}
			if (saved)
			{
				const uint64 size = fs::file_size(fs::path(m_archiveWritePath), ec);
				cemuLog_log(LogType::Force, "Metal binary archive: saved {} pipelines, {} MB, in {} ms", added, ec ? 0 : size / (1024 * 1024), std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count());
				if (!ec && m_archiveBaseBytes + size >= ARCHIVE_MAX_BYTES)
				{
					std::lock_guard<std::mutex> lock(m_archiveMutex);
					m_archiveWriteEnabled = false;
				}
			}
			else
			{
				cemuLog_log(LogType::Force, "Metal binary archive could not be saved: {}", error ? error->localizedDescription()->utf8String() : "rename failed");
				fs::remove(fs::path(tmpPath), ec);
			}
			pending = 0;
			lastSave = std::chrono::steady_clock::now();
		}
		if (flushing && queueEmpty)
		{
			std::lock_guard<std::mutex> lock(m_archiveMutex);
			if (m_archiveQueue.empty())
			{
				m_archiveFlushDoneGen = flushGeneration;
				m_archiveFlushRequested = m_archiveFlushGen != flushGeneration;
				m_archiveFlushCv.notify_all();
			}
		}
		if (stopping)
			break;
	}
	if (archive)
		archive->release();
}
