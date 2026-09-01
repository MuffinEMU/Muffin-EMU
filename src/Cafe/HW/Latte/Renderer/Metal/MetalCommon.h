#pragma once

#include <atomic>

#include <Foundation/Foundation.hpp>
#include <Metal/Metal.hpp>

#include <objc/message.h>
#include <objc/runtime.h>

#include "Cafe/HW/Latte/Core/LatteConst.h"

/// Off by default; per-game/global setting exposed through
/// cemu_bridge_set_reduce_encoder_splitting(). Set from a Settings toggle rather than
/// baked in, because it targets a specific, unconfirmed hypothesis rather than a proven
/// fix: intermittent rainbow/garbage geometry (screen recordings, 2026-08-31) that
/// coincides with Metal's own runtime warning about heavy interleaving of blit encoders
/// with other encoder types on this exact game. EndEncoding()'s auto-commit is checked
/// after EVERY encoder-type switch, including the short blit encoders textures use for
/// upload/readback - so a frame with a lot of that interleaving can end up auto-committing
/// the command buffer in the middle of a blit rather than at a natural "finished this
/// batch of draws" boundary. MetalSynchronizedRingAllocator's sync points are recorded
/// against whichever command buffer is current AT ALLOCATION TIME; if the buffer that
/// actually reads that memory ends up split into a later command buffer by one of these
/// mid-sequence commits, the allocator can consider the memory free to reuse before the
/// GPU work that reads it has actually run - which is exactly the class of bug that
/// produces occasional, self-correcting garbage geometry rather than a hard crash.
/// Atomic because it is set from the app's main thread (a Settings toggle, or a per-game
/// launch-time read) and read from wherever EndEncoding() runs.
extern std::atomic<bool> g_metal_reduceEncoderSplitting;

// Read a BOOL property off a MTLDevice by selector name. Capability selectors get
// added to the MTLDevice protocol over time and are not implemented by every driver
// class, and sending one that isn't there kills the process - see the depth24Stencil8
// note below, which was found the hard way on device. Going through the runtime lets
// us ask whether the selector exists first, and keeps the query independent of which
// metal-cpp revision happens to be vendored.
//
// The device stays a void* the whole way through, and the two runtime entry points are
// called through recast function pointers. This header reaches ARC Objective-C++ by way
// of CemuBridge.mm, and there a cast from MTL::Device* to id is a hard error: ARC has no
// way to know whether such a cast transfers ownership, so it demands a __bridge
// annotation that a plain C++ translation unit cannot parse. Keeping ObjC pointer types
// out of the signatures sidesteps the question in both kinds of TU. objc_msgSend is
// already called this way below; on arm64 a void* and an id are the same register.
inline bool MtlDeviceBoolProperty(MTL::Device* device, const char* selectorName, bool fallback)
{
	void* deviceObject = static_cast<void*>(device);
	SEL selector = sel_registerName(selectorName);

	using ClassGetter = Class (*)(void*);
	Class deviceClass = reinterpret_cast<ClassGetter>(object_getClass)(deviceObject);
	if (!deviceClass || !class_respondsToSelector(deviceClass, selector))
		return fallback;

	using BoolPropertyGetter = BOOL (*)(void*, SEL);
	return reinterpret_cast<BoolPropertyGetter>(objc_msgSend)(deviceObject, selector) != NO;
}

struct MetalPixelFormatSupport
{
	bool m_supportsR8Unorm_sRGB;
	bool m_supportsRG8Unorm_sRGB;
	bool m_supportsPacked16BitFormats;
	bool m_supportsDepth24Unorm_Stencil8;
	bool m_supportsBCTextureCompression;

	MetalPixelFormatSupport() = default;
	MetalPixelFormatSupport(MTL::Device* device)
	{
        m_supportsR8Unorm_sRGB = device->supportsFamily(MTL::GPUFamilyApple1);
        m_supportsRG8Unorm_sRGB = device->supportsFamily(MTL::GPUFamilyApple1);
        m_supportsPacked16BitFormats = device->supportsFamily(MTL::GPUFamilyApple1);
        // -[MTLDevice depth24Stencil8PixelFormatSupported] is a macOS-only method -
        // Apple deliberately excludes it from the MTLDevice protocol on iOS (the
        // legacy packed D24S8 format isn't relevant to Apple Silicon GPUs, which use
        // D32-based depth/stencil formats instead - see MTL_DEPTH_FORMAT_TABLE in
        // LatteToMtl.cpp, which already maps GX2's D24_S8 formats to
        // PixelFormatDepth32Float_Stencil8 regardless of this flag). Confirmed via a
        // live device crash: -[AGXA12XDevice isDepth24Stencil8PixelFormatSupported]:
        // unrecognized selector sent to instance - calling it unconditionally on iOS
        // reliably throws, since the selector genuinely isn't implemented there.
#if !defined(CEMU_PLATFORM_IOS)
        m_supportsDepth24Unorm_Stencil8 = device->depth24Stencil8PixelFormatSupported();
#else
        m_supportsDepth24Unorm_Stencil8 = false;
#endif
        // BC (DXT/S3TC) is a desktop-GPU format family. Apple Silicon Macs have it,
        // but the A12Z in this iPad does not, and Metal answers a BC texture descriptor
        // by calling MTLReportFailure() -> abort() instead of returning nil - so the
        // very first BC-compressed game texture takes the whole process down with
        // signal 6 inside newTexture(). Ask the device, and let
        // CheckForPixelFormatSupport() swap in CPU decompression when the answer is no.
        // The selector only exists from iOS 16.4 / macOS 11 onwards; where it is
        // missing, assume BC is present on everything except Apple GPUs, which is what
        // the feature set tables say.
        m_supportsBCTextureCompression = MtlDeviceBoolProperty(device, "supportsBCTextureCompression", !device->supportsFamily(MTL::GPUFamilyApple1));
	}
};

// TODO: don't define a new struct for this
struct MetalQueryRange
{
    uint32 begin;
	uint32 end;
};

#define MAX_MTL_BUFFERS 31
// Buffer indices 28-30 are reserved for the helper shaders
#define MTL_RESERVED_BUFFERS 3
#define MAX_MTL_VERTEX_BUFFERS (MAX_MTL_BUFFERS - MTL_RESERVED_BUFFERS)
#define GET_MTL_VERTEX_BUFFER_INDEX(index) (MAX_MTL_VERTEX_BUFFERS - index - 1)

#define MAX_MTL_TEXTURES 31
#define MAX_MTL_SAMPLERS 16

#define GET_HELPER_BUFFER_BINDING(index) (28 + index)
#define GET_HELPER_TEXTURE_BINDING(index) (29 + index)
#define GET_HELPER_SAMPLER_BINDING(index) (14 + index)

constexpr uint32 INVALID_UINT32 = std::numeric_limits<uint32>::max();
constexpr size_t INVALID_OFFSET = std::numeric_limits<size_t>::max();

inline size_t Align(size_t size, size_t alignment)
{
    return (size + alignment - 1) & ~(alignment - 1);
}

__attribute__((unused)) static inline void StackAutoRelease(void* object)
{
    (*(NS::Object**)object)->release();
}

#define NS_STACK_SCOPED __attribute__((cleanup(StackAutoRelease))) __attribute__((unused))

// Cast from const char* to NS::String*
inline NS::String* ToNSString(const char* str)
{
    return NS::String::string(str, NS::ASCIIStringEncoding);
}

// Cast from std::string to NS::String*
inline NS::String* ToNSString(const std::string& str)
{
    return ToNSString(str.c_str());
}

// Cast from const char* to NS::URL*
inline NS::URL* ToNSURL(const char* str)
{
    return NS::URL::fileURLWithPath(ToNSString(str));
}

// Cast from std::string to NS::URL*
inline NS::URL* ToNSURL(const std::string& str)
{
    return ToNSURL(str.c_str());
}

inline NS::String* GetLabel(const std::string& label, const void* identifier)
{
    return ToNSString(label + " (" + std::to_string(reinterpret_cast<uintptr_t>(identifier)) + ")");
}

constexpr MTL::RenderStages ALL_MTL_RENDER_STAGES = MTL::RenderStageVertex | MTL::RenderStageObject | MTL::RenderStageMesh | MTL::RenderStageFragment;

inline bool IsValidDepthTextureType(Latte::E_DIM dim)
{
    return (dim == Latte::E_DIM::DIM_2D || dim == Latte::E_DIM::DIM_2D_MSAA || dim == Latte::E_DIM::DIM_2D_ARRAY || dim == Latte::E_DIM::DIM_2D_ARRAY_MSAA || dim == Latte::E_DIM::DIM_CUBEMAP);
}

inline bool CommandBufferCompleted(MTL::CommandBuffer* commandBuffer)
{
    auto status = commandBuffer->status();
    return (status == MTL::CommandBufferStatusCompleted || status == MTL::CommandBufferStatusError);
}

inline bool FormatIsRenderable(Latte::E_GX2SURFFMT format)
{
    return !Latte::IsCompressedFormat(format);
}

template <typename... T>
inline bool executeCommand(fmt::format_string<T...> fmt, T&&... args) {
#if defined(CEMU_PLATFORM_IOS)
    // system() is unavailable on iOS (App Store sandboxing) and every caller of
    // executeCommand() in RendererShaderMtl.cpp is currently disabled code (the
    // AIR-cache-via-xcrun path); the live path is LibraryFromSource(), which
    // compiles MSL in-process through the real Metal API instead of shelling out.
    std::string command = fmt::format(fmt, std::forward<T>(args)...);
    cemuLog_log(LogType::Force, "executeCommand unavailable on iOS, skipped: {}", command);
    return false;
#else
    std::string command = fmt::format(fmt, std::forward<T>(args)...);
    int res = system(command.c_str());
    if (res != 0)
    {
        cemuLog_log(LogType::Force, "command \"{}\" failed with exit code {}", command, res);
        return false;
    }

    return true;
#endif
}

/*
class MemoryMappedFile
{
public:
    MemoryMappedFile(const std::string& filePath)
    {
        // Open the file
        m_fd = open(filePath.c_str(), O_RDONLY);
        if (m_fd == -1) {
            cemuLog_log(LogType::Force, "failed to open file: {}", filePath);
            return;
        }

        // Get the file size
        // Use a loop to handle the case where the file size is 0 (more of a safety net)
        struct stat fileStat;
        while (true)
        {
            if (fstat(m_fd, &fileStat) == -1)
            {
                close(m_fd);
                cemuLog_log(LogType::Force, "failed to get file size: {}", filePath);
                return;
            }
            m_fileSize = fileStat.st_size;

            if (m_fileSize == 0)
            {
                cemuLog_logOnce(LogType::Force, "file size is 0: {}", filePath);
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
                continue;
            }

            break;
        }

        // Memory map the file
        m_data = mmap(nullptr, m_fileSize, PROT_READ, MAP_PRIVATE, m_fd, 0);
        if (m_data == MAP_FAILED)
        {
            close(m_fd);
            cemuLog_log(LogType::Force, "failed to memory map file: {}", filePath);
            return;
        }
    }

    ~MemoryMappedFile()
    {
        if (m_data && m_data != MAP_FAILED)
            munmap(m_data, m_fileSize);

        if (m_fd != -1)
            close(m_fd);
    }

    uint8* data() const { return static_cast<uint8*>(m_data); }
    size_t size() const { return m_fileSize; }

private:
    int m_fd = -1;
    void* m_data = nullptr;
    size_t m_fileSize = 0;
};
*/

inline uint32 GetVerticesPerPrimitive(LattePrimitiveMode primitiveMode)
{
    switch (primitiveMode)
    {
    case LattePrimitiveMode::POINTS:
        return 1;
    case LattePrimitiveMode::LINES:
        return 2;
    case LattePrimitiveMode::LINE_STRIP:
        // Same as line, but requires connection
        return 2;
    case LattePrimitiveMode::TRIANGLES:
        return 3;
    case LattePrimitiveMode::RECTS:
        return 3;
    default:
        cemuLog_log(LogType::Force, "Unimplemented primitive type {}", primitiveMode);
        return 0;
    }
}

inline bool PrimitiveRequiresConnection(LattePrimitiveMode primitiveMode)
{
    if (primitiveMode == LattePrimitiveMode::LINE_STRIP)
        return true;
    else
        return false;
}

inline bool UseRectEmulation(const LatteContextRegister& lcr) {
    const LattePrimitiveMode primitiveMode = lcr.VGT_PRIMITIVE_TYPE.get_PRIMITIVE_MODE();
    return (primitiveMode == Latte::LATTE_VGT_PRIMITIVE_TYPE::E_PRIMITIVE_TYPE::RECTS);
}

inline bool UseGeometryShader(const LatteContextRegister& lcr, bool hasGeometryShader) {
    return hasGeometryShader || UseRectEmulation(lcr);
}
