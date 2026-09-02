# Muffin (cemu-ios) — Prioritized Work Backlog

Grounded in `ROADMAP.md` + project memory as of 2026-08-31. Real gaps and real
next steps, not filler — organized by priority tier. Overnight-session prompt:
work down from P0, pick anything unblocked, keep both `origin` (bward-dev1) and
`ci` (kiddreads — the real build repo, see tag-rot notes) in sync, push to a
**new branch** per item (never re-push a branch mid-CI-run), and don't stop for
questions until the 2026-09-01 14:00 check-in.

Repo: `kiddreads/cemu-ios-muffin` is canonical (`git push ci <branch>`).
Current HEAD: `metal-shader-binary-archive`. Target device: iPad Pro 12.9" 4th
gen, A12Z, 6 GB, fanless — no Metal3/mesh shaders, no BC texture formats.

## Progress log (overnight session, 2026-08-31 → 2026-09-01)

Real outcomes as of the 2026-09-01 14:00 check-in and after, so the next session
doesn't re-investigate these. Each is code-verified (compiles clean in CI);
none has been run on a device.

- **#24 fixed** — `metal-buffer-storage-mode-fix` branch: `GetResourceOptions()`'s
  storage-mode check could never match Shared (tested against 0 via `&`), and
  the related `RequiresFlush()` also misidentified Memoryless as Managed.
- **#36-38, #42, #54, #56 done** — `metal-shader-binary-archive` branch: real
  `MTLBinaryArchive`-backed cache for compiled Metal shader binaries, gated by
  the existing Persistent Shader Cache toggle (#56), serialized to
  `shaderCache/precompiled/<id>_mtlbinaries.bin` on title exit, degrades to
  uncached compilation on any failure (#54). Mesh pipelines deliberately not
  archived (#48-49 partially addressed by scoping them out — metal-cpp here has
  no `addMeshRenderPipelineFunctions`, and this device reports
  `SupportsMeshShaders() == false` anyway, so there's nothing to cache there).
- **#57 done** — `ARCHITECTURE.md` now documents which cache is which (merged
  to `main`).
- **#74 confirmed** — `snd_user.cpp`'s "unsupported audio effect" warning is
  genuine upstream Cemu behavior (missing optional `snd_user.rpl`/
  `snduser2.rpl` firmware files), not iOS-specific and not a missing codec path.
- **#122 confirmed** — no ETC2/ASTC/PVRTC reference exists anywhere in
  `Renderer/Metal/` (grepped the whole tree, zero hits), consistent with Wii U
  hardware never using these formats. No incorrect fallback logic to find.
- **#67 confirmed** — `IOSInput_Initialize()` already writes every button AND
  axis override slot across the full `kButtonId_None`..`kButtonId_Max` enum
  range (not just the 16 controls actually exercised) before any title thread
  exists - exactly the write-once-then-safe guarantee the item asked to
  verify. No gap found.
- **#33 fixed** — `metal-shader-compile-failure-logging` branch: each Metal
  shader compile failure now also gets its own file under
  `shaderCache/failedCompiles/`, instead of being buried and truncated in
  log.txt alongside every other line from the session. Purely additive on an
  already-failure path.
- **#124 confirmed** — no reference to Metal argument buffers exists anywhere
  in `Renderer/Metal/` (grepped the whole tree and both doc files, zero
  hits). Genuinely unused, not a still-needed optimization silently skipped -
  there is no code path that could depend on it.
- **#80-84 partially addressed** — `ios-interpreter-thread-qos` branch: CPU-
  emulation scheduler threads now explicitly request
  `QOS_CLASS_USER_INTERACTIVE` instead of inheriting whatever priority they
  happened to spawn at. Real speed lever, zero correctness risk, but the
  actual on-device instructions/sec delta (#80) is still unmeasured.
- **#101-102 already done, #105-107 fixed** — the mmap-PROT_EXEC-first fix
  (#101) and `useProtect()` reporting (#102) were already implemented in
  `AppleJitAllocator` (`BackendAArch64.cpp`) before this session; found that
  `PPCRecompiler_setSurvivedFirstEntryCallback()` — built specifically to fix
  #105's too-early sentinel clear — was never actually registered anywhere, so
  it had been a complete no-op. `ios-jit-sentinel-clear-timing` branch wires it
  up and removes the two premature `ios_jit_survived_boot()` calls that were
  clearing the sentinel the instant a launch was *requested* rather than once
  it *survived*. #104 (on-device re-test) still needs a device.
- **#8-related fixed** — `latte-scan-buffer-drop-per-target-log` branch: the
  "Scan buffer dropped" diagnostic line (named in #8 as a real diagnostic step)
  was keyed by call site via `cemuLog_logOnce()`, so whichever renderTarget
  combination dropped first permanently silenced a later, different one. Same
  bug class as the already-fixed TV/pad-window CAMetalLayer check.
  Now keyed per-renderTarget-combination.
- **#147 confirmed** — `origin` and `ci` remotes carry identical commits on
  every branch present on both (9 checked).
- **#148 confirmed** — the `bward-dev1` phantom queued run (`32984538691`) is
  already `cancelled`/`completed`, not actually stuck.
- **#151 confirmed** — repo-wide sweep for the Fiber.h bug class (a platform
  added to a CMake file-selection condition without updating the matching
  header guard) found no other instance; the one other Android-only
  conditional in `src/input/CMakeLists.txt` is correctly scoped and unrelated
  to iOS.
- **#152 confirmed** — no stray Claude-instruction `.txt` files remain on any
  current branch (both from earlier this session were read and deleted).
- **#153 reviewed, not pruned** — `.claude/worktrees/agent-*` are all stale
  (dated 2026-08-23, based on a pre-merge `main`); spot-checked two with clean
  single commits and confirmed both are already ancestors of current `main`.
  Left in place per "don't silently delete" — safe to prune whenever someone
  wants the disk space back.
- **#154, #158-159 done** — `ARCHITECTURE.md` input/CPU rows corrected (were
  badly stale — input has been wired for a while, the recompiler is not force-
  disabled); `UIFileSharingEnabled` verified surviving a clean v6/v7 release
  build via `PlistBuddy` on the actual downloaded IPA; no other Info.plist key
  found silently dropped by the same Xcode merge quirk.
- **Interpreter audit (3 subagents, full read of the retail/HLE interpreter's
  ALU/SPR, FPU/paired-single, and load-store/dispatch files) — 3 real bugs
  found and fixed, all merged to `main` + `preview/showcase-sneak-peek`:**
  - `mfspr DEC` hit an unconditional `assert_dbg()`/SIGTRAP on every read in
    the retail (Slim/HLE) interpreter — guaranteed crash on an ordinary,
    common instruction. `mtspr DEC` was a silent no-op. Both fixed; `SRAWI`
    also replaced with a verified-equivalent closed-form (perf only, no
    behavior change).
  - `fctiw`/`fctiwz` (float→int convert) relied on C-cast UB for NaN input;
    x86 happens to yield the Power-ISA-correct `0x80000000`, ARM64's `FCVTZS`
    yields `0` instead — silently wrong value, no crash, ARM64-specific.
    `fcmpo`/`ps_cmpo0` had incorrect VXSNAN/VXVC FPSCR flag logic (VXVC was
    spuriously set on ordinary non-NaN compares). All three fixed to match
    real Power ISA semantics.
  - `PPCInterpreter_TW` (trap instruction) could hang the core forever: the
    instruction-pointer advance was gated on `TO != 0`, but `TO=0` is a valid
    no-op encoding (also used by the debugger/gdbstub to inject breakpoints
    via an `rA` marker) — a `TO=0` trap with a non-marker `rA` fell through
    every branch with nothing advancing the IP. Fixed to advance in every
    case except an actual matching debugger marker.
  - Flagged, deliberately NOT fixed (out of scope for tonight, don't affect
    the retail/Slim-HLE path used by real games): inconsistent
    `flushDenormalToZero()` application across paired-single ops; `DSI_EXIT()`
    missing from ~47 of ~50 load/store handlers in the LLE/supervisor+MMU
    interpreter (only reachable via `PPCSchedulerLLE.cpp`, not the retail
    path); `LFS`/`STFS`-family accessors in the same LLE class skip MMU
    translation entirely. All real, all scoped to the unused-tonight LLE path
    — logged here rather than guessed at blind.
- **Root cause of "every WUD/WUX title crashes on launch" found and fixed.**
  Void sent a real crash log (signal 11 in `FSTVolume::FindDiscKey`,
  called from `TitleInfo::Mount` → `ParseXmlInfo` on boot). Traced it to
  `AES128_CBC_decrypt` — a function pointer that starts `nullptr` and is only
  ever assigned by `AES128_init()`, which desktop Cemu calls from
  `main.cpp`'s `CemuCommonInit()`. The iOS bridge never runs
  `CemuCommonInit()`; it hand-picks pieces of it individually (this is the
  same pattern `PPCTimer_init()` already needed and has its own comment
  explaining), and `AES128_init()` was never one of the picks. Result: the
  pointer stayed null for the process's entire lifetime, and the first thing
  to call through it — decrypting a disc header to find the title's AES key,
  on every single WUD/WUX title launch — jumped through address 0. Fixed by
  adding the `AES128_init()` call next to `PPCTimer_init()` in
  `CemuBridge.mm`. This is almost certainly the actual Super Mario 3D World
  crash (and likely every other disc-title crash reported this session) —
  not the WUX sector-bounds issue fixed earlier, which was real but
  defensive-only since this null-pointer call would fire first on any title
  that has a valid WUX index table. Not yet confirmed on-device; going into
  v13.
- **`.elf` import was silently rejected; engine already supported it.**
  Void asked whether `.elf`/`.wuhb` roms work. `.wuhb` already did
  end-to-end. `.elf` didn't, but not in the engine —
  `IOSTitleLaunch_PrepareForegroundTitle` already detects and boots a
  standalone `.elf` exactly like `.rpx` (same as desktop, whose file-open
  filter has always grouped `*.rpx;*.elf` together) — `GameManager.swift`'s
  `supportedROMExtensions` just never included `"elf"`, so the iOS import
  screen rejected the file before it ever reached that code. Added it to
  the allowlist and to `isValidROMFile`'s magic-byte check (reusing `.rpx`'s
  existing ELF signature), and fixed the two UI strings that listed
  supported formats without mentioning `.elf` or the already-working
  `.wuhb`.
- **Real Metal drawable leak found from a `.wuhb` hang report, fixed.**
  Void reported a homebrew title "stays on gx2 forever, with no frames."
  The log showed GX2Init reached fine and the guest CPU genuinely executing
  the whole time (200+ MIPS, real progress) — not a deadlock — but
  `MetalLayerHandle::AcquireDrawable()`'s "failed to acquire next drawable"
  started flooding the log a few seconds in and never stopped, while
  process memory grew from ~350MB to ~2.9GB in under a minute (heading
  straight for a jetsam kill). Root cause: `nextDrawable()` is a Cocoa "get"
  accessor, not alloc/new/copy, so — like `commandQueue()->commandBuffer()`
  in `MetalRenderer::GetCommandBuffer()`, which explicitly retains its
  result for exactly this reason — it returns an object the caller doesn't
  own. `AcquireDrawable()` never retained it, so the pointer was only good
  until the next autorelease pool drain, which can happen before
  `PresentDrawable()` runs given how much rendering happens per GX2 frame
  in between. Presenting (or destroying/moving the handle while holding) an
  already-deallocated drawable never returns the real drawable to
  `CAMetalLayer`'s fixed-size pool, permanently losing a slot each time —
  draining the whole pool within the first several frames. Fixed by
  retaining in `AcquireDrawable()` and releasing in `PresentDrawable()`,
  the destructor, and move-assignment (same ownership pattern `m_layer`
  already uses in this class). Also switched the failure log to
  `cemuLog_logOnce` — once the leak is fixed this can still legitimately
  fail on a title that outruns its swapchain, and the old unconditional
  version fired hundreds of times a second, which is almost certainly why
  several of Void's mailed logs this session read as truncated on
  arrival. Not yet confirmed on-device; going into v14 with the `.elf` fix.
- **Second, related Metal leak found from a real crash log — the shader
  and pipeline compile thread pools.** Void sent a real signal-11 crash
  inside `compileThreadFunc`, memory climbing from 38MB to 961MB in the
  seconds beforehand — the same shape as the drawable leak, different
  subsystem. Root cause: `MetalPipelineCache`'s `compileThreadFunc` (up to
  8 threads) and `RendererShaderMtl`'s `CompilerThreadFunc` (2 threads)
  both run forever on a raw `std::thread` with no run loop of its own, so
  neither ever gets an implicit autorelease pool — and every single compile
  on both pools creates autoreleased objects with nowhere to drain them:
  `NS::Array::array()` for `setBinaryArchives()`, the `NSError*` out-param
  from `newRenderPipelineState()`/`newLibrary()`, and an autoreleased
  `NS::String` from `ToNSString()` on every shader compile (`NS::String::
  string()` is the Cocoa factory convention, not alloc/init). Every shader
  and pipeline compiled during real play leaked, on both thread pools, for
  the rest of the process's life. Fixed by wrapping each unit of compile
  work in its own `NS::AutoreleasePool`, matching the exact per-operation
  pattern `MetalRenderer.cpp`'s `GetCommandBuffer()`/
  `GetTemporaryRenderCommandEncoder()` already use for the same reason.
  Also caught and fixed the same exposure on
  `MetalPipelineCache::GetRenderPipelineState()`'s synchronous compile path
  (runs on the render thread when async compile isn't allowed — same
  missing-pool situation). Not yet confirmed on-device; going into v15.

---

## P0 — M3 blockers (get a real frame on screen)

1. Confirm on-device whether `MetalRenderer: presented the first frame to the TV window (WxH pixels)` fires on current `main` — this is the still-unresolved fork point from ROADMAP M3.
2. If it fires: the geometry defect is next — `MetalViewIOS.makeUIView()` passes `UIScreen.main.bounds` (whole screen) instead of the actual `VStack` middle-region view bounds.
3. Implement the real resize path: expose `MetalRenderer::ResizeLayer()` through the bridge (currently no bridge function calls it).
4. Fix `MetalLayerHandle::Resize()` to update the `CALayer` frame, not just the drawable size.
5. Wire that resize path into rotation events.
6. Wire that resize path into Slide Over / multitasking size-class changes.
7. Verify `CreateMetalLayer()`'s 4-arg points-aware signature is used consistently everywhere a layer is created, not just at init.
8. If the frame does NOT fire: check `Scan buffer dropped: renderTarget=… showDRC=… pad window active=…` in `LatteRenderTarget_itHLECopyColorBufferToScanBuffer`.
9. Check `GX2SwapScanBuffers() reached for the first time` marker in `GX2.cpp` to confirm the title produced a frame at all.
10. For DRC-only titles: wire a UI toggle for `showDRC` (currently only reachable via Tab/VPAD screen button, neither of which exists on iOS).
11. Confirm `IsPadWindowActive()` gating is consistent across every renderer entry point that touches the pad window (per the 2026-08-10 fix note — audit for regressions since).
12. Re-verify `DrawEmptyFrame()`'s magenta-vs-black test on current `main` (v1.22 shipped it; confirm still true after subsequent renderer changes).
13. Confirm position-invariance fix (`Initialize()` on GPU thread, not ctor) still holds for BotW.
14. Confirm same for Mario Kart 8.
15. Confirm same for Bayonetta 1.
16. Confirm same for Bayonetta 2.
17. Confirm same for Star Fox Zero.
18. Confirm same for The Wonderful 101.
19. Confirm same for Mario Tennis Ultra Smash (already reached GX2Init per 2026-08-29 log — good first full-pipeline candidate).
20. Re-run the BC-texture-format fix (`eab9ae73`, shipped v1.33) against a second retail title to confirm it's not title-specific.
21. Re-run it against a third retail title.
22. Confirm no other A12-unsupported Metal call exists outside the already-audited `Renderer/Metal/` tree (check `Renderer/Common/`, bridge glue in `src/ios/`).
23. Audit `CachedFBOMtl`'s `MTL::LoadActionLoad` usage for any code path that skips `ResetEncoderState()` (the audit note says every getter calls it — verify no new getter was added since without the call).
24. Fix the `GetResourceOptions` cosmetic bug (`MetalBufferAllocator.h:12` tests `options & MTL::ResourceStorageModeShared`, which is 0, so it's always false) — Shared buffers never get `CPUCacheModeWriteCombined`.
25. Port the non-mesh geometry-shader path for real (not just RECTS) so titles using actual GS draws don't silently drop them on A12Z — this is the multi-pass-compute branch's real goal.
26. Get `ios-geometry-shader-emulation` onto real hardware — it's compiles-only, never run.
27. If it crashes on first run: check the two-struct MSL split (`GeometryOut` vs `GeometryOutRaster`) compiles correctly for every GS-using title, not just the one used to design it.
28. Verify the `gsPassthroughVS` strip-winding quirk (`set_index()` mapping) actually matches the mesh path's output bit-for-bit on a title that uses both mesh-capable and non-mesh-capable draws in the same frame (there are none on A12Z, but verify against a captured mesh-path reference if one exists from macOS/desktop Cemu).
29. Confirm degenerate triangle/line/point handling doesn't leave stray lit pixels on real UI-heavy titles (lots of RECTS use).
30. Wire telemetry: log a per-frame count of GS-emulated draws vs RECTS-emulated draws vs dropped draws, gated behind the existing debug-overlay toggle.
31. Settings toggle for GS emulation: verify it's read once at renderer init as documented, not re-read mid-session (which would half-bake shaders).
32. Add a CI job that at least compiles the generated MSL for known shader combinations offline (current gap: "CI does not validate the generated MSL — it compiles on-device at runtime").
33. Capture `LibraryFromSource` Force-level failure logs into a persistent, greppable location so a compile failure across dozens of shaders isn't lost in scrollback.
34. Investigate whether the render-pass `memoryBarrier` calls that are currently dead/commented-out (MetalRenderer.cpp ~2396/2407) should be removed entirely now that the design uses ordered compute dispatches instead.
35. Double-check `ResetEncoderState()` ordering holds under the geometry-shader-emulation branch's two-dispatch-per-draw pattern specifically (not just the general case already audited).

## P1 — Shader pipelines & caching ("fancy cached shader pipelines")

This is the live branch (`metal-shader-binary-archive`) and the explicit ask —
go deep here.

36. Finish the `MTLBinaryArchive`-based raw compiled-shader (AIR) cache — flagged in the overnight memory as a known real gap: Metal's upstream raw-AIR cache path is dead/commented-out code, this needs a genuine from-scratch implementation.
37. Design the archive key: hash of (Latte shader bytecode + emitted MSL source + pipeline state: vertex layout, blend state, pixel formats, sample count).
38. Persist the `MTLBinaryArchive` to `Documents/ShaderCache/` (survives app reinstall via LiveContainer's per-app Documents; verify path matches the same LiveContainer-redirected-`$HOME` quirk already documented for the crash log).
39. Version the cache file format — bump on any Cemu engine version bump so a stale archive from an older build never gets loaded against new shader-emission logic.
40. Add cache invalidation on iOS version change (Metal driver/compiler behavior can change across OS updates; a cached binary compiled under one driver may misbehave — or fail to load — under another).
41. Add cache invalidation on device model change if the cache is ever shared via iCloud/file-sharing (it shouldn't cross devices, but guard it).
42. Implement async pipeline-state compilation off the render thread so first-use-of-a-new-shader doesn't hitch the frame.
43. Queue pending pipeline compiles and fall back to a "flat color" placeholder pipeline for the frame(s) where the real one isn't ready yet, rather than blocking.
44. Add a warm-cache pass: on game launch, walk `bin/gameProfiles/<title>` (now that per-title profiles actually load per the 2026-08-18 fix) for a shader-hash manifest and pre-compile in the background before the title reaches its first heavy draw.
45. Expose cache hit/miss/compile-time stats in the existing debug overlay.
46. Add a Settings "Clear Shader Cache" action for when a bad cached binary needs to be nuked (corruption, driver regression).
47. Cap the cache file size and implement LRU eviction so it doesn't grow unbounded across many titles on a 6 GB device.
48. Separate the render-pipeline-state cache from the compute-pipeline-state cache (the GS-emulation branch needs its own compute PSOs cached distinctly).
49. Cache the three GS-emulation-pass pipelines (vertex-as-compute, geometry-as-compute, passthrough-raster) keyed together so a partial cache hit (2 of 3) doesn't silently produce wrong output.
50. Verify `setShouldMaximizeConcurrentCompilation` (already gated on `m_supportsMetal3`, so off on A12Z) doesn't need a manual multi-threaded-compile fallback for non-Metal3 devices — check if `MTLCompileOptions` threading knobs help without it.
51. Add a build-time or first-launch background sweep that compiles the small fixed set of "always needed" shaders (UI blit, clear, RECTS passthrough) synchronously before any title loads, so those are never the ones causing a mid-game hitch.
52. Log every cold pipeline compile with source hash + wall-clock compile time, to build a real dataset of which shaders are expensive.
53. Investigate precompiling common shader *patterns* (not full binaries) — many titles share near-identical UI/RECTS shaders; consider a shared library instead of per-title duplication.
54. Handle `MTLBinaryArchive` serialization failure gracefully (disk full mid-write, corrupted read) — must never crash boot, only skip caching for that session (tie into [[feedback-never-mask-errors-as-data]]-style honesty: log it as a real failure, don't silently pretend the cache is fine).
55. Add a unit/smoke test (host-side, macOS) that exercises the archive save/load round-trip logic before ever touching a device, since CI can't validate on-device Metal compiles.
56. Confirm the existing "Persistent Shader Cache" Settings toggle (merged per the overnight update) actually gates this new binary-archive path once it lands, not just some earlier/simpler cache.
57. Document in `ROADMAP.md`/`ARCHITECTURE.md` which cache is which once both exist, so a future session doesn't conflate "Persistent Shader Cache toggle" with "MTLBinaryArchive AIR cache."
58. Consider a fragment-only micro-cache for the most common blend/format permutations of a single shader, since full PSO recompiles are the expensive path when only blend state differs.
59. Investigate whether pipeline descriptors can be partially reused (same vertex function, varying fragment) to reduce total PSO count needing caching.
60. Add cache warm/cold A-B timing captured to the debug overlay so Void can see the actual perf win on next boot of a previously-played title.
61. Guard against cache poisoning from the not-yet-verified GS-emulation shaders — keep that cache namespace separate until GS emulation is confirmed correct on hardware, so a bad GS shader can't taint the main render-pipeline cache.
62. Add telemetry for cache-file size growth per session, surfaced in Settings, so unbounded growth is visible before it becomes a storage problem on a space-constrained iPad.

## P2 — M4: input + audio (not started)

63. Map on-screen controller skins to Cemu's `src/input` GamePad/Pro Controller emulation.
64. Map MFi controllers to the same input layer.
65. Map Bluetooth controllers (non-MFi, if any relevant class exists) similarly.
66. Finish the stick-axis path: confirm `setAxisValue()`'s four 0..1 direction split + `get_axis()` recombination doesn't lose precision at edge values.
67. Fix the `m_overriddenAxisMappings` atomic-insertion race properly — confirm every slot really is written once in `IOSInput_Initialize()` before any title thread exists, across all 16 controls, not just the ones exercised so far.
68. Add a regression test/log-assertion that would have caught the "stick press does nothing" silent-discard bug class if it recurs elsewhere.
69. Resolve the still-open pad-color question (grey-like-reference vs current skin colors on d-pad/A/B/X/Y) — needs Void's call, flag it, don't invent an answer.
70. Verify joystick-mode replacement of the whole left cross (dot included) behaves correctly when switching modes mid-session, not just at launch.
71. Verify L3/R3 dot behavior in d-pad mode still works after any pad-layout changes.
72. Re-measure `IMG_3278.jpeg` against current `ControllerLayout.swift` constants after any pad-related commit — regression-check the "reproduce to within 1px" invariant per [[cemu-ios-pad-layout-is-measured]].
73. Wire a CoreAudio backend into Cemu's audio subsystem (currently unimplemented per ROADMAP M4).
74. Confirm the `snd_user.cpp:1070` unsupported-audio-effect warning (seen in the jetsam investigation log) is cosmetic and doesn't indicate a missing audio codec path.
75. Test audio latency once CoreAudio lands — Wii U audio timing assumptions may not map cleanly to iOS's audio session model.
76. Handle iOS audio session interruptions (phone call, Siri, another app) without crashing or leaving audio desynced.
77. Handle iOS audio route changes (headphones plugged/unplugged, AirPlay) gracefully.
78. Confirm haptics (if any are planned for button feedback) don't fight with the audio session.
79. Exit-test M4 for real: move a character AND hear sound simultaneously on the same run, on a title that isn't homebrew.

## P3 — Performance & M5 (playability)

80. Profile the single-core interpreter's actual instructions/sec on-device (baseline needed before any optimization claims).
81. Investigate whether the multi-core interpreter path (now that the Fiber sizing bug is fixed in v1.28) is safe to re-enable and measure its real perf delta.
82. Re-run the original "0 instr / 3 cores at 0x00000000" repro now that both the fiber-sizing bug and the JIT-probe crash-loop are fixed, since neither fix has been credited as the actual cause yet.
83. Once JIT's SIGBUS is fixed (see P4), benchmark JIT vs interpreter on the same title/scene for a real before/after number.
84. Investigate thermal throttling behavior specifically on this fanless A12Z under sustained 3-core interpreter load — the target-device memory already flags this as a real risk, not yet measured.
85. Add a low-power / thermal-state visible indicator so Void can tell throttling from an actual bug when frame rate drops.
86. Reduce `LatteBufferCache_init`'s fixed 164 MB allocation if a smaller working set is viable — flagged as a leading footprint-reduction candidate for the jetsam investigation.
87. Investigate whether the increased-memory-limit entitlement can be added safely despite SideStore stripping entitlements at signing time — find a signing path (or a build variant) where it survives.
88. If the entitlement can't be made to survive, prioritize footprint reduction over it as the signing-independent fix.
89. Read the tail of `CemuCrashLog.txt` after a jetsam-suspected crash per the existing instrumentation (10 Hz `os_proc_available_memory`/`phys_footprint` sampler) — confirm on a fresh device run whether ample headroom exists or jetsam is truly the killer.
90. If jetsam is confirmed: instrument per-subsystem memory (texture cache, shader cache, buffer cache, MEM2 emulation) to find the real biggest consumer instead of guessing.
91. If jetsank is NOT confirmed: shift full attention to the Metal renderer's untested GX2 path per the existing note.
92. Implement save states through the iOS sandbox (M5, not started).
93. Implement persistent saves through the iOS sandbox (distinct from save states — actual game save data).
94. Test save/load round-trip survives a LiveContainer app reinstall (given the earlier LiveContainer-destroys-executable and Documents-redirection quirks, this is a real risk area, not a formality).
95. Stability-harden the JIT-enabled path specifically for SideStore.
96. Stability-harden the JIT-enabled path specifically for LiveContainer.
97. Investigate StikJIT as a third JIT-enabler path and confirm behavior parity/differences.
98. Add a startup self-check that reports which JIT-enabler (if any) is attached and whether `CS_DEBUGGED` is actually set, surfaced in the UI rather than only the log — reduces "my JIT setting didn't take" confusion.
99. Add render-scale options and confirm they don't regress the already-fragile Metal layer sizing work from P0.
100. Investigate frame pacing / vsync behavior on the fanless device to avoid needless GPU churn beyond display refresh rate.

## P4 — JIT correctness (real, currently-blocking bug)

101. Fix the SIGBUS root cause: switch to `PROT_EXEC` at `mmap` time and never `mprotect` afterward, per the diagnosed fix direction.
102. Implement `useProtect() == false` reporting so Xbyak's `ready()` skips both `setProtectMode` calls (`xbyak_aarch64_gen.h`).
103. Confirm `AppleJitAllocator` is updated consistently everywhere it currently does the RW-then-promote pattern, not just the one call site that crashed.
104. Re-test on-device with a JIT enabler attached after the fix — first real target is getting past `PPCRecompiler_attemptEnter` without signal 10.
105. Fix the crash-sentinel timing bug: `ios_jit_survived_boot()` currently clears `jit_enabled_boot_did_not_finish` at title-launch, ~3s before generated code is ever entered — move the clear to after control returns alive from generated code.
106. Add a regression test/log-assertion for sentinel timing so "JIT crashes no matter what" (caused by the sentinel re-arming JIT every launch instead of catching the real crash) can't silently recur.
107. Once both fixes land, do a full clean-state test: sentinel should read "boot did not finish" exactly once, on the run that actually crashes — not on every run.
108. Confirm the earlier finding (macOS `mmap MAP_JIT` accepting plain RW, vs plain RWX failing EACCES) is documented clearly enough that no one re-ports a macOS JIT result to iOS by mistake — add an explicit comment at the iOS JIT allocator site citing the divergence.
109. Investigate whether `dynamic-codesigning` entitlement (as opposed to a debugger-attach JIT enabler) is viable for a distribution path, and what its real availability constraints are for a sideloaded app.

## P5 — Compatibility triage (concrete titles + formats)

110. Build a running compatibility matrix doc: title, furthest milestone reached, last log line, date tested, build sha (use the `Init Cemu <sha>` line as ground truth per the tag-rot memory, never the release tag).
111. Add BotW to that matrix once P0 frame work lands.
112. Add Mario Kart 8.
113. Add Bayonetta 1.
114. Add Bayonetta 2.
115. Add Star Fox Zero.
116. Add The Wonderful 101.
117. Add Mario Tennis Ultra Smash (furthest-progressed retail title so far — good weekly regression candidate).
118. Add at least one DRC-only title once the `showDRC` toggle (P0 item 10) exists, to specifically test that path.
119. Keep `helloworld.rpx` and `rainbow.rpx` in the matrix as the known-good homebrew baselines (never mistake their "boots but draws nothing" / "OSScreen-only" behavior for a regression).
120. Add a homebrew RPX that actually draws geometry (ROADMAP flags this as still missing — needed to close M3 for real, since helloworld draws nothing).
121. For every title added to the matrix, capture and store its `CemuCrashLog.txt` tail alongside the entry, not just a pass/fail.
122. Audit texture-format coverage beyond BC/DXT — confirm ETC2/ASTC aren't silently needed anywhere in the retail path (Wii U doesn't use these, but verify no incorrect fallback logic assumes them).
123. Audit multi-sample (MSAA) texture handling now that "explicit MSAA sample counts" was noted as unused — confirm that's intentional and not a missing feature silently no-op'ing.
124. Confirm argument buffers really are unnecessary for correctness (noted as unused) rather than a still-needed optimization being skipped.
125. Confirm `MTLHeap` really is unnecessary rather than a real memory-pressure mitigation being left on the table (ties to P3's jetsam work).

## P6 — Repo, CI, and process hygiene (real debt, not busywork)

126. Audit every stale branch for merge status: `ios-bundle-data-files`.
127. `ios-launch-log-overlay`.
128. `ios-livecontainer-resilience`.
129. `ios-controls-custom`.
130. `ios-controls-on-extras`.
131. `ios-gamepad-clone-layout`.
132. `ios-launch-intro`.
133. `ios-tv-window-presentation`.
134. `ios-console-logging-and-layer-ownership`.
135. `ios-coreaudio-backend`.
136. `ios-v137-base`.
137. `ios-v137-controls`.
138. `ios-v137-extras`.
139. `ios-v138-renderer-restore`.
140. `ios-vulkan-moltenvk`.
141. `ios-audio-and-renderscale`.
142. `fix-confirmed-render-bugs`.
143. `fix-ios-log-format-crash`.
144. For each of the above: either merge to `main`, document why it's intentionally parked, or delete it — don't leave "is this live work or dead?" ambiguous for the next session.
145. Fix the underlying tag-rot problem for real: re-point `kiddreads/` release tags at the commits their IPAs actually built from, per the queued-but-not-done fix noted in memory.
146. Once tags are fixed, add a CI step that refuses to publish a release whose tag doesn't match `headSha` of the build that produced its asset — prevents the whole class of bug from recurring.
147. Reconcile `origin` (bward-dev1) vs `ci` (kiddreads) branch divergence — confirm both remotes carry the same commit for every "live" branch, not just `main`.
148. Investigate the `bward-dev1` phantom queued run (`32984538691`) — confirm it's still inert or clean it up if the API now allows cancelling it.
149. Harden every build-watcher script to the three-way success/cancelled/failed case (per the CI-cancel memory) — audit beyond the one script already fixed for the same bug pattern.
150. Add a "still the newest run on this branch" check before any watcher mails a build link, per the same memory's stated fix.
151. Grep the whole tree once more for any other place a platform is added to a CMake condition without its header twin (the Fiber.h bug's general lesson) — the fiber one is confirmed fixed, but a repo-wide re-sweep after any new CMake edits is cheap insurance.
152. Clean up the leftover instruction/trash files that have shown up in commits before (e.g. "Create Read contents of this please then delete this and rerun Claude thanks.txt" — confirm no similar stray file exists on any current branch).
153. Review the `.claude/worktrees/agent-*` directories left in the local checkout — confirm each is either active work or safe to prune, don't silently delete anything that might be another session's in-progress worktree.
154. Update `ARCHITECTURE.md` to reflect the current true state of M3 (partially blocked on layer sizing) rather than any stale earlier description.
155. Update `STATUS.md` similarly.
156. Re-check `docs/_archive_original_claims/` periodically to confirm nothing there has been mistakenly treated as current status by a future session skimming docs.
157. Confirm the `.muffinlyt`/`.muffinclr` Uniform Type registration (already landed) doesn't collide with any other app's UTI on a shared device.
158. Verify `UIFileSharingEnabled` fix (landed per overnight memory) actually survives a clean release build, not just the branch it was tested on.
159. Sweep for any other Info.plist key that's silently dropped between source and shipped bundle the same way `UIFileSharingEnabled` was.

## P7 — Polish / UI / lower-priority features

160. Finish the movable-groups / Fit-vs-Native display mode work's edge cases in Slide Over specifically (already mostly done per recent commits — verify no regression from later renderer changes).
161. Re-verify no cluster overlap regression in portrait after any pad-layout change (previously fixed, easy to silently reintroduce).
162. Add a visible build/commit-sha readout in the app's own UI (not just the log) so Void can confirm what he's running without pulling a device log — directly addresses the tag-rot confusion class at the UX layer.
163. Add an in-app "copy crash log" or "share crash log" action so `CemuCrashLog.txt` doesn't require manual Files-app archaeology through the LiveContainer path quirk.
164. Add an in-app shader-cache-status view (ties to P1) showing cache size and last-clear date.
165. Investigate a pause/resume-friendly shader-cache flush point so backgrounding the app doesn't lose in-flight compiles.
166. Revisit the still-open pad-color design question with Void rather than guessing (surface it, don't resolve it silently).
167. General pass: anywhere `cemuLog_logOnce()` keys on call site rather than per-window/per-context (the same bug class that hid the TV-window frame evidence) — audit for other call sites with the same flaw.
168. Consider exposing the per-frame GS/RECTS/dropped-draw counters (P0 item 30) in the visible debug overlay, not just the log.
169. Consider a lightweight in-app FPS + frame-time overlay toggle for perf work in P3.
170. Documentation pass: fold this backlog's outcomes back into `ROADMAP.md`'s per-milestone checkboxes as items land, so the roadmap stays the single source of truth rather than drifting from this file.

---

**Note on scope:** this is the honest, real engineering backlog derivable from
the actual repo and project memory today — 170 concrete, non-duplicate items
across every open subsystem, not a padded list stretched to a round number.
Treat it as a priority-ordered pool: work top-down within a tier, skip an item
only if it's genuinely blocked (needs Void's call, needs on-device
confirmation you can't get), and log what you tried even when a device test
can't be run tonight — a written dead-end is worth more to the next session
than a silently skipped line.
