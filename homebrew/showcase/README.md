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
| Y | Toggle render quality (320x180 or 160x90 internal; also drops automatically on slow hosts) |
| Left stick, right stick, ZL/ZR, A, X, D-pad | Per scene, shown on the GamePad |

GamePad and Pro Controller both work. Leave it idle on the title or menu and an **auto demo** cycles
every scene; any input stops it.

## Scenes and what they exercise

| # | Scene | What it shows | Emulator surface |
| --- | --- | --- | --- |
| 1 | 3D Landscape | 256x256 procedural fBm heightmap, voxel column raycaster, fog, slope lighting, animated water, day/night cycle (sky gradient, sun, moon, stars). Fly with the sticks. GamePad shows a live terrain map and sky clock. | PPC integer/float throughput, OSScreen scanout |
| 2 | Particles | Up to 6000 additive fireworks sparks (sphere, ring, heart, willow bursts) or a 7000-star 3D spiral galaxy. Touch the GamePad view to fire bursts. | PPC float maths, additive blending, VPAD touch |
| 3 | Shader Lab | Domain-warped plasma fractal, tunnel, metaballs and a sphere-tracing raymarcher over an infinite lattice, with a pseudo-shader readout on the GamePad. | Heavy per-pixel float maths, second-screen mirror |
| 4 | Input Lab | Buttons, both sticks, multitouch-style drawing canvas, accelerometer, gyroscope, a software 3D cube that tilts with the sensors, rumble on A. | VPAD buttons/sticks/touch/motion/motor, KPAD Pro Controller |
| 5 | Audio | The soundtrack, a live waveform read from the PCM buffer at the AX voice's play offset, a 6-lane step sequencer and lead piano roll, track select, mute and volume. | sndcore2 (AX) voice, LPCM16 looping, SRC, mixer, TV + DRC buses |
| 6 | Stress and Info | A Mandelbrot zoom rendered by three OSThreads, one per PPC core, with a 1 core vs 3 core speed-up readout. Frame timing graph, MEM1/MEM2/heap, scrolling credits. | OSThread affinity on all 3 cores, OSSemaphore, OSGetSystemTime, OSGetMemBound |

## How it works

- **Display.** Scenes render into a 320x180 (or 160x90) CPU framebuffer, upscaled 4x or 8x into the
  TV's OSScreen buffer; the HUD is drawn at native 1280x720. The GamePad screen is redrawn every
  third frame. OSScreen is double buffered: the program writes the back half and flips.
- **Shaders.** GX2 shaders need a shader compiler (CafeGLSL / GSH tooling) that is not available in
  the CI container, so the "shader" scenes are CPU fragment functions evaluated per pixel at reduced
  resolution. GX2 itself is **not used**. This is deliberate scope, not an omission to hide.
- **Music.** `audio.c` holds five tracks as data (scale, chord progression, drum/bass/arp masks, a
  64-step lead line). A step sequencer drives a software synth (pulse and triangle oscillators,
  kick/snare/hat generators, an echo) and renders each 64-step loop to PCM16 on a worker thread
  (core 2). Each loop plays on one AX voice as a looping LPCM16 source at 24 kHz through the TV and
  GamePad buses; tracks swap with a short fade. Each scene has its own track.
- **No libm.** Trig, sqrt and exp are small table/polynomial routines in `util.c`.

## Files

`source/` holds `main.c` (loop, title, menu, auto demo), `gfx.c` (OSScreen layer, primitives, font),
`input.c` (VPAD and KPAD), `audio.c` (sequencer, synth, AX), `util.c` (maths, colour), and one
`sc_*.c` per scene.

## Credits and licence

Original code by MuffinEMU, licensed MPL-2.0 like the rest of the repository. Built with devkitPro's
devkitPPC and wut (see their licences); no third-party code is bundled. No Nintendo code, assets,
music or fonts are used.
