#pragma once

#include "Cafe/HW/Latte/Renderer/RendererShader.h"
#include "HW/Latte/Renderer/Metal/CachedFBOMtl.h"
#include "HW/Latte/Renderer/Metal/MetalRenderer.h"
#include "util/helpers/ConcurrentQueue.h"
#include "util/helpers/Semaphore.h"

#include <Metal/Metal.hpp>

class RendererShaderMtl : public RendererShader
{
    friend class ShaderMtlThreadPool;

	enum class COMPILATION_STATE : uint32
	{
		NONE,
		QUEUED,
		COMPILING,
		DONE,
		DEFERRED
	};

public:
    static void ShaderCacheLoading_begin(uint64 cacheTitleId);
    static void ShaderCacheLoading_end();
    static void ShaderCacheLoading_Close();

    static void Initialize();
	static void Shutdown();

	RendererShaderMtl(class MetalRenderer* mtlRenderer, ShaderType type, uint64 baseHash, uint64 auxHash, bool isGameShader, bool isGfxPackShader, const std::string& mslCode);
	virtual ~RendererShaderMtl();

	MTL::Function* GetFunction() const
	{
	    return m_function;
	}

	// Only non-null for a geometry shader compiled for emulation (a RECTS kernel or a decompiled one). The kernel in main0 only
	// fills buffers; this entry point turns them into a draw, and ships in the same library because it has to agree with that
	// shader's own GeometryOut layout.
	MTL::Function* GetPassthroughFunction() const
	{
	    return m_passthroughFunction;
	}

	// For a shader compiled as a kernel (emulated vertex and geometry stages). Built on first use and kept with the shader, so
	// it cannot outlive or alias the function it was made from. Null when the kernel could not be turned into a pipeline.
	MTL::ComputePipelineState* GetComputePipelineState();

	MTL::ArgumentEncoder* GetArgumentEncoder() const
	{
		return m_argumentEncoder;
	}

	uint32 GetArgumentBufferEncodedLength() const
	{
		return m_argumentEncoder ? static_cast<uint32>(m_argumentEncoder->encodedLength()) : 0;
	}

	void PreponeCompilation(bool isRenderThread) override;
	bool IsCompiled() override;
	bool WaitForCompiled() override;

private:
	class MetalRenderer* m_mtlr;

	MTL::Function* m_function = nullptr;
	MTL::Function* m_passthroughFunction = nullptr;
	MTL::ComputePipelineState* m_computePipeline = nullptr;
	bool m_computePipelineFailed = false;
	MTL::ArgumentEncoder* m_argumentEncoder = nullptr;

	StateSemaphore<COMPILATION_STATE> m_compilationState{ COMPILATION_STATE::NONE };

	std::string m_mslCode;

	bool ShouldCountCompilation() const;

	MTL::Library* LibraryFromSource();

	//MTL::Library* LibraryFromAIR(std::span<uint8> data);

	void CompileInternal();

	//void CompileToAIR();

	void FinishCompilation();
};
