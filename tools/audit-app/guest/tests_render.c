// tests_render.c - the rendering tests of the audit guest.
//
// Every scene is deterministic: what it draws, where and in what colour is fixed by the test id and
// its parameters, so the Audit app can state in the catalogue exactly what each region of the frame
// has to look like (tools/audit-app/Catalogue/*.json). Where a test draws through a path that has
// no obvious "right answer" (copies between surfaces of different sizes, say), the catalogue says
// what is asserted and what is only reported.

#include "audit_internal.h"

#include <gx2/event.h>

#include <malloc.h>
#include <stdio.h>

// ---------------------------------------------------------------------------------------------
// Shared bits

static const float kBgDark[4] = {0.06f, 0.06f, 0.06f, 1.0f};
static const float kBgGrey[4] = {0.20f, 0.20f, 0.20f, 1.0f};

// Four quadrant colours, top-left, top-right, bottom-left, bottom-right.
typedef struct Palette
{
   float c[4][3];
} Palette;

static const Palette kPal0 = {{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}, {1, 1, 0}}};
static const Palette kPal1 = {{{0, 1, 1}, {1, 0, 1}, {1, 1, 1}, {0.5f, 0.5f, 0.5f}}};
static const Palette kPal2 = {{{1, 0.5f, 0}, {0.5f, 0, 1}, {0.5f, 1, 0}, {1, 0.5f, 0.5f}}};

static void DrawQuadrants(float x, float y, float w, float h, float z, const Palette *p)
{
   DrawRect(x, y, w * 0.5f, h * 0.5f, z, p->c[0][0], p->c[0][1], p->c[0][2], 1.0f);
   DrawRect(x + w * 0.5f, y, w * 0.5f, h * 0.5f, z, p->c[1][0], p->c[1][1], p->c[1][2], 1.0f);
   DrawRect(x, y + h * 0.5f, w * 0.5f, h * 0.5f, z, p->c[2][0], p->c[2][1], p->c[2][2], 1.0f);
   DrawRect(x + w * 0.5f, y + h * 0.5f, w * 0.5f, h * 0.5f, z, p->c[3][0], p->c[3][1], p->c[3][2], 1.0f);
}

// Cell `i` of a cols x rows grid over the whole screen, with a margin so neighbours never touch.
static void Cell(uint32_t i, uint32_t cols, uint32_t rows, float *x, float *y, float *w, float *h)
{
   float cw = 1.0f / (float)cols;
   float ch = 1.0f / (float)rows;
   *x       = (float)(i % cols) * cw + cw * 0.08f;
   *y       = (float)(i / cols) * ch + ch * 0.08f;
   *w       = cw * 0.84f;
   *h       = ch * 0.84f;
}

// ---------------------------------------------------------------------------------------------
// handshake: proves the mailbox and the log channel work before anything else is trusted.

static BOOL TestHandshake(Ctx *ctx)
{
   SetMessage("handshake ok");
   LogNote(ctx, "handshake frames=%d", ParamInt(ctx, "frames", 10));
   int32_t frames = ParamInt(ctx, "frames", 10);
   for (int32_t i = 0; i < frames; i++) {
      if (!PresentFrame(ctx, kBgDark, NULL, NULL, (uint32_t)i)) {
         return FALSE;
      }
   }
   Fold(ctx, 0x4D41u);
   return TRUE;
}

// ---------------------------------------------------------------------------------------------
// orientation: which way the screen came out. Four different corner markers on both screens.

static void SceneOrientation(Ctx *ctx, void *user, uint32_t frame)
{
   (void)ctx;
   (void)user;
   (void)frame;
   DrawRect(0.85f, 0.05f, 0.10f, 0.10f, 0.5f, 1, 0, 0, 1);    // "top right":    red
   DrawRect(0.05f, 0.85f, 0.10f, 0.10f, 0.5f, 0, 1, 0, 1);    // "bottom left":  green
   DrawRect(0.05f, 0.05f, 0.10f, 0.10f, 0.5f, 0, 0, 1, 1);    // "top left":     blue
   DrawRect(0.85f, 0.85f, 0.10f, 0.10f, 0.5f, 1, 1, 1, 1);    // "bottom right": white
   DrawRect(0.40f, 0.40f, 0.20f, 0.20f, 0.5f, 0.5f, 0.5f, 0.5f, 1);
}

static BOOL TestOrientation(Ctx *ctx)
{
   LogPhase(ctx, "markers");
   return HoldScene(ctx, "markers", (uint32_t)ParamInt(ctx, "hold", 20), kBgDark, SceneOrientation, NULL);
}

// ---------------------------------------------------------------------------------------------
// clear_colours: the plainest thing a renderer does. A black frame here is the bug, unless the
// colour being cleared to is black.

static BOOL TestClearColours(Ctx *ctx)
{
   static const float kColours[7][4] = {
      {1, 0, 0, 1}, {0, 1, 0, 1}, {0, 0, 1, 1}, {1, 1, 1, 1}, {0, 0, 0, 1}, {0.5f, 0.5f, 0.5f, 1}, {0.25f, 0.5f, 0.75f, 1}};
   uint32_t hold = (uint32_t)ParamInt(ctx, "hold", 20);
   for (uint32_t i = 0; i < 7; i++) {
      char name[24];
      snprintf(name, sizeof(name), "clear_%u", (unsigned)i);
      LogPhase(ctx, name);
      // The GamePad gets the inverse colour, so the two screens can be told apart in a capture of either.
      SetPadClear(1.0f - kColours[i][0], 1.0f - kColours[i][1], 1.0f - kColours[i][2], 1.0f);
      if (!HoldScene(ctx, name, hold, kColours[i], NULL, NULL)) {
         return FALSE;
      }
   }
   SetPadClear(0.10f, 0.00f, 0.20f, 1.0f);
   return TRUE;
}

// ---------------------------------------------------------------------------------------------
// blend_alpha: eight blend set-ups, each over a known background, so the expected result of each
// cell is arithmetic. Catalogue: bs.blend_alpha.

typedef struct BlendCase
{
   float dst[3];
   float src[4];
   BlendState bs;
} BlendCase;

static Tex gBlendTex;

static void SceneBlend(Ctx *ctx, void *user, uint32_t frame)
{
   (void)ctx;
   (void)user;
   (void)frame;
   static const BlendCase kCases[8] = {
      // 0 standard, alpha 0.5, red over blue
      {{0, 0, 1}, {1, 0, 0, 0.5f}, {TRUE, GX2_BLEND_MODE_SRC_ALPHA, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD, GX2_BLEND_MODE_SRC_ALPHA, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD}},
      // 1 standard, alpha 0.25
      {{0, 0, 1}, {1, 0, 0, 0.25f}, {TRUE, GX2_BLEND_MODE_SRC_ALPHA, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD, GX2_BLEND_MODE_SRC_ALPHA, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD}},
      // 2 additive
      {{0.4f, 0.2f, 0.0f}, {0.4f, 0.4f, 1.0f, 1.0f}, {TRUE, GX2_BLEND_MODE_ONE, GX2_BLEND_MODE_ONE, GX2_BLEND_COMBINE_MODE_ADD, GX2_BLEND_MODE_ONE, GX2_BLEND_MODE_ONE, GX2_BLEND_COMBINE_MODE_ADD}},
      // 3 multiply
      {{0.8f, 0.4f, 0.2f}, {0.5f, 1.0f, 0.5f, 1.0f}, {TRUE, GX2_BLEND_MODE_DST_COLOR, GX2_BLEND_MODE_ZERO, GX2_BLEND_COMBINE_MODE_ADD, GX2_BLEND_MODE_DST_COLOR, GX2_BLEND_MODE_ZERO, GX2_BLEND_COMBINE_MODE_ADD}},
      // 4 premultiplied alpha
      {{0, 1, 0}, {0.5f, 0, 0, 0.5f}, {TRUE, GX2_BLEND_MODE_ONE, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD, GX2_BLEND_MODE_ONE, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD}},
      // 5 standard, alpha 0: the source must leave no trace
      {{0, 1, 0}, {1, 0, 0, 0.0f}, {TRUE, GX2_BLEND_MODE_SRC_ALPHA, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD, GX2_BLEND_MODE_SRC_ALPHA, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD}},
      // 6 textured alpha: left half of the texture has alpha 0, right half alpha 1 (drawn below)
      {{0, 0, 1}, {1, 1, 1, 1}, {TRUE, GX2_BLEND_MODE_SRC_ALPHA, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD, GX2_BLEND_MODE_SRC_ALPHA, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD}},
      // 7 max
      {{0.6f, 0.3f, 0.4f}, {0.2f, 0.9f, 0.4f, 1.0f}, {TRUE, GX2_BLEND_MODE_ONE, GX2_BLEND_MODE_ONE, GX2_BLEND_COMBINE_MODE_MAX, GX2_BLEND_MODE_ONE, GX2_BLEND_MODE_ONE, GX2_BLEND_COMBINE_MODE_MAX}},
   };

   for (uint32_t i = 0; i < 8; i++) {
      float x, y, w, h;
      Cell(i, 4, 2, &x, &y, &w, &h);
      SetBlendOff();
      DrawRect(x, y, w, h, 0.5f, kCases[i].dst[0], kCases[i].dst[1], kCases[i].dst[2], 1.0f);
      SetBlend(&kCases[i].bs);
      if (i == 6) {
         BindTexture(&gBlendTex.tex, FALSE);
         DrawTexRect(x, y, w, h, 0.5f, 1, 1, 1, 1);
      } else {
         DrawRect(x, y, w, h, 0.5f, kCases[i].src[0], kCases[i].src[1], kCases[i].src[2], kCases[i].src[3]);
      }
   }
   SetBlendStandard();
}

static BOOL TestBlendAlpha(Ctx *ctx)
{
   if (!TexCreate(&gBlendTex, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, 64, 64)) {
      LogSelf(ctx, "fail", "could not allocate the blend texture");
      return TRUE;
   }
   uint32_t rowBytes = TexRowBytes(&gBlendTex);
   for (uint32_t y = 0; y < 64; y++) {
      uint8_t *row = (uint8_t *)gBlendTex.image + y * rowBytes;
      for (uint32_t x = 0; x < 64; x++) {
         row[x * 4 + 0] = 255;
         row[x * 4 + 1] = 0;
         row[x * 4 + 2] = 0;
         row[x * 4 + 3] = x < 32 ? 0 : 255;
      }
   }
   TexUploaded(&gBlendTex);
   LogPhase(ctx, "cells");
   BOOL ok = HoldScene(ctx, "blend_cells", (uint32_t)ParamInt(ctx, "hold", 20), kBgDark, SceneBlend, NULL);
   GX2DrawDone();
   TexDestroy(&gBlendTex);
   return ok;
}

// ---------------------------------------------------------------------------------------------
// depth_test: eight depth set-ups, two overlapping quads each. Only the order of the depth values
// matters, not their absolute range, so nothing here depends on how the shader maps z.

typedef struct DepthCase
{
   GX2CompareFunction func;
   BOOL bFirst;      // draw B before A
   BOOL initDepth;   // write a nearer depth across the cell first (for GREATER)
   BOOL writeA;      // A writes depth
} DepthCase;

static void SceneDepth(Ctx *ctx, void *user, uint32_t frame)
{
   (void)ctx;
   (void)user;
   (void)frame;
   static const DepthCase kCases[8] = {
      {GX2_COMPARE_FUNC_LESS, FALSE, FALSE, TRUE},    // 0: red wins
      {GX2_COMPARE_FUNC_LESS, TRUE, FALSE, TRUE},     // 1: red wins
      {GX2_COMPARE_FUNC_GREATER, FALSE, TRUE, TRUE},  // 2: green wins
      {GX2_COMPARE_FUNC_GREATER, TRUE, TRUE, TRUE},   // 3: green wins
      {GX2_COMPARE_FUNC_ALWAYS, FALSE, FALSE, TRUE},  // 4: last drawn (green) wins
      {GX2_COMPARE_FUNC_ALWAYS, TRUE, FALSE, TRUE},   // 5: last drawn (red) wins
      {GX2_COMPARE_FUNC_NEVER, FALSE, FALSE, TRUE},   // 6: nothing drawn
      {GX2_COMPARE_FUNC_LESS, FALSE, FALSE, FALSE},   // 7: A does not write depth, so B draws over it
   };
   const float zA = 0.30f, zB = 0.70f, zInit = 0.05f;

   SetBlendOff();
   for (uint32_t i = 0; i < 8; i++) {
      float x, y, w, h;
      Cell(i, 4, 2, &x, &y, &w, &h);
      const DepthCase *c = &kCases[i];
      if (c->initDepth) {
         SetDepth(TRUE, TRUE, GX2_COMPARE_FUNC_ALWAYS);
         DrawRect(x, y, w, h, zInit, kBgGrey[0], kBgGrey[1], kBgGrey[2], 1.0f); // invisible: the clear colour
      }
      for (uint32_t pass = 0; pass < 2; pass++) {
         BOOL drawA = c->bFirst ? (pass == 1) : (pass == 0);
         if (drawA) {
            SetDepth(TRUE, c->writeA, c->func);
            DrawRect(x, y, w * 0.66f, h, zA, 1, 0, 0, 1);
         } else {
            SetDepth(TRUE, TRUE, c->func);
            DrawRect(x + w * 0.34f, y, w * 0.66f, h, zB, 0, 1, 0, 1);
         }
      }
   }
   SetDepth(FALSE, FALSE, GX2_COMPARE_FUNC_ALWAYS);
   SetBlendStandard();
}

static BOOL TestDepth(Ctx *ctx)
{
   LogPhase(ctx, "cells");
   return HoldScene(ctx, "depth_cells", (uint32_t)ParamInt(ctx, "hold", 20), kBgGrey, SceneDepth, NULL);
}

// ---------------------------------------------------------------------------------------------
// texture_formats: one 64x64 texture per format, four quadrants, each sampled in its own cell.
//
// Colour formats carry red / green / blue / yellow; the packed formats carry white / black /
// black / white, which cannot be confused by a channel-order difference; the compressed formats
// use blocks whose bytes read the same in either byte order. So a difference from the catalogue's
// expectation means the texture was uploaded, decoded or transcoded wrongly, not that this
// program and the core disagree about a layout.

typedef enum FillKind
{
   FILL_RGBA8,
   FILL_RGBA16,
   FILL_RGBA16F,
   FILL_RGBA32F,
   FILL_RG8,
   FILL_R8,
   FILL_PACKED16,
   FILL_PACKED32,
   FILL_BC1,
   FILL_BC2,
   FILL_BC3,
   FILL_BC4,
   FILL_BC5,
} FillKind;

typedef struct FormatCase
{
   const char *name;
   GX2SurfaceFormat format;
   FillKind fill;
} FormatCase;

static const FormatCase kFormats[19] = {
   {"rgba8", GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, FILL_RGBA8},
   {"srgb_rgba8", GX2_SURFACE_FORMAT_SRGB_R8_G8_B8_A8, FILL_RGBA8},
   {"rgba16", GX2_SURFACE_FORMAT_UNORM_R16_G16_B16_A16, FILL_RGBA16},
   {"rgba16f", GX2_SURFACE_FORMAT_FLOAT_R16_G16_B16_A16, FILL_RGBA16F},
   {"rgba32f", GX2_SURFACE_FORMAT_FLOAT_R32_G32_B32_A32, FILL_RGBA32F},
   {"rg8", GX2_SURFACE_FORMAT_UNORM_R8_G8, FILL_RG8},
   {"r8", GX2_SURFACE_FORMAT_UNORM_R8, FILL_R8},
   {"rgb565", GX2_SURFACE_FORMAT_UNORM_R5_G6_B5, FILL_PACKED16},
   {"rgb5a1", GX2_SURFACE_FORMAT_UNORM_R5_G5_B5_A1, FILL_PACKED16},
   {"rgba4", GX2_SURFACE_FORMAT_UNORM_R4_G4_B4_A4, FILL_PACKED16},
   {"rgb10a2", GX2_SURFACE_FORMAT_UNORM_R10_G10_B10_A2, FILL_PACKED32},
   {"bc1", GX2_SURFACE_FORMAT_UNORM_BC1, FILL_BC1},
   {"bc2", GX2_SURFACE_FORMAT_UNORM_BC2, FILL_BC2},
   {"bc3", GX2_SURFACE_FORMAT_UNORM_BC3, FILL_BC3},
   {"bc4", GX2_SURFACE_FORMAT_UNORM_BC4, FILL_BC4},
   {"bc5", GX2_SURFACE_FORMAT_UNORM_BC5, FILL_BC5},
   {"srgb_bc1", GX2_SURFACE_FORMAT_SRGB_BC1, FILL_BC1},
   {"srgb_bc2", GX2_SURFACE_FORMAT_SRGB_BC2, FILL_BC2},
   {"srgb_bc3", GX2_SURFACE_FORMAT_SRGB_BC3, FILL_BC3},
};

#define TEX_SIZE 64u

static inline uint32_t Quadrant(uint32_t x, uint32_t y, uint32_t w, uint32_t h)
{
   return (x >= w / 2 ? 1u : 0u) + (y >= h / 2 ? 2u : 0u);
}

static void PutBE16(uint8_t *p, uint16_t v)
{
   p[0] = (uint8_t)(v >> 8);
   p[1] = (uint8_t)(v & 0xFF);
}

static void PutBE32(uint8_t *p, uint32_t v)
{
   p[0] = (uint8_t)(v >> 24);
   p[1] = (uint8_t)(v >> 16);
   p[2] = (uint8_t)(v >> 8);
   p[3] = (uint8_t)(v & 0xFF);
}

static void FillFormatTexture(Tex *t, FillKind kind)
{
   static const uint8_t kColour[4][4]  = {{255, 0, 0, 255}, {0, 255, 0, 255}, {0, 0, 255, 255}, {255, 255, 0, 255}};
   static const uint8_t kRg[4][2]      = {{255, 0}, {0, 255}, {0, 0}, {255, 255}};
   static const uint8_t kRed[4]        = {255, 0, 128, 255};
   static const uint8_t kGreyWhite[4]  = {1, 0, 0, 1}; // 1 = white, 0 = black
   // BC1 colour words whose two bytes are equal (see the header comment), one per quadrant.
   static const uint8_t kBlockByte[4]  = {0x1F, 0xE0, 0x07, 0xF8};

   uint32_t rowBytes = TexRowBytes(t);
   uint8_t *base     = (uint8_t *)t->image;

   switch (kind) {
   case FILL_RGBA8:
   case FILL_RGBA16:
   case FILL_RGBA16F:
   case FILL_RGBA32F:
   case FILL_RG8:
   case FILL_R8:
   case FILL_PACKED16:
   case FILL_PACKED32:
      for (uint32_t y = 0; y < TEX_SIZE; y++) {
         uint8_t *row = base + y * rowBytes;
         for (uint32_t x = 0; x < TEX_SIZE; x++) {
            uint32_t q = Quadrant(x, y, TEX_SIZE, TEX_SIZE);
            switch (kind) {
            case FILL_RGBA8:
               memcpy(row + x * 4, kColour[q], 4);
               break;
            case FILL_RGBA16:
               for (int c = 0; c < 4; c++) {
                  PutBE16(row + x * 8 + c * 2, kColour[q][c] ? 0xFFFFu : 0u);
               }
               break;
            case FILL_RGBA16F:
               for (int c = 0; c < 4; c++) {
                  PutBE16(row + x * 8 + c * 2, kColour[q][c] ? 0x3C00u : 0u); // half 1.0
               }
               break;
            case FILL_RGBA32F:
               for (int c = 0; c < 4; c++) {
                  PutBE32(row + x * 16 + c * 4, kColour[q][c] ? 0x3F800000u : 0u); // float 1.0
               }
               break;
            case FILL_RG8:
               row[x * 2 + 0] = kRg[q][0];
               row[x * 2 + 1] = kRg[q][1];
               break;
            case FILL_R8:
               row[x] = kRed[q];
               break;
            case FILL_PACKED16:
               PutBE16(row + x * 2, kGreyWhite[q] ? 0xFFFFu : 0x0000u);
               break;
            default: // FILL_PACKED32
               PutBE32(row + x * 4, kGreyWhite[q] ? 0xFFFFFFFFu : 0x00000000u);
               break;
            }
         }
      }
      break;

   default: {
      // Compressed: 16x16 blocks of 4x4 texels.
      uint32_t blockBytes = (kind == FILL_BC1 || kind == FILL_BC4) ? 8u : 16u;
      uint32_t blocks     = TEX_SIZE / 4u;
      for (uint32_t by = 0; by < blocks; by++) {
         uint8_t *row = base + by * rowBytes;
         for (uint32_t bx = 0; bx < blocks; bx++) {
            uint32_t q  = Quadrant(bx, by, blocks, blocks);
            uint8_t *b  = row + bx * blockBytes;
            uint8_t cb  = kBlockByte[q];
            memset(b, 0, blockBytes);
            switch (kind) {
            case FILL_BC1:
               b[0] = b[1] = b[2] = b[3] = cb; // color0 == color1, all indices 0
               break;
            case FILL_BC2:
               memset(b, 0xFF, 8); // explicit alpha, all 15
               b[8] = b[9] = b[10] = b[11] = cb;
               break;
            case FILL_BC3:
               b[0] = b[1] = 0xFF; // alpha endpoints, indices 0
               b[8] = b[9] = b[10] = b[11] = cb;
               break;
            case FILL_BC4:
               b[0] = b[1] = kRed[q];
               break;
            default: // FILL_BC5: red block, green block
               b[0] = b[1] = kRg[q][0];
               b[8] = b[9] = kRg[q][1];
               break;
            }
         }
      }
      break;
   }
   }
}

static Tex gFormatTex[19];
static BOOL gFormatTexOk[19];

static void SceneFormats(Ctx *ctx, void *user, uint32_t frame)
{
   (void)ctx;
   (void)user;
   (void)frame;
   SetBlendOff();
   for (uint32_t i = 0; i < 19; i++) {
      float x, y, w, h;
      Cell(i, 5, 4, &x, &y, &w, &h);
      if (!gFormatTexOk[i]) {
         DrawRect(x, y, w, h, 0.5f, 1.0f, 0.0f, 1.0f, 1.0f); // magenta: this format could not be created at all
         continue;
      }
      BindTexture(&gFormatTex[i].tex, FALSE);
      DrawTexRectUV(x, y, w, h, 0.5f, 0, 0, 1, 1);
   }
   SetBlendStandard();
}

static BOOL TestTextureFormats(Ctx *ctx)
{
   LogPhase(ctx, "upload");
   for (uint32_t i = 0; i < 19; i++) {
      gFormatTexOk[i] = TexCreate(&gFormatTex[i], kFormats[i].format, TEX_SIZE, TEX_SIZE);
      if (!gFormatTexOk[i]) {
         LogSelf(ctx, "fail", "could not create a %s texture", kFormats[i].name);
         continue;
      }
      FillFormatTexture(&gFormatTex[i], kFormats[i].fill);
      TexUploaded(&gFormatTex[i]);
      LogNote(ctx, "format %u %s pitch=%u imageSize=%u", (unsigned)i, kFormats[i].name,
              (unsigned)gFormatTex[i].tex.surface.pitch, (unsigned)gFormatTex[i].tex.surface.imageSize);
      Fold(ctx, gFormatTex[i].tex.surface.imageSize);
   }
   LogPhase(ctx, "cells");
   BOOL ok = HoldScene(ctx, "format_cells", (uint32_t)ParamInt(ctx, "hold", 30), kBgDark, SceneFormats, NULL);
   GX2DrawDone();
   for (uint32_t i = 0; i < 19; i++) {
      if (gFormatTexOk[i]) {
         TexDestroy(&gFormatTex[i]);
      }
   }
   return ok;
}

// ---------------------------------------------------------------------------------------------
// rt_copy: GX2CopySurface between render targets of the same size, between mip levels, from a
// smaller source into a larger destination and the other way round, and into a non-base mip level.
// Catalogue: bs.rt_copy. The small-into-large case is the one behind the black-surface regression.

typedef struct CopyState
{
   RT src;      // 128x128, palette 0
   RT srcSmall; // 64x64, palette 0
   RT srcBig;   // 128x128, palette 0 (copied into a 64x64 destination)
   RT mipped;   // 256x256, four mips, a different palette in each
   RT dSame;    // 128x128
   RT dMip1;    // 128x128, from mipped level 1
   RT dMip2;    // 64x64, from mipped level 2
   RT dSmall;   // 128x128, source 64x64
   RT dLarge;   // 64x64, source 128x128
   RT dMipDst;  // 128x128 with two mips; the copy lands in level 1
   GX2Texture t[6];
   BOOL built;
} CopyState;

static const float kGreyClear[4] = {0.25f, 0.25f, 0.25f, 1.0f};

static void PassPattern(RT *rt, uint32_t mip, const Palette *p)
{
   RTBegin(rt, mip, kGreyClear);
   SetBlendOff();
   DrawQuadrants(0, 0, 1, 1, 0.5f, p);
   SetBlendStandard();
   RTEnd(rt);
}

static void PassClear(RT *rt, uint32_t mip)
{
   RTBegin(rt, mip, kGreyClear);
   RTEnd(rt);
}

static void SceneCopy(Ctx *ctx, void *user, uint32_t frame)
{
   CopyState *s = (CopyState *)user;
   if (!s->built) {
      s->built = TRUE;
      PassPattern(&s->src, 0, &kPal0);
      PassPattern(&s->srcSmall, 0, &kPal0);
      PassPattern(&s->srcBig, 0, &kPal0);
      PassPattern(&s->mipped, 0, &kPal0);
      PassPattern(&s->mipped, 1, &kPal1);
      PassPattern(&s->mipped, 2, &kPal2);
      PassPattern(&s->mipped, 3, &kPal0);
      PassClear(&s->dSame, 0);
      PassClear(&s->dMip1, 0);
      PassClear(&s->dMip2, 0);
      PassClear(&s->dSmall, 0);
      PassClear(&s->dLarge, 0);
      PassClear(&s->dMipDst, 0);
      PassClear(&s->dMipDst, 1);
      GX2DrawDone();

      GX2CopySurface(&s->src.cb.surface, 0, 0, &s->dSame.cb.surface, 0, 0);                 // same size
      GX2CopySurface(&s->mipped.cb.surface, 1, 0, &s->dMip1.cb.surface, 0, 0);              // mip 1 -> base
      GX2CopySurface(&s->mipped.cb.surface, 2, 0, &s->dMip2.cb.surface, 0, 0);              // mip 2 -> base
      GX2CopySurface(&s->srcSmall.cb.surface, 0, 0, &s->dSmall.cb.surface, 0, 0);           // source smaller than destination
      GX2CopySurface(&s->srcBig.cb.surface, 0, 0, &s->dLarge.cb.surface, 0, 0);             // source larger than destination
      GX2CopySurface(&s->srcSmall.cb.surface, 0, 0, &s->dMipDst.cb.surface, 1, 0);          // same size, into mip 1
      GX2DrawDone();

      RTAsTexture(&s->dSame, &s->t[0], 0);
      RTAsTexture(&s->dMip1, &s->t[1], 0);
      RTAsTexture(&s->dMip2, &s->t[2], 0);
      RTAsTexture(&s->dSmall, &s->t[3], 0);
      RTAsTexture(&s->dLarge, &s->t[4], 0);
      RTAsTexture(&s->dMipDst, &s->t[5], 1);
      for (int i = 0; i < 6; i++) {
         GX2Invalidate(GX2_INVALIDATE_MODE_TEXTURE, s->t[i].surface.image, s->t[i].surface.imageSize);
      }
   }
   (void)ctx;
   (void)frame;

   SetBlendOff();
   for (uint32_t i = 0; i < 6; i++) {
      float x, y, w, h;
      Cell(i, 3, 2, &x, &y, &w, &h);
      BindTexture(&s->t[i], FALSE);
      DrawTexRectUV(x, y, w, h, 0.5f, 0, 0, 1, 1);
   }
   SetBlendStandard();
}

static BOOL TestRtCopy(Ctx *ctx)
{
   static CopyState s;
   memset(&s, 0, sizeof(s));
   BOOL ok = RTCreate(&s.src, 128, 128, 1, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, GX2_SURFACE_FORMAT_INVALID) &&
             RTCreate(&s.srcSmall, 64, 64, 1, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, GX2_SURFACE_FORMAT_INVALID) &&
             RTCreate(&s.srcBig, 128, 128, 1, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, GX2_SURFACE_FORMAT_INVALID) &&
             RTCreate(&s.mipped, 256, 256, 4, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, GX2_SURFACE_FORMAT_INVALID) &&
             RTCreate(&s.dSame, 128, 128, 1, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, GX2_SURFACE_FORMAT_INVALID) &&
             RTCreate(&s.dMip1, 128, 128, 1, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, GX2_SURFACE_FORMAT_INVALID) &&
             RTCreate(&s.dMip2, 64, 64, 1, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, GX2_SURFACE_FORMAT_INVALID) &&
             RTCreate(&s.dSmall, 128, 128, 1, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, GX2_SURFACE_FORMAT_INVALID) &&
             RTCreate(&s.dLarge, 64, 64, 1, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, GX2_SURFACE_FORMAT_INVALID) &&
             RTCreate(&s.dMipDst, 128, 128, 2, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, GX2_SURFACE_FORMAT_INVALID);
   if (!ok) {
      LogSelf(ctx, "fail", "could not allocate the copy surfaces");
      return TRUE;
   }
   LogPhase(ctx, "copies");
   ok = HoldScene(ctx, "copy_cells", (uint32_t)ParamInt(ctx, "hold", 30), kBgDark, SceneCopy, &s);
   GX2DrawDone();
   RT *all[] = {&s.src, &s.srcSmall, &s.srcBig, &s.mipped, &s.dSame, &s.dMip1, &s.dMip2, &s.dSmall, &s.dLarge, &s.dMipDst};
   for (int i = 0; i < 10; i++) {
      RTDestroy(all[i]);
   }
   return ok;
}

// ---------------------------------------------------------------------------------------------
// rt_copy_fuzz: GX2CopySurface between randomly sized surfaces with random mip counts and levels,
// chosen from the seed. Discovers failures nobody thought to write a case for: the parameters of
// every iteration are logged, so any frame the app flags can be reproduced by seed and iteration.

typedef struct FuzzState
{
   uint32_t rng;
   uint32_t iteration;
   BOOL doOp;
   RT src;
   RT dst;
   BOOL haveRts;
   GX2Texture view;
   BOOL haveView;
} FuzzState;

static void FuzzPickSize(uint32_t *rng, uint32_t *w, uint32_t *h)
{
   static const uint32_t kSizes[] = {4, 8, 16, 24, 32, 48, 64, 100, 128, 200, 256, 300};
   *w = kSizes[Rand32(rng) % (sizeof(kSizes) / sizeof(kSizes[0]))];
   *h = kSizes[Rand32(rng) % (sizeof(kSizes) / sizeof(kSizes[0]))];
}

static uint32_t MipsFor(uint32_t w, uint32_t h, uint32_t want)
{
   uint32_t n = 1;
   while (n < want && (w >> n) >= 1 && (h >> n) >= 1 && (w >> n) * (h >> n) >= 4) {
      n++;
   }
   return n;
}

static void SceneFuzz(Ctx *ctx, void *user, uint32_t frame)
{
   FuzzState *s = (FuzzState *)user;
   (void)frame;
   if (s->doOp) {
      s->doOp = FALSE;
      if (s->haveRts) {
         GX2DrawDone();
         RTDestroy(&s->src);
         RTDestroy(&s->dst);
         s->haveRts = FALSE;
      }
      static const GX2SurfaceFormat kFormatsF[3] = {GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8,
                                                   GX2_SURFACE_FORMAT_FLOAT_R16_G16_B16_A16,
                                                   GX2_SURFACE_FORMAT_UNORM_R10_G10_B10_A2};
      GX2SurfaceFormat fmt = kFormatsF[Rand32(&s->rng) % 3u];
      uint32_t sw, sh, dw, dh;
      FuzzPickSize(&s->rng, &sw, &sh);
      FuzzPickSize(&s->rng, &dw, &dh);
      uint32_t smips = MipsFor(sw, sh, 1 + Rand32(&s->rng) % 4u);
      uint32_t dmips = MipsFor(dw, dh, 1 + Rand32(&s->rng) % 4u);
      uint32_t slvl  = Rand32(&s->rng) % smips;
      uint32_t dlvl  = Rand32(&s->rng) % dmips;

      LogNote(ctx, "iter=%u fmt=0x%x src=%ux%u mips=%u level=%u dst=%ux%u mips=%u level=%u", (unsigned)s->iteration,
              (unsigned)fmt, (unsigned)sw, (unsigned)sh, (unsigned)smips, (unsigned)slvl, (unsigned)dw, (unsigned)dh,
              (unsigned)dmips, (unsigned)dlvl);
      Fold(ctx, sw * 31u + sh * 17u + dw * 13u + dh * 7u + smips + dmips + slvl + dlvl);

      if (!RTCreate(&s->src, sw, sh, smips, fmt, GX2_SURFACE_FORMAT_INVALID) ||
          !RTCreate(&s->dst, dw, dh, dmips, fmt, GX2_SURFACE_FORMAT_INVALID)) {
         LogSelf(ctx, "info", "iteration %u: allocation failed, skipped", (unsigned)s->iteration);
         s->haveView = FALSE;
         return;
      }
      s->haveRts = TRUE;
      for (uint32_t m = 0; m < smips; m++) {
         PassPattern(&s->src, m, m == slvl ? &kPal0 : &kPal1);
      }
      for (uint32_t m = 0; m < dmips; m++) {
         PassClear(&s->dst, m);
      }
      GX2DrawDone();
      GX2CopySurface(&s->src.cb.surface, slvl, 0, &s->dst.cb.surface, dlvl, 0);
      GX2DrawDone();
      RTAsTexture(&s->dst, &s->view, dlvl);
      GX2Invalidate(GX2_INVALIDATE_MODE_TEXTURE, s->view.surface.image, s->view.surface.imageSize);
      s->haveView = TRUE;
      s->iteration++;
   }

   SetBlendOff();
   if (s->haveView) {
      BindTexture(&s->view, FALSE);
      DrawTexRectUV(0.1f, 0.1f, 0.8f, 0.8f, 0.5f, 0, 0, 1, 1);
   }
   SetBlendStandard();
}

static BOOL TestRtCopyFuzz(Ctx *ctx)
{
   static FuzzState s;
   memset(&s, 0, sizeof(s));
   s.rng = ctx->seed ? ctx->seed : 1u;
   int32_t iterations = ParamInt(ctx, "iterations", 48);
   int32_t checkEvery = ParamInt(ctx, "checkEvery", 16);
   LogPhase(ctx, "fuzz");
   for (int32_t i = 0; i < iterations; i++) {
      s.doOp = TRUE;
      if (!PresentFrame(ctx, kBgDark, SceneFuzz, &s, (uint32_t)i)) {
         return FALSE;
      }
      if (checkEvery > 0 && ((i + 1) % checkEvery) == 0) {
         char name[32];
         snprintf(name, sizeof(name), "fuzz_%d", (int)(i + 1));
         if (!HoldScene(ctx, name, 2, kBgDark, SceneFuzz, &s)) {
            return FALSE;
         }
      }
   }
   GX2DrawDone();
   if (s.haveRts) {
      RTDestroy(&s.src);
      RTDestroy(&s.dst);
   }
   return TRUE;
}

// ---------------------------------------------------------------------------------------------
// rt_feedback: a pattern rendered into a target, then sampled into the other target and back,
// six generations, with a depth buffer of each supported format attached. Every generation is a
// 1:1 copy by drawing, so the pattern has to come out exactly as it went in.

typedef struct FeedbackState
{
   RT a[4];
   RT b[4];
   GX2Texture result[4];
   BOOL built;
} FeedbackState;

static const GX2SurfaceFormat kDepthFormats[4] = {GX2_SURFACE_FORMAT_FLOAT_R32, GX2_SURFACE_FORMAT_UNORM_R16,
                                                  GX2_SURFACE_FORMAT_FLOAT_D24_S8, GX2_SURFACE_FORMAT_UNORM_R24_X8};

static void SceneFeedback(Ctx *ctx, void *user, uint32_t frame)
{
   FeedbackState *s = (FeedbackState *)user;
   (void)ctx;
   (void)frame;
   if (!s->built) {
      s->built = TRUE;
      for (int f = 0; f < 4; f++) {
         RTBegin(&s->a[f], 0, kGreyClear);
         SetBlendOff();
         SetDepth(TRUE, TRUE, GX2_COMPARE_FUNC_LESS);
         DrawQuadrants(0, 0, 1, 1, 0.5f, &kPal0);
         SetDepth(FALSE, FALSE, GX2_COMPARE_FUNC_ALWAYS);
         SetBlendStandard();
         RTEnd(&s->a[f]);

         RT *from = &s->a[f];
         RT *to   = &s->b[f];
         for (int gen = 0; gen < 6; gen++) {
            GX2Texture tex;
            RTAsTexture(from, &tex, 0);
            RTBegin(to, 0, kGreyClear);
            SetBlendOff();
            SetDepth(TRUE, TRUE, GX2_COMPARE_FUNC_LESS);
            BindTexture(&tex, FALSE);
            DrawTexRectUV(0, 0, 1, 1, 0.5f, 0, 0, 1, 1);
            SetDepth(FALSE, FALSE, GX2_COMPARE_FUNC_ALWAYS);
            SetBlendStandard();
            RTEnd(to);
            RT *tmp = from;
            from    = to;
            to      = tmp;
         }
         RTAsTexture(from, &s->result[f], 0); // after six swaps `from` holds the newest generation
      }
      GX2DrawDone();
   }

   SetBlendOff();
   for (uint32_t f = 0; f < 4; f++) {
      float x, y, w, h;
      Cell(f, 4, 1, &x, &y, &w, &h);
      BindTexture(&s->result[f], FALSE);
      DrawTexRectUV(x, y + h * 0.15f, w, w * 1.7f, 0.5f, 0, 0, 1, 1);
   }
   SetBlendStandard();
}

static BOOL TestRtFeedback(Ctx *ctx)
{
   static FeedbackState s;
   memset(&s, 0, sizeof(s));
   for (int f = 0; f < 4; f++) {
      if (!RTCreate(&s.a[f], 128, 128, 1, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, kDepthFormats[f]) ||
          !RTCreate(&s.b[f], 128, 128, 1, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, kDepthFormats[f])) {
         LogSelf(ctx, "fail", "could not create targets with depth format 0x%x", (unsigned)kDepthFormats[f]);
         return TRUE;
      }
   }
   LogPhase(ctx, "generations");
   BOOL ok = HoldScene(ctx, "feedback_cells", (uint32_t)ParamInt(ctx, "hold", 30), kBgDark, SceneFeedback, &s);
   GX2DrawDone();
   for (int f = 0; f < 4; f++) {
      RTDestroy(&s.a[f]);
      RTDestroy(&s.b[f]);
   }
   return ok;
}

// ---------------------------------------------------------------------------------------------
// texture_churn: textures created, drawn once and discarded far faster than a game would, with a
// canary texture that is created first and never freed. When the core evicts a texture it is
// still using, the canary (or a cell of the current generation) goes black. Every cell of the 8x8
// grid has a colour decided only by its index, so the expected frame never changes however long
// the test runs.

#define CHURN_GRID 64u

typedef struct ChurnState
{
   Tex *slots;
   uint32_t slotCount;
   uint32_t size;
   uint32_t perFrame;
   uint32_t nextId;
   uint32_t rng;
   uint64_t bytesCreated;
   Tex canary;
   BOOL canaryOk;
   uint32_t failures;
} ChurnState;

static const float kChurnPalette[8][3] = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}, {1, 1, 0}, {0, 1, 1}, {1, 0, 1}, {1, 0.5f, 0}, {0.5f, 0, 1}};

static void ChurnMakeTexture(ChurnState *s, Tex *t, uint32_t id)
{
   if (!TexCreate(t, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, s->size, s->size)) {
      s->failures++;
      return;
   }
   const float *c  = kChurnPalette[id % 8u];
   uint32_t word   = ((uint32_t)(c[0] * 255.0f) << 24) | ((uint32_t)(c[1] * 255.0f) << 16) | ((uint32_t)(c[2] * 255.0f) << 8) | 0xFFu;
   uint32_t pitchW = TexRowBytes(t) / 4u;
   uint32_t *px    = (uint32_t *)t->image;
   for (uint32_t y = 0; y < s->size; y++) {
      for (uint32_t x = 0; x < s->size; x++) {
         px[y * pitchW + x] = word; // bytes R,G,B,A in memory order on a big-endian CPU
      }
   }
   TexUploaded(t);
   s->bytesCreated += t->tex.surface.imageSize;
}

static void SceneChurn(Ctx *ctx, void *user, uint32_t frame)
{
   ChurnState *s = (ChurnState *)user;
   (void)ctx;
   (void)frame;
   SetBlendOff();

   for (uint32_t k = 0; k < s->perFrame; k++) {
      uint32_t id   = s->nextId++;
      Tex *slot     = &s->slots[id % s->slotCount];
      if (slot->image) {
         TexDestroy(slot); // the previous occupant: drawn many frames ago, finished on the GPU since
      }
      ChurnMakeTexture(s, slot, id);
      if (!slot->image) {
         continue;
      }
      float x, y, w, h;
      Cell(id % CHURN_GRID, 8, 9, &x, &y, &w, &h);
      BindTexture(&slot->tex, FALSE);
      DrawTexRectUV(x, y, w, h, 0.5f, 0, 0, 1, 1);
   }

   // Touch a few older textures so eviction has to choose between live ones.
   for (uint32_t k = 0; k < 4; k++) {
      Tex *old = &s->slots[Rand32(&s->rng) % s->slotCount];
      if (old->image) {
         BindTexture(&old->tex, FALSE);
         DrawTexRectUV(0.995f, 0.995f, 0.004f, 0.004f, 0.5f, 0, 0, 1, 1);
      }
   }

   // The canary strip (row 9 of the grid): a long-lived quadrant texture and a plain rectangle.
   if (s->canaryOk) {
      BindTexture(&s->canary.tex, FALSE);
      DrawTexRectUV(0.05f, 0.90f, 0.40f, 0.08f, 0.5f, 0, 0, 1, 1);
   }
   DrawRect(0.55f, 0.90f, 0.40f, 0.08f, 0.5f, 0.0f, 0.8f, 0.0f, 1.0f);
   SetBlendStandard();
}

static BOOL TestTextureChurn(Ctx *ctx)
{
   static ChurnState s;
   memset(&s, 0, sizeof(s));
   s.size      = (uint32_t)ParamInt(ctx, "size", 256);
   s.perFrame  = (uint32_t)ParamInt(ctx, "perFrame", 4);
   uint32_t residentMB = (uint32_t)ParamInt(ctx, "residentMB", 64);
   uint64_t totalMB    = (uint64_t)ParamInt(ctx, "totalMB", 1024);
   uint32_t checkEvery = (uint32_t)ParamInt(ctx, "checkEvery", 150);
   uint32_t durationMs = ctx->durationMs ? ctx->durationMs : 15000u;
   s.rng               = ctx->seed ? ctx->seed : 7u;

   uint32_t bytesPer = s.size * s.size * 4u;
   s.slotCount       = (residentMB * 1024u * 1024u) / bytesPer;
   if (s.slotCount < 16u) {
      s.slotCount = 16u;
   }
   if (s.slotCount > 2048u) {
      s.slotCount = 2048u;
   }
   s.slots = (Tex *)calloc(s.slotCount, sizeof(Tex));
   if (!s.slots) {
      LogSelf(ctx, "fail", "could not allocate %u texture slots", (unsigned)s.slotCount);
      return TRUE;
   }

   // The canary: 64x64 quadrants of the colour palette, made once and never freed.
   s.canaryOk = TexCreate(&s.canary, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, 64, 64);
   if (s.canaryOk) {
      uint32_t pitchW = TexRowBytes(&s.canary) / 4u;
      uint32_t *px    = (uint32_t *)s.canary.image;
      static const uint32_t kQ[4] = {0xFF0000FFu, 0x00FF00FFu, 0x0000FFFFu, 0xFFFF00FFu};
      for (uint32_t y = 0; y < 64; y++) {
         for (uint32_t x = 0; x < 64; x++) {
            px[y * pitchW + x] = kQ[Quadrant(x, y, 64, 64)];
         }
      }
      TexUploaded(&s.canary);
   }

   LogNote(ctx, "size=%u perFrame=%u slots=%u residentMB=%u totalMB=%u", (unsigned)s.size, (unsigned)s.perFrame,
           (unsigned)s.slotCount, (unsigned)residentMB, (unsigned)totalMB);
   LogPhase(ctx, "churn");

   OSTime start     = OSGetTime();
   uint32_t frame   = 0;
   uint32_t nextChk = checkEvery;
   BOOL ok          = TRUE;
   while (OSTicksToMilliseconds(OSGetTime() - start) < durationMs && (s.bytesCreated >> 20) < totalMB) {
      if (!PresentFrame(ctx, kBgDark, SceneChurn, &s, frame++)) {
         ok = FALSE;
         break;
      }
      if (checkEvery && frame >= nextChk) {
         nextChk += checkEvery;
         char name[32];
         snprintf(name, sizeof(name), "churn_%u", (unsigned)frame);
         if (!HoldScene(ctx, name, 2, kBgDark, SceneChurn, &s)) {
            ok = FALSE;
            break;
         }
      }
   }
   LogNote(ctx, "created %u textures, %u MB, %u failures", (unsigned)s.nextId, (unsigned)(s.bytesCreated >> 20),
           (unsigned)s.failures);
   if (s.failures) {
      LogSelf(ctx, "fail", "%u texture allocations failed", (unsigned)s.failures);
   }
   Fold(ctx, frame);

   GX2DrawDone();
   for (uint32_t i = 0; i < s.slotCount; i++) {
      if (s.slots[i].image) {
         TexDestroy(&s.slots[i]);
      }
   }
   free(s.slots);
   if (s.canaryOk) {
      TexDestroy(&s.canary);
   }
   return ok;
}

// ---------------------------------------------------------------------------------------------
// rt_lifecycle: six render targets of different sizes created, drawn into, sampled and destroyed
// every iteration. The picture never changes; memory must not keep growing.

typedef struct LifecycleState
{
   uint32_t iteration;
} LifecycleState;

static void SceneLifecycle(Ctx *ctx, void *user, uint32_t frame)
{
   LifecycleState *s = (LifecycleState *)user;
   (void)ctx;
   (void)frame;
   static const uint32_t kW[6] = {640, 1280, 512, 1024, 256, 320};
   static const uint32_t kH[6] = {360, 720, 512, 576, 256, 180};
   static const float kCol[6][3] = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}, {1, 1, 0}, {0, 1, 1}, {1, 0, 1}};

   RT rt[6];
   GX2Texture tex[6];
   BOOL ok[6];
   for (int i = 0; i < 6; i++) {
      ok[i] = RTCreate(&rt[i], kW[i], kH[i], 1, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, GX2_SURFACE_FORMAT_FLOAT_R32);
      if (!ok[i]) {
         continue;
      }
      float clear[4] = {kCol[i][0], kCol[i][1], kCol[i][2], 1.0f};
      RTBegin(&rt[i], 0, clear);
      RTEnd(&rt[i]);
      RTAsTexture(&rt[i], &tex[i], 0);
   }
   SetBlendOff();
   for (uint32_t i = 0; i < 6; i++) {
      float x, y, w, h;
      Cell(i, 3, 2, &x, &y, &w, &h);
      if (ok[i]) {
         BindTexture(&tex[i], FALSE);
         DrawTexRectUV(x, y, w, h, 0.5f, 0, 0, 1, 1);
      } else {
         DrawRect(x, y, w, h, 0.5f, 1, 0, 1, 1);
      }
   }
   SetBlendStandard();
   GX2DrawDone(); // everything above has to finish before its memory is handed back
   for (int i = 0; i < 6; i++) {
      if (ok[i]) {
         RTDestroy(&rt[i]);
      }
   }
   s->iteration++;
}

static BOOL TestRtLifecycle(Ctx *ctx)
{
   LifecycleState s = {0};
   int32_t iterations = ParamInt(ctx, "iterations", 30);
   int32_t checkEvery = ParamInt(ctx, "checkEvery", 10);
   LogPhase(ctx, "cycles");
   for (int32_t i = 0; i < iterations; i++) {
      if (!PresentFrame(ctx, kBgDark, SceneLifecycle, &s, (uint32_t)i)) {
         return FALSE;
      }
      if (checkEvery > 0 && ((i + 1) % checkEvery) == 0) {
         char name[32];
         snprintf(name, sizeof(name), "cycle_%d", (int)(i + 1));
         if (!HoldScene(ctx, name, 2, kBgDark, SceneLifecycle, &s)) {
            return FALSE;
         }
      }
   }
   Fold(ctx, s.iteration);
   return TRUE;
}

// ---------------------------------------------------------------------------------------------
// flicker_static: a scene that does not change, presented for a long time. Any difference between
// two captured frames is flicker (or corruption that came and went).

static Tex gStaticTex;
static BOOL gStaticTexOk;

static void SceneStatic(Ctx *ctx, void *user, uint32_t frame)
{
   (void)ctx;
   (void)user;
   (void)frame;
   // A colour ramp in 16 columns.
   for (uint32_t i = 0; i < 16; i++) {
      float t = (float)i / 15.0f;
      DrawRect((float)i / 16.0f, 0.0f, 1.0f / 16.0f, 0.25f, 0.5f, t, 1.0f - t, 0.5f, 1.0f);
   }
   // A checkerboard texture.
   if (gStaticTexOk) {
      SetBlendOff();
      BindTexture(&gStaticTex.tex, FALSE);
      DrawTexRectUV(0.05f, 0.30f, 0.40f, 0.40f, 0.5f, 0, 0, 1, 1);
      SetBlendStandard();
   }
   // Overlapping translucent quads.
   DrawRect(0.55f, 0.30f, 0.30f, 0.30f, 0.5f, 1.0f, 0.0f, 0.0f, 0.5f);
   DrawRect(0.65f, 0.40f, 0.30f, 0.30f, 0.5f, 0.0f, 0.0f, 1.0f, 0.5f);
   // Thin lines: a missing or shimmering line is easy to see in a frame comparison.
   for (uint32_t i = 0; i < 8; i++) {
      DrawRect(0.05f + (float)i * 0.11f, 0.75f, 0.004f, 0.20f, 0.5f, 1, 1, 1, 1);
   }
}

static BOOL TestFlickerStatic(Ctx *ctx)
{
   gStaticTexOk = TexCreate(&gStaticTex, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, 64, 64);
   if (gStaticTexOk) {
      uint32_t pitchW = TexRowBytes(&gStaticTex) / 4u;
      uint32_t *px    = (uint32_t *)gStaticTex.image;
      for (uint32_t y = 0; y < 64; y++) {
         for (uint32_t x = 0; x < 64; x++) {
            px[y * pitchW + x] = (((x / 8u) ^ (y / 8u)) & 1u) ? 0xEBEBEBFFu : 0x282858FFu;
         }
      }
      TexUploaded(&gStaticTex);
   }
   LogPhase(ctx, "early");
   BOOL ok = HoldScene(ctx, "static_early", (uint32_t)ParamInt(ctx, "early", 60), kBgDark, SceneStatic, NULL);
   if (ok) {
      LogPhase(ctx, "late");
      ok = HoldScene(ctx, "static_late", (uint32_t)ParamInt(ctx, "late", 300), kBgDark, SceneStatic, NULL);
   }
   GX2DrawDone();
   if (gStaticTexOk) {
      TexDestroy(&gStaticTex);
   }
   return ok;
}

// ---------------------------------------------------------------------------------------------
// motion_counter: something moves, and the frame number is drawn twice, in a strip along the top
// and another along the bottom, as 16 black/white squares. The app decodes both from every frame
// it captures: different numbers in one frame is a tear, numbers that do not increase are a
// repeated or out-of-order frame, and gaps are dropped frames.

static void SceneMotion(Ctx *ctx, void *user, uint32_t frame)
{
   (void)ctx;
   (void)user;
   (void)frame;
   uint32_t n = FramesPresented() & 0xFFFFu;
   for (uint32_t bit = 0; bit < 16; bit++) {
      float v = (n >> bit) & 1u ? 1.0f : 0.0f;
      float x = (float)bit / 16.0f;
      DrawRect(x, 0.0f, 1.0f / 16.0f, 0.07f, 0.5f, v, v, v, 1.0f);
      DrawRect(x, 0.93f, 1.0f / 16.0f, 0.07f, 0.5f, v, v, v, 1.0f);
   }
   float bar = (float)(n % 120u) / 120.0f;
   DrawRect(bar * 0.9f, 0.40f, 0.10f, 0.20f, 0.5f, 1.0f, 0.3f, 0.0f, 1.0f);
   DrawRect(0.0f, 0.49f, 1.0f, 0.02f, 0.4f, 0.2f, 0.2f, 0.2f, 1.0f);
}

static BOOL TestMotionCounter(Ctx *ctx)
{
   LogPhase(ctx, "moving");
   return HoldScene(ctx, "motion", (uint32_t)ParamInt(ctx, "early", 90), kBgDark, SceneMotion, NULL);
}

// ---------------------------------------------------------------------------------------------

const TestEntry kRenderTests[] = {
   {"handshake", TestHandshake},
   {"orientation", TestOrientation},
   {"clear_colours", TestClearColours},
   {"blend_alpha", TestBlendAlpha},
   {"depth_test", TestDepth},
   {"texture_formats", TestTextureFormats},
   {"rt_copy", TestRtCopy},
   {"rt_copy_fuzz", TestRtCopyFuzz},
   {"rt_feedback", TestRtFeedback},
   {"texture_churn", TestTextureChurn},
   {"rt_lifecycle", TestRtLifecycle},
   {"flicker_static", TestFlickerStatic},
   {"motion_counter", TestMotionCounter},
   {NULL, NULL},
};
