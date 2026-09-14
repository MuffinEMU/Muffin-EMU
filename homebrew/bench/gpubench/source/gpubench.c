// gpubench.rpx - a real GX2 renderer workload: a grid of textured,
// alpha-blended quads driven through a compiled vertex+pixel shader, drawn
// across several draw calls, every frame, for a fixed frame count. See
// ../../README.md for the marker protocol and the shader story (how
// scene.vs/scene.ps got turned into the GFD bytes baked into scene_gsh.h).
//
// Unlike cpubench.rpx this cannot avoid touching the GPU pipeline just to
// produce a marker - GX2SwapScanBuffers()/GX2Flush() at the end of a frame
// are the whole point of the test, so BEGIN/END wrap the entire per-frame
// loop rather than a single call.
//
// Scene setup (shader load, vertex buffer fill, texture generation) all
// happens before BEGIN. Nothing in the loop allocates.

#include "bench_marker.h" // copied in next to this file by CI, see the workflow

#include <coreinit/thread.h>
#include <coreinit/time.h>
#include <gx2/clear.h>
#include <gx2/draw.h>
#include <gx2/enum.h>
#include <gx2/mem.h>
#include <gx2/registers.h>
#include <gx2/sampler.h>
#include <gx2/shaders.h>
#include <gx2/surface.h>
#include <gx2/texture.h>
#include <gx2/utils.h>
#include <gx2r/buffer.h>
#include <gx2r/draw.h>
#include <whb/gfx.h>
#include <whb/proc.h>

#include <malloc.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
// Not every newlib math.h configuration defines this outside strict-ANSI
// mode, and this file has no way to test which devkitPPC's does.
#define M_PI 3.14159265358979323846
#endif

// The compiled shader binary. Generated at build time by the CI workflow
// from shaders/scene.vs and shaders/scene.ps via CafeGLSL's glslcompiler,
// then turned into this byte array - see the workflow and ../../README.md
// for exactly how and why. Declares:
//   static const unsigned char kSceneShaderGsh[];
//   static const unsigned int  kSceneShaderGshSize;
#include "scene_gsh.h"

// ---------------------------------------------------------------------------
// Tuning constants
// ---------------------------------------------------------------------------

#define GPUBENCH_FRAME_COUNT      (600u)
#define GPUBENCH_GRID_SIZE        (64u) // 64x64 quads = 4096 quads = 8192 triangles/frame
#define GPUBENCH_DRAW_BATCH_COUNT (4u)  // GPUBENCH_GRID_SIZE^2 must divide evenly by this
#define GPUBENCH_TEXTURE_SIZE     (64u) // procedural checkerboard, texels per side
#define GPUBENCH_TEXTURE_BLOCK    (8u)  // checker block size in texels
#define GPUBENCH_GRID_EXTENT      (4.0f)  // world-space size of the grid, one side
#define GPUBENCH_SPIN_TURNS       (1.0f)  // full model rotations over the whole run
#define GPUBENCH_FOV_RADIANS      (0.7853981634f) // 45 degrees
#define GPUBENCH_NEAR_Z           (0.1f)
#define GPUBENCH_FAR_Z            (100.0f)

// Fixed, NOT read from GX2GetSystemTVScanMode()/the live colour buffer size.
// The MVP built from this feeds the checksum, and two engines (or two real
// consoles) configured for different TV resolutions would otherwise produce
// different, but equally "correct", checksums - a false mismatch that has
// nothing to do with an emulation bug. Keeping every checksum input a
// compile-time constant is what makes the checksum comparable across engines
// at all.
#define GPUBENCH_ASPECT (16.0f / 9.0f)

#define GPUBENCH_TOTAL_QUADS ((uint32_t)(GPUBENCH_GRID_SIZE * GPUBENCH_GRID_SIZE))
#define GPUBENCH_TOTAL_VERTICES (GPUBENCH_TOTAL_QUADS * 6u)

// ---------------------------------------------------------------------------
// Minimal column-major 4x4 float matrix helpers (the layout a raw mat4
// uniform upload expects to match GLSL's column-major indexing). Kept local
// rather than shared with cpubench.c's matrix test - the wut sample Makefile
// this builds with only sees one flattened source/ directory per target, so
// there is nowhere to put a second .c file for it to also compile.
// ---------------------------------------------------------------------------

static void Mat4Identity(float m[16])
{
   memset(m, 0, sizeof(float) * 16);
   m[0] = m[5] = m[10] = m[15] = 1.0f;
}

static void Mat4Multiply(float out[16], const float a[16], const float b[16])
{
   float r[16];
   for (int c = 0; c < 4; c++) {
      for (int row = 0; row < 4; row++) {
         float sum = 0.0f;
         for (int k = 0; k < 4; k++) {
            sum += a[k * 4 + row] * b[c * 4 + k];
         }
         r[c * 4 + row] = sum;
      }
   }
   memcpy(out, r, sizeof(r));
}

static void Mat4Translate(float m[16], float x, float y, float z)
{
   Mat4Identity(m);
   m[12] = x;
   m[13] = y;
   m[14] = z;
}

static void Mat4RotateY(float m[16], float radians)
{
   Mat4Identity(m);
   float s = sinf(radians);
   float c = cosf(radians);
   m[0]    = c;
   m[2]    = -s;
   m[8]    = s;
   m[10]   = c;
}

static void Mat4Perspective(float m[16], float fovyRadians, float aspect, float nearZ, float farZ)
{
   float f = 1.0f / tanf(fovyRadians * 0.5f);
   memset(m, 0, sizeof(float) * 16);
   m[0]  = f / aspect;
   m[5]  = f;
   m[10] = (farZ + nearZ) / (nearZ - farZ);
   m[11] = -1.0f;
   m[14] = (2.0f * farZ * nearZ) / (nearZ - farZ);
}

// ---------------------------------------------------------------------------
// Scene data
// ---------------------------------------------------------------------------

typedef struct
{
   float pos[3];
   float color[4];
   float uv[2];
} SceneVertex;

// A flat grid of quads on the XZ plane, each a deterministic colour with a
// checkerboard alpha pattern so blending is actually exercised (a grid that
// was fully opaque would enable blending without ever visibly using it).
static void BuildSceneVertices(SceneVertex *out)
{
   float cell = GPUBENCH_GRID_EXTENT / (float)GPUBENCH_GRID_SIZE;
   float half = GPUBENCH_GRID_EXTENT * 0.5f;
   uint32_t vi = 0;

   for (uint32_t gz = 0; gz < GPUBENCH_GRID_SIZE; gz++) {
      for (uint32_t gx = 0; gx < GPUBENCH_GRID_SIZE; gx++) {
         float x0 = -half + (float)gx * cell;
         float x1 = x0 + cell;
         float z0 = -half + (float)gz * cell;
         float z1 = z0 + cell;

         float r = (float)gx / (float)(GPUBENCH_GRID_SIZE - 1u);
         float g = (float)gz / (float)(GPUBENCH_GRID_SIZE - 1u);
         float b = 1.0f - 0.5f * (r + g);
         float a = ((gx ^ gz) & 1u) ? 1.0f : 0.35f;

         SceneVertex quad[6] = {
            {{x0, 0.0f, z0}, {r, g, b, a}, {0.0f, 0.0f}},
            {{x1, 0.0f, z0}, {r, g, b, a}, {1.0f, 0.0f}},
            {{x1, 0.0f, z1}, {r, g, b, a}, {1.0f, 1.0f}},
            {{x0, 0.0f, z0}, {r, g, b, a}, {0.0f, 0.0f}},
            {{x1, 0.0f, z1}, {r, g, b, a}, {1.0f, 1.0f}},
            {{x0, 0.0f, z1}, {r, g, b, a}, {0.0f, 1.0f}},
         };
         memcpy(&out[vi], quad, sizeof(quad));
         vi += 6u;
      }
   }
}

// A small procedural checkerboard, generated on the CPU so the test needs no
// bundled image asset or decoder. GX2_TILE_MODE_LINEAR_ALIGNED keeps the
// layout a plain row-major array (respecting surface.pitch, which GX2 gives
// in texels), avoiding the tiled/swizzled addressing math a "real" texture
// upload would need.
static void BuildCheckerTexture(GX2Texture *tex)
{
   memset(tex, 0, sizeof(*tex));
   tex->surface.dim       = GX2_SURFACE_DIM_TEXTURE_2D;
   tex->surface.width     = GPUBENCH_TEXTURE_SIZE;
   tex->surface.height    = GPUBENCH_TEXTURE_SIZE;
   tex->surface.depth     = 1;
   tex->surface.mipLevels = 1;
   tex->surface.format    = GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8;
   tex->surface.aa        = GX2_AA_MODE1X;
   tex->surface.use       = GX2_SURFACE_USE_TEXTURE;
   tex->surface.tileMode  = GX2_TILE_MODE_LINEAR_ALIGNED;
   GX2CalcSurfaceSizeAndAlignment(&tex->surface);

   tex->surface.image = memalign(tex->surface.alignment, tex->surface.imageSize);

   uint8_t *pixels     = (uint8_t *)tex->surface.image;
   uint32_t pitch      = tex->surface.pitch;
   for (uint32_t y = 0; y < GPUBENCH_TEXTURE_SIZE; y++) {
      for (uint32_t x = 0; x < GPUBENCH_TEXTURE_SIZE; x++) {
         uint32_t light  = ((x / GPUBENCH_TEXTURE_BLOCK) ^ (y / GPUBENCH_TEXTURE_BLOCK)) & 1u;
         uint8_t v       = light ? 235u : 40u;
         uint32_t idx    = (y * pitch + x) * 4u;
         pixels[idx + 0] = v;
         pixels[idx + 1] = v;
         pixels[idx + 2] = light ? v : 90u; // faint blue tint on the dark squares
         pixels[idx + 3] = 255u;
      }
   }

   tex->viewFirstMip   = 0;
   tex->viewNumMips    = 1;
   tex->viewFirstSlice = 0;
   tex->viewNumSlices  = 1;
   tex->compMap        = GX2_COMP_MAP(GX2_SQ_SEL_R, GX2_SQ_SEL_G, GX2_SQ_SEL_B, GX2_SQ_SEL_A);
   GX2InitTextureRegs(tex);
   GX2Invalidate(GX2_INVALIDATE_MODE_CPU_TEXTURE, tex->surface.image, tex->surface.imageSize);
}

// A cheap FNV-ish byte fold, used once to bring the static vertex data into
// the checksum so a corrupted upload doesn't just look like a slow frame.
static uint32_t FoldBytes(uint32_t seed, const void *data, uint32_t size)
{
   const uint8_t *bytes = (const uint8_t *)data;
   uint32_t h           = seed;
   for (uint32_t i = 0; i < size; i++) {
      h = (h * 16777619u) ^ bytes[i];
   }
   return h;
}

static void DrawSceneOnce(const WHBGfxShaderGroup *group,
                          GX2RBuffer *vertexBuffer,
                          const GX2Texture *tex,
                          const GX2Sampler *sampler,
                          const float mvp[16])
{
   GX2SetFetchShader(&group->fetchShader);
   GX2SetVertexShader(group->vertexShader);
   GX2SetPixelShader(group->pixelShader);

   GX2SetVertexUniformBlock(0, sizeof(float) * 16, mvp);

   GX2SetPixelTexture(tex, 0);
   GX2SetPixelSampler(sampler, 0);

   GX2SetDepthOnlyControl(TRUE, TRUE, GX2_COMPARE_FUNC_LESS);
   GX2SetBlendControl(GX2_RENDER_TARGET_0,
                      GX2_BLEND_MODE_SRC_ALPHA, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD,
                      TRUE,
                      GX2_BLEND_MODE_SRC_ALPHA, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD);
   GX2SetColorControl(GX2_LOGIC_OP_COPY, 0x01, FALSE, TRUE);

   GX2RSetAttributeBuffer(vertexBuffer, 0, vertexBuffer->elemSize, 0);

   uint32_t verticesPerBatch = GPUBENCH_TOTAL_VERTICES / GPUBENCH_DRAW_BATCH_COUNT;
   for (uint32_t batch = 0; batch < GPUBENCH_DRAW_BATCH_COUNT; batch++) {
      GX2DrawEx(GX2_PRIMITIVE_MODE_TRIANGLES, verticesPerBatch, batch * verticesPerBatch, 1);
   }
}

int main(int argc, char **argv)
{
   (void)argc;
   (void)argv;

   WHBProcInit();
   WHBGfxInit();

   OSReport("gpubench.rpx: starting\n");

   // --- One-time setup, all before BEGIN -----------------------------------

   WHBGfxShaderGroup group = {0};
   if (!WHBGfxLoadGFDShaderGroup(&group, 0, kSceneShaderGsh)) {
      OSReport("gpubench.rpx: WHBGfxLoadGFDShaderGroup failed - bad/missing scene_gsh.h?\n");
      WHBGfxShutdown();
      WHBProcShutdown();
      return 1;
   }
   OSReport("gpubench.rpx: loaded embedded shader (%u bytes)\n", kSceneShaderGshSize);
   WHBGfxInitShaderAttribute(&group, "in_pos", 0, offsetof(SceneVertex, pos), GX2_ATTRIB_FORMAT_FLOAT_32_32_32);
   WHBGfxInitShaderAttribute(&group, "in_color", 0, offsetof(SceneVertex, color), GX2_ATTRIB_FORMAT_FLOAT_32_32_32_32);
   WHBGfxInitShaderAttribute(&group, "in_uv", 0, offsetof(SceneVertex, uv), GX2_ATTRIB_FORMAT_FLOAT_32_32);
   WHBGfxInitFetchShader(&group);

   // Uniform-block mode (not uniform-register mode) is what our shaders were
   // compiled for - see ../../README.md's CafeGLSL section for why this
   // matters on real hardware even though Cemu-family emulators don't care.
   GX2SetShaderMode(GX2_SHADER_MODE_UNIFORM_BLOCK);

   GX2RBuffer vertexBuffer = {0};
   vertexBuffer.flags      = GX2R_RESOURCE_BIND_VERTEX_BUFFER |
                        GX2R_RESOURCE_USAGE_CPU_READ |
                        GX2R_RESOURCE_USAGE_CPU_WRITE |
                        GX2R_RESOURCE_USAGE_GPU_READ;
   vertexBuffer.elemSize  = sizeof(SceneVertex);
   vertexBuffer.elemCount = GPUBENCH_TOTAL_VERTICES;
   GX2RCreateBuffer(&vertexBuffer);
   SceneVertex *vertices = (SceneVertex *)GX2RLockBufferEx(&vertexBuffer, 0);
   BuildSceneVertices(vertices);
   uint32_t setupChecksum = FoldBytes(2166136261u, vertices, sizeof(SceneVertex) * GPUBENCH_TOTAL_VERTICES);
   GX2RUnlockBufferEx(&vertexBuffer, 0);

   GX2Texture tex;
   BuildCheckerTexture(&tex);
   setupChecksum = FoldBytes(setupChecksum, tex.surface.image, tex.surface.imageSize);

   GX2Sampler sampler;
   GX2InitSampler(&sampler, GX2_TEX_CLAMP_MODE_WRAP, GX2_TEX_XY_FILTER_MODE_LINEAR);

   // --- Timed region --------------------------------------------------------

   MuffinBenchBegin("gx2_scene", GPUBENCH_FRAME_COUNT);

   uint32_t checksum = setupChecksum;

   for (uint32_t frame = 0; frame < GPUBENCH_FRAME_COUNT; frame++) {
      float angle = ((float)frame / (float)GPUBENCH_FRAME_COUNT) * 2.0f * (float)M_PI * GPUBENCH_SPIN_TURNS;

      float model[16], view[16], proj[16], modelView[16], mvp[16];
      Mat4RotateY(model, angle);
      Mat4Translate(view, 0.0f, -1.0f, -6.0f);
      Mat4Perspective(proj, GPUBENCH_FOV_RADIANS, GPUBENCH_ASPECT, GPUBENCH_NEAR_Z, GPUBENCH_FAR_Z);
      Mat4Multiply(modelView, view, model);
      Mat4Multiply(mvp, proj, modelView);

      checksum = FoldBytes(checksum, mvp, sizeof(mvp));

      WHBGfxBeginRender();

      WHBGfxBeginRenderTV();
      WHBGfxClearColor(0.06f, 0.06f, 0.10f, 1.0f);
      DrawSceneOnce(&group, &vertexBuffer, &tex, &sampler, mvp);
      WHBGfxFinishRenderTV();

      WHBGfxBeginRenderDRC();
      WHBGfxClearColor(0.06f, 0.06f, 0.10f, 1.0f);
      DrawSceneOnce(&group, &vertexBuffer, &tex, &sampler, mvp);
      WHBGfxFinishRenderDRC();

      WHBGfxFinishRender(); // GX2SwapScanBuffers + GX2Flush + GX2DrawDone
   }

   MuffinBenchEnd("gx2_scene", checksum);
   MuffinBenchDone();

   // --- Idle until the host closes us ---------------------------------------

   while (WHBProcIsRunning()) {
      OSSleepTicks(OSMillisecondsToTicks(100));
   }

   free(tex.surface.image);
   GX2RDestroyBufferEx(&vertexBuffer, 0);
   WHBGfxFreeShaderGroup(&group);
   WHBGfxShutdown();
   WHBProcShutdown();
   return 0;
}
