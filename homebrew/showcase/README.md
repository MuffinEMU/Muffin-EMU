# MuffinEMU Showcase

An original Wii U homebrew program (`showcase.rpx`) that shows what MuffinEMU can do. It runs in
MuffinEMU and on real Wii U homebrew loaders. It draws on the **TV and the GamePad at once**: the
TV shows the scene, the GamePad is an interactive control panel or a second view.

Everything is original code. There are no Nintendo assets, no samples and no system fonts: all
music is synthesised in code and all text uses a 5x7 bitmap font drawn by the program.

## Build

CI builds it: `.github/workflows/build-showcase-rpx.yml` (devkitPPC container, wut's sample
Makefile, sources from `source/`). It uploads `showcase.rpx` as an artifact, and a manual run with
`publish=true` publishes a `showcase-<sha>` pre-release. Nothing is built locally.

## Controls

| Input | Action |
| --- | --- |
| A / touch | Start, select |
| D-pad up/down or left stick | Menu navigation |
| B | Back (scene to menu, menu to title) |
| L / R | Previous / next scene |
| - (minus) | Back to the menu |
| + (plus) | Mute / unmute the soundtrack |
| Y | Cycle render quality: 640x360, 320x180, 160x90 internal (also steps down automatically on slow hosts) |
| Left stick, right stick, ZL/ZR, A, X, D-pad | Per scene, shown on the GamePad |

GamePad and Pro Controller both work. Leave it idle on the title or menu and an **auto demo** cycles
every scene; any input stops it.

## Scenes and what they exercise

| # | Scene | What it shows | Emulator surface |
| --- | --- | --- | --- |
| 1 | 3D Landscape | 256x256 procedural fBm heightmap raycast across all three cores at 640x360: bilinear height and colour, per-pixel sun/moon lighting from the surface gradient, soft heightfield shadows, animated water with Fresnel reflection, wave normals and sun glints, in-scattered fog, drifting clouds, day/night cycle (sky, sun, moon, stars). Fly with the sticks. GamePad shows a hill-shaded map and sky clock. | PPC integer/float throughput, three-core scaling, OSScreen scanout |
| 2 | Particles | Up to 6000 additive fireworks sparks (sphere, ring, heart, willow bursts, burst flashes, glow halos) or a 14000-star 3D spiral galaxy. Touch the GamePad view to fire bursts. | PPC float maths, additive blending, VPAD touch |
| 3 | Shader Lab | Domain-warped plasma, tunnel, lit 3D metaballs and a sphere-tracing raymarcher (soft shadows, ambient occlusion, specular, sky reflection) over an infinite lattice. Evaluated per pixel on three cores, expanded with bilinear filtering. | Heavy per-pixel float maths, second-screen mirror |
| 4 | 3D Mesh Lab | A real software triangle pipeline: a 7,680 triangle torus knot and three spheres, z-buffer, perspective projection, per-pixel shading from interpolated normals. Environment-mapped chrome, gold, pearl and glass (Fresnel, refraction), glossy ceramic, sphere-in-knot reflections, a filtered checker floor with soft shadows and a mirrored-geometry reflection, anti-aliased silhouettes. | PPC float throughput, OSThread on three cores, cache flushes between cores |
| 5 | Input Lab | Buttons, both sticks, multitouch-style drawing canvas, accelerometer, gyroscope, a Gouraud-shaded 3D cube that tilts with the sensors, rumble on A. | VPAD buttons/sticks/touch/motion/motor, KPAD Pro Controller |
| 6 | Audio | The soundtrack, a live waveform read from the PCM buffer at the AX voice's play offset, a 6-lane step sequencer and lead piano roll, track select, mute and volume. | sndcore2 (AX) voice, LPCM16 looping, SRC, mixer, TV + DRC buses |
| 7 | Stress and Info | A smooth-coloured Mandelbrot zoom rendered by three OSThreads, one per PPC core, with a 1 core vs 3 core speed-up readout. Frame timing graph, MEM1/MEM2/heap, scrolling credits. | OSThread affinity on all 3 cores, OSSemaphore, OSGetSystemTime, OSGetMemBound |

## How it works

- **Display.** Scenes render into a 640x360 CPU framebuffer (320x180 and 160x90 are fallbacks the
  program steps down to when the host is slow, or on Y). It is upscaled with linear filtering
  (2x or 4x) into the TV's OSScreen buffer on all three cores; the HUD is drawn at native
  1280x720 with a smoothed bitmap font (the 5x7 glyphs are bilinearly sampled and thresholded, so
  corners round off and diagonals anti-alias). The GamePad screen is redrawn every third frame.
  OSScreen is double buffered: the program writes the back half and flips.
- **Three cores.** `par.c` is a small fork-join pool: the calling thread plus two OSThreads pinned
  to cores 0 and 2. Present, the landscape, the shader grid, the mesh rasteriser and the
  fades all use it. The video hardware reads the frame
  buffers from RAM, so each slice flushes the rows it wrote (`DCFlushRange`), and column bands
  start on 32-byte boundaries so no cache line is shared between cores. If the threads
  cannot be created everything runs on the calling thread.
- **Shaders.** The "shader" scenes are CPU fragment functions evaluated per pixel on a grid
  (320x180, 213x120 for the raymarcher) and expanded to the scene buffer with bilinear filtering.
  GX2 itself is **not used** by this program; it is the CPU/OSScreen showcase.
- **Music.** `audio.c` holds five tracks as data (scale, chord progression, drum/bass/arp masks, a
  64-step lead line). A step sequencer drives a software synth (pulse and triangle oscillators,
  kick/snare/hat generators, an echo) and renders each 64-step loop to PCM16 on a worker thread
  (core 2). Each loop plays on one AX voice as a looping LPCM16 source at 24 kHz through the TV and
  GamePad buses; tracks swap with a short fade. Each scene has its own track.
- **No libm.** Trig, sqrt, exp and log2 are small table/polynomial routines in `util.c`.

## Files

`source/` holds `main.c` (loop, title, menu, auto demo, quality stepping), `gfx.c` (OSScreen layer,
smooth upscale, primitives, anti-aliased lines/discs/glows, font), `par.c` (three-core job pool),
`input.c` (VPAD and KPAD), `audio.c` (sequencer, synth, AX), `util.c` (maths, colour), and one
`sc_*.c` per scene.

## Credits and licence

Original code by MuffinEMU, licensed MPL-2.0 like the rest of the repository. Built with devkitPro's
devkitPPC and wut (see their licences); no third-party code is bundled. No Nintendo code, assets,
music or fonts are used.
