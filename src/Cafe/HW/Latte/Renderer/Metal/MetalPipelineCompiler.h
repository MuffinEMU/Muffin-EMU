#pragma once

#include "Cafe/HW/Latte/Renderer/Metal/MetalAttachmentsInfo.h"

#include "Cafe/HW/Latte/ISA/LatteReg.h"
#include "Cafe/HW/Latte/LegacyShaderDecompiler/LatteDecompiler.h"

struct PipelineObject
{
    MTL::RenderPipelineState* m_pipeline = nullptr;
    // GPUs without mesh shaders: the RECTS expansion kernel generated for this pipeline. It depends on the pixel shader's input
    // table, so it belongs to the pipeline and not to the vertex shader. Owned here, released with the pipeline cache.
    class RendererShaderMtl* m_rectKernel = nullptr;
    uint32 m_rectOutVertexStride = 0;
    ~PipelineObject();
};

class MetalPipelineCompiler
{
public:
    MetalPipelineCompiler(class MetalRenderer* metalRenderer, PipelineObject& pipelineObj) : m_mtlr{metalRenderer}, m_pipelineObj{pipelineObj} {}
    ~MetalPipelineCompiler();

    void InitFromState(const LatteFetchShader* fetchShader, const LatteDecompilerShader* vertexShader, const LatteDecompilerShader* geometryShader, const LatteDecompilerShader* pixelShader, const class MetalAttachmentsInfo& lastUsedAttachmentsInfo, const class MetalAttachmentsInfo& activeAttachmentsInfo, const LatteContextRegister& lcr);

    bool Compile(bool forceCompile, bool isRenderThread, bool showInOverlay);

private:
    class MetalRenderer* m_mtlr;
    PipelineObject& m_pipelineObj;

    class RendererShaderMtl* m_vertexShaderMtl;
    class RendererShaderMtl* m_geometryShaderMtl;
    class RendererShaderMtl* m_pixelShaderMtl;
    bool m_usesGeometryShader;
    // usesGeometryShader is true but this GPU has no mesh pipeline: the vertex and geometry stages run as compute and this
    // pipeline only rasterizes what they wrote
    bool m_emulateGeometryShader = false;
    bool m_rasterizationEnabled;

    NS::Object* m_pipelineDescriptor = nullptr;

    void InitFromStateRender(const LatteFetchShader* fetchShader, const LatteDecompilerShader* vertexShader, const LatteDecompilerShader* pixelShader, const class MetalAttachmentsInfo& lastUsedAttachmentsInfo, const class MetalAttachmentsInfo& activeAttachmentsInfo, const LatteContextRegister& lcr);

	void InitFromStateGeometryEmulation(const class MetalAttachmentsInfo& lastUsedAttachmentsInfo, const class MetalAttachmentsInfo& activeAttachmentsInfo, const LatteContextRegister& lcr, const LatteDecompilerShader* pixelShader);

	void InitFromStateMesh(const LatteFetchShader* fetchShader, const LatteDecompilerShader* pixelShader, const class MetalAttachmentsInfo& lastUsedAttachmentsInfo, const class MetalAttachmentsInfo& activeAttachmentsInfo, const LatteContextRegister& lcr);
};
