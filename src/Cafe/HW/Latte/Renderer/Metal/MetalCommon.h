#pragma once

#include <Foundation/Foundation.hpp>
#include <Metal/Metal.hpp>

#include "Cafe/HW/Latte/Core/LatteConst.h"
#include "Cafe/HW/Latte/Core/LatteWaitInfo.h"
#include "Cafe/HW/Latte/Core/PerfTelemetry.h"

#include <chrono>
#include <thread>

struct MetalPixelFormatSupport
{
	bool m_supportsR8Unorm_sRGB;
	bool m_supportsRG8Unorm_sRGB;
	bool m_supportsPacked16BitFormats;
	bool m_supportsDepth24Unorm_Stencil8;
    bool m_supportsBCFormats;
    // Apple GPUs lack native BC support; ASTC LDR (GPUFamilyApple2 and later) is the fallback.
    bool m_supportsASTCFormats;

	MetalPixelFormatSupport() = default;
	MetalPixelFormatSupport(MTL::Device* device)
	{
        m_supportsR8Unorm_sRGB = device->supportsFamily(MTL::GPUFamilyApple1);
        m_supportsRG8Unorm_sRGB = device->supportsFamily(MTL::GPUFamilyApple1);
        m_supportsPacked16BitFormats = device->supportsFamily(MTL::GPUFamilyApple1);
        m_supportsDepth24Unorm_Stencil8 = false; //device->depth24Stencil8PixelFormatSupported();
        m_supportsBCFormats = device->supportsBCTextureCompression();
        m_supportsASTCFormats = device->supportsFamily(MTL::GPUFamilyApple2);
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

namespace MetalArgumentBuffer
{
	constexpr uint32 BindingIndex = 0;
	constexpr uint32 Dummy = 0;
	constexpr uint32 SupportBuffer = 1;
	constexpr uint32 UniformBufferBase = 2;
	constexpr uint32 StreamoutBuffer = UniformBufferBase + LATTE_NUM_MAX_UNIFORM_BUFFERS;
	constexpr uint32 TextureBase = StreamoutBuffer + 1;
	constexpr uint32 SamplerBase = TextureBase + LATTE_NUM_MAX_TEX_UNITS;
	constexpr uint32 VertexBufferBase = SamplerBase + MAX_MTL_SAMPLERS;
	constexpr uint32 VertexBufferSizeBase = VertexBufferBase + LATTE_MAX_VERTEX_BUFFERS;
	constexpr uint32 IndexBuffer = VertexBufferSizeBase + LATTE_MAX_VERTEX_BUFFERS;
	constexpr uint32 IndexBufferSize = IndexBuffer + 1;
	constexpr uint32 IndexType = IndexBufferSize + 1;
}

// Buffer slots the emulated geometry-shader kernels use next to the argument buffer at MetalArgumentBuffer::BindingIndex
#define MTL_GS_PAYLOAD_BUFFER 1
#define MTL_GS_OUT_BUFFER 2
#define MTL_GS_PRIMCOUNT_BUFFER 3

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

// Waits for a command buffer without ever blocking the GPU thread forever. A command buffer
// that the GPU never finishes (a lost reply, a dead event dependency) would otherwise freeze
// the picture while the game keeps running. Returns false if it gave up; the first few
// give-ups are logged with what was being waited for. After one give-up the GPU is presumed
// lost and later waits only poll briefly, until a wait succeeds again.
inline bool WaitForCommandBuffer(MTL::CommandBuffer* commandBuffer, const char* what)
{
    if (!commandBuffer)
        return true;

    auto& state = LatteWait::Get();
    if (CommandBufferCompleted(commandBuffer))
    {
        // A command buffer that finished cleanly shows the GPU is running this process's work, so an earlier give-up no longer stands. The flag
        // used to clear only on a wait that really blocked: after one slow moment and CPU-bound play it stayed set, and the stop that ended
        // the game read it as a lost GPU and refused every later launch
        if (commandBuffer->status() == MTL::CommandBufferStatusCompleted && state.gpuPresumedLost.load(std::memory_order_relaxed))
            state.gpuPresumedLost.store(false, std::memory_order_relaxed);
        return true;
    }
    LatteWait::Scope waitScope(what);
    PerfTelemetry::ScopedTimer syncTimer(PerfTelemetry::Get().gpuSyncNs);

    const int64_t timeoutMs = state.gpuPresumedLost.load(std::memory_order_relaxed) ? 50 : 2500;
    const auto start = std::chrono::steady_clock::now();
    uint32 spins = 0;
    while (!CommandBufferCompleted(commandBuffer))
    {
        if (std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count() >= timeoutMs)
        {
            const uint32 count = state.timeouts.fetch_add(1) + 1;
            state.lastTimeoutReason.store(what);
            state.gpuPresumedLost.store(true);
            if (count <= 8)
                cemuLog_log(LogType::Force, "Metal: gave up waiting for the GPU ({}) after {} ms, command buffer status {} (timeout #{})", what, timeoutMs, (int)commandBuffer->status(), count);
            return false;
        }
        if (++spins < 64)
            std::this_thread::yield();
        else
            std::this_thread::sleep_for(std::chrono::microseconds(200));
    }
    state.gpuPresumedLost.store(false, std::memory_order_relaxed);
    return true;
}

inline bool FormatIsRenderable(Latte::E_GX2SURFFMT format)
{
    return !Latte::IsCompressedFormat(format);
}

template <typename... T>
inline bool executeCommand(fmt::format_string<T...> fmt, T&&... args) {
    std::string command = fmt::format(fmt, std::forward<T>(args)...);
    // int res = system(command.c_str());

    int res = 0;
    if (res != 0)
    {
        cemuLog_log(LogType::Force, "command \"{}\" failed with exit code {}", command, res);
        return false;
    }

    return true;
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
    case LattePrimitiveMode::TRIANGLE_STRIP:
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
    if (primitiveMode == LattePrimitiveMode::LINE_STRIP ||
        primitiveMode == LattePrimitiveMode::TRIANGLE_STRIP)
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
