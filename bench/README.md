# MuffinEMU Bench

A single iOS app that benchmarks all three Wii U emulator engines under evaluation -
`muffin-v38`, `melocafe`, `muffin-v38-melofixes` - back to back, in one process, one run,
and prints one plain-text report meant to be copied straight into a chat.

## What it measures

For each engine, in the fixed order above:

1. **cpu_interpreter** - `cpubench.rpx` run on the single-core interpreter.
2. **cpu_recompiler** - `cpubench.rpx` run on the single-core recompiler, only if
   `mbench_jit_permitted()` is true for this process (same answer for every engine, since
   it depends on whether iOS granted the process `CS_DEBUGGED`, not on which engine is
   loaded). Skipped and recorded as such otherwise.
3. **gpu_renderer** - `gpubench.rpx` on the Metal renderer, CPU mode following the same
   permitted/not-permitted rule as above.

Each test is 3 independent fresh-boot attempts (`mbench_shutdown` is never called
mid-test, but `mbench_stop_title` + `mbench_boot` run again for every attempt). The
report's numbers are the median across whichever attempts completed, with the min-max
spread shown alongside.

## Method

The host never times anything itself beyond wall clock. It boots the RPX, then tails the
file `mbench_log_path()` returns and watches for the guest's own markers:

```
MUFFINBENCH BEGIN <test> <n>
MUFFINBENCH END <test> <checksum>
MUFFINBENCH DONE
```

A sub-test's duration is the host's own monotonic-clock timestamp at the moment it reads
the `END` line minus the timestamp at the moment it read the matching `BEGIN` line. For
`gpu_renderer`, `mbench_frame_count()` is also sampled by the host at both of those
moments, so frames and fps come from the same measurement, not from anything the guest
reports about itself. Every engine is driven through this exact same code - no per-engine
special cases - so a timing difference in the report is the engine, not the harness.

Between engines, and before starting one that's overdue, the app checks
`ProcessInfo.thermalState` and waits (up to 180s) for the device to cool back to
`.nominal`/`.fair` rather than letting one engine's heat throttle the next engine's
numbers. It also measures 5 seconds of this process's own idle CPU right before loading
each engine - a nonzero number here means a *previous* engine left threads spinning after
`mbench_shutdown()`, which iOS can't clean up by itself since it never unloads a
`dlopen`'d framework.

## Isolation checking

All three engine frameworks export the same `mbench_*` symbol names on purpose (that's
the whole point of `MuffinBenchEngine.h`). Only one engine is ever `dlopen`'d with
`RTLD_LOCAL` at a time, and every call goes through that specific `dlopen` handle's own
`dlsym` results - never `RTLD_DEFAULT`, which would let dyld silently route every
engine's calls to whichever engine's image happened to define the symbol first.

The header's `-fvisibility=hidden` / `-exported_symbols_list` build requirement only
constrains the C `mbench_*` functions. It does not stop an engine's ObjC++ code from
vending an ordinary Objective-C class whose name collides with another engine's - the
Objective-C runtime registers classes globally regardless of `dlopen`'s `RTLD_LOCAL`, so
a name two engines both define is a real, silent isolation failure (the runtime keeps
whichever definition registered first). The app checks for this: right after loading each
engine it asks the Objective-C runtime what classes that engine's Mach-O image defines
(`objc_copyClassNamesForImage`, keyed off the exact path `dyld` itself reports for that
image), and any class name shared by more than one loaded engine is called out by name in
the report's Notes section.

## Report layout

```
MuffinEMU Bench Report
=======================
App:      1.0 (build 1)
Date:     2026-09-14T18:04:00Z
Device:   iPad8,6 / iOS 15.8.1
RAM:      5.83 GB
JIT:      permitted

Engines
-------
[1] muffin-v38 - Muffin v3.8 (restore)
    commit:         53e77328
    framework load: ok
    thermal start:  fair (waited 0s to settle)
    idle CPU (5s):  1.2%
    cooldown after: 30s
[2] melocafe - MeloCafe
    framework load: FAILED - dlopen(.../MuffinBenchMelo.framework/MuffinBenchMelo) failed: image not found

CPU - interpreter
-----------------
sub-test     muffin-v38                 melocafe    muffin-v38-melofixes vs base
int_mix      1.203s (1.190-1.220)       skipped     1.055s (1.041-1.070)  1.14x
mem_copy     0.884s (0.879-0.891)       skipped     0.792s (0.788-0.799)  1.12x

Checksums
---------
  [cpu_interpreter] int_mix: OK - all engines agree
  [cpu_interpreter] mem_copy: MISMATCH
      muffin-v38: a1b2c3d4
      muffin-v38-melofixes: 9f8e7d6c

Notes
-----
- melocafe: did not run - dlopen(.../MuffinBenchMelo.framework/MuffinBenchMelo) failed: image not found

Method: identical cpubench.rpx / gpubench.rpx per test, identical MUFFINBENCH
BEGIN/END/DONE markers, wall clock measured host-side from log timestamps at the
moment each marker line is read, 3 fresh-boot runs per test, reported values are
median (min-max) across the runs that completed.
```

(Real output has one such table per test - CPU interpreter, CPU recompiler, GPU renderer
- and every sub-test the guest actually reported, not just the two shown above.)

## Building

```
cd bench
xcodegen generate
open MuffinEMU\ Bench.xcodeproj
```

Requires, before `xcodegen generate` runs:
- `../build-bench/engines/MuffinBenchV38.framework`
- `../build-bench/engines/MuffinBenchMelo.framework`
- `../build-bench/engines/MuffinBenchV38Melo.framework`
- `../dependencies/MoltenVK.xcframework`
- `../build-bench/rpx/cpubench.rpx` and `../build-bench/rpx/gpubench.rpx`

Each engine framework must be built with `-fvisibility=hidden
-fvisibility-inlines-hidden` and `-Wl,-exported_symbols_list,<file>` listing exactly the
`mbench_*` symbols from `MuffinBenchEngine.h` - see that header for why.

## Installing and running

Same constraints as MuffinEMU itself: this needs a JIT enabler to get anything out of the
`cpu_recompiler` test or a JIT-backed `gpu_renderer` run.

- **SideStore / LiveContainer** - sideload the IPA, then launch it through
  StikDebug/SideStore's JIT-enable flow (or LiveContainer's own JIT toggle) before tapping
  Start. Without that, `mbench_jit_permitted()` is false for every engine and the report
  will show `cpu_recompiler` skipped across the board - that's the harness working
  correctly, not a bug.
- **TrollStore** - installs with `CS_DEBUGGED`-equivalent trust already in place; no
  separate JIT-enable step is needed before Start.

`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` mean
`Documents/MuffinBenchResults.json` is reachable from the Files app under the app's own
folder after a run, independent of the in-app "Copy report" / Share buttons.
