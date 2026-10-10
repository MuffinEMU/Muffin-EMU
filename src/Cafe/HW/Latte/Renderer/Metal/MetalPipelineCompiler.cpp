#include "Cafe/HW/Latte/Renderer/Metal/MetalCommon.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalPipelineCompiler.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalPipelineCache.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalRenderer.h"
#include "Cafe/HW/Latte/Renderer/Metal/CachedFBOMtl.h"
#include "Cafe/HW/Latte/Renderer/Metal/LatteToMtl.h"
#include "Cafe/HW/Latte/Renderer/Metal/RendererShaderMtl.h"
#include "Cafe/HW/Latte/Renderer/Metal/LatteTextureViewMtl.h"

#include "Cafe/HW/Latte/Core/FetchShader.h"
#include "Cafe/HW/Latte/ISA/RegDefines.h"
#include "Cafe/HW/Latte/Core/LatteConst.h"
#include "Cafe/HW/Latte/Core/LatteShader.h"

#include <chrono>

extern std::atomic_int g_compiling_pipelines;
extern std::atomic_int g_compiling_pipelines_async;
extern std::atomic_uint64_t g_compiling_pipelines_syncTimeSum;

static void rectsEmulationGS_outputSingleVertex(std::string& gsSrc, const LatteDecompilerShader* vertexShader, LatteShaderPSInputTable& psInputTable, sint32 vIdx, const LatteContextRegister& latteRegister, bool compute)
{
	auto parameterMask = vertexShader->outputParameterMask;
	for (uint32 i = 0; i < 32; i++)
	{
		if ((parameterMask & (1 << i)) == 0)
			continue;
		sint32 vsSemanticId = psInputTable.getVertexShaderOutParamSemanticId(latteRegister.GetRawView(), i);
		if (vsSemanticId < 0)
			continue;
		// make sure PS has matching input
		if (!psInputTable.hasPSImportForSemanticId(vsSemanticId))
			continue;
		gsSrc.append(fmt::format("out.passParameterSem{} = objectPayload.vertexOut[{}].passParameterSem{};\r\n", vsSemanticId, vIdx, vsSemanticId));
	}
	gsSrc.append(fmt::format("out.position = objectPayload.vertexOut[{}].position;\r\n", vIdx));
	if (compute)
		gsSrc.append(fmt::format("v[{}] = out;\r\n", vIdx));
	else
		gsSrc.append(fmt::format("mesh.set_vertex({}, out);\r\n", vIdx));
}

static void rectsEmulationGS_outputGeneratedVertex(std::string& gsSrc, const LatteDecompilerShader* vertexShader, LatteShaderPSInputTable& psInputTable, const char* variant, const LatteContextRegister& latteRegister, bool compute)
{
	auto parameterMask = vertexShader->outputParameterMask;
	for (uint32 i = 0; i < 32; i++)
	{
		if ((parameterMask & (1 << i)) == 0)
			continue;
		sint32 vsSemanticId = psInputTable.getVertexShaderOutParamSemanticId(latteRegister.GetRawView(), i);
		if (vsSemanticId < 0)
			continue;
		// make sure PS has matching input
		if (!psInputTable.hasPSImportForSemanticId(vsSemanticId))
			continue;
		gsSrc.append(fmt::format("out.passParameterSem{} = gen4thVertex{}(objectPayload.vertexOut[0].passParameterSem{}, objectPayload.vertexOut[1].passParameterSem{}, objectPayload.vertexOut[2].passParameterSem{});\r\n", vsSemanticId, variant, vsSemanticId, vsSemanticId, vsSemanticId));
	}
	gsSrc.append(fmt::format("out.position = gen4thVertex{}(objectPayload.vertexOut[0].position, objectPayload.vertexOut[1].position, objectPayload.vertexOut[2].position);\r\n", variant));
	if (compute)
		gsSrc.append("v[3] = out;\r\n");
	else
		gsSrc.append(fmt::format("mesh.set_vertex(3, out);\r\n"));
}

static void rectsEmulationGS_outputVerticesCode(std::string& gsSrc, const LatteDecompilerShader* vertexShader, LatteShaderPSInputTable& psInputTable, sint32 p0, sint32 p1, sint32 p2, sint32 p3, const char* variant, const LatteContextRegister& latteRegister, bool compute)
{
	sint32 pList[4] = { p0, p1, p2, p3 };
	for (sint32 i = 0; i < 4; i++)
	{
		if (pList[i] == 3)
			rectsEmulationGS_outputGeneratedVertex(gsSrc, vertexShader, psInputTable, variant, latteRegister, compute);
		else
			rectsEmulationGS_outputSingleVertex(gsSrc, vertexShader, psInputTable, pList[i], latteRegister, compute);
	}
	if (compute)
	{
		// The same six vertices the mesh path indexes: (p0, p1, p2) and (p1, p2, p3)
		const sint32 order[6] = { pList[0], pList[1], pList[2], pList[1], pList[2], pList[3] };
		for (sint32 i = 0; i < 6; i++)
			gsSrc.append(fmt::format("gsOut[gid * 6 + {}] = v[{}];\r\n", i, order[i]));
		return;
	}
	gsSrc.append(fmt::format("mesh.set_index(0, {});\r\n", pList[0]));
	gsSrc.append(fmt::format("mesh.set_index(1, {});\r\n", pList[1]));
	gsSrc.append(fmt::format("mesh.set_index(2, {});\r\n", pList[2]));
	gsSrc.append(fmt::format("mesh.set_index(3, {});\r\n", pList[1]));
	gsSrc.append(fmt::format("mesh.set_index(4, {});\r\n", pList[2]));
	gsSrc.append(fmt::format("mesh.set_index(5, {});\r\n", pList[3]));
}

// compute: no mesh shaders on this GPU, so the same expansion runs as a kernel that writes its six vertices to a device buffer, and a
// passthrough vertex function in the same library draws them. outVertexStride receives the byte size of one stored vertex.
static RendererShaderMtl* rectsEmulationGS_generate(MetalRenderer* metalRenderer, const LatteDecompilerShader* vertexShader, const LatteContextRegister& latteRegister, bool compute = false, uint32* outVertexStride = nullptr)
{
	std::string gsSrc;
	gsSrc.append("#include <metal_stdlib>\r\n");
	gsSrc.append("using namespace metal;\r\n");

	LatteShaderPSInputTable psInputTable;
	LatteShader_CreatePSInputTable(&psInputTable, latteRegister.GetRawView());

	// inputs & outputs
	std::string vertexOutDefinition = "struct VertexOut {\r\n";
	vertexOutDefinition += "float4 position;\r\n";
	std::string geometryOutDefinition = "struct GeometryOut {\r\n";
	geometryOutDefinition += compute ? "float4 position;\r\n" : "float4 position [[position]];\r\n";
	std::string rasterOutDefinition = "struct GeometryOutRaster {\r\nfloat4 position [[position]];\r\n";
	std::string rasterConvert = "static GeometryOutRaster gsToRaster(GeometryOut o) {\r\nGeometryOutRaster r;\r\nr.position = o.position;\r\n";
	uint32 storedParamCount = 0;
	auto parameterMask = vertexShader->outputParameterMask;
	for (uint32 i = 0; i < 32; i++)
	{
		if ((parameterMask & (1 << i)) == 0)
			continue;
		sint32 vsSemanticId = psInputTable.getVertexShaderOutParamSemanticId(latteRegister.GetRawView(), i);
		if (vsSemanticId < 0)
			continue;
		auto psImport = psInputTable.getPSImportBySemanticId(vsSemanticId);
		if (psImport == nullptr)
			continue;

		// VertexOut
		vertexOutDefinition += fmt::format("float4 passParameterSem{};\r\n", vsSemanticId);

		// GeometryOut
		std::string attributes = fmt::format(" [[user(locn{})]]", psInputTable.getPSImportLocationBySemanticId(vsSemanticId));
        if (psImport->isFlat)
            attributes += " [[flat]]";
        if (psImport->isNoPerspective)
			attributes += " [[center_no_perspective]]";
		if (compute)
		{
			geometryOutDefinition += fmt::format("float4 passParameterSem{};\r\n", vsSemanticId);
			rasterOutDefinition += fmt::format("float4 passParameterSem{}{};\r\n", vsSemanticId, attributes);
			rasterConvert += fmt::format("r.passParameterSem{} = o.passParameterSem{};\r\n", vsSemanticId, vsSemanticId);
			storedParamCount++;
		}
		else
			geometryOutDefinition += fmt::format("float4 passParameterSem{}{};\r\n", vsSemanticId, attributes);
	}
	vertexOutDefinition += "};\r\n";
	geometryOutDefinition += "};\r\n";

	if (compute)
	{
		// The vertex kernel wrote its VertexOut with this exact definition, so the kernel reads it back with the same text. A second
		// hand-built struct could differ in size (pointSize, PS inputs the VS does not write) and then every vertexOut[i] would be off.
		vertexOutDefinition = vertexShader->mtlRectVertexOutDef;
		rasterOutDefinition += "};\r\n";
		rasterConvert += "return r;\r\n}\r\n";
		if (outVertexStride)
			*outVertexStride = 16u + storedParamCount * 16u;
	}

	gsSrc.append(vertexOutDefinition);
	gsSrc.append(geometryOutDefinition);
	if (compute)
	{
		gsSrc.append(rasterOutDefinition);
		gsSrc.append(rasterConvert);
	}

	gsSrc.append("struct ObjectPayload {\r\n");
	gsSrc.append("VertexOut vertexOut[3];\r\n");
	if (compute)
		gsSrc.append("uint primitiveID;\r\n");
	gsSrc.append("};\r\n");

	// gen function
	gsSrc.append("float4 gen4thVertexA(float4 a, float4 b, float4 c)\r\n");
	gsSrc.append("{\r\n");
	gsSrc.append("return b - (c - a);\r\n");
	gsSrc.append("}\r\n");

	gsSrc.append("float4 gen4thVertexB(float4 a, float4 b, float4 c)\r\n");
	gsSrc.append("{\r\n");
	gsSrc.append("return c - (b - a);\r\n");
	gsSrc.append("}\r\n");

	gsSrc.append("float4 gen4thVertexC(float4 a, float4 b, float4 c)\r\n");
	gsSrc.append("{\r\n");
	gsSrc.append("return c + (b - a);\r\n");
	gsSrc.append("}\r\n");

	// main
	if (compute)
	{
		gsSrc.append(fmt::format("kernel void main0(uint gid [[thread_position_in_grid]], const device ObjectPayload* gsPayloadIn [[buffer({})]], device GeometryOut* gsOut [[buffer({})]], device uint* gsPrimCount [[buffer({})]])\r\n", MTL_GS_PAYLOAD_BUFFER, MTL_GS_OUT_BUFFER, MTL_GS_PRIMCOUNT_BUFFER));
		gsSrc.append("{\r\n");
		gsSrc.append("const device ObjectPayload& objectPayload = gsPayloadIn[gid];\r\n");
		gsSrc.append("GeometryOut v[4];\r\n");
	}
	else
	{
		gsSrc.append("using MeshType = mesh<GeometryOut, void, 4, 2, topology::triangle>;\r\n");
		gsSrc.append("[[mesh, max_total_threads_per_threadgroup(1)]]\r\n");
		gsSrc.append("void main0(MeshType mesh, const object_data ObjectPayload& objectPayload [[payload]])\r\n");
		gsSrc.append("{\r\n");
	}
	gsSrc.append("GeometryOut out;\r\n");

	// there are two possible winding orders that need different triangle generation:
	// 0 1
	// 2 3
	// and
	// 0 1
	// 3 2
	// all others are just symmetries of these cases

	// we can determine the case by comparing the distance 0<->1 and 0<->2

	gsSrc.append("float dist0_1 = length(objectPayload.vertexOut[1].position.xy - objectPayload.vertexOut[0].position.xy);\r\n");
	gsSrc.append("float dist0_2 = length(objectPayload.vertexOut[2].position.xy - objectPayload.vertexOut[0].position.xy);\r\n");
	gsSrc.append("float dist1_2 = length(objectPayload.vertexOut[2].position.xy - objectPayload.vertexOut[1].position.xy);\r\n");

	// emit vertices
	gsSrc.append("if(dist0_1 > dist0_2 && dist0_1 > dist1_2)\r\n");
	gsSrc.append("{\r\n");
	// p0 to p1 is diagonal
	rectsEmulationGS_outputVerticesCode(gsSrc, vertexShader, psInputTable, 2, 1, 0, 3, "A", latteRegister, compute);
	gsSrc.append("} else if ( dist0_2 > dist0_1 && dist0_2 > dist1_2 ) {\r\n");
	// p0 to p2 is diagonal
	rectsEmulationGS_outputVerticesCode(gsSrc, vertexShader, psInputTable, 1, 2, 0, 3, "B", latteRegister, compute);
	gsSrc.append("} else {\r\n");
	// p1 to p2 is diagonal
	rectsEmulationGS_outputVerticesCode(gsSrc, vertexShader, psInputTable, 0, 1, 2, 3, "C", latteRegister, compute);
	gsSrc.append("}\r\n");

	if (compute)
	{
		gsSrc.append("gsPrimCount[gid] = 2;\r\n");
		gsSrc.append("}\r\n");
		gsSrc.append(fmt::format("vertex GeometryOutRaster gsPassthroughVS(uint vid [[vertex_id]], const device GeometryOut* gsOut [[buffer(0)]]) {{ return gsToRaster(gsOut[vid]); }}\r\n"));
	}
	else
	{
		gsSrc.append("mesh.set_primitive_count(2);\r\n");

		gsSrc.append("}\r\n");
	}

	auto mtlShader = new RendererShaderMtl(metalRenderer, RendererShader::ShaderType::kGeometry, 0, 0, false, false, gsSrc);
	mtlShader->PreponeCompilation(true);

	return mtlShader;
}

PipelineObject::~PipelineObject()
{
    delete m_rectKernel;
}

#define INVALID_TITLE_ID 0xFFFFFFFFFFFFFFFF

uint64 s_cacheTitleId = INVALID_TITLE_ID;

extern std::atomic_int g_compiled_shaders_total;
extern std::atomic_int g_compiled_shaders_async;

static bool ShaderReadsFramebufferFetchAttachment(const LatteDecompilerShader* pixelShader, uint8 attachmentIndex)
{
	if (!pixelShader)
		return false;
    
    for (sint32 i = 0; i < pixelShader->textureUnitListCount; i++)
    {
        sint32 textureIndex = pixelShader->textureUnitList[i];
        if (pixelShader->textureRenderTargetIndex[textureIndex] == attachmentIndex)
            return true;
	}

	return false;
}

template<typename T>
void SetFragmentState(T* desc, const MetalAttachmentsInfo& lastUsedAttachmentsInfo, const MetalAttachmentsInfo& activeAttachmentsInfo, bool rasterizationEnabled, bool supportsFramebufferFetch, const LatteContextRegister& lcr, const LatteDecompilerShader* pixelShader)
{
	// TODO: check if the pixel shader is valid as well?
	if (!rasterizationEnabled/* || !pixelShaderMtl*/)
	{
	    desc->setRasterizationEnabled(false);
		return;
	}

    // Color attachments
	const Latte::LATTE_CB_COLOR_CONTROL& colorControlReg = lcr.CB_COLOR_CONTROL;
	uint32 blendEnableMask = colorControlReg.get_BLEND_MASK();
	uint32 renderTargetMask = lcr.CB_TARGET_MASK.get_MASK();
	for (uint8 i = 0; i < LATTE_NUM_COLOR_TARGET; i++)
	{
	    Latte::E_GX2SURFFMT format = lastUsedAttachmentsInfo.colorFormats[i];
		if (format == Latte::E_GX2SURFFMT::INVALID_FORMAT && supportsFramebufferFetch && ShaderReadsFramebufferFetchAttachment(pixelShader, i))
		{
			format = activeAttachmentsInfo.colorFormats[i];
			if (format == Latte::E_GX2SURFFMT::INVALID_FORMAT)
				format = LatteMRT::GetColorBufferFormat(i, lcr);
		}
		if (format == Latte::E_GX2SURFFMT::INVALID_FORMAT)
		    continue;

		MTL::PixelFormat pixelFormat = GetMtlPixelFormat(format, false);
		if (pixelFormat == MTL::PixelFormatInvalid)
			continue;

		auto colorAttachment = desc->colorAttachments()->object(i);
		colorAttachment->setPixelFormat(pixelFormat);

		// Disable writes if not in the active FBO
		if (activeAttachmentsInfo.colorFormats[i] == Latte::E_GX2SURFFMT::INVALID_FORMAT)
        {
            colorAttachment->setWriteMask(MTL::ColorWriteMaskNone);
            continue;
        }

		colorAttachment->setWriteMask(GetMtlColorWriteMask((renderTargetMask >> (i * 4)) & 0xF));

		// Blending
		bool blendEnabled = ((blendEnableMask & (1 << i))) != 0;
		// Only float data type is blendable
		if (blendEnabled && GetMtlPixelFormatInfo(format, false).dataType == MetalDataType::FLOAT)
		{
       		colorAttachment->setBlendingEnabled(true);

       		const auto& blendControlReg = lcr.CB_BLENDN_CONTROL[i];

       		auto rgbBlendOp = GetMtlBlendOp(blendControlReg.get_COLOR_COMB_FCN());
       		auto srcRgbBlendFactor = GetMtlBlendFactor(blendControlReg.get_COLOR_SRCBLEND());
       		auto dstRgbBlendFactor = GetMtlBlendFactor(blendControlReg.get_COLOR_DSTBLEND());

       		colorAttachment->setRgbBlendOperation(rgbBlendOp);
       		colorAttachment->setSourceRGBBlendFactor(srcRgbBlendFactor);
       		colorAttachment->setDestinationRGBBlendFactor(dstRgbBlendFactor);
       		if (blendControlReg.get_SEPARATE_ALPHA_BLEND())
       		{
       			colorAttachment->setAlphaBlendOperation(GetMtlBlendOp(blendControlReg.get_ALPHA_COMB_FCN()));
      		    colorAttachment->setSourceAlphaBlendFactor(GetMtlBlendFactor(blendControlReg.get_ALPHA_SRCBLEND()));
      		    colorAttachment->setDestinationAlphaBlendFactor(GetMtlBlendFactor(blendControlReg.get_ALPHA_DSTBLEND()));
       		}
       		else
       		{
           		colorAttachment->setAlphaBlendOperation(rgbBlendOp);
           		colorAttachment->setSourceAlphaBlendFactor(srcRgbBlendFactor);
           		colorAttachment->setDestinationAlphaBlendFactor(dstRgbBlendFactor);
       		}
		}
	}

	// Depth stencil attachment
	if (lastUsedAttachmentsInfo.depthFormat != Latte::E_GX2SURFFMT::INVALID_FORMAT)
	{
	    MTL::PixelFormat pixelFormat = GetMtlPixelFormat(lastUsedAttachmentsInfo.depthFormat, true);
        desc->setDepthAttachmentPixelFormat(pixelFormat);
        if (lastUsedAttachmentsInfo.hasStencil)
            desc->setStencilAttachmentPixelFormat(pixelFormat);
	}
}

MetalPipelineCompiler::~MetalPipelineCompiler()
{
    /*
    for (auto& pair : m_pipelineCache)
    {
        pair.second->release();
    }
    m_pipelineCache.clear();

    NS::Error* error = nullptr;
    m_binaryArchive->serializeToURL(m_binaryArchiveURL, &error);
    if (error)
    {
        cemuLog_log(LogType::Force, "error serializing binary archive: {}", error->localizedDescription()->utf8String());
        error->release();
    }
    m_binaryArchive->release();

    m_binaryArchiveURL->release();
    */
    if (m_pipelineDescriptor)
        m_pipelineDescriptor->release();
}

void MetalPipelineCompiler::InitFromState(const LatteFetchShader* fetchShader, const LatteDecompilerShader* vertexShader, const LatteDecompilerShader* geometryShader, const LatteDecompilerShader* pixelShader, const MetalAttachmentsInfo& lastUsedAttachmentsInfo, const MetalAttachmentsInfo& activeAttachmentsInfo, const LatteContextRegister& lcr)
{
    m_usesGeometryShader = UseGeometryShader(lcr, geometryShader != nullptr);
    m_emulateGeometryShader = m_usesGeometryShader && m_mtlr->UseGeometryShaderEmulation();

    // Rasterization
	m_rasterizationEnabled = lcr.IsRasterizationEnabled();

    // Shaders
    m_vertexShaderMtl = static_cast<RendererShaderMtl*>(vertexShader->shader);
    if (geometryShader)
        m_geometryShaderMtl = static_cast<RendererShaderMtl*>(geometryShader->shader);
    else if (UseRectEmulation(lcr))
    {
        if (m_emulateGeometryShader)
        {
            // Without the vertex stage's own VertexOut text there is nothing the kernel could read the payload with
            if (!vertexShader->mtlRectVertexOutDef.empty())
            {
                m_geometryShaderMtl = rectsEmulationGS_generate(m_mtlr, vertexShader, lcr, true, &m_pipelineObj.m_rectOutVertexStride);
                m_pipelineObj.m_rectKernel = m_geometryShaderMtl;
            }
            else
                m_geometryShaderMtl = nullptr;
        }
        else
            m_geometryShaderMtl = rectsEmulationGS_generate(m_mtlr, vertexShader, lcr);
    }
    else
        m_geometryShaderMtl = nullptr;
    m_pixelShaderMtl = static_cast<RendererShaderMtl*>(pixelShader->shader);

    if (m_emulateGeometryShader)
        InitFromStateGeometryEmulation(lastUsedAttachmentsInfo, activeAttachmentsInfo, lcr, pixelShader);
    else if (m_usesGeometryShader)
        InitFromStateMesh(fetchShader, pixelShader, lastUsedAttachmentsInfo, activeAttachmentsInfo, lcr);
    else
        InitFromStateRender(fetchShader, vertexShader, pixelShader, lastUsedAttachmentsInfo, activeAttachmentsInfo, lcr);
}

bool MetalPipelineCompiler::Compile(bool forceCompile, bool isRenderThread, bool showInOverlay)
{
	NS_STACK_SCOPED NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
    // Emulated, there is no render pipeline to build when nothing is rasterized: the compute stages are the whole draw
    if (m_emulateGeometryShader && !m_rasterizationEnabled)
        return true;

    if (forceCompile)
	{
		// if some shader stages are not compiled yet, compile them now
		if (m_vertexShaderMtl && !m_vertexShaderMtl->IsCompiled())
			m_vertexShaderMtl->PreponeCompilation(isRenderThread);
		if (m_geometryShaderMtl && !m_geometryShaderMtl->IsCompiled())
			m_geometryShaderMtl->PreponeCompilation(isRenderThread);
		if (m_pixelShaderMtl && !m_pixelShaderMtl->IsCompiled())
			m_pixelShaderMtl->PreponeCompilation(isRenderThread);
	}
	else
	{
	    // fail early if some shader stages are not compiled
		if (m_vertexShaderMtl && !m_vertexShaderMtl->IsCompiled())
			return false;
		if (m_geometryShaderMtl && !m_geometryShaderMtl->IsCompiled())
			return false;
		if (m_pixelShaderMtl && !m_pixelShaderMtl->IsCompiled())
			return false;
	}

	// Compile
    MTL::RenderPipelineState* pipeline = nullptr;
    NS::Error* error = nullptr;

    auto start = std::chrono::high_resolution_clock::now();
    if (m_emulateGeometryShader)
    {
        auto desc = static_cast<MTL::RenderPipelineDescriptor*>(m_pipelineDescriptor);

        // The vertex stage already ran as compute. What is left to rasterize is whatever the geometry kernel wrote, and the
        // passthrough function in that shader's library is what reads it.
        MTL::Function* passthroughFunction = m_geometryShaderMtl ? m_geometryShaderMtl->GetPassthroughFunction() : nullptr;
        MTL::Function* fragmentFunction = m_pixelShaderMtl->GetFunction();
        if (!passthroughFunction || !fragmentFunction)
        {
            cemuLog_logOnce(LogType::Force, "Metal: a geometry-shader emulation pipeline could not be built because a shader function is nil (passthrough {}, fragment {})", passthroughFunction ? "ok" : "missing", fragmentFunction ? "ok" : "missing");
            return false;
        }
        desc->setVertexFunction(passthroughFunction);
        desc->setFragmentFunction(fragmentFunction);
        desc->setLabel(ToNSString(fmt::format("emulated geometry pipeline PS {:016x}-{:016x}", m_pixelShaderMtl->GetBaseHash(), m_pixelShaderMtl->GetAuxHash())));
        pipeline = m_mtlr->GetDevice()->newRenderPipelineState(desc, MTL::PipelineOptionNone, nullptr, &error);
    }
    else if (m_usesGeometryShader)
    {
        auto desc = static_cast<MTL::MeshRenderPipelineDescriptor*>(m_pipelineDescriptor);

        // Shaders
        MTL::Function* objectFunction = m_vertexShaderMtl->GetFunction();
        MTL::Function* meshFunction = m_geometryShaderMtl->GetFunction();
        MTL::Function* fragmentFunction = m_rasterizationEnabled ? m_pixelShaderMtl->GetFunction() : nullptr;
        
        if (!objectFunction || !meshFunction || (m_rasterizationEnabled && !fragmentFunction))
        {
            cemuLog_log(LogType::Force, "failed to create Metal mesh pipeline because a shader function is nil");
            return false;
        }
        
        desc->setObjectFunction(objectFunction);
        desc->setMeshFunction(meshFunction);
        if (m_rasterizationEnabled)
            desc->setFragmentFunction(fragmentFunction);

        desc->setLabel(ToNSString(fmt::format("mesh pipeline PS {:016x}-{:016x}", m_pixelShaderMtl ? m_pixelShaderMtl->GetBaseHash() : 0, m_pixelShaderMtl ? m_pixelShaderMtl->GetAuxHash() : 0)));
       	pipeline = m_mtlr->GetDevice()->newRenderPipelineState(desc, MTL::PipelineOptionNone, nullptr, &error);
    }
    else
    {
        auto desc = static_cast<MTL::RenderPipelineDescriptor*>(m_pipelineDescriptor);

        // Shaders
        MTL::Function* vertexFunction = m_vertexShaderMtl->GetFunction();
        MTL::Function* fragmentFunction = m_rasterizationEnabled ? m_pixelShaderMtl->GetFunction() : nullptr;
        if (!vertexFunction || (m_rasterizationEnabled && !fragmentFunction))
        {
            cemuLog_log(LogType::Force, "failed to create Metal render pipeline because a shader function is nil");
            return false;
        }
        desc->setVertexFunction(vertexFunction);
        if (m_rasterizationEnabled)
            desc->setFragmentFunction(fragmentFunction);

        desc->setLabel(ToNSString(fmt::format("pipeline VS {:016x}-{:016x} PS {:016x}-{:016x}", m_vertexShaderMtl->GetBaseHash(), m_vertexShaderMtl->GetAuxHash(), m_pixelShaderMtl ? m_pixelShaderMtl->GetBaseHash() : 0, m_pixelShaderMtl ? m_pixelShaderMtl->GetAuxHash() : 0)));
        if (NS::Array* archives = MetalPipelineCache_GetBinaryArchives())
        {
            desc->setBinaryArchives(archives);
            pipeline = m_mtlr->GetDevice()->newRenderPipelineState(desc, MTL::PipelineOptionFailOnBinaryArchiveMiss, nullptr, &error);
            MetalPipelineCache_NoteArchiveLookup(pipeline != nullptr);
            if (!pipeline)
                error = nullptr;
        }
        if (!pipeline)
        {
            pipeline = m_mtlr->GetDevice()->newRenderPipelineState(desc, MTL::PipelineOptionNone, nullptr, &error);
            if (pipeline && !(isRenderThread && showInOverlay))
                MetalPipelineCache_QueueArchiveAdd(desc);
        }
    }
    auto end = std::chrono::high_resolution_clock::now();

    auto creationDuration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
    PerfTelemetry::Get().pipelineCompiles.fetch_add(1, std::memory_order_relaxed);
    PerfTelemetry::Get().pipelineCompileNs.fetch_add((uint64)creationDuration, std::memory_order_relaxed);

   	if (error)
   	{
       	cemuLog_log(LogType::Force, "error creating render pipeline state: {}", error->localizedDescription()->utf8String());
   	}

    if (showInOverlay)
	{
		if (isRenderThread)
			g_compiling_pipelines_syncTimeSum += creationDuration;
		else
			g_compiling_pipelines_async++;
		g_compiling_pipelines++;
	}

	m_pipelineObj.m_pipeline = pipeline;

	return true;
}

void MetalPipelineCompiler::InitFromStateRender(const LatteFetchShader* fetchShader, const LatteDecompilerShader* vertexShader, const LatteDecompilerShader* pixelShader, const MetalAttachmentsInfo& lastUsedAttachmentsInfo, const MetalAttachmentsInfo& activeAttachmentsInfo, const LatteContextRegister& lcr)
{
	// Render pipeline state
	MTL::RenderPipelineDescriptor* desc = MTL::RenderPipelineDescriptor::alloc()->init();
	desc->vertexBuffers()->object(MetalArgumentBuffer::BindingIndex)->setMutability(MTL::MutabilityImmutable);
	desc->fragmentBuffers()->object(MetalArgumentBuffer::BindingIndex)->setMutability(MTL::MutabilityImmutable);

    // Vertex descriptor
    if (!fetchShader->mtlFetchVertexManually && !vertexShader->hasStreamoutBufferWrite)
    {
    	NS_STACK_SCOPED MTL::VertexDescriptor* vertexDescriptor = MTL::VertexDescriptor::alloc()->init();
    	for (auto& bufferGroup : fetchShader->bufferGroups)
    	{
    		std::optional<LatteConst::VertexFetchType2> fetchType;

    		uint32 minBufferStride = 0;
    		for (sint32 j = 0; j < bufferGroup.attribCount; ++j)
    		{
    			auto& attr = bufferGroup.attrib[j];

    			uint32 semanticId = vertexShader->resourceMapping.attributeMapping[attr.semanticId];
    			if (semanticId == (uint32)-1)
    				continue; // attribute not used?

    			auto attribute = vertexDescriptor->attributes()->object(semanticId);
    			attribute->setOffset(attr.offset);
    			attribute->setBufferIndex(GET_MTL_VERTEX_BUFFER_INDEX(attr.attributeBufferIndex));
    			attribute->setFormat(GetMtlVertexFormat(attr.format));

    			minBufferStride = std::max(minBufferStride, attr.offset + GetMtlVertexFormatSize(attr.format));

    			if (fetchType.has_value())
    				cemu_assert_debug(fetchType == attr.fetchType);
    			else
    				fetchType = attr.fetchType;

    			if (attr.fetchType == LatteConst::INSTANCE_DATA)
    			{
    				cemu_assert_debug(attr.aluDivisor == 1); // other divisor not yet supported
    			}
    		}

    		uint32 bufferIndex = bufferGroup.attributeBufferIndex;
    		uint32 bufferBaseRegisterIndex = mmSQ_VTX_ATTRIBUTE_BLOCK_START + bufferIndex * 7;
    		uint32 bufferStride = (lcr.GetRawView()[bufferBaseRegisterIndex + 2] >> 11) & 0xFFFF;

    		auto layout = vertexDescriptor->layouts()->object(GET_MTL_VERTEX_BUFFER_INDEX(bufferIndex));
    		if (bufferStride == 0)
    		{
    		    // Buffer stride cannot be zero, let's use the minimum stride
    			bufferStride = minBufferStride;

    			// Additionally, constant vertex function must be used
    			layout->setStepFunction(MTL::VertexStepFunctionConstant);
    			layout->setStepRate(0);
    		}
    		else
    		{
      		if (!fetchType.has_value() || fetchType == LatteConst::VertexFetchType2::VERTEX_DATA)
     			layout->setStepFunction(MTL::VertexStepFunctionPerVertex);
      		else if (fetchType == LatteConst::VertexFetchType2::INSTANCE_DATA)
     			layout->setStepFunction(MTL::VertexStepFunctionPerInstance);
      		else
      		{
      		    cemuLog_log(LogType::Force, "unimplemented vertex fetch type {}", (uint32)fetchType.value());
     			cemu_assert(false);
      		}
    		}
    		bufferStride = Align(bufferStride, 4);
    		layout->setStride(bufferStride);
    	}

    	desc->setVertexDescriptor(vertexDescriptor);
    }

	SetFragmentState(desc, lastUsedAttachmentsInfo, activeAttachmentsInfo, m_rasterizationEnabled, m_mtlr->SupportsFramebufferFetch(), lcr, pixelShader);

	m_pipelineDescriptor = desc;
}

void MetalPipelineCompiler::InitFromStateGeometryEmulation(const MetalAttachmentsInfo& lastUsedAttachmentsInfo, const MetalAttachmentsInfo& activeAttachmentsInfo, const LatteContextRegister& lcr, const LatteDecompilerShader* pixelShader)
{
	// An ordinary render pipeline with no vertex descriptor: the passthrough vertex function takes no stage_in, it indexes the buffer
	// the geometry kernel filled by its own vertex_id
	MTL::RenderPipelineDescriptor* desc = MTL::RenderPipelineDescriptor::alloc()->init();
	desc->fragmentBuffers()->object(MetalArgumentBuffer::BindingIndex)->setMutability(MTL::MutabilityImmutable);

	SetFragmentState(desc, lastUsedAttachmentsInfo, activeAttachmentsInfo, m_rasterizationEnabled, m_mtlr->SupportsFramebufferFetch(), lcr, pixelShader);

	m_pipelineDescriptor = desc;
}

void MetalPipelineCompiler::InitFromStateMesh(const LatteFetchShader* fetchShader, const LatteDecompilerShader* pixelShader, const MetalAttachmentsInfo& lastUsedAttachmentsInfo, const MetalAttachmentsInfo& activeAttachmentsInfo, const LatteContextRegister& lcr)
{
	// Render pipeline state
	MTL::MeshRenderPipelineDescriptor* desc = MTL::MeshRenderPipelineDescriptor::alloc()->init();
	desc->objectBuffers()->object(MetalArgumentBuffer::BindingIndex)->setMutability(MTL::MutabilityImmutable);
	desc->meshBuffers()->object(MetalArgumentBuffer::BindingIndex)->setMutability(MTL::MutabilityImmutable);
	desc->fragmentBuffers()->object(MetalArgumentBuffer::BindingIndex)->setMutability(MTL::MutabilityImmutable);

	SetFragmentState(desc, lastUsedAttachmentsInfo, activeAttachmentsInfo, m_rasterizationEnabled, m_mtlr->SupportsFramebufferFetch(), lcr, pixelShader);

	m_pipelineDescriptor = desc;
}
