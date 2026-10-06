#pragma once

uint32 LatteShaderCache_getShaderCacheExtraVersion(uint64 titleId);
uint32 LatteShaderCache_getPipelineCacheExtraVersion(uint64 titleId);

// When the learned-shader file is loaded, shaders whose stored aux hash differs from the one this renderer computes
// are re-keyed (see LatteShaderCache.cpp). Pipeline cache entries name their shaders by the stored hash, so the
// pipeline loaders run each entry through this to get the hash the shader is registered under.
struct LatteShaderCachePipelineRekey
{
	uint64 fromName1, fromName2;
	uint64 toName1, toName2;
	std::vector<uint8> data; // the entry under the new name
};

// Replaces the stored shader aux hashes in a serialized pipeline entry (the layout the Vulkan and Metal pipeline
// caches share) with the current ones. If anything changed, the entry is patched in place and queued in rekeys
// so it can be rewritten under its new name once loading is over.
void LatteShaderCache_TranslatePipelineEntry(uint64 name1, uint64 name2, std::vector<uint8>& blob, std::vector<LatteShaderCachePipelineRekey>& rekeys);
// Writes the queued entries to the pipeline cache file in one batch, then empties the list.
void LatteShaderCache_ApplyPipelineRekeys(class FileCache* pipelineCache, std::vector<LatteShaderCachePipelineRekey>& rekeys);
