#pragma once
#include <algorithm>
#include <atomic>
#include <thread>
#include <vector>
#include "LatteTextureLoader.h"
#include "Common/DeviceCapabilities.h"
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

// Images smaller than this (in texels) are encoded on the calling thread alone: a thread costs tens of
// microseconds to start, and a 256x256 encode already takes longer than three of them.
static constexpr size_t kAstcThreadedMinTexels = 256 * 256;

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
        ASTCENC_PRE_FAST,
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
// output is byte-identical to a single-threaded run. The helpers are joined before this returns, which
// is what makes the astcenc_compress_reset() the caller does next legal. If a helper cannot be started
// the remaining threads simply do its share.
static astcenc_error astcCompressImageThreaded(astcenc_context* context, astcenc_image* image, const astcenc_swizzle* swizzle,
                                               uint8* outputData, size_t outputSize, uint32 threads)
{
    std::atomic<int> helperFailure{(int)ASTCENC_SUCCESS};
    std::vector<std::thread> helpers;
    helpers.reserve(threads - 1);
    for (uint32 i = 1; i < threads; i++)
    {
        try
        {
            helpers.emplace_back([context, image, swizzle, outputData, outputSize, i, &helperFailure]() {
                const astcenc_error st = astcenc_compress_image(context, image, swizzle, outputData, outputSize, i);
                if (st != ASTCENC_SUCCESS)
                {
                    int expected = (int)ASTCENC_SUCCESS;
                    helperFailure.compare_exchange_strong(expected, (int)st);
                }
            });
        }
        catch (...)
        {
            break;
        }
    }

    const astcenc_error mainStatus = astcenc_compress_image(context, image, swizzle, outputData, outputSize, 0);

    for (std::thread& helper : helpers)
        helper.join();

    if (mainStatus != ASTCENC_SUCCESS)
        return mainStatus;
    return (astcenc_error)helperFailure.load();
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
    if ((size_t)width * (size_t)height < kAstcThreadedMinTexels)
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

template<typename BandDecodeFn>
static void decodeBandsAndCompressASTC(LatteTextureLoaderCtx* tl, uint8* outputData, astcenc_profile profile, BandDecodeFn decodeBand)
{
    const sint32 width = tl->width;
    const sint32 height = tl->height;
    const size_t rowBytes = (size_t)width * 4u;
    size_t bandRows = std::max<size_t>(4, (kAstcScratchBudgetBytes / std::max<size_t>(rowBytes, 1)) & ~(size_t)3);
    bandRows = std::min<size_t>(bandRows, (size_t)((height + 3) & ~3));
    std::vector<uint8> rgba8(rowBytes * std::min<size_t>(bandRows, (size_t)height));
    const size_t blocksX = (size_t)((width + 3) / 4);
    for (sint32 y0 = 0; y0 < height; y0 += (sint32)bandRows)
    {
        const sint32 y1 = std::min<sint32>(height, y0 + (sint32)bandRows);
        decodeBand(rgba8.data(), y0, y1);
        uint8* bandOutput = outputData + (size_t)(y0 / 4) * blocksX * 16u;
        if (!astcCompressRGBA8Image(rgba8.data(), width, y1 - y0, profile, bandOutput))
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
