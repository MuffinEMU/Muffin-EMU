#pragma once
#include <algorithm>
#include <vector>
#include "LatteTextureLoader.h"
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

struct ASTCEncoderContextSet
{
    astcenc_context* ldr = nullptr;
    astcenc_context* ldrSrgb = nullptr;

    ~ASTCEncoderContextSet()
    {
        if (ldr)
            astcenc_context_free(ldr);
        if (ldrSrgb)
            astcenc_context_free(ldrSrgb);
    }
};

static astcenc_context* astcGetContext(astcenc_profile profile)
{
    thread_local ASTCEncoderContextSet contexts;
    astcenc_context*& ctx = (profile == ASTCENC_PRF_LDR_SRGB) ? contexts.ldrSrgb : contexts.ldr;
    if (ctx)
        return ctx;

    astcenc_config config;
    astcenc_error status = astcenc_config_init(
        profile,
        4, 4, 1,
        ASTCENC_PRE_FAST,
        0,
        &config);
    if (status != ASTCENC_SUCCESS)
        return nullptr;

    status = astcenc_context_alloc(&config, 1, &ctx, nullptr);
    if (status != ASTCENC_SUCCESS) {
        ctx = nullptr;
        return nullptr;
    }

    return ctx;
}

static bool astcCompressRGBA8Image(const uint8* rgba8, sint32 width, sint32 height, astcenc_profile profile, uint8* outputData)
{
    astcenc_context* context = astcGetContext(profile);
    if (!context) {
        cemuLog_log(LogType::Force, "ASTC Encode Fail: no context");
        return false;
    }

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
    astcenc_error status = astcenc_compress_image(
        context,
        &image,
        &kIdentitySwizzle,
        outputData,
        outputSize,
        0);
    if (status != ASTCENC_SUCCESS) {
        cemuLog_log(LogType::Force, "ASTC Encode Fail: {}", status);
        return false;
    }

    astcenc_compress_reset(context);
    return true;
}

template<typename DecodeFn>
static void decodeBCToRGBA8Image(DecodeFn fn, LatteTextureLoaderCtx* tl, uint8* rgba8)
{
    for (sint32 y = 0; y < tl->height; y += tl->stepY) {
        for (sint32 x = 0; x < tl->width; x += tl->stepX) {
            uint8* blockData = LatteTextureLoader_GetInput(tl, x, y);
            sint32 bsX = std::min(4, tl->width - x);
            sint32 bsY = std::min(4, tl->height - y);

            float floatBuf[16 * 4] = {};
            fn(blockData, floatBuf);

            for (sint32 py = 0; py < bsY; ++py) {
                for (sint32 px = 0; px < bsX; ++px) {
                    sint32 src = (py * 4 + px) * 4;
                    sint32 dst = ((y + py) * tl->width + (x + px)) * 4;
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
static void decodeBC4ToRGBA8Image(DecodeFn fn, LatteTextureLoaderCtx* tl, uint8* rgba8, bool isSigned)
{
    for (sint32 y = 0; y < tl->height; y += tl->stepY) {
        for (sint32 x = 0; x < tl->width; x += tl->stepX) {
            uint8* blockData = LatteTextureLoader_GetInput(tl, x, y);
            sint32 bsX = std::min(4, tl->width - x);
            sint32 bsY = std::min(4, tl->height - y);

            float floatBuf[16] = {};
            fn(blockData, floatBuf);

            for (sint32 py = 0; py < bsY; ++py) {
                for (sint32 px = 0; px < bsX; ++px) {
                    sint32 src = py * 4 + px;
                    sint32 dst = ((y + py) * tl->width + (x + px)) * 4;
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
static void decodeBC5ToRGBA8Image(DecodeFn fn, LatteTextureLoaderCtx* tl, uint8* rgba8, bool isSigned)
{
    for (sint32 y = 0; y < tl->height; y += tl->stepY) {
        for (sint32 x = 0; x < tl->width; x += tl->stepX) {
            uint8* blockData = LatteTextureLoader_GetInput(tl, x, y);
            sint32 bsX = std::min(4, tl->width - x);
            sint32 bsY = std::min(4, tl->height - y);

            float floatBuf[32] = {};
            fn(blockData, floatBuf);

            for (sint32 py = 0; py < bsY; ++py) {
                for (sint32 px = 0; px < bsX; ++px) {
                    sint32 src = (py * 4 + px) * 2;
                    sint32 dst = ((y + py) * tl->width + (x + px)) * 4;
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

template<astcenc_profile Profile, typename DecodeFn>
static void decodeRGBAAndCompressASTC(LatteTextureLoaderCtx* tl, uint8* outputData, DecodeFn fn)
{
    std::vector<uint8> rgba8((size_t)tl->width * (size_t)tl->height * 4u);
    decodeBCToRGBA8Image(fn, tl, rgba8.data());

    if (!astcCompressRGBA8Image(rgba8.data(), tl->width, tl->height, Profile, outputData))
        std::fill(outputData, outputData + astcCompressedImageSize(tl->width, tl->height), 0);
}

static void decodeBC4AndCompressASTC(LatteTextureLoaderCtx* tl, uint8* outputData, bool isSigned)
{
    std::vector<uint8> rgba8((size_t)tl->width * (size_t)tl->height * 4u);
    if (isSigned)
        decodeBC4ToRGBA8Image(decodeBC4Block_SNORM, tl, rgba8.data(), true);
    else
        decodeBC4ToRGBA8Image(decodeBC4Block_UNORM, tl, rgba8.data(), false);

    if (!astcCompressRGBA8Image(rgba8.data(), tl->width, tl->height, ASTCENC_PRF_LDR, outputData))
        std::fill(outputData, outputData + astcCompressedImageSize(tl->width, tl->height), 0);
}

static void decodeBC5AndCompressASTC(LatteTextureLoaderCtx* tl, uint8* outputData, bool isSigned)
{
    std::vector<uint8> rgba8((size_t)tl->width * (size_t)tl->height * 4u);
    if (isSigned)
        decodeBC5ToRGBA8Image(decodeBC5Block_SNORM, tl, rgba8.data(), true);
    else
        decodeBC5ToRGBA8Image(decodeBC5Block_UNORM, tl, rgba8.data(), false);

    if (!astcCompressRGBA8Image(rgba8.data(), tl->width, tl->height, ASTCENC_PRF_LDR, outputData))
        std::fill(outputData, outputData + astcCompressedImageSize(tl->width, tl->height), 0);
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
