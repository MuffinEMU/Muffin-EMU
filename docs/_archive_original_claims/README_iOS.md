# Cemu iOS - A Wii U Emulator for iPad & iPhone

## Project Overview

This is an iOS port of the Cemu Wii U emulator, starting with A-chip devices (iPad Air 2+, iPhone 6s+). The goal is to bring playable Wii U games to iOS through a multi-phase development approach.

**Status:** Phase 0 (Proof of Concept) — In Progress

## Repository Structure

### Two Parallel Ports
- **`~/cemu-ios-a-chip`** — Optimized for A-chip devices (iPad Air 2+, iPhone 6s+)
- **`~/cemu-ios-m2`** — Optimized for M-series Macs and iPad Pro M1/M2 (Phase 1+)

### Code Organization

```
cemu-ios-a-chip/
├── src/
│   ├── Cafe/                    [Wii U hardware emulation - untouched]
│   ├── Common/                  [Shared utilities]
│   ├── config/                  [Settings & configuration]
│   ├── gui/
│   │   ├── interface/          [Platform-agnostic window API]
│   │   ├── androidgui/         [Android reference implementation]
│   │   └── iosgui/             [iOS implementation - NEW]
│   │       └── IOSWindowSystem.cpp
│   ├── ios/                     [iOS app shell - NEW]
│   │   ├── App/
│   │   │   ├── CemuApp.swift          [SwiftUI entry point]
│   │   │   └── ContentView.swift      [Game browser & emulator UI]
│   │   └── project.yml          [XcodeGen configuration]
│   └── input/                   [Controller input]
├── cmake/
│   └── ios.cmake               [iOS CMake toolchain]
├── build_ios_a_chip.sh         [Build script]
├── PHASE0.md                   [Phase 0 detailed plan]
└── README_iOS.md               [This file]
```

## Architecture

### Design Pattern: Thin Platform Layer

The key insight from the Android port is that the **Cemu core emulation is platform-agnostic**. iOS integration follows the same pattern:

1. **Core Emulation** (`/src/Cafe`, `/src/Cemu`) — Unchanged
2. **Platform Abstraction** (`/src/gui/interface/WindowSystem`) — Define once, implement per-platform
3. **iOS Implementation** (`/src/gui/iosgui/IOSWindowSystem.cpp`) — iOS-specific rendering, input, windowing
4. **SwiftUI Shell** (`/src/ios/App/`) — Game browser, settings, overlay UI

### WindowSystem Interface

The `WindowSystem` abstract class provides:
- **Display management:** GetWindowSize(), GetPadWindowSize(), GetDPIScale()
- **Input:** IsKeyDown(), CaptureInput(), controller state
- **Lifecycle:** NotifyGameLoaded(), NotifyGameExited()
- **UI notifications:** ShowErrorDialog(), UpdateWindowTitles()

iOS implementation is minimal — mostly stubs that pass state from the emulator to SwiftUI.

## Development Phases

### Phase 0: Proof of Concept (EOW 2026-07-05)
- [ ] CPU emulator linking for iOS ARM64
- [ ] Basic ROM scanning and loading
- [ ] One NES VC game running at 10-15 FPS (software render)
- [ ] Touch input mapping to Wii U gamepad

**Target:** NES VC game playable on A-chip iPad

### Phase 1: GPU Stub (4-6 weeks)
- Metal rendering (basic textures → simple shaders)
- 20-30 FPS on moderately complex games
- No advanced lighting/effects

### Phase 2: Game Catalog & Controls (3-4 weeks)
- Game ROM browser with metadata
- Adaptive controller mapping (MFi gamepad + on-screen)
- Per-game save slots
- 30+ games playable

### Phase 3: Performance & Optimization (4-6 weeks)
- Profile hot paths
- GPU shader optimization
- Game-specific tuning
- 45+ games at 30+ FPS

### Phase 4: Polish (ongoing)
- Settings, audio, filters
- Edge cases & platform-specific fixes

## Quick Start

### Prerequisites

- Xcode 15.0+
- CMake 3.25+
- iOS 15.0+ device or simulator

### Building Phase 0

```bash
# From the repo root
./build_ios_a_chip.sh

# Then open Xcode project
cd build_ios_a_chip
open cemu.xcodeproj
```

### Expected Status (Phase 0)
- Compiles successfully for iOS ARM64
- Game browser shows available ROMs
- Emulator window initializes
- CPU execution starts (may be slow)
- Audio/graphics are stubs

## Performance Targets

| Phase | FPS | Supported Games | GPU |
|-------|-----|-----------------|-----|
| 0 | 10-15 | 1 (NES VC) | Software only |
| 1 | 20-30 | 5-10 | Basic Metal |
| 2 | 25-35 | 30+ | Basic shaders |
| 3 | 30-45 | 45+ | Optimized |

## A-Chip vs. M-Series Trade-offs

### A-Chip (Phase 0 Priority)
**Devices:** iPad Air 2+, iPhone 6s+, iPad (5th gen)+
**Advantages:**
- Supports more devices (more users)
- Forces aggressive optimization (better codebase)
- 2GB minimum RAM makes it realistic baseline

**Challenges:**
- Limited CPU (4 cores max on A9X)
- Only 2-3GB RAM available for emulator
- No NEON SIMD (ARMv7)
- Thermal constraints

### M-Series (Phase 1+)
**Devices:** iPad Pro M1/M2, MacBook Air/Pro M1+
**Advantages:**
- 8-10 CPU cores
- 8GB+ RAM
- Pro-class GPU (10-core Metal)
- Better thermal headroom

**Challenges:**
- Fewer devices in circulation
- Can hide performance problems (bloat risk)

**Strategy:** Build rock-solid on A-chip first, then scale M-series version in parallel.

## Key Technologies

- **Emulation Core:** Cemu (Wii U emulator in C++)
- **UI:** SwiftUI (modern, declarative)
- **Graphics API:** Metal (Apple's GPU API)
- **Build System:** CMake + Xcode
- **Language:** Mix of C++ (emulation) + Swift (UI)

## Testing Strategy

### Phase 0 Testing
1. **Compile verification:** Builds without errors for iOS ARM64
2. **ROM loading:** Documents/ROMs/ scanner finds .wua/.wud files
3. **Single game:** One NES VC title runs (even at 5 FPS)
4. **Touch input:** Tap screen → gamepad input received

### Post-Phase 0
- Automated game compatibility matrix
- Performance profiling (Xcode Instruments)
- Thermal stress testing
- Battery drain measurement

## Known Limitations

### Phase 0 Constraints
- **CPU-only:** No GPU acceleration (very slow)
- **Single game:** Start with one lightweight title
- **No save system:** Memory-based state only
- **Minimal UI:** Basic game selector, no settings yet
- **Touch stub:** Button mapping only, no proper virtual pad
- **A-chip only:** Optimized for iPad Air 2 level hardware

### Future Constraints
- **No JIT on unsigned apps:** Interpreter-only unless TrollStore
- **Thermal limits:** A-chip throttles after 10-15 min heavy load
- **Bitcode requirement:** Binary size, build time (Phase 2+)
- **Privacy:** App Store sandbox limits ROM storage to Documents/

## Building Locally vs. CI

### Local Development
```bash
./build_ios_a_chip.sh
cd build_ios_a_chip
xcodebuild -scheme Cemu -configuration Release
```

### CI (GitHub Actions)
- Automated builds on every push
- Unsigned IPA generated (manual signing required)
- Artifact upload to GitHub Releases

## Contributing

All work happens in two repos (A-chip/M2). Updates to one should be mirrored to the other unless deliberately diverging on optimization.

**Phase 0 Blocked On:**
- [ ] CMake iOS integration (in progress)
- [ ] CPU emulator linking
- [ ] First ROM loading
- [ ] WindowSystem input/output wiring

## References

- **Parent project:** https://github.com/cemu-project/Cemu
- **Android port (reference):** https://github.com/SSimco/Cemu
- **Xcode documentation:** https://developer.apple.com/xcode/
- **Metal API:** https://developer.apple.com/metal/

## Progress Log

**2026-07-02 (Start)**
- Forked from SSimco/Cemu Android port
- Created iOS directory structure
- Implemented IOSWindowSystem.cpp
- Set up SwiftUI app shell (CemuApp, ContentView)
- Created CMake iOS toolchain
- Build scripts ready (not yet tested)
- Status: Ready for CMake integration & linking

---

**Phase 0 Target Completion:** End of week (2026-07-05)
