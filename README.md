# Cemu — iOS Port (Wii U Emulator), work in progress

An **early, honest, in-progress** iOS port of [Cemu](https://github.com/cemu-project/Cemu), the Wii U emulator written in C/C++. Forked to build the port for real.

> **Does it play games yet? No.** Read [`STATUS.md`](STATUS.md) for exactly what works and what doesn't, and [`ROADMAP.md`](ROADMAP.md) for the real milestones. This README will not claim more than the code delivers.

## Where things actually stand

- ✅ **The genuine Cemu C++ engine compiles for iOS arm64** — `libCemuCafe.a`, verified via CI (2026-07-19, 410/410 objects, zero errors). [`ROADMAP.md`](ROADMAP.md) **M1 is done.**
- ✅ A SwiftUI app shell exists (game browser, controller skins).
- ✅ A **real** Swift↔C++ bridge (`src/ios/Bridge/CemuBridge.{h,mm}`) targets the actual `CafeSystem` API — no fake emulator.
- ⬜ The compiled core is **not yet linked into the app** — that's M2's first task.
- ⬜ No graphics/input/audio wiring yet (M3–M4).

The earlier version of this repo shipped ~20 markdown files declaring the project "complete/delivered/production-ready." None of that was true. Those files are preserved for history under [`docs/_archive_original_claims/`](docs/_archive_original_claims/) and should not be trusted. A hand-rolled Swift PowerPC "CPU" (mostly empty stubs) has been retired for the same reason.

## Architecture

See [`ARCHITECTURE.md`](ARCHITECTURE.md). Short version: the SwiftUI shell drives the **real** Cemu core through a thin C bridge. The bridge is guarded by `CEMU_CORE_AVAILABLE`; until the core links for iOS it compiles to honest "engine not built yet" responses so the app shell still builds, then flips to the real engine when M1 lands.

## Building

- The Xcode project is generated from `src/ios/project.yml` via [XcodeGen](https://github.com/yonwoo9/XcodeGen): `cd src/ios && xcodegen generate`.
- Device builds require a Mac with **full Xcode** (iOS SDK) — Command Line Tools alone are not enough.
- Deployment to a non-jailbroken device uses sideloading (SideStore/AltStore/TrollStore); the Cemu interpreter needs JIT, which requires a JIT-enable step on device.

## License

Cemu is licensed under [Mozilla Public License 2.0](/LICENSE.txt). Files under `dependencies/` and some individual `src/` files carry their original licenses as noted in their headers.
