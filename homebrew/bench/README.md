# bench - cross-engine guest workloads

Two homebrew RPX files, `cpubench.rpx` and `gpubench.rpx`, built by
`.github/workflows/build-bench-rpx.yml`. They are the actual benchmark: the
host iOS app boots the same RPX in Muffin's own engine, MeloCafe's engine,
and Muffin+MeloCafe's fixes, and times each one by tailing its OSReport log
for a fixed marker protocol. Retail games can't be bundled with the app, so
these are what gets compared instead.

## The marker protocol

All three engines route guest `OSReport` output to their own log, which the
host tails. Every test in both RPX files prints exactly:

```
MUFFINBENCH BEGIN <test> <iterations>
MUFFINBENCH END <test> <checksum>
```

immediately before and after its timed work, in that order, with nothing
else - not even another `OSReport` call - happening in between. After the
last test, both RPX files print:

```
MUFFINBENCH DONE
```

and then idle (`WHBProcIsRunning()` loop) until the host closes the app. The
guest never times itself: an emulator is free to scale guest time (a slow
interpreter and a fast recompiler can both report "10000 PPC cycles" to the
guest OS while taking very different amounts of real time), so the only
number that means anything is the host's own wall clock between the moment
it *sees* `BEGIN` and the moment it *sees* `END` in the log.

`<checksum>` is a `%08x`-formatted `uint32_t`, and it is a correctness gate,
not a benchmark result. All three engines run the identical PPC binary
against identical, fully-deterministic inputs, so a given test must produce
the same checksum everywhere. If one engine's checksum doesn't match, that
engine has an emulation bug for that test, and whatever "speed" it reported
must not be counted - a wrong answer computed quickly isn't a fast correct
answer. See `homebrew/bench/common/bench_marker.h` for the three one-line
helpers (`MuffinBenchBegin`/`MuffinBenchEnd`/`MuffinBenchDone`) that both RPX
files use to print these lines.

## cpubench.rpx

Five deterministic, allocation-free tests, run once each in sequence, no
display output at all (pure `OSReport`, no OSScreen/GX2). Iteration counts
are `#define` constants at the top of
`homebrew/bench/cpubench/source/cpubench.c` for exactly this reason - retune
them there:

| Test | What it exercises |
| --- | --- |
| `int_mix` | Integer ALU, shifts, and a branch-heavy xorshift32 mix - stresses interpreter dispatch, not just raw ALU throughput. |
| `mem_copy` | `memset`/`memcpy` plus a byte-wise touch pass over a 4 MiB buffer - the memory access path (MMU/fastmem), not compute. |
| `float_math` | `double` and `float` `sqrt`/`sin`, plain C, no paired-singles intrinsics - the FPU path. |
| `call_heavy` | Many small `__attribute__((noinline))` calls and 16-deep recursion - branch-and-link and stack frame overhead. |
| `matrix` | 4x4 float matrix multiplies, result fed back in each iteration so the compiler can't hoist the work out of the loop. |

Every test's buffers/inputs are allocated or generated once, before its
`BEGIN`, and its checksum is a fold of the final accumulator state (or, for
`mem_copy`, a sample of the copied buffer) - so a test that silently produces
wrong output, not just a slow one, is also caught.

**Iteration counts are unverified.** They were sized by rough
instruction-count reasoning (an interpreter doing on the order of tens of
millions of simple ops/sec, aiming for each test to land in roughly 5-20
seconds there and be comfortably shorter on a recompiler) - there is no
devkitPPC toolchain, no Wii U, and no Cemu/Muffin/MeloCafe instance available
in the environment this was written in to actually run and time them. Expect
to adjust the `_ITERATIONS` constants after the first real run on real
engines.

## gpubench.rpx

One test, `gx2_scene`: a grid of `GPUBENCH_GRID_SIZE`² textured,
alpha-blended quads (64x64 = 4096 quads = 8192 triangles by default),
spinning around Y, drawn to both the TV and DRC targets across
`GPUBENCH_DRAW_BATCH_COUNT` (4) draw calls per target per frame, for
`GPUBENCH_FRAME_COUNT` (600) frames. Unlike cpubench, the timed region here
*is* the per-frame loop - `BEGIN` prints immediately before the first frame,
`END` immediately after the last frame's `GX2SwapScanBuffers`/`GX2Flush`
(inside `WHBGfxFinishRender()`), because that swap/flush is the thing being
measured, not incidental overhead around it. All constants are at the top of
`homebrew/bench/gpubench/source/gpubench.c`.

The scene texture is a small procedural checkerboard generated on the CPU at
startup (no bundled image asset), and half the quads (checkerboarded by grid
position) are drawn at 0.35 alpha so blending is actually visible in the
output, not just enabled. Depth test is on. None of this setup happens inside
the timed region.

**The aspect ratio is a fixed constant (`16.0f/9.0f`), not read from the live
TV mode.** This is deliberate: the aspect ratio feeds directly into the
per-frame MVP matrix, which feeds the checksum. If it were read from
`GX2GetSystemTVScanMode()`/the live colour buffer size, two setups configured
for different TV resolutions (720p vs. 1080p, say) would produce different,
but equally *correct*, checksums - a false mismatch with nothing to do with
an emulation bug. Every checksum input in this test is a compile-time
constant or a value computed purely from the frame index for exactly this
reason.

**The checksum is CPU-side only - it does not read back rendered pixels.**
It folds in a hash of the generated vertex buffer and texture once at setup,
then the bytes of every frame's MVP matrix as the loop runs. That catches a
real and meaningful class of bug (wrong FPU/matrix math, corrupted vertex or
texture upload - the CPU-side half of the pipeline), but it cannot catch a
bug that is purely on the GPU side of the pipeline (a broken blend equation,
a shader that compiles but samples the wrong texel, incorrect Latte-to-host
shader translation) - only the rendered picture would show those. A genuine
pixel checksum would need `GX2CopySurface`-ing part of the color buffer back
to a CPU-readable surface and reading it after a GPU sync, which was ruled
out here: the checksum has to be known before the `END` line is printed
(it's part of that line), so a GPU readback would add a sync stall of
unknown, engine-dependent cost *inside* what's supposed to be a clean
speed measurement, biasing exactly the comparison this whole benchmark
exists to make. If a future revision wants real pixel verification, it needs
to happen as a separate, explicitly-unmeasured step after `END`, not before
it.

**The rendered scene has not been visually verified.** There is no devkitPPC
toolchain, Wii U, or Cemu-family emulator available in the environment this
was written in - the code was written and self-reviewed against wut's real
headers and a real, permissively-licensed shader author's working examples
(see below), but nobody has seen a frame of it actually render. If the
picture looks wrong (or the RPX doesn't come up at all) when this is first
run for real, that is the first thing to check, not assumed-correct
infrastructure.

### The shader problem, and how it's solved here

GX2 has no runtime GLSL compiler on real hardware - shaders are always
precompiled to a Latte GPU binary and packaged into a `.gsh` (GFD) blob that
`WHBGfxLoadGFDShaderGroup()` reads. Three ways to get one were considered:

1. **decaf-emu's `latte-assembler`**, which assembles hand-written Latte ISA
   assembly (not GLSL) into a `.gsh`. Ruled out: its only public release is a
   2015 Windows binary under GPLv3, and building it from source pulls in
   decaf-emu's full CMake tree (`libcpu`, SDL2, libuv, c-ares, CURL, OpenSSL,
   Vulkan, ffmpeg, Qt...) just to get one small tool that only needs `common`,
   `libgfd`, `excmd`, `peglib`, and `SPIRV` - not a "reasonably buildable in
   CI" ask, and nothing in this environment could build or test it to check.
2. **Hand-written Latte assembly**, following
   [GaryOderNichts' shader guide](https://github.com/GaryOderNichts/wiiu-shaders)
   and the real, MIT-licensed, hardware-verified example shaders in his
   [`librw` GX2 port](https://github.com/GaryOderNichts/librw/tree/gx2/src/gx2/shaders/shader_source)
   (he shipped these in a real Wii U port of GTA III). This is a legitimate,
   de-risked option - `im3d.vsh`/`simple.psh` there are almost exactly this
   test's vertex/pixel shader - but it still needs `latte-assembler` (problem
   1) to actually assemble, and hand-editing raw ALU/export assembly for the
   attributes and uniforms this benchmark uses is much more error-prone to
   get right blind than writing GLSL and letting a real compiler catch
   mistakes.
3. **[CafeGLSL](https://github.com/Exzap/CafeGLSL)** - the option used here.
   It's a Mesa fork ("an experimental runtime GLSL shader compiler library
   for the Wii U") by **Exzap**, who also wrote Cemu's own Metal/Vulkan
   backends and its GX2 shader decompiler - the strongest compatibility
   signal available for a benchmark whose only real target is Cemu-family
   emulators. It ships a precompiled, PC-hosted (`x86-64` Linux) CLI,
   `glslcompiler.elf`, from its
   [GitHub Releases](https://github.com/Exzap/CafeGLSL/releases) - no build
   step, no Wine, no decaf-emu dependency tree. The workflow downloads
   `v0.2.0`'s `glslcompiler.elf`, verifies its sha256 against the hash
   recorded in `.github/workflows/build-bench-rpx.yml`, and runs
   `glslcompiler -vs scene.vs -ps scene.ps -o scene.gsh` on plain GLSL
   (`homebrew/bench/gpubench/source/shaders/scene.{vs,ps}`) to produce the
   `.gsh`. `homebrew/bench/gpubench/source/gpubench.c` was written to match
   the exact explicit-binding style CafeGLSL's own test suite
   (`cafecompiler/tests.cpp` in that repo) shows compiling successfully -
   `layout(binding = N)` on every uniform block and sampler,
   `layout(location = N)` on every attribute and varying - because CafeGLSL's
   separable-shader model has no implicit binding assignment
   ("Current Limitations" in its README).

   Licensing: CafeGLSL's own additions are MIT-licensed; the underlying code
   is a Mesa fork (Mesa's license: <https://docs.mesa3d.org/license.html>,
   predominantly MIT); its README credits **exjam** (decaf-emu) for
   permission to reuse decaf's `libgfd` GFD-serialization code. Only the
   compiler tool is consumed here (downloaded fresh at CI build time, never
   committed to this repo) - the actual shipped artifact is `scene.gsh`,
   compiled from GLSL source this repo owns outright.

`gpubench.c` embeds the compiled `.gsh` as a C byte array
(`scene_gsh.h`, generated at build time by the workflow via `od`/`awk` - see
its "Turn scene.gsh into a bundled C header" step) rather than loading a
`.gsh` file from an SD card at runtime the way wut's own `gx2_triangle`
sample does. That keeps `gpubench.rpx` a single self-contained file with no
external asset dependency, which matters here since it has to run standalone
inside three different emulators with no SD card image prepared for it.

## Rebuilding

Not built locally - there is no Wii U toolchain (or, for gpubench, GLSL-to-
GX2 compiler) on the machine this was written on. Run the
**Build Bench RPX (Homebrew)** workflow
(`.github/workflows/build-bench-rpx.yml`), which has two jobs,
`build-cpubench-rpx` and `build-gpubench-rpx`, both building in the official
`devkitpro/devkitppc` container against wut's own sample Makefile, the same
way `build-rainbow-rpx.yml` and `build-showcase-rpx.yml` do. It's
`workflow_dispatch` (run it manually) and also `workflow_call`, so a later
workflow that packages these into the host iOS app can invoke it as a step
of its own build.

## Tuning iteration counts

Every test's iteration/frame count is a `#define` constant at the top of its
`.c` file - `homebrew/bench/cpubench/source/cpubench.c` for the five CPU
tests, `homebrew/bench/gpubench/source/gpubench.c` for `gx2_scene`. To
retune: change the constant, commit, and re-run the build workflow - nothing
else in either file depends on the exact values beyond a couple of
divisibility constraints called out at each constant's definition (for
example, `GPUBENCH_GRID_SIZE`² must divide evenly by
`GPUBENCH_DRAW_BATCH_COUNT`). Changing a checksummed test's inputs changes
its checksum, so expect every engine's recorded checksum for that test to
change too the next time it's run after a retune - that's expected, not a
regression.
