// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

#pragma once

// Finished BC to ASTC transcodes, kept on disk per title. A GPU without BC re-encodes every BC texture as
// ASTC when the game loads it, and a game that loads a whole level at once (a race start) spends seconds
// doing that. The same source blocks always give the same ASTC bytes, so the result is looked up by the
// source's content before encoding and written back after.

struct ASTCCacheKey
{
	uint64 hashA;
	uint64 hashB;
	uint32 width;
	uint32 height;
	uint32 kind; // which BC decoder and ASTC profile made it
};

// True when the encoded image was found and copied into outputData (exactly outputSize bytes).
bool LatteTextureASTCCache_Lookup(const ASTCCacheKey& key, uint8* outputData, size_t outputSize);
// Keeps an encoded image for next time. Silently skipped when the cache is full or cannot be written.
void LatteTextureASTCCache_Store(const ASTCCacheKey& key, const uint8* data, size_t size);
