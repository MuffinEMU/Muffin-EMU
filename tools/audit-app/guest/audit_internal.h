// audit_internal.h - what the audit guest's source files share. See audit.c for the overview.
#pragma once

#include "audit_protocol.h"

#include <coreinit/debug.h>
#include <coreinit/time.h>
#include <gx2/clear.h>
#include <gx2/context.h>
#include <gx2/draw.h>
#include <gx2/enum.h>
#include <gx2/mem.h>
#include <gx2/registers.h>
#include <gx2/sampler.h>
#include <gx2/shaders.h>
#include <gx2/state.h>
#include <gx2/surface.h>
#include <gx2/swap.h>
#include <gx2/texture.h>
#include <gx2/utils.h>
#include <whb/gfx.h>

#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// ---------------------------------------------------------------------------------------------
// Test context and the test table

typedef struct Ctx
{
   char testId[AUDIT_NAME_LEN];
   char params[AUDIT_PARAMS_LEN];
   uint32_t token;
   uint32_t seed;
   uint32_t durationMs;
   uint32_t errors;    // error returns the guest noticed itself
   uint32_t checksum;  // digest of what the test did (scene count, frame counts), same on every correct core
   BOOL aborted;
} Ctx;

// Returns TRUE when the test ran to its end, FALSE when the host aborted it.
typedef BOOL (*TestFn)(Ctx *ctx);

typedef struct TestEntry
{
   const char *id;
   TestFn fn;
} TestEntry;

extern const TestEntry kRenderTests[];
extern const TestEntry kAvTests[];

// ---------------------------------------------------------------------------------------------
// Parameters ("key=value;key=value") and logging

int32_t ParamInt(const Ctx *ctx, const char *key, int32_t def);
BOOL ParamStr(const Ctx *ctx, const char *key, char *out, uint32_t outSize);

void LogPhase(Ctx *ctx, const char *name);
void LogNote(Ctx *ctx, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
// verdict is "pass", "fail" or "info"; a "fail" also counts as an error the test reports.
void LogSelf(Ctx *ctx, const char *verdict, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
void SetMessage(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
void Fold(Ctx *ctx, uint32_t value);

uint32_t Rand32(uint32_t *state);

// ---------------------------------------------------------------------------------------------
// Mailbox access for the tests that publish input and audio state

void MbSet(uint32_t offset, uint32_t value);
uint32_t MbGet(uint32_t offset);
uint32_t FramesPresented(void);

// ---------------------------------------------------------------------------------------------
// Frames. A scene is called once per presented frame with the frame number within the scene.

typedef void (*SceneFn)(Ctx *ctx, void *user, uint32_t frame);

// Presents one TV frame (and a GamePad frame) whose TV content is drawn by `scene`, background
// cleared to bg. Returns FALSE when the host aborted the test.
BOOL PresentFrame(Ctx *ctx, const float bg[4], SceneFn scene, void *user, uint32_t frame);

// Presents `minFrames` frames, then raises a checkpoint and keeps presenting the same scene until
// the host answers CONTINUE (or a timeout passes). FALSE when aborted.
BOOL HoldScene(Ctx *ctx, const char *checkpoint, uint32_t minFrames, const float bg[4], SceneFn scene, void *user);

// Background of the GamePad screen (default deep purple). Tests that check the pad use it.
void SetPadClear(float r, float g, float b, float a);

// TRUE once if a CONTINUE arrived since the last call (for tests that loop until the host is done).
BOOL ConsumeContinue(void);

// Polls the mailbox once; sets ctx->aborted on ABORT. Returns TRUE when CONTINUE arrived.
BOOL PollHost(Ctx *ctx);

// ---------------------------------------------------------------------------------------------
// Drawing in the TV's current render target. Coordinates are screen space: x to the right and y
// DOWN, both 0..1 across the target, z in 0..1. They are converted to clip space with y flipped
// (y = 0 is clip +1); the host measures which way the screen actually came out (test
// "orientation") and maps its expectations through that, so a flipped output is reported once,
// as a finding, instead of failing every test.

typedef struct BlendState
{
   BOOL enable;
   GX2BlendMode colorSrc;
   GX2BlendMode colorDst;
   GX2BlendCombineMode colorCombine;
   GX2BlendMode alphaSrc;
   GX2BlendMode alphaDst;
   GX2BlendCombineMode alphaCombine;
} BlendState;

void ApplyDefaultState(void);
void SetBlend(const BlendState *b);
void SetBlendStandard(void);
void SetBlendOff(void);
void SetDepth(BOOL test, BOOL write, GX2CompareFunction func);
void BindTexture(const GX2Texture *tex, BOOL linear);
void BindWhite(void);
void DrawRect(float x, float y, float w, float h, float z, float r, float g, float b, float a);
void DrawTexRect(float x, float y, float w, float h, float z, float r, float g, float b, float a);
void DrawTexRectUV(float x, float y, float w, float h, float z, float u0, float v0, float u1, float v1);

// ---------------------------------------------------------------------------------------------
// Textures and render targets

typedef struct Tex
{
   GX2Texture tex;
   void *image;
   void *mips;
} Tex;

// CPU-written texture, linear layout, one mip level. Returns FALSE on allocation failure.
BOOL TexCreate(Tex *t, GX2SurfaceFormat format, uint32_t width, uint32_t height);
void TexDestroy(Tex *t);
// Bytes per texel row and the number of texel rows to write, as the surface actually laid out.
uint32_t TexRowBytes(const Tex *t);
uint32_t TexRowCount(const Tex *t);
void TexUploaded(Tex *t);

typedef struct RT
{
   GX2ColorBuffer cb;
   GX2DepthBuffer db;
   void *image;
   void *mips;
   void *depthImage;
   uint32_t width;
   uint32_t height;
   BOOL hasDepth;
} RT;

// Color target with optional mip chain and an optional depth buffer of `depthFormat`
// (GX2_SURFACE_FORMAT_INVALID for none).
BOOL RTCreate(RT *rt, uint32_t width, uint32_t height, uint32_t mipLevels, GX2SurfaceFormat format,
              GX2SurfaceFormat depthFormat);
void RTDestroy(RT *rt);
// Binds mip `mip` of the target (and its depth buffer), sets viewport and scissor, clears it.
void RTBegin(RT *rt, uint32_t mip, const float clear[4]);
// Restores the TV's own color and depth buffers and the default state.
void RTEnd(RT *rt);
// A texture view of mip `mip` of the target, to sample it.
void RTAsTexture(RT *rt, GX2Texture *out, uint32_t mip);
