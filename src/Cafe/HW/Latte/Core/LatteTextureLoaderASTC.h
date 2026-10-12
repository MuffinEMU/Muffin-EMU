#pragma once
#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>
#include "LatteTextureLoader.h"
#include "PerfTelemetry.h"
#include "Common/DeviceCapabilities.h"
#if defined(__APPLE__)
#include <pthread/qos.h>
#endif
#include "astcenc.h"

static inline uint8 astcFloatToUNorm8(float v)
{
    v = std::clamp(v, 0.0f, 1.0f);
    return (uint8)(v * 255.0f + 0.5f);
}

static inline uint8 astcFloatToUNorm8FromSNorm(float v)
{
    v = std::clamp(v, -1.0f, 1.0f);
    return (uint8)((v * 0.5f + 0.5f) * 255.0f + 0.5f);
}

static inline size_t astcCompressedImageSize(sint32 width, sint32 height)
{
    return (size_t)((width + 3) / 4) * (size_t)((height + 3) / 4) * 16u;
}

// How many threads one encode may use, the calling (Latte) thread included. Derived from the device,
// never from one model: the emulated PPC thread and the Latte thread each keep a performance core, an
// efficiency core counts as half a core, and the ceiling is four. A device with fewer than three such
// cores gets 1, which is the single-threaded encode this file always did.
static uint32 astcEncodeThreadCount()
{
    static const uint32 count = []() -> uint32 {
        const DeviceCaps::Info& info = DeviceCaps::Get();
        if (info.perfCores == 0)
            return 1; // not reported: do not guess
        const uint32 usable = info.perfCores + info.effCores / 2;
        if (usable <= 2)
            return 1;
        return std::min<uint32>(usable - 2, 3) + 1;
    }();
    return count;
}

// Images with fewer blocks than this are decoded and encoded on the calling thread alone. The helpers are
// persistent (ASTCWorkerPool below), so handing work to them costs a wake-up, not a thread start; 256 blocks
// (64x64 texels) is already far more encode time than that. A race start in Mario Kart 8 transcodes thousands of
// images at about 1 ms each, most of them below the 1024 blocks this used to be, on the Latte thread alone.
static constexpr size_t kAstcThreadedMinBlocks = 16 * 16;

// The threads one decode+encode shares. They are started on first use, live for the rest of the process and
// sleep between images, so the per-image cost is a condition-variable wake-up instead of creating and joining
// threads. One job runs at a time (the Latte thread is the only normal caller); a second caller that finds the
// pool busy gets false back and does the work itself, which gives the same bytes.
class ASTCWorkerPool
{
public:
    static ASTCWorkerPool& Get()
    {
        static ASTCWorkerPool* pool = new ASTCWorkerPool(); // never destroyed: the workers outlive static destruction
        return *pool;
    }

    // Runs body(i) once on each of up to `threads` threads, i = 0 on the calling thread, and returns when all
    // of them are done. Returns false without running anything if the pool is busy or has no helpers.
    template<typename Body>
    bool Run(uint32 threads, Body& body)
    {
        if (threads <= 1)
            return false;
        std::unique_lock<std::mutex> submit(m_submitMutex, std::try_to_lock);
        if (!submit.owns_lock())
            return false;
        EnsureWorkers(threads - 1);
        const uint32 helpers = std::min<uint32>(threads - 1, m_workerCount);
        if (helpers == 0)
            return false;
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_trampoline = [](void* arg, uint32 index) { (*static_cast<Body*>(arg))(index); };
            m_arg = &body;
            m_helpers = helpers;
            m_pending = helpers;
            m_generation++;
        }
        m_wake.notify_all();
        body(0);
        std::unique_lock<std::mutex> lock(m_mutex);
        m_done.wait(lock, [this]() { return m_pending == 0; });
        return true;
    }

private:
    void EnsureWorkers(uint32 wanted)
    {
        while (m_workerCount < wanted)
        {
            uint64 generation;
            {
                std::lock_guard<std::mutex> lock(m_mutex);
                generation = m_generation;
            }
            const uint32 index = m_workerCount + 1;
            try
            {
                std::thread([this, index, generation]() { WorkerMain(index, generation); }).detach();
            }
            catch (...)
            {
                return; // run with the helpers there are
            }
            m_workerCount++;
        }
    }

    void WorkerMain(uint32 index, uint64 seen)
    {
#if defined(__APPLE__)
        // Same class as the Latte thread, so the scheduler keeps these on performance cores while a decode runs.
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0);
#endif
        for (;;)
        {
            void (*trampoline)(void*, uint32) = nullptr;
            void* arg = nullptr;
            {
                std::unique_lock<std::mutex> lock(m_mutex);
                m_wake.wait(lock, [&]() { return m_generation != seen; });
                seen = m_generation;
                if (index > m_helpers)
                    continue; // this job wants fewer threads
                trampoline = m_trampoline;
                arg = m_arg;
            }
            trampoline(arg, index);
            {
                std::lock_guard<std::mutex> lock(m_mutex);
                m_pending--;
            }
            m_done.notify_all();
        }
    }

    std::mutex m_submitMutex;
    std::mutex m_mutex;
    std::condition_variable m_wake;
    std::condition_variable m_done;
    uint32 m_workerCount = 0; // only touched by the thread holding m_submitMutex
    void (*m_trampoline)(void*, uint32) = nullptr;
    void* m_arg = nullptr;
    uint32 m_helpers = 0;
    uint32 m_pending = 0;
    uint64 m_generation = 0;
};

// chunkFn(c) for every c in [0, chunkCount), spread over the pool. Chunks are handed out dynamically; each is
// independent, so which thread runs which one cannot change the result.
template<typename ChunkFn>
static void astcParallelChunks(uint32 threads, size_t chunkCount, ChunkFn chunkFn)
{
    std::atomic<size_t> next{0};
    auto body = [&](uint32) {
        for (size_t c = next.fetch_add(1, std::memory_order_relaxed); c < chunkCount; c = next.fetch_add(1, std::memory_order_relaxed))
            chunkFn(c);
    };
    if (!ASTCWorkerPool::Get().Run(threads, body))
        body(0);
}

struct ASTCEncoderContext
{
    astcenc_context* ctx = nullptr;
    uint32 threads = 1; // the thread count the context was allocated for
};

struct ASTCEncoderContextSet
{
    ASTCEncoderContext ldr;
    ASTCEncoderContext ldrSrgb;

    ~ASTCEncoderContextSet()
    {
        if (ldr.ctx)
            astcenc_context_free(ldr.ctx);
        if (ldrSrgb.ctx)
            astcenc_context_free(ldrSrgb.ctx);
    }
};

static ASTCEncoderContext* astcGetContext(astcenc_profile profile)
{
    thread_local ASTCEncoderContextSet contexts;
    ASTCEncoderContext& enc = (profile == ASTCENC_PRF_LDR_SRGB) ? contexts.ldrSrgb : contexts.ldr;
    if (enc.ctx)
        return &enc;

    astcenc_config config;
    astcenc_error status = astcenc_config_init(
        profile,
        4, 4, 1,
        // The source is already BC (4 or 8 bits per texel) and 4x4 ASTC has 8, so the fastest search loses nothing
        // visible against it, and takes about half the time of the next preset up.
        ASTCENC_PRE_FASTEST,
        0,
        &config);
    if (status != ASTCENC_SUCCESS)
        return nullptr;

    uint32 threads = astcEncodeThreadCount();
    astcenc_context* ctx = nullptr;
    status = astcenc_context_alloc(&config, threads, &ctx, nullptr);
    if (status != ASTCENC_SUCCESS && threads > 1)
    {
        // The per-thread working buffers did not fit: take the single-threaded context instead.
        threads = 1;
        ctx = nullptr;
        status = astcenc_context_alloc(&config, threads, &ctx, nullptr);
    }
    if (status != ASTCENC_SUCCESS)
        return nullptr;

    enc.ctx = ctx;
    enc.threads = threads;
    return &enc;
}

// One image across several threads, the way astcenc documents it: every thread calls
// astcenc_compress_image() with its own index and the library hands out blocks dynamically, so the
// output is byte-identical to a single-threaded run. The pool returns only when every helper has left
// astcenc_compress_image(), which is what makes the astcenc_compress_reset() the caller does next legal.
// If the pool cannot supply helpers the calling thread encodes the whole image.
static astcenc_error astcCompressImageThreaded(astcenc_context* context, astcenc_image* image, const astcenc_swizzle* swizzle,
                                               uint8* outputData, size_t outputSize, uint32 threads)
{
    std::atomic<int> failure{(int)ASTCENC_SUCCESS};
    auto body = [&](uint32 index) {
        const astcenc_error st = astcenc_compress_image(context, image, swizzle, outputData, outputSize, index);
        if (st != ASTCENC_SUCCESS)
        {
            int expected = (int)ASTCENC_SUCCESS;
            failure.compare_exchange_strong(expected, (int)st);
        }
    };
    if (!ASTCWorkerPool::Get().Run(threads, body))
        body(0);
    return (astcenc_error)failure.load();
}

static bool astcCompressRGBA8Image(const uint8* rgba8, sint32 width, sint32 height, astcenc_profile profile, uint8* outputData)
{
    ASTCEncoderContext* enc = astcGetContext(profile);
    if (!enc) {
        cemuLog_log(LogType::Force, "ASTC Encode Fail: no context");
        return false;
    }
    astcenc_context* context = enc->ctx;

    astcenc_image image;
    image.dim_x = (unsigned int)width;
    image.dim_y = (unsigned int)height;
    image.dim_z = 1;
    image.data_type = ASTCENC_TYPE_U8;

    uint8* imageSlice = const_cast<uint8*>(rgba8);
    image.data = reinterpret_cast<void**>(&imageSlice);

    static const astcenc_swizzle kIdentitySwizzle = {
        ASTCENC_SWZ_R, ASTCENC_SWZ_G, ASTCENC_SWZ_B, ASTCENC_SWZ_A
    };

    size_t outputSize = astcCompressedImageSize(width, height);
    uint32 threads = enc->threads;
    if ((size_t)((width + 3) / 4) * (size_t)((height + 3) / 4) < kAstcThreadedMinBlocks)
        threads = 1;

    astcenc_error status;
    if (threads > 1)
        status = astcCompressImageThreaded(context, &image, &kIdentitySwizzle, outputData, outputSize, threads);
    else
        status = astcenc_compress_image(context, &image, &kIdentitySwizzle, outputData, outputSize, 0);

    // A context allocated for more than one thread is not reset implicitly, and it must be reset after a
    // failure as well, or the next image would find the work already marked done.
    astcenc_compress_reset(context);

    if (status != ASTCENC_SUCCESS) {
        cemuLog_log(LogType::Force, "ASTC Encode Fail: {}", (int)status);
        return false;
    }
    return true;
}

template<typename DecodeFn>
static void decodeBCToRGBA8Image(DecodeFn fn, LatteTextureLoaderCtx* tl, uint8* rgba8, sint32 yBegin, sint32 yEnd)
{
    for (sint32 y = yBegin; y < yEnd; y += tl->stepY) {
        for (sint32 x = 0; x < tl->width; x += tl->stepX) {
            uint8* blockData = LatteTextureLoader_GetInput(tl, x, y);
            sint32 bsX = std::min(4, tl->width - x);
            sint32 bsY = std::min(4, tl->height - y);

            float floatBuf[16 * 4] = {};
            fn(blockData, floatBuf);

            for (sint32 py = 0; py < bsY; ++py) {
                for (sint32 px = 0; px < bsX; ++px) {
                    sint32 src = (py * 4 + px) * 4;
                    sint32 dst = ((y - yBegin + py) * tl->width + (x + px)) * 4;
                    rgba8[dst + 0] = astcFloatToUNorm8(floatBuf[src + 0]);
                    rgba8[dst + 1] = astcFloatToUNorm8(floatBuf[src + 1]);
                    rgba8[dst + 2] = astcFloatToUNorm8(floatBuf[src + 2]);
                    rgba8[dst + 3] = astcFloatToUNorm8(floatBuf[src + 3]);
                }
            }
        }
    }
}

template<typename DecodeFn>
static void decodeBC4ToRGBA8Image(DecodeFn fn, LatteTextureLoaderCtx* tl, uint8* rgba8, bool isSigned, sint32 yBegin, sint32 yEnd)
{
    for (sint32 y = yBegin; y < yEnd; y += tl->stepY) {
        for (sint32 x = 0; x < tl->width; x += tl->stepX) {
            uint8* blockData = LatteTextureLoader_GetInput(tl, x, y);
            sint32 bsX = std::min(4, tl->width - x);
            sint32 bsY = std::min(4, tl->height - y);

            float floatBuf[16] = {};
            fn(blockData, floatBuf);

            for (sint32 py = 0; py < bsY; ++py) {
                for (sint32 px = 0; px < bsX; ++px) {
                    sint32 src = py * 4 + px;
                    sint32 dst = ((y - yBegin + py) * tl->width + (x + px)) * 4;
                    uint8 r = isSigned ? astcFloatToUNorm8FromSNorm(floatBuf[src]) : astcFloatToUNorm8(floatBuf[src]);
                    rgba8[dst + 0] = r;
                    rgba8[dst + 1] = 0;
                    rgba8[dst + 2] = 0;
                    rgba8[dst + 3] = 255;
                }
            }
        }
    }
}

template<typename DecodeFn>
static void decodeBC5ToRGBA8Image(DecodeFn fn, LatteTextureLoaderCtx* tl, uint8* rgba8, bool isSigned, sint32 yBegin, sint32 yEnd)
{
    for (sint32 y = yBegin; y < yEnd; y += tl->stepY) {
        for (sint32 x = 0; x < tl->width; x += tl->stepX) {
            uint8* blockData = LatteTextureLoader_GetInput(tl, x, y);
            sint32 bsX = std::min(4, tl->width - x);
            sint32 bsY = std::min(4, tl->height - y);

            float floatBuf[32] = {};
            fn(blockData, floatBuf);

            for (sint32 py = 0; py < bsY; ++py) {
                for (sint32 px = 0; px < bsX; ++px) {
                    sint32 src = (py * 4 + px) * 2;
                    sint32 dst = ((y - yBegin + py) * tl->width + (x + px)) * 4;
                    uint8 r = isSigned ? astcFloatToUNorm8FromSNorm(floatBuf[src + 0]) : astcFloatToUNorm8(floatBuf[src + 0]);
                    uint8 g = isSigned ? astcFloatToUNorm8FromSNorm(floatBuf[src + 1]) : astcFloatToUNorm8(floatBuf[src + 1]);
                    rgba8[dst + 0] = r;
                    rgba8[dst + 1] = g;
                    rgba8[dst + 2] = 0;
                    rgba8[dst + 3] = 255;
                }
            }
        }
    }
}

// The RGBA8 copy of a BC image is the biggest scratch allocation a texture load makes (64 MB for 4096x4096) and the
// one that failed on a device with memory to spare. ASTC blocks are encoded independently (no alpha-weight radius,
// no cross-block state), so the image is decoded and encoded in bands of whole block rows into the matching part of
// the output, which is byte-identical to one pass. Images whose RGBA8 copy fits the budget are one band, as before.
static constexpr size_t kAstcScratchBudgetBytes = 8u * 1024u * 1024u;

// The scratch lives on after the call so the next texture does not map, fault in and zero a fresh block of memory
// (the decode writes every byte of the band before the encode reads it). Only a modest buffer is kept; a band that
// needs more is allocated for the one call.
static constexpr size_t kAstcScratchKeepBytes = 2u * 1024u * 1024u;

template<typename BandDecodeFn>
static void decodeBandsAndCompressASTC(LatteTextureLoaderCtx* tl, uint8* outputData, astcenc_profile profile, BandDecodeFn decodeBand)
{
    // Counted here because this is the one place every BC to ASTC transcode (BC1 to BC5) passes through.
    PerfTelemetry::Get().textureTranscodes.fetch_add(1, std::memory_order_relaxed);
    PerfTelemetry::ScopedTimer transcodeTimer(PerfTelemetry::Get().textureTranscodeNs);

    const sint32 width = tl->width;
    const sint32 height = tl->height;
    const size_t rowBytes = (size_t)width * 4u;
    size_t bandRows = std::max<size_t>(4, (kAstcScratchBudgetBytes / std::max<size_t>(rowBytes, 1)) & ~(size_t)3);
    bandRows = std::min<size_t>(bandRows, (size_t)((height + 3) & ~3));
    const size_t scratchBytes = rowBytes * std::min<size_t>(bandRows, (size_t)height);
    thread_local std::unique_ptr<uint8[]> keptScratch;
    thread_local size_t keptScratchBytes = 0;
    std::unique_ptr<uint8[]> tempScratch;
    uint8* rgba8;
    if (scratchBytes <= kAstcScratchKeepBytes)
    {
        if (keptScratchBytes < scratchBytes)
        {
            keptScratch.reset(new uint8[scratchBytes]);
            keptScratchBytes = scratchBytes;
        }
        rgba8 = keptScratch.get();
    }
    else
    {
        tempScratch.reset(new uint8[scratchBytes]);
        rgba8 = tempScratch.get();
    }

    const uint32 threads = astcEncodeThreadCount();
    const size_t blocksX = (size_t)((width + 3) / 4);
    // Block rows are independent, so a band is decoded in chunks of whole block rows by whichever thread is free.
    constexpr sint32 kDecodeChunkRows = 16;
    for (sint32 y0 = 0; y0 < height; y0 += (sint32)bandRows)
    {
        const sint32 y1 = std::min<sint32>(height, y0 + (sint32)bandRows);
        if (threads > 1 && blocksX * (size_t)((y1 - y0 + 3) / 4) >= kAstcThreadedMinBlocks)
        {
            astcParallelChunks(threads, (size_t)((y1 - y0 + kDecodeChunkRows - 1) / kDecodeChunkRows), [&](size_t chunk) {
                const sint32 ya = y0 + (sint32)chunk * kDecodeChunkRows;
                decodeBand(rgba8 + (size_t)(ya - y0) * rowBytes, ya, std::min<sint32>(y1, ya + kDecodeChunkRows));
            });
        }
        else
            decodeBand(rgba8, y0, y1);
        uint8* bandOutput = outputData + (size_t)(y0 / 4) * blocksX * 16u;
        if (!astcCompressRGBA8Image(rgba8, width, y1 - y0, profile, bandOutput))
        {
            std::fill(outputData, outputData + astcCompressedImageSize(width, height), 0);
            return;
        }
    }
}

template<astcenc_profile Profile, typename DecodeFn>
static void decodeRGBAAndCompressASTC(LatteTextureLoaderCtx* tl, uint8* outputData, DecodeFn fn)
{
    decodeBandsAndCompressASTC(tl, outputData, Profile, [&](uint8* rgba8, sint32 y0, sint32 y1) {
        decodeBCToRGBA8Image(fn, tl, rgba8, y0, y1);
    });
}

static void decodeBC4AndCompressASTC(LatteTextureLoaderCtx* tl, uint8* outputData, bool isSigned)
{
    decodeBandsAndCompressASTC(tl, outputData, ASTCENC_PRF_LDR, [&](uint8* rgba8, sint32 y0, sint32 y1) {
        if (isSigned)
            decodeBC4ToRGBA8Image(decodeBC4Block_SNORM, tl, rgba8, true, y0, y1);
        else
            decodeBC4ToRGBA8Image(decodeBC4Block_UNORM, tl, rgba8, false, y0, y1);
    });
}

static void decodeBC5AndCompressASTC(LatteTextureLoaderCtx* tl, uint8* outputData, bool isSigned)
{
    decodeBandsAndCompressASTC(tl, outputData, ASTCENC_PRF_LDR, [&](uint8* rgba8, sint32 y0, sint32 y1) {
        if (isSigned)
            decodeBC5ToRGBA8Image(decodeBC5Block_SNORM, tl, rgba8, true, y0, y1);
        else
            decodeBC5ToRGBA8Image(decodeBC5Block_UNORM, tl, rgba8, false, y0, y1);
    });
}

template<astcenc_profile Profile>
class TextureDecoder_BC1_to_ASTC_Generic : public TextureDecoder
{
public:
    sint32 getBytesPerTexel(LatteTextureLoaderCtx*) override { return 16; }
    sint32 getTexelCountX(LatteTextureLoaderCtx* tl) override { return (tl->width + 3) / 4; }
    sint32 getTexelCountY(LatteTextureLoaderCtx* tl) override { return (tl->height + 3) / 4; }

    void decode(LatteTextureLoaderCtx* tl, uint8* outputData) override
    {
        decodeRGBAAndCompressASTC<Profile>(tl, outputData, decodeBC1Block);
    }

    void decodePixelToRGBA(uint8* blockData, uint8* out, uint8 ox, uint8 oy) override
    {
        BC1_GetPixel(blockData, ox, oy, out);
    }
};

class TextureDecoder_BC1_UNORM_to_ASTC : public TextureDecoder_BC1_to_ASTC_Generic<ASTCENC_PRF_LDR>, public SingletonClass<TextureDecoder_BC1_UNORM_to_ASTC>
{
};

class TextureDecoder_BC1_SRGB_to_ASTC : public TextureDecoder_BC1_to_ASTC_Generic<ASTCENC_PRF_LDR_SRGB>, public SingletonClass<TextureDecoder_BC1_SRGB_to_ASTC>
{
};

template<astcenc_profile Profile>
class TextureDecoder_BC2_to_ASTC_Generic : public TextureDecoder
{
public:
    sint32 getBytesPerTexel(LatteTextureLoaderCtx*) override { return 16; }
    sint32 getTexelCountX(LatteTextureLoaderCtx* tl) override { return (tl->width + 3) / 4; }
    sint32 getTexelCountY(LatteTextureLoaderCtx* tl) override { return (tl->height + 3) / 4; }

    void decode(LatteTextureLoaderCtx* tl, uint8* outputData) override
    {
        decodeRGBAAndCompressASTC<Profile>(tl, outputData, decodeBC2Block_UNORM);
    }

    void decodePixelToRGBA(uint8* blockData, uint8* out, uint8 ox, uint8 oy) override
    {
        float buf[64];
        decodeBC2Block_UNORM(blockData, buf);
        int i = (ox + oy * 4) * 4;
        out[0] = (uint8)(buf[i] * 255.0f);
        out[1] = (uint8)(buf[i + 1] * 255.0f);
        out[2] = (uint8)(buf[i + 2] * 255.0f);
        out[3] = (uint8)(buf[i + 3] * 255.0f);
    }
};

class TextureDecoder_BC2_UNORM_to_ASTC : public TextureDecoder_BC2_to_ASTC_Generic<ASTCENC_PRF_LDR>, public SingletonClass<TextureDecoder_BC2_UNORM_to_ASTC>
{
};

class TextureDecoder_BC2_SRGB_to_ASTC : public TextureDecoder_BC2_to_ASTC_Generic<ASTCENC_PRF_LDR_SRGB>, public SingletonClass<TextureDecoder_BC2_SRGB_to_ASTC>
{
};

template<astcenc_profile Profile>
class TextureDecoder_BC3_to_ASTC_Generic : public TextureDecoder
{
public:
    sint32 getBytesPerTexel(LatteTextureLoaderCtx*) override { return 16; }
    sint32 getTexelCountX(LatteTextureLoaderCtx* tl) override { return (tl->width + 3) / 4; }
    sint32 getTexelCountY(LatteTextureLoaderCtx* tl) override { return (tl->height + 3) / 4; }

    void decode(LatteTextureLoaderCtx* tl, uint8* outputData) override
    {
        decodeRGBAAndCompressASTC<Profile>(tl, outputData, decodeBC3Block_UNORM);
    }

    void decodePixelToRGBA(uint8* blockData, uint8* out, uint8 ox, uint8 oy) override
    {
        float buf[64];
        decodeBC3Block_UNORM(blockData, buf);
        int i = (ox + oy * 4) * 4;
        out[0] = (uint8)(buf[i] * 255.0f);
        out[1] = (uint8)(buf[i + 1] * 255.0f);
        out[2] = (uint8)(buf[i + 2] * 255.0f);
        out[3] = (uint8)(buf[i + 3] * 255.0f);
    }
};

class TextureDecoder_BC3_UNORM_to_ASTC : public TextureDecoder_BC3_to_ASTC_Generic<ASTCENC_PRF_LDR>, public SingletonClass<TextureDecoder_BC3_UNORM_to_ASTC>
{
};

class TextureDecoder_BC3_SRGB_to_ASTC : public TextureDecoder_BC3_to_ASTC_Generic<ASTCENC_PRF_LDR_SRGB>, public SingletonClass<TextureDecoder_BC3_SRGB_to_ASTC>
{
};

class TextureDecoder_BC4_UNORM_to_ASTC : public TextureDecoder, public SingletonClass<TextureDecoder_BC4_UNORM_to_ASTC>
{
public:
    sint32 getBytesPerTexel(LatteTextureLoaderCtx*) override { return 16; }
    sint32 getTexelCountX(LatteTextureLoaderCtx* tl) override { return (tl->width + 3) / 4; }
    sint32 getTexelCountY(LatteTextureLoaderCtx* tl) override { return (tl->height + 3) / 4; }

    void decode(LatteTextureLoaderCtx* tl, uint8* outputData) override
    {
        decodeBC4AndCompressASTC(tl, outputData, false);
    }

    void decodePixelToRGBA(uint8* blockData, uint8* out, uint8 ox, uint8 oy) override
    {
        float buf[16];
        decodeBC4Block_UNORM(blockData, buf);
        uint8 v = (uint8)(buf[ox + oy * 4] * 255.0f);
        out[0] = v;
        out[1] = 0;
        out[2] = 0;
        out[3] = 255;
    }
};

class TextureDecoder_BC4_SNORM_to_ASTC : public TextureDecoder, public SingletonClass<TextureDecoder_BC4_SNORM_to_ASTC>
{
public:
    sint32 getBytesPerTexel(LatteTextureLoaderCtx*) override { return 16; }
    sint32 getTexelCountX(LatteTextureLoaderCtx* tl) override { return (tl->width + 3) / 4; }
    sint32 getTexelCountY(LatteTextureLoaderCtx* tl) override { return (tl->height + 3) / 4; }

    void decode(LatteTextureLoaderCtx* tl, uint8* outputData) override
    {
        decodeBC4AndCompressASTC(tl, outputData, true);
    }

    void decodePixelToRGBA(uint8* blockData, uint8* out, uint8 ox, uint8 oy) override
    {
        float buf[16];
        decodeBC4Block_SNORM(blockData, buf);
        uint8 v = (uint8)((buf[ox + oy * 4] * 0.5f + 0.5f) * 255.0f);
        out[0] = v;
        out[1] = 0;
        out[2] = 0;
        out[3] = 255;
    }
};

class TextureDecoder_BC5_UNORM_to_ASTC : public TextureDecoder, public SingletonClass<TextureDecoder_BC5_UNORM_to_ASTC>
{
public:
    sint32 getBytesPerTexel(LatteTextureLoaderCtx*) override { return 16; }
    sint32 getTexelCountX(LatteTextureLoaderCtx* tl) override { return (tl->width + 3) / 4; }
    sint32 getTexelCountY(LatteTextureLoaderCtx* tl) override { return (tl->height + 3) / 4; }

    void decode(LatteTextureLoaderCtx* tl, uint8* outputData) override
    {
        decodeBC5AndCompressASTC(tl, outputData, false);
    }

    void decodePixelToRGBA(uint8* blockData, uint8* out, uint8 ox, uint8 oy) override
    {
        float buf[32];
        decodeBC5Block_UNORM(blockData, buf);
        int i = (ox + oy * 4) * 2;
        out[0] = (uint8)(buf[i] * 255.0f);
        out[1] = (uint8)(buf[i + 1] * 255.0f);
        out[2] = 0;
        out[3] = 255;
    }
};

class TextureDecoder_BC5_SNORM_to_ASTC : public TextureDecoder, public SingletonClass<TextureDecoder_BC5_SNORM_to_ASTC>
{
public:
    sint32 getBytesPerTexel(LatteTextureLoaderCtx*) override { return 16; }
    sint32 getTexelCountX(LatteTextureLoaderCtx* tl) override { return (tl->width + 3) / 4; }
    sint32 getTexelCountY(LatteTextureLoaderCtx* tl) override { return (tl->height + 3) / 4; }

    void decode(LatteTextureLoaderCtx* tl, uint8* outputData) override
    {
        decodeBC5AndCompressASTC(tl, outputData, true);
    }

    void decodePixelToRGBA(uint8* blockData, uint8* out, uint8 ox, uint8 oy) override
    {
        float buf[32];
        decodeBC5Block_SNORM(blockData, buf);
        int i = (ox + oy * 4) * 2;
        out[0] = (uint8)((buf[i] * 0.5f + 0.5f) * 255.0f);
        out[1] = (uint8)((buf[i + 1] * 0.5f + 0.5f) * 255.0f);
        out[2] = 0;
        out[3] = 255;
    }
};
