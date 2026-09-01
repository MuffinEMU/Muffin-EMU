# rainbow.rpx

A homebrew Wii U test rom whose entire job is to be impossible to confuse with a black
screen.

## Why

Graphics testing on this port kept producing an ambiguous result. `helloworld.rpx` is
the designated test rom and there is nothing wrong with it, but a black screen while it
runs means either "the emulator never drew" or "the rom drew nothing worth seeing", and
the logs looked identical either way. v1.19's magenta empty frame settled half of that:
magenta means the Metal path is alive. This rom settles the other half by putting a very
large amount of very loud colour on the glass.

## What it does

1. Flashes the full screen through red, orange, yellow, green, blue, indigo and violet -
   twice, on both the TV and the GamePad.
2. Then draws `hello world!` in rainbow neon letters, each letter a different hue, with
   the hue drifting slowly, forever.

## How to read the result

| What you see | What it means |
| --- | --- |
| Rainbow flashes, then neon letters | The whole chain works: PPC execution, coreinit HLE, OSScreen scanout, Latte, Metal, presentation. |
| Rainbow flashes but no letters | Clears and presentation are fine; `OSScreenPutPixelEx` is where it breaks. |
| One flat colour, no cycling | It got as far as a single clear and stopped. |
| Magenta | The emulator's own empty frame. The rom never drew. |
| Black | Neither the rom nor the emulator's empty-frame clear ran. |

A low frame rate in the neon phase is expected, not a bug - per-pixel drawing goes
through an HLE call each time and there is no working recompiler on iOS yet.

## Deliberate design choices

**No ProcUI / WHBProc.** wut's `helloworld` sample uses `WHBProcInit()` and loops on
`WHBProcIsRunning()`. If ProcUI is incompletely implemented, that returns false on the
first iteration, the rom exits before drawing, and the screen stays black - which looks
exactly like a broken renderer. This rom touches nothing but coreinit and loops
unconditionally, so it cannot fail that way. The cost is no HOME-menu exit: close the
app to stop it.

**OSScreen, not GX2.** OSScreen is what homebrew actually uses, it is scanned out by
`LatteThread_HandleOSScreen()` on a path entirely independent of `GX2SwapScanBuffers()`,
and it is the shortest route from "PPC code ran" to "pixels".

**Its own 5x7 font.** `OSScreenPutFontEx` has a built-in font, but draws in a fixed
colour with no way to ask for another one, which rules it out for a rom about colour.

## Building

Not built locally - there is no Wii U toolchain on the dev machine. Run the
**Build Rainbow Demo RPX (Homebrew)** workflow, which builds it in the official
`devkitpro/devkitppc` container against wut's own sample Makefile.
