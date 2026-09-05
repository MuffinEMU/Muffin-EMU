#pragma once

#include "Common/precompiled.h"
#include "Cafe/HW/Latte/Renderer/Metal/MetalRenderer.h"
#include "Cafe/HW/Latte/Core/LatteShader.h"

namespace LatteDecompiler
{
	static void _emitUniformVariables(LatteDecompilerShaderContext* decompilerContext, bool usesGeometryShader)
	{
	    auto src = decompilerContext->shaderSource;

		auto& uniformOffsets = decompilerContext->output->uniformOffsetsVK;

		src->add("struct SupportBuffer {" _CRLF);

		uint32 uniformCurrentOffset = 0;
		auto shader = decompilerContext->shader;
		auto shaderType = decompilerContext->shader->shaderType;
		if (decompilerContext->shader->uniformMode == LATTE_DECOMPILER_UNIFORM_MODE_REMAPPED)
		{
			// uniform registers or buffers are accessed statically with predictable offsets
			// this allows us to remap the used entries into a more compact array
			src->addFmt("int4 remapped[{}];" _CRLF, (sint32)shader->list_remappedUniformEntries.size());
			uniformOffsets.offset_remapped = uniformCurrentOffset;
			uniformCurrentOffset += 16 * shader->list_remappedUniformEntries.size();
		}
		else if (decompilerContext->shader->uniformMode == LATTE_DECOMPILER_UNIFORM_MODE_FULL_CFILE)
		{
			uint32 cfileSize = decompilerContext->analyzer.uniformRegisterAccessTracker.DetermineSize(decompilerContext->shaderBaseHash, 256);
			// full or partial uniform register file has to be present
			src->addFmt("int4 uniformRegister[{}];" _CRLF, cfileSize);
			uniformOffsets.offset_uniformRegister = uniformCurrentOffset;
			uniformOffsets.count_uniformRegister = cfileSize;
			uniformCurrentOffset += 16 * cfileSize;
		}
		// special uniforms
		bool hasAnyViewportScaleDisabled =
			!decompilerContext->contextRegistersNew->PA_CL_VTE_CNTL.get_VPORT_X_SCALE_ENA() ||
			!decompilerContext->contextRegistersNew->PA_CL_VTE_CNTL.get_VPORT_Y_SCALE_ENA() ||
			!decompilerContext->contextRegistersNew->PA_CL_VTE_CNTL.get_VPORT_Z_SCALE_ENA();

		if (decompilerContext->shaderType == LatteConst::ShaderType::Vertex && hasAnyViewportScaleDisabled)
		{
			// aka GX2 special state 0
			uniformCurrentOffset = (uniformCurrentOffset + 7)&~7;
			src->add("float2 windowSpaceToClipSpaceTransform;" _CRLF);
			uniformOffsets.offset_windowSpaceToClipSpaceTransform = uniformCurrentOffset;
			uniformCurrentOffset += 8;
		}
		bool alphaTestEnable = decompilerContext->contextRegistersNew->SX_ALPHA_TEST_CONTROL.get_ALPHA_TEST_ENABLE();
		if (decompilerContext->shaderType == LatteConst::ShaderType::Pixel && alphaTestEnable)
		{
			uniformCurrentOffset = (uniformCurrentOffset + 3)&~3;
			src->add("float alphaTestRef;" _CRLF);
			uniformOffsets.offset_alphaTestRef = uniformCurrentOffset;
			uniformCurrentOffset += 4;
		}
		if (decompilerContext->analyzer.outputPointSize && decompilerContext->analyzer.writesPointSize == false)
		{
			if ((decompilerContext->shaderType == LatteConst::ShaderType::Vertex && !decompilerContext->options->usesGeometryShader) ||
				decompilerContext->shaderType == LatteConst::ShaderType::Geometry)
			{
				uniformCurrentOffset = (uniformCurrentOffset + 3)&~3;
				src->add("float pointSize;" _CRLF);
				uniformOffsets.offset_pointSize = uniformCurrentOffset;
				uniformCurrentOffset += 4;
			}
		}
		// define fragCoordScale which holds the xy scale for render target resolution vs effective resolution
		if (shader->shaderType == LatteConst::ShaderType::Pixel)
		{
			uniformCurrentOffset = (uniformCurrentOffset + 7)&~7;
			src->add("float2 fragCoordScale;" _CRLF);
			uniformOffsets.offset_fragCoordScale = uniformCurrentOffset;
			uniformCurrentOffset += 8;
		}
		// provide scale factor for every texture that is accessed via texel coordinates (texelFetch)
		for (sint32 t = 0; t < LATTE_NUM_MAX_TEX_UNITS; t++)
		{
			if (decompilerContext->analyzer.texUnitUsesTexelCoordinates.test(t) == false)
				continue;
			uniformCurrentOffset = (uniformCurrentOffset + 7) & ~7;
			src->addFmt("float2 tex{}Scale;" _CRLF, t);
			uniformOffsets.offset_texScale[t] = uniformCurrentOffset;
			uniformCurrentOffset += 8;
		}
		// define verticesPerInstance + streamoutBufferBaseX
		if ((shader->shaderType == LatteConst::ShaderType::Vertex &&
		    usesGeometryShader) ||
	        (decompilerContext->analyzer.useSSBOForStreamout &&
			(shader->shaderType == LatteConst::ShaderType::Vertex && !decompilerContext->options->usesGeometryShader) ||
			(shader->shaderType == LatteConst::ShaderType::Geometry)))
		{
			src->add("int verticesPerInstance;" _CRLF);
			uniformOffsets.offset_verticesPerInstance = uniformCurrentOffset;
			uniformCurrentOffset += 4;
			for (uint32 i = 0; i < LATTE_NUM_STREAMOUT_BUFFER; i++)
			{
				if (decompilerContext->output->streamoutBufferWriteMask[i])
				{
					src->addFmt("int streamoutBufferBase{};" _CRLF, i);
					uniformOffsets.offset_streamoutBufferBase[i] = uniformCurrentOffset;
					uniformCurrentOffset += 4;
				}
			}
		}

		src->add("};" _CRLF _CRLF);

		uniformOffsets.offset_endOfBlock = uniformCurrentOffset;
	}

	static void _emitUniformBuffers(LatteDecompilerShaderContext* decompilerContext)
	{
		auto shaderSrc = decompilerContext->shaderSource;
		// uniform buffer definition
		if (decompilerContext->shader->uniformMode == LATTE_DECOMPILER_UNIFORM_MODE_FULL_CBANK)
		{
			for (uint32 i = 0; i < LATTE_NUM_MAX_UNIFORM_BUFFERS; i++)
			{
				if (!decompilerContext->analyzer.uniformBufferAccessTracker[i].HasAccess())
					continue;

				cemu_assert_debug(decompilerContext->output->resourceMappingMTL.uniformBuffersBindingPoint[i] >= 0);

				shaderSrc->addFmt("struct UBuff{} {{" _CRLF, i);
				shaderSrc->addFmt("float4 d[{}];" _CRLF, decompilerContext->analyzer.uniformBufferAccessTracker[i].DetermineSize(decompilerContext->shaderBaseHash, LATTE_GLSL_DYNAMIC_UNIFORM_BLOCK_SIZE));
				shaderSrc->add("};" _CRLF _CRLF);
			}
		}
		else if (decompilerContext->shader->uniformMode == LATTE_DECOMPILER_UNIFORM_MODE_REMAPPED)
		{
			// already generated in _emitUniformVariables
		}
		else if (decompilerContext->shader->uniformMode == LATTE_DECOMPILER_UNIFORM_MODE_FULL_CFILE)
		{
			// already generated in _emitUniformVariables
		}
		else if (decompilerContext->shader->uniformMode == LATTE_DECOMPILER_UNIFORM_MODE_NONE)
		{
			// no uniforms used
		}
		else
		{
			cemu_assert_debug(false);
		}
	}

	static void _emitAttributes(LatteDecompilerShaderContext* decompilerContext, bool fetchVertexManually)
	{
		auto src = decompilerContext->shaderSource;
		std::string attributeNames;

		if (decompilerContext->shader->shaderType == LatteConst::ShaderType::Vertex)
		{
		    src->add("struct VertexIn {" _CRLF);
			// attribute inputs
			for (uint32 i = 0; i < LATTE_NUM_MAX_ATTRIBUTE_LOCATIONS; i++)
			{
				if (decompilerContext->analyzer.inputAttributSemanticMask[i])
				{
					cemu_assert_debug(decompilerContext->output->resourceMappingMTL.attributeMapping[i] >= 0);

					src->addFmt("uint4 attrDataSem{}", i);
					if (fetchVertexManually)
					    attributeNames += "#define ATTRIBUTE_NAME" + std::to_string((sint32)decompilerContext->output->resourceMappingMTL.attributeMapping[i]) + " attrDataSem" + std::to_string(i) + "\n";
					else
					    src->addFmt(" [[attribute({})]]", (sint32)decompilerContext->output->resourceMappingMTL.attributeMapping[i]);
					src->add(";" _CRLF);
				}
			}
			src->add("};" _CRLF _CRLF);
		}
		src->addFmt("{}", attributeNames);
	}

	static void _emitVSOutputs(LatteDecompilerShaderContext* shaderContext, bool isRectVertexShader)
	{
		auto* src = shaderContext->shaderSource;

		src->add("struct VertexOut {" _CRLF);
		src->add("float4 position [[position]] [[invariant]];" _CRLF);
		if (shaderContext->analyzer.outputPointSize)
		    src->add("float pointSize [[point_size]];" _CRLF);

		LatteShaderPSInputTable* psInputTable = LatteSHRC_GetPSInputTable();
		auto parameterMask = shaderContext->shader->outputParameterMask;
		bool psInputsWritten[GPU7_PS_MAX_INPUTS] = {false};
		for (uint32 i = 0; i < 32; i++)
		{
			if ((parameterMask&(1 << i)) == 0)
				continue;
			uint32 vsSemanticId = _getVertexShaderOutParamSemanticId(shaderContext->contextRegisters, i);
			if (vsSemanticId > LATTE_ANALYZER_IMPORT_INDEX_PARAM_MAX)
				continue;
			// get import based on semanticId
			sint32 psInputIndex = -1;
			for (sint32 f = 0; f < psInputTable->count; f++)
			{
				if (psInputTable->import[f].semanticId == vsSemanticId)
				{
					psInputIndex = f;
					break;
				}
			}
			if (psInputIndex == -1)
				continue; // no ps input

			psInputsWritten[psInputIndex] = true;

			src->addFmt("float4 passParameterSem{}", psInputTable->import[psInputIndex].semanticId);
			if (!isRectVertexShader)
			{
     			src->addFmt(" [[user(locn{})]]", psInputIndex);
     			if (psInputTable->import[psInputIndex].isFlat)
    				src->add(" [[flat]]");
     			if (psInputTable->import[psInputIndex].isNoPerspective)
    				src->add(" [[center_no_perspective]]");
			}
			src->addFmt(";" _CRLF);
		}

		// TODO: handle this in the fragment shader instead?
		// Declare all PS inputs that are not written by the VS
		for (uint32 i = 0; i < psInputTable->count; i++)
		{
		    if (psInputsWritten[i])
				continue;

			if (psInputTable->import[i].semanticId > LATTE_ANALYZER_IMPORT_INDEX_PARAM_MAX)
				continue;

			src->addFmt("float4 unknown{} [[user(locn{})]];" _CRLF, psInputTable->import[i].semanticId, i);
		}

		src->add("};" _CRLF _CRLF);

		if (isRectVertexShader)
		{
		    src->add("struct ObjectPayload {" _CRLF);
            src->add("VertexOut vertexOut[VERTICES_PER_VERTEX_PRIMITIVE];" _CRLF);
            src->add("};" _CRLF _CRLF);
		}
	}

	static void _emitPSInputs(LatteDecompilerShaderContext* shaderContext)
	{
		auto* src = shaderContext->shaderSource;

		src->add("#define GET_FRAGCOORD() float4(in.position.xy * supportBuffer.fragCoordScale.xy, in.position.z, 1.0 / in.position.w)" _CRLF);

		src->add("struct FragmentIn {" _CRLF);
		src->add("float4 position [[position]];" _CRLF);

		LatteShaderPSInputTable* psInputTable = LatteSHRC_GetPSInputTable();
		for (sint32 i = 0; i < psInputTable->count; i++)
		{
			if (psInputTable->import[i].semanticId > LATTE_ANALYZER_IMPORT_INDEX_PARAM_MAX)
				continue;
			src->addFmt("float4 passParameterSem{}", psInputTable->import[i].semanticId);
			src->addFmt(" [[user(locn{})]]", i);
			if (psInputTable->import[i].isFlat)
				src->add(" [[flat]]");
			if (psInputTable->import[i].isNoPerspective)
				src->add(" [[center_no_perspective]]");
			src->add(";" _CRLF);
		}

		src->add("};" _CRLF _CRLF);
	}

	static void _emitInputsAndOutputs(LatteDecompilerShaderContext* decompilerContext, bool isRectVertexShader, bool usesGeometryShader, bool fetchVertexManually)
	{
		auto src = decompilerContext->shaderSource;

		if (decompilerContext->shaderType == LatteConst::ShaderType::Vertex)
		{
		    _emitAttributes(decompilerContext, fetchVertexManually);
		}
		else if (decompilerContext->shaderType == LatteConst::ShaderType::Pixel)
		{
		    _emitPSInputs(decompilerContext);

			src->add("struct FragmentOut {" _CRLF);

            // generate pixel outputs for pixel shader
            for (uint32 i = 0; i < LATTE_NUM_COLOR_TARGET; i++)
            {
               	if ((decompilerContext->shader->pixelColorOutputMask & (1 << i)) != 0)
               	{
                    auto dataType = GetColorBufferDataType(i, *decompilerContext->contextRegistersNew);
                    if (dataType != MetalDataType::NONE)
                    {
              		    src->addFmt("{} passPixelColor{} [[color({})]];" _CRLF, GetDataTypeStr(dataType), i, i);
                    }
               	}
            }

            // generate depth output for pixel shader
            if (decompilerContext->shader->depthMask)
                src->add("float passDepth [[depth(any)]];" _CRLF);

            src->add("};" _CRLF _CRLF);
		}

		if (!usesGeometryShader || isRectVertexShader)
		{
    		if (decompilerContext->shaderType == LatteConst::ShaderType::Vertex && decompilerContext->contextRegistersNew->IsRasterizationEnabled())
    			_emitVSOutputs(decompilerContext, isRectVertexShader);
		}
		else
		{
            if (decompilerContext->shaderType == LatteConst::ShaderType::Vertex || decompilerContext->shaderType == LatteConst::ShaderType::Geometry)
    		{
                src->add("struct VertexOut {" _CRLF);
    			uint32 ringParameterCountVS2GS = 0;
    			if (decompilerContext->shaderType == LatteConst::ShaderType::Vertex)
    			{
    				ringParameterCountVS2GS = decompilerContext->shader->ringParameterCount;
    			}
    			else
    			{
    				ringParameterCountVS2GS = decompilerContext->shader->ringParameterCountFromPrevStage;
    			}
    			for (uint32 f = 0; f < ringParameterCountVS2GS; f++)
    				src->addFmt("int4 passParameterSem{};" _CRLF, f);
    			src->add("};" _CRLF _CRLF);
                if (decompilerContext->options->geometryShaderEmulation)
                {
                    // Metal lays this out by the ordinary C++ rules: VertexOut is int4s so
                    // it is 16-aligned, and the trailing uint rounds the whole payload up
                    // to the next multiple of 16.
                    LattePrimitiveMode payloadPrimType = decompilerContext->contextRegistersNew->VGT_PRIMITIVE_TYPE.get_PRIMITIVE_MODE();
                    uint32 verticesPerVertexPrimitive = GetVerticesPerPrimitive(payloadPrimType);
                    uint32 vertexOutSize = ringParameterCountVS2GS * 16u;
                    decompilerContext->shader->mtlGsPayloadStride = verticesPerVertexPrimitive * vertexOutSize + 16u;
                }
                src->add("struct ObjectPayload {" _CRLF);
                src->add("VertexOut vertexOut[VERTICES_PER_VERTEX_PRIMITIVE];" _CRLF);
                // The geometry stage's streamout writes are indexed by which primitive is
                // being processed. GLSL hands a geometry shader gl_PrimitiveIDIn for that;
                // Metal has no equivalent in a mesh shader, and the mesh stage cannot work
                // it out for itself because it is spawned with a grid of exactly 1, so its
                // own threadgroup position is always zero. The object stage IS dispatched
                // one threadgroup per primitive, so it knows the number - this is how it
                // crosses the boundary.
                src->add("uint primitiveId;" _CRLF);
                src->add("};" _CRLF _CRLF);
    		}
    		if (decompilerContext->shaderType == LatteConst::ShaderType::Geometry)
    		{
    			// parameters shared between geometry and pixel shader
    			uint32 ringItemSize = decompilerContext->contextRegisters[mmSQ_GSVS_RING_ITEMSIZE] & 0x7FFF;
    			if ((ringItemSize & 0xF) != 0)
    				debugBreakpoint();
    			if (((decompilerContext->contextRegisters[mmSQ_GSVS_RING_ITEMSIZE] & 0x7FFF) & 0xF) != 0)
    				debugBreakpoint();

                // Two structs when emulating, one when not. A struct carrying [[position]]
                // and [[user(...)]] describes a rasterizer interface, and MSL does not
                // accept it as the element type of a device buffer -- but a device buffer
                // is exactly where the emulated geometry stage has to put its output. So
                // the attribute-free GeometryOut is what gets stored, and the attributed
                // GeometryOutRaster below is only ever a vertex function's return type.
                // Same fields in the same order, so the stride computed here describes
                // both.
                const bool gsEmulation = decompilerContext->options->geometryShaderEmulation;
                src->add("struct GeometryOut {" _CRLF);
                // Two forms. MSL will not accept a struct carrying [[position]] as the
                // element type of a device buffer, and the emulated geometry stage has to
                // store its output in exactly that - so when emulating, this is the plain
                // storable struct and GeometryOutRaster below carries the attributes.
                if (gsEmulation)
                    src->add("float4 position;" _CRLF);
                else
                    src->add("float4 position [[position]];" _CRLF);
                // pointSize is declared for the same reason VertexOut declares it. Without
                // it the emitter still writes out.pointSize for every emitted vertex (see
                // GPU7_CF_INST_EMIT_VERTEX and the point-size export in
                // LatteDecompilerEmitMSL.cpp, both guarded by this same flag), and Metal
                // rejects the whole shader with "no member named 'pointSize' in
                // 'GeometryOut'" - one error per emitted vertex. A device log showed
                // exactly four of those.
                if (decompilerContext->analyzer.outputPointSize)
                    src->add(gsEmulation ? "float pointSize;" _CRLF : "float pointSize [[point_size]];" _CRLF);
    			for (sint32 p = 0; p < decompilerContext->parsedGSCopyShader->numParam; p++)
    			{
    				if (decompilerContext->parsedGSCopyShader->paramMapping[p].exportType != 2)
    					continue;
                    if (gsEmulation)
        				src->addFmt("float4 passParameterSem{};" _CRLF, (sint32)decompilerContext->parsedGSCopyShader->paramMapping[p].exportParam);
                    else
        				src->addFmt("float4 passParameterSem{} [[user(locn{})]];" _CRLF, (sint32)decompilerContext->parsedGSCopyShader->paramMapping[p].exportParam, decompilerContext->parsedGSCopyShader->paramMapping[p].exportParam & 0x7F);
    			}
                src->add("};" _CRLF _CRLF);

                if (gsEmulation)
                {
                    uint32 exportedParamCount = 0;
                    src->add("struct GeometryOutRaster {" _CRLF);
                    src->add("float4 position [[position]];" _CRLF);
                    if (decompilerContext->analyzer.outputPointSize)
                        src->add("float pointSize [[point_size]];" _CRLF);
                    for (sint32 p = 0; p < decompilerContext->parsedGSCopyShader->numParam; p++)
                    {
                        if (decompilerContext->parsedGSCopyShader->paramMapping[p].exportType != 2)
                            continue;
                        exportedParamCount++;
                        src->addFmt("float4 passParameterSem{} [[user(locn{})]];" _CRLF, (sint32)decompilerContext->parsedGSCopyShader->paramMapping[p].exportParam, decompilerContext->parsedGSCopyShader->paramMapping[p].exportParam & 0x7F);
                    }
                    src->add("};" _CRLF _CRLF);

                    // float4 members force 16-byte alignment, so the lone float costs a
                    // full 16 and the total is already a multiple of it.
                    decompilerContext->shader->mtlGsVertexStride = 16u + (decompilerContext->analyzer.outputPointSize ? 16u : 0u) + exportedParamCount * 16u;

                    src->add("static GeometryOutRaster gsToRaster(GeometryOut o) {" _CRLF);
                    src->add("GeometryOutRaster r;" _CRLF);
                    src->add("r.position = o.position;" _CRLF);
                    if (decompilerContext->analyzer.outputPointSize)
                        src->add("r.pointSize = o.pointSize;" _CRLF);
                    for (sint32 p = 0; p < decompilerContext->parsedGSCopyShader->numParam; p++)
                    {
                        if (decompilerContext->parsedGSCopyShader->paramMapping[p].exportType != 2)
                            continue;
                        src->addFmt("r.passParameterSem{} = o.passParameterSem{};" _CRLF, (sint32)decompilerContext->parsedGSCopyShader->paramMapping[p].exportParam, (sint32)decompilerContext->parsedGSCopyShader->paramMapping[p].exportParam);
                    }
                    src->add("return r;" _CRLF);
                    src->add("}" _CRLF _CRLF);
                }

                const uint32 MAX_VERTEX_COUNT = 32;

                if (decompilerContext->options->geometryShaderEmulation)
                {
                    // No mesh pipeline exists to declare an output type for. The same bound
                    // instead sizes the device buffer each geometry invocation writes into,
                    // and it has to be a macro because the emitted body and the passthrough
                    // vertex shader below both index with it.
                    src->addFmt("#define GS_MAX_VERTICES {}" _CRLF, MAX_VERTEX_COUNT);
                    src->addFmt("#define MAX_PRIMS_PER_INVOCATION (GET_PRIMITIVE_COUNT(GS_MAX_VERTICES))" _CRLF);
                }
                else
                {
                    // Define the mesh shader output type
                    src->addFmt("using MeshType = mesh<GeometryOut, void, {}, GET_PRIMITIVE_COUNT({}), topology::MTL_PRIMITIVE_TYPE>;" _CRLF, MAX_VERTEX_COUNT, MAX_VERTEX_COUNT);
                }
    		}
		}
	}

	static void emitHeader(LatteDecompilerShaderContext* decompilerContext, bool isRectVertexShader, bool usesGeometryShader, bool fetchVertexManually)
	{
	    auto src = decompilerContext->shaderSource;

        if (usesGeometryShader && (decompilerContext->shaderType == LatteConst::ShaderType::Vertex || decompilerContext->shaderType == LatteConst::ShaderType::Geometry))
        {
            LattePrimitiveMode vsOutPrimType = decompilerContext->contextRegistersNew->VGT_PRIMITIVE_TYPE.get_PRIMITIVE_MODE();
            src->addFmt("#define VERTICES_PER_VERTEX_PRIMITIVE {}" _CRLF, GetVerticesPerPrimitive(vsOutPrimType));

            uint32 gsOutPrimType = decompilerContext->contextRegisters[mmVGT_GS_OUT_PRIM_TYPE];
            if (decompilerContext->shaderType == LatteConst::ShaderType::Geometry)
            {
                switch (gsOutPrimType)
                {
                case 0: // Point
                    src->add("#define MTL_PRIMITIVE_TYPE point" _CRLF);
                   	src->add("#define GET_PRIMITIVE_COUNT(vertexCount) (vertexCount / 1)" _CRLF);
                    break;
                case 1: // Line strip
                    src->add("#define MTL_PRIMITIVE_TYPE line" _CRLF);
                   	src->add("#define GET_PRIMITIVE_COUNT(vertexCount) (vertexCount - 1)" _CRLF);
                    break;
                case 2: // Triangle strip
                    src->add("#define MTL_PRIMITIVE_TYPE triangle" _CRLF);
                   	src->add("#define GET_PRIMITIVE_COUNT(vertexCount) (vertexCount - 2)" _CRLF);
                    break;
                default:
                    cemuLog_log(LogType::Force, "Unknown geometry out primitive type {}", gsOutPrimType);
                    break;
                }
                if (decompilerContext->options->geometryShaderEmulation)
                {
                    // The mesh path turns the emitted strip into a list with set_index();
                    // with no mesh stage the passthrough vertex shader has to do the same
                    // mapping itself, so it needs the list's vertices-per-primitive.
                    uint32 verticesPerOutPrimitive = (gsOutPrimType == 0) ? 1 : ((gsOutPrimType == 1) ? 2 : 3);
                    src->addFmt("#define VERTICES_PER_OUT_PRIMITIVE {}" _CRLF, verticesPerOutPrimitive);
                }
            }
        }

        if (decompilerContext->contextRegistersNew->PA_CL_CLIP_CNTL.get_DX_CLIP_SPACE_DEF())
			src->add("#define SET_POSITION(_v) out.position = _v" _CRLF);
		else
			src->add("#define SET_POSITION(_v) out.position = _v; out.position.z = (out.position.z + out.position.w) / 2.0" _CRLF);

		const bool dump_shaders_enabled = ActiveSettings::DumpShadersEnabled();
		if(dump_shaders_enabled)
			decompilerContext->shaderSource->add("// start of shader inputs/outputs, predetermined by Cemu. Do not touch" _CRLF);
		// uniform variables
		_emitUniformVariables(decompilerContext, usesGeometryShader);
		// uniform buffers
		_emitUniformBuffers(decompilerContext);
		// inputs and outputs
		_emitInputsAndOutputs(decompilerContext, isRectVertexShader, usesGeometryShader, fetchVertexManually);

		if (dump_shaders_enabled)
			decompilerContext->shaderSource->add("// end of shader inputs/outputs" _CRLF);
	}

	static void _emitUniformBufferDefinitions(LatteDecompilerShaderContext* decompilerContext)
	{
		auto src = decompilerContext->shaderSource;
		// uniform buffer definition
		if (decompilerContext->shader->uniformMode == LATTE_DECOMPILER_UNIFORM_MODE_FULL_CBANK)
		{
			for (uint32 i = 0; i < LATTE_NUM_MAX_UNIFORM_BUFFERS; i++)
			{
				if (!decompilerContext->analyzer.uniformBufferAccessTracker[i].HasAccess())
					continue;

				cemu_assert_debug(decompilerContext->output->resourceMappingMTL.uniformBuffersBindingPoint[i] >= 0);

				src->addFmt(", constant UBuff{}& ubuff{} [[buffer({})]]", i, i, (sint32)decompilerContext->output->resourceMappingMTL.uniformBuffersBindingPoint[i]);
			}
		}
	}

	static void _emitTextureDefinitions(LatteDecompilerShaderContext* shaderContext)
	{
	    bool renderTargetIndexUsed[LATTE_NUM_COLOR_TARGET] = {false};

		auto src = shaderContext->shaderSource;
		// texture sampler definition
		for (sint32 i = 0; i < LATTE_NUM_MAX_TEX_UNITS; i++)
		{
			if (!shaderContext->output->textureUnitMask[i])
				continue;

			uint8 renderTargetIndex = shaderContext->shader->textureRenderTargetIndex[i];
			if (static_cast<MetalRenderer*>(g_renderer.get())->SupportsFramebufferFetch() && renderTargetIndex != 255)
			{
                if (!renderTargetIndexUsed[renderTargetIndex])
				{
			        src->addFmt(", {} col{} [[color({})]]", GetDataTypeStr(GetColorBufferDataType(renderTargetIndex, *shaderContext->contextRegistersNew)), renderTargetIndex, renderTargetIndex);
					renderTargetIndexUsed[renderTargetIndex] = true;
				}
			}
			else
			{
                src->add(", ");

    			// Only certain texture dimensions can be used with comparison samplers
    			if (shaderContext->shader->textureUsesDepthCompare[i] && IsValidDepthTextureType(shaderContext->shader->textureUnitDim[i]))
    			    src->add("depth");
    			else
                    src->add("texture");

    			if (shaderContext->shader->textureIsIntegerFormat[i])
    			{
    				// integer samplers
    				if (shaderContext->shader->textureUnitDim[i] == Latte::E_DIM::DIM_1D)
    					src->add("1d<uint>");
    				else if (shaderContext->shader->textureUnitDim[i] == Latte::E_DIM::DIM_2D || shaderContext->shader->textureUnitDim[i] == Latte::E_DIM::DIM_2D_MSAA)
    					src->add("2d<uint>");
    				else
    					cemu_assert_unimplemented();
    			}
    			else if (shaderContext->shader->textureUnitDim[i] == Latte::E_DIM::DIM_2D || shaderContext->shader->textureUnitDim[i] == Latte::E_DIM::DIM_2D_MSAA)
    				src->add("2d<float>");
    			else if (shaderContext->shader->textureUnitDim[i] == Latte::E_DIM::DIM_1D)
    				src->add("1d<float>");
    			else if (shaderContext->shader->textureUnitDim[i] == Latte::E_DIM::DIM_2D_ARRAY)
    				src->add("2d_array<float>");
    			else if (shaderContext->shader->textureUnitDim[i] == Latte::E_DIM::DIM_CUBEMAP)
    				src->add("cube_array<float>");
    			else if (shaderContext->shader->textureUnitDim[i] == Latte::E_DIM::DIM_3D)
    				src->add("3d<float>");
    			else
    			{
    				cemu_assert_unimplemented();
    			}

    			uint32 binding = shaderContext->output->resourceMappingMTL.textureUnitToBindingPoint[i];
    			//uint32 textureBinding = shaderContext->output->resourceMappingMTL.textureUnitToBindingPoint[i] % 31;
    			//uint32 samplerBinding = textureBinding % 16;
    			src->addFmt(" tex{} [[texture({})]]", i, binding);
    			src->addFmt(", sampler samplr{} [[sampler({})]]", i, binding);
			}
		}
	}

	static void emitInputs(LatteDecompilerShaderContext* decompilerContext, bool isRectVertexShader, bool usesGeometryShader, bool fetchVertexManually)
	{
	    auto src = decompilerContext->shaderSource;

		switch (decompilerContext->shaderType)
		{
		case LatteConst::ShaderType::Vertex:
		    if (usesGeometryShader && decompilerContext->options->geometryShaderEmulation)
			{
                // A compute kernel standing in for the object stage. The object stage was
                // dispatched one threadgroup per primitive with one thread per vertex of
                // that primitive; a flat thread id carries the same information, so tig and
                // tid are recovered from it in the body rather than supplied as builtins.
                src->add("uint gid [[thread_position_in_grid]]");
                src->addFmt(", device ObjectPayload* gsPayload [[buffer({})]]", decompilerContext->output->resourceMappingMTL.gsPayloadBinding);
                src->addFmt(", device uint* indexBuffer [[buffer({})]]", decompilerContext->output->resourceMappingMTL.indexBufferBinding);
                src->addFmt(", constant uchar& indexType [[buffer({})]]", decompilerContext->output->resourceMappingMTL.indexTypeBinding);
			}
		    else if (usesGeometryShader)
			{
                src->add("object_data ObjectPayload& objectPayload [[payload]]");
                src->add(", mesh_grid_properties meshGridProperties");
                src->add(", uint tig [[threadgroup_position_in_grid]]");
                src->add(", uint tid [[thread_index_in_threadgroup]]");
                // TODO: only include index buffer if needed
                src->addFmt(", device uint* indexBuffer [[buffer({})]]", decompilerContext->output->resourceMappingMTL.indexBufferBinding);
                // TODO: put into the support buffer?
                src->addFmt(", constant uchar& indexType [[buffer({})]]", decompilerContext->output->resourceMappingMTL.indexTypeBinding);
			}
			else
			{
			    // TODO: only include these if needed?
                src->add("uint vid [[vertex_id]]");
                src->add(", uint iid [[instance_id]]");
			}

            if (fetchVertexManually)
                src->add(" VERTEX_BUFFER_DEFINITIONS");
			else
				src->add(", VertexIn in [[stage_in]]");

            break;
        case LatteConst::ShaderType::Geometry:
            if (decompilerContext->options->geometryShaderEmulation)
            {
                // One thread per primitive, matching the mesh stage's one-threadgroup-per-
                // primitive dispatch. The payload is read out of a device buffer instead of
                // being handed over by the object stage.
                src->add("uint gid [[thread_position_in_grid]]");
                src->addFmt(", const device ObjectPayload* gsPayloadIn [[buffer({})]]", decompilerContext->output->resourceMappingMTL.gsPayloadBinding);
                src->addFmt(", device GeometryOut* gsOut [[buffer({})]]", decompilerContext->output->resourceMappingMTL.gsOutBinding);
                src->addFmt(", device uint* gsPrimCount [[buffer({})]]", decompilerContext->output->resourceMappingMTL.gsPrimCountBinding);
            }
            else
            {
                src->add("MeshType mesh");
                src->add(", const object_data ObjectPayload& objectPayload [[payload]]");
            }
            break;
        case LatteConst::ShaderType::Pixel:
            src->add("FragmentIn in [[stage_in]]");
            // TODO: only include these if needed?
            src->add(", float2 pointCoord [[point_coord]]");
            src->add(", bool frontFacing [[front_facing]]");
            break;
        default:
            break;
		}

		if (decompilerContext->output->resourceMappingMTL.uniformVarsBufferBindingPoint >= 0)
		    src->addFmt(", constant SupportBuffer& supportBuffer [[buffer({})]]", decompilerContext->output->resourceMappingMTL.uniformVarsBufferBindingPoint);

        // streamout buffer (transform feedback)
        if ((decompilerContext->shaderType == LatteConst::ShaderType::Vertex && !decompilerContext->options->usesGeometryShader) || decompilerContext->shaderType == LatteConst::ShaderType::Geometry)
        {
            if (decompilerContext->analyzer.hasStreamoutEnable && decompilerContext->analyzer.hasStreamoutWrite)
                src->addFmt(", device int* sb [[buffer({})]]" _CRLF, decompilerContext->output->resourceMappingMTL.tfStorageBindingPoint);
        }

		// uniform buffers
		_emitUniformBufferDefinitions(decompilerContext);
		// textures
		_emitTextureDefinitions(decompilerContext);
	}
}
