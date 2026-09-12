# Desktop Cemu → Muffin-iOS feature parity

Grounded in the actual source tree (this repo IS Cemu, forked — desktop's real
feature surface is still sitting in `src/gui/wxgui/`, `src/Cafe/`, `src/Cemu/`,
`src/input/`), checked against what `src/ios/App/*.swift` actually exposes to
the user. Not a guess at what emulators typically have — every entry below
points at a real file. Where iOS's own README/STATUS/ROADMAP disagree with the
code (they're stale — still describing M1/M2 as in-progress when this session
alone shipped decrypt/WUA, memory fixes, dark mode, and more), the code wins.

**How this doc is organized:** four buckets, roughly cheapest-to-most-expensive.
Within each bucket, entries are grouped by desktop source area.

> **Correction, 2026-09-10 (documentation-only reality check, no code changed):**
> two entries below were overtaken by work that landed within hours to a few
> days of this doc being written and were never followed up here. **Graphics
> packs** (bucket 2) got a real Settings UI on 2026-09-04 (`6c063087`, the same
> day as this doc's own `b61d4ff2` commit) — `LoadAll()` is now called and
> Settings > Library > Graphic Packs lists/toggles what's in
> `Documents/mlc/graphicPacks/`. **DLC and Update import/management** (bucket 3)
> was built in full over 2026-09-04/05 (`83a94e4c` through `fbcff902`): title-ID
> derivation and matching, an import flow with a manual-match picker, discovery
> of already-installed content at launch, and removal via long-press — see
> `docs/MUFFIN_WORK_BACKLOG.md`'s own correction block for the commit list. Both
> entries are left in place below with an inline note rather than moved, so the
> bucket structure and rough counts stay traceable to what this doc originally
> found; treat the inline notes as authoritative over the bucket they still sit
> in.

---

## 1. Already have it

Real desktop features iOS already covers, confirmed by reading both sides.

- **CPU mode (interpreter/recompiler)** — desktop: general settings CPU tab.
  iOS: `SettingsView.swift` "CPU" section, `muffin.cpu.recompiler` toggle.
- **Emulated clock / timebase scale** — desktop: implicit in CPU timing.
  iOS: explicit "Emulated Clock" section with `TimebaseScale`, legacy-timebase
  toggle — iOS actually goes further here (desktop has no user-facing clock
  speed dial).
- **Shader cache (compiled + transferable)** — desktop: `GeneralSettings2.cpp`
  shader cache options. iOS: "Shader Compilation" section, async compile
  toggle, persistent cache toggle, clear-cache actions, cache size readout.
- **Render scale / VSync / frame pacing** — desktop: graphics settings.
  iOS: "Performance"/"Rendering (Experimental)" sections — render scale,
  vsync, frame stretch, reduce-encoder-splitting (an iOS-specific dial with
  no desktop equivalent, going the other way).
- **Per-game overrides (partial)** — desktop: `GameProfileWindow.cpp` +
  `src/Cafe/GameProfile/GameProfile.cpp`, a broad per-title config file.
  iOS: `PerGameSettingsStore` (referenced from SettingsView) covers
  shader-precompile and encoder-splitting per game — real, but a narrow
  slice of what desktop's GameProfile actually stores (see §3).
- **Controller layout customization** — desktop: fixed keyboard/gamepad
  binding UI. iOS: per-button drag/pinch, cluster drag, Grouped/Individual
  editing mode, layout export/import (`.muffinlyt`) — iOS's touch-first
  layout system is arguably *more* flexible than desktop's here, just a
  different kind of customization (position/size vs. key-remap).
- **Colour/skin customization (preview)** — desktop has no equivalent at all
  (no re-skinnable pad UI). iOS: colour export/import (`.muffinclr`),
  preview pad system — iOS-only, not a parity gap, noted for completeness.
- **Key import (`keys.txt`)** — desktop: config file drop-in, no dedicated
  UI. iOS: explicit "Wii U keys" import/remove UI — iOS does this *better*
  (a real onboarding step where desktop just expects a file to exist).
- **Decrypt-to-folder / decrypt-to-WUA** — no direct desktop GUI equivalent
  (desktop works from already-decrypted or pre-owned dumps), but iOS's
  version is a genuine, working feature covering ground desktop doesn't
  need to (sideloaded titles arriving encrypted). Not a gap either way.
- **Device/GPU diagnostic report** — desktop has no single "copy my specs"
  action; iOS's device-report-with-copy-button is net-new and, if anything,
  ahead of desktop for bug-report ergonomics.

## 2. Backend exists, needs iOS UI only (cheap)

The C++ engine already implements these; nothing on the iOS Swift side
reaches them. This is the cheapest bucket — no engine work, just wiring.

- **Graphics packs** — **DONE as of 2026-09-04 (`6c063087`), corrected
  2026-09-10; no longer a gap.** `src/Cafe/GraphicPack/GraphicPack2.cpp` (+
  `GraphicPack2Patches*.cpp`) is a complete, working mod/texture-pack engine:
  loads pack definitions, applies shader/texture patches, per-pack
  enable/disable. Desktop UI: `GraphicPacksWindow2.cpp` (718 lines — pack
  list, per-pack toggle, download manager). iOS now has Settings > Library >
  Graphic Packs, listing `Documents/mlc/graphicPacks/` with a per-pack toggle
  persisted through the same `graphic_pack_entries` config desktop reads —
  the fix was calling `LoadAll()`, which iOS never did, so `GetGraphicPacks()`
  was always empty even though `CafeSystem.cpp` already activated packs
  unconditionally on every boot. Preset selection is still not exposed (a
  pack activates with whichever preset was already default), and packs
  using geometry shaders or RECTS won't render correctly on this hardware
  until the compute-emulation work in `STATUS.md`/`ROADMAP.md` M3 is finished
  — said so in the UI. This is graphics *mods* (community texture packs, aspect
  ratio fixes, FPS unlocks per game) — a real, popular desktop feature with
  no iOS surface at all. Feasible on iOS: yes, packs are just files in a
  known folder structure (`graphicPacks/`) — the constraint is *importing*
  pack files into the app sandbox (via the Files-app import flow already
  built for ROMs) and a simple per-pack toggle list, not new engine code.
  `DownloadGraphicPacksWindow.cpp`'s auto-download-from-repo behavior is a
  separate, lower-priority piece — App Store review risk if it fetches
  arbitrary community code/shaders at runtime, worth a deliberate call
  rather than a default port.
- **Title/storage manager** — `TitleManager.cpp` (907 lines): list every
  installed base/update/DLC title, storage used, uninstall, "open folder."
  iOS's game browser lists base titles only; there's no per-title DLC/update
  breakdown or storage accounting anywhere. **Narrower update, 2026-09-10:**
  "Uninstall DLC"/"Uninstall Update" itself now exists (long-press context
  menu, checked live against `Documents/mlc`, see the entry below) — what's
  still missing is the dedicated manager screen this bullet is actually
  about: a storage-accounting breakdown and an "open folder" action. Still a
  real gap, just a smaller one than before.
- **DLC/update install matching (see full writeup below)** — **DONE as of
  2026-09-04/05, corrected 2026-09-10.** The matching logic was already
  proven correct on desktop, as this entry says, and the gap it names — "the
  iOS import flow and UI" — is now built. See the corrected entry in bucket 3
  above for the commit range.
- **Multiple Wii U user accounts** — `src/Cafe/Account/Account.cpp` — real
  account emulation (save-data segregation per account slot). iOS: no
  account-switching UI found anywhere in SettingsView or elsewhere; presumably
  always runs as a single default account. Cheap to expose (a picker), but
  lower value for a single-user-per-iPad device than it is on a shared living
  room console — worth asking whether this is wanted before building it.

## 3. Fully missing, feasible

Real gaps with a clear, buildable path on iOS.

- **DLC and Update import/management (Void's plan, items 2-4)** — **DONE as
  of 2026-09-04/05 (`83a94e4c` through `fbcff902`), corrected 2026-09-10; no
  longer a gap.** Built in full: title-ID-based base/update/DLC matching
  (`cemu_bridge_derive_content_title_id` and friends, using the same bit
  arithmetic desktop's `TitleIdParser` already proves correct — see the
  writeup below, which is otherwise still accurate), an import flow from both
  a game's long-press menu and the general import menu (with a manual
  "which game is this for" picker when auto-match fails), discovery of
  already-installed DLC/update at launch so a base game no longer boots
  unpatched, and removal via long-press. The matching logic and the general
  shape of the writeup below held up; what was missing was purely the iOS
  wiring, exactly as this doc predicted.
- **Per-game profile depth** — desktop's `GameProfile.cpp` stores far more
  than iOS's current per-game slice: per-game CPU mode override, per-game
  graphics-API-level tweaks, per-game controller profile. iOS has the
  *pattern* already (`PerGameSettingsStore`, a `Codable` overrides struct
  keyed by game ID) — extending it is additive, not architectural.
- **In-game DLC/Update active toggles (plan item 4)** — no desktop
  equivalent exists as a *toggle* (desktop's model is install = active,
  uninstall = inactive; there's no "installed but disabled" state in
  `TitleInfo`/`CafeSystem` as far as this read found). This may be a genuine
  new capability neither platform has today, not a port — worth flagging to
  Void directly rather than assuming the engine already supports
  selectively disabling installed AOC/update content at boot. Needs a real
  design conversation, not just iOS wiring.
- **Structured import diagnostics (plan item 5)** — desktop's install path
  (`GameUpdateWindow::ParseUpdate`, read above) already produces distinct,
  specific outcomes (type mismatch, already-installed-same-version,
  already-installed-newer-version, insufficient space) as dialog boxes.
  Porting the *logic* is straightforward; the gap is that iOS's current
  import error surface (`GameManager.ROMImportError`) is generic by
  comparison and would need the same case-by-case treatment plumbed through.
- **First-run onboarding** — desktop: `GettingStartedDialog.cpp`. iOS has no
  equivalent walkthrough (keys, JIT enablement, folder visibility are all
  things this session's mail thread shows Void *personally* re-discovering
  each time — a real, felt gap, not a hypothetical one).

## 4. Fully missing, questionable feasibility on iOS

Real desktop features where porting as-is doesn't make sense on this platform.

- **Alternate controller backends** (`src/input/api/DirectInput`, `XInput`,
  `GameCube` adapter, `Wiimote`, `DSU` motion server) — these are
  Windows/Linux/desktop-USB-peripheral APIs with no iOS equivalent; iOS's
  real path is MFi/Game Controller framework + touch, which is a different
  implementation, not a port. Not a gap so much as a different, already-
  address platform requirement — worth a line in the doc so nobody assumes
  it's simply unbuilt.
- **Motion controls** (`src/input/motion/`, Wiimote-style gyro) — technically
  portable (iPhones/iPads have real gyros), but there's no physical Wiimote
  shape to point it at; only relevant to a handful of Wii-U titles with
  actual Wiimote support (rare — most Wii U titles use the Gamepad or Pro
  Controller). Low value, real but narrow feasibility.
- **Discord Rich Presence** (`src/Cemu/DiscordPresence/`) — Discord's iOS
  SDK doesn't expose an equivalent "what game are you playing" surface the
  way desktop Discord does; would need Discord's specific mobile presence
  API if one exists, not a straight port. Low priority, cosmetic.
- **Cemu self-update checker** (`CemuUpdateWindow.cpp`) — actively wrong to
  port as-is: iOS distribution is sideloading/TestFlight, not an in-app
  updater fetching binaries. The *concept* (tell the user a new build
  exists) could map to a "check GitHub releases" notice, but that's a
  different feature wearing the same name, not a port.
- **Debug tool suite** (`MemorySearcherTool.cpp` — a cheat-search/memory-
  editor tool, `ChecksumTool.cpp`, `AudioDebuggerWindow.cpp`,
  `PadViewFrame.cpp`) — genuine desktop developer tools. Technically
  portable, but this is a kid-facing consumer app (per the project's own
  brand/audience), and a live memory editor in particular is a strange fit
  for that audience without a clear ask for it. Flagging rather than
  recommending against — Void may want the input-debugging value
  (`PadViewFrame` equivalent would help diagnose the pad-layout bugs this
  session hit repeatedly) even if a cheat-search tool isn't wanted.

---

## DLC/Update matching: the real mechanism (feeds plan items 2-4 directly)

Void's plan worried about "if Muffin cannot confidently identify the
matching game, prompt the user." Reading `src/Cafe/TitleList/TitleId.h`: this
mostly isn't a fuzzy-matching problem. A Wii U title ID is a 64-bit value
where the type (base game / update / DLC / demo / system) lives in one byte
and the *rest of the ID is shared* across a base game and its own
updates/DLC:

```
base game:  00050000-11223344
its update: 0005000E-11223344   (type byte 0x0E, same low bits)
its DLC:    0005000C-11223344   (type byte 0x0C, same low bits)
```

`TitleIdParser::MakeTitleIdWithType()` already does this conversion in both
directions (`GetType()`, and turning an update ID back into its base-game
ID) — this is exactly what desktop's own `GameUpdateWindow::ParseUpdate`
(`src/gui/wxgui/GameUpdateWindow.cpp`) uses to find where an update installs
to. So "automatically identify the appropriate base game" on iOS is: parse
the imported content's title ID, mask off the type, look for a base title
in the library with the same masked ID. That's a deterministic lookup, not
a guess — the "prompt the user to select manually" fallback in Void's
plan should be rare in practice (only needed if the base game genuinely
isn't in the library yet, which desktop's own dialog also just treats as
"install anyway, warn about the version mismatch").

Desktop's `ParseUpdate` also already encodes the specific-error cases
Void's plan asked for by name: type mismatch between what's being
installed and what's there, same-version-already-installed, newer-version-
already-installed. That logic is directly portable, not something to
redesign.

---

## Rough counts

_(as originally counted; not re-tallied for the 2026-09-10 correction above —
graphics packs and DLC/update matching/plumbing, both counted below as gaps,
are now done. Left as-is rather than renumbered, so this section stays a
record of what the original pass found rather than a second thing to keep in
sync by hand.)_

- Already have it: 10
- Backend exists, iOS UI-only gap: 4 (graphics packs, title/storage manager,
  DLC/update install plumbing, multi-account)
- Fully missing, feasible: 5
- Fully missing, questionable fit for iOS: 5

Graphics packs is the single most surprising finding — a complete, working
engine-side feature with literally no iOS entry point, likely because it
was never on anyone's radar rather than because it's hard. Worth strong
consideration alongside the DLC/update work given how little net-new code
it needs. **Both since built — see the 2026-09-10 correction near the top of
this file.**
