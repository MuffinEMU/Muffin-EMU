// cpubench.rpx - five deterministic, allocation-free CPU/FPU/memory workloads
// for the Muffin vs. MeloCafe engine benchmark. See ../../README.md for the
// marker protocol and how the host times this against gpubench.rpx.
//
// Every test below is pure computation on data that is either a compile-time
// constant or generated once, deterministically, before its BEGIN marker.
// Nothing allocates and nothing branches on wall-clock time inside a timed
// region, so the same binary must produce the same checksum on every engine
// that emulates the PPC instruction set correctly - a checksum mismatch means
// an emulation bug, not a slow answer.
//
// Iteration counts are declared as constants up top exactly so they can be
// retuned. They were sized by rough instruction-count reasoning (an
// interpreter doing tens of millions of simple ops per second), not measured
// on real hardware or against Muffin/MeloCafe directly - there is no PPC
// toolchain or Wii U/Cemu instance available to calibrate them where this
// file was written. Treat the "~5-20s on a slow interpreter" comments as a
// first guess to correct after the first real run, not a verified fact.

// bench_marker.h is copied in next to this file by the CI workflow (it lives
// at homebrew/bench/common/ in the repo, shared with gpubench.rpx) - see
// .github/workflows/build-bench-rpx.yml. The include is deliberately flat,
// not a relative "../../common/..." path, because the wut sample Makefile
// this is built with only ever sees a single flattened source/ directory.
#include "bench_marker.h"

#include <coreinit/thread.h>
#include <coreinit/time.h>
#include <math.h>
#include <stdint.h>
#include <string.h>
#include <whb/proc.h>

// ---------------------------------------------------------------------------
// Tuning constants
// ---------------------------------------------------------------------------

// int_mix: integer ALU + branch-heavy xorshift mixing.
#define INT_MIX_ITERATIONS (20000000u)

// mem_copy: memset/memcpy plus touch passes over this buffer, this many times.
#define MEM_COPY_BUFFER_SIZE (4u * 1024u * 1024u) // 4 MiB
#define MEM_COPY_ITERATIONS  (30u)

// float_math: double + float transcendental math per iteration.
#define FLOAT_MATH_ITERATIONS (3000000u)

// call_heavy: non-inlined calls per iteration = 2 * (CALL_HEAVY_RECURSION_DEPTH + 1)
// (CallRecurse plus one CallLeaf per recursion level, called once more at the base case).
#define CALL_HEAVY_ITERATIONS      (1500000u)
#define CALL_HEAVY_RECURSION_DEPTH (16u)

// matrix: 4x4 float matrix multiplies (64 multiply-adds each).
#define MATRIX_ITERATIONS (2000000u)

// ---------------------------------------------------------------------------
// int_mix - integer arithmetic, shifts, branches, xorshift32.
//
// Branch-heavy on purpose: half the iterations take the add-and-rotate path
// and half take the subtract-and-or path, so an interpreter's branch
// dispatch is exercised as heavily as its ALU is.
// ---------------------------------------------------------------------------
static uint32_t BenchIntMix(uint32_t iterations)
{
   uint32_t x   = 0x12345678u;
   uint32_t acc = 0u;

   for (uint32_t i = 0; i < iterations; i++) {
      x ^= x << 13;
      x ^= x >> 17;
      x ^= x << 5;

      if (x & 1u) {
         acc += (x >> 3) ^ 0x9E3779B9u;
      } else {
         acc -= (x << 2) | 0x1u;
      }

      acc = (acc << 7) | (acc >> 25); // rotate left 7
   }

   return acc ^ x;
}

// ---------------------------------------------------------------------------
// mem_copy - memset/memcpy plus a byte-wise touch pass over a multi-MB
// buffer, exercising the memory access path (MMU/fastmem) rather than pure
// ALU throughput. Buffers are allocated once, before BEGIN; nothing in the
// timed region allocates.
// ---------------------------------------------------------------------------
static uint32_t BenchMemCopy(uint32_t iterations, uint8_t *src, uint8_t *dst)
{
   uint32_t checksum = 0u;

   for (uint32_t iter = 0; iter < iterations; iter++) {
      memset(src, (int)(iter & 0xFFu), MEM_COPY_BUFFER_SIZE);
      memcpy(dst, src, MEM_COPY_BUFFER_SIZE);

      // One touch per page-ish stride: cheap enough not to dominate the
      // test, but enough addresses that a broken fastmem path would show up
      // as either a crash or a bad checksum instead of silently passing.
      for (uint32_t i = 0; i < MEM_COPY_BUFFER_SIZE; i += 4096u) {
         checksum = (checksum * 31u) + dst[i];
      }
   }

   // Fold a real sample of the final buffer contents into the checksum too,
   // so a memcpy/memset that runs but corrupts data is caught, not just one
   // that crashes or hangs.
   for (uint32_t i = 0; i < MEM_COPY_BUFFER_SIZE; i += 1024u) {
      checksum = (checksum * 131u) + dst[i];
   }

   return checksum;
}

// ---------------------------------------------------------------------------
// float_math - double and float transcendental math (sqrt/sin), plain C,
// no paired-singles intrinsics. Renormalized periodically so the running
// accumulators can't drift to zero or overflow across millions of iterations
// and go numerically meaningless.
// ---------------------------------------------------------------------------
static uint32_t BenchFloatMath(uint32_t iterations)
{
   double acc  = 1.0;
   float  accf = 1.0f;

   for (uint32_t i = 0; i < iterations; i++) {
      double d = (double)(i % 997u) * 0.0001 + 0.5;
      acc      = acc * 0.999999 + sqrt(d) + sin(d);
      if ((i & 0xFFFu) == 0u) {
         acc = fmod(acc, 1000.0) + 1.0;
      }

      float f = (float)(i % 613u) * 0.001f + 0.25f;
      accf    = accf * 0.9999f + sqrtf(f) + sinf(f);
      if ((i & 0xFFFu) == 0u) {
         accf = fmodf(accf, 1000.0f) + 1.0f;
      }
   }

   // memcpy, not a pointer cast, to read the bit patterns back out - an
   // aliasing violation here could let the compiler assume the float and
   // double stores can't interact and reorder them.
   uint64_t accBits;
   uint32_t accfBits;
   memcpy(&accBits, &acc, sizeof(accBits));
   memcpy(&accfBits, &accf, sizeof(accfBits));

   return (uint32_t)(accBits ^ (accBits >> 32)) ^ accfBits;
}

// ---------------------------------------------------------------------------
// call_heavy - many small non-inlined function calls and recursion, to
// exercise branch-and-link and stack frame setup/teardown rather than ALU
// throughput. noinline is load-bearing: an inlined CallLeaf/CallRecurse
// would collapse this into int_mix and stop measuring what its name says.
// ---------------------------------------------------------------------------
__attribute__((noinline)) static uint32_t CallLeaf(uint32_t x)
{
   return (x ^ 0x2545F491u) + (x >> 3);
}

__attribute__((noinline)) static uint32_t CallRecurse(uint32_t x, uint32_t depth)
{
   if (depth == 0u) {
      return CallLeaf(x);
   }
   return CallRecurse(CallLeaf(x), depth - 1u) ^ (depth * 0x9E3779B1u);
}

static uint32_t BenchCallHeavy(uint32_t iterations)
{
   uint32_t acc = 0xCAFEBABEu;

   for (uint32_t i = 0; i < iterations; i++) {
      acc = CallRecurse(acc + i, CALL_HEAVY_RECURSION_DEPTH);
   }

   return acc;
}

// ---------------------------------------------------------------------------
// matrix - 4x4 float matrix multiplies in a loop. Feeds the result back in
// as the next left operand so the compiler can't hoist the multiply out of
// the loop, and rescales periodically to keep values in a sane float range
// across millions of iterations.
// ---------------------------------------------------------------------------
typedef struct
{
   float m[4][4];
} Mat4;

static void Mat4Multiply(Mat4 *out, const Mat4 *a, const Mat4 *b)
{
   for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 4; c++) {
         float sum = 0.0f;
         for (int k = 0; k < 4; k++) {
            sum += a->m[r][k] * b->m[k][c];
         }
         out->m[r][c] = sum;
      }
   }
}

static uint32_t BenchMatrix(uint32_t iterations)
{
   Mat4 a, b, c;

   // Deterministic non-trivial seed data - not identity, so every element
   // of every multiply does real work from the first iteration.
   for (int r = 0; r < 4; r++) {
      for (int col = 0; col < 4; col++) {
         a.m[r][col] = (float)(r * 4 + col) * 0.1f + 1.0f;
         b.m[r][col] = (float)(col * 4 + r) * 0.05f + 0.5f;
      }
   }

   for (uint32_t i = 0; i < iterations; i++) {
      Mat4Multiply(&c, &a, &b);
      a = c;

      if ((i & 0xFFu) == 0u) {
         float scale = 1.0f / (fabsf(a.m[0][0]) + 1.0f);
         for (int r = 0; r < 4; r++) {
            for (int col = 0; col < 4; col++) {
               a.m[r][col] *= scale;
            }
         }
      }
   }

   uint32_t checksum = 0u;
   for (int r = 0; r < 4; r++) {
      for (int col = 0; col < 4; col++) {
         uint32_t bits;
         memcpy(&bits, &a.m[r][col], sizeof(bits));
         checksum = (checksum * 131u) + bits;
      }
   }

   return checksum;
}

// ---------------------------------------------------------------------------

int main(int argc, char **argv)
{
   (void)argc;
   (void)argv;

   WHBProcInit();

   OSReport("cpubench.rpx: starting\n");

   // mem_copy's buffers are allocated once here, outside every timed region -
   // the spec for this suite is "no allocation inside timed regions", and a
   // static array is simplest way to guarantee that on a homebrew heap.
   static uint8_t sMemCopySrc[MEM_COPY_BUFFER_SIZE];
   static uint8_t sMemCopyDst[MEM_COPY_BUFFER_SIZE];

   MuffinBenchBegin("int_mix", INT_MIX_ITERATIONS);
   uint32_t intMixChecksum = BenchIntMix(INT_MIX_ITERATIONS);
   MuffinBenchEnd("int_mix", intMixChecksum);

   MuffinBenchBegin("mem_copy", MEM_COPY_ITERATIONS);
   uint32_t memCopyChecksum = BenchMemCopy(MEM_COPY_ITERATIONS, sMemCopySrc, sMemCopyDst);
   MuffinBenchEnd("mem_copy", memCopyChecksum);

   MuffinBenchBegin("float_math", FLOAT_MATH_ITERATIONS);
   uint32_t floatMathChecksum = BenchFloatMath(FLOAT_MATH_ITERATIONS);
   MuffinBenchEnd("float_math", floatMathChecksum);

   MuffinBenchBegin("call_heavy", CALL_HEAVY_ITERATIONS);
   uint32_t callHeavyChecksum = BenchCallHeavy(CALL_HEAVY_ITERATIONS);
   MuffinBenchEnd("call_heavy", callHeavyChecksum);

   MuffinBenchBegin("matrix", MATRIX_ITERATIONS);
   uint32_t matrixChecksum = BenchMatrix(MATRIX_ITERATIONS);
   MuffinBenchEnd("matrix", matrixChecksum);

   MuffinBenchDone();

   // The suite is done, but the process stays up until the host closes it -
   // guest-side, there is no reliable way to know the host has finished
   // reading the log, so the only correct behaviour is to wait to be told.
   while (WHBProcIsRunning()) {
      OSSleepTicks(OSMillisecondsToTicks(100));
   }

   WHBProcShutdown();
   return 0;
}
