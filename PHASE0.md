# Phase 0: Proof of Concept - Cemu iOS (A-chip)

## Status: IN PROGRESS (Start Date: 2026-07-02)

### Goal
Get a lightweight Wii U game (NES VC title) running at 10-15 FPS on A-chip iPad using CPU emulation only (no GPU).

### Architecture

**Project Structure:**
```
src/
├── Cafe/               [Core emulation - untouched]
├── Common/             [Shared utilities - untouched]
├── config/             [Settings system]
├── gui/
│   ├── interface/      [Platform-agnostic window API]
│   ├── androidgui/     [Android implementation]
│   └── iosgui/         [iOS implementation - NEW]
├── ios/                [iOS app shell - NEW]
│   └── App/
│       ├── CemuApp.swift         [SwiftUI app entry]
│       └── ContentView.swift      [Game browser + emulator view]
└── input/              [Controller input system]
```

**Implementation Model:**
- `IOSWindowSystem.cpp`: Implements `WindowSystem` interface (same as Android)
- `CemuApp.swift`: SwiftUI app shell with game browser
- `ContentView.swift`: Game selection and emulator view (Metal placeholder)

### Phase 0 Milestones

- [ ] **Day 1-2:** CPU emulator linking + basic ROM loading
  - Get Cemu core compiling for iOS ARM64
  - Create ROM scanner for Documents/ROMs/ directory
  - Implement WindowSystem::GetWindowInfo() for display setup

- [ ] **Day 3-4:** Game loading + CPU execution stub
  - Load first NES VC ROM (.wua file)
  - Initialize CPU emulator thread
  - Render basic frame buffer (software) at 10 FPS

- [ ] **Day 5:** Touch input + basic controls
  - Map touch to Wii U gamepad input
  - MFi controller support stub
  - Simple pause/resume

### Current Work

1. **iOS Window System** (DONE)
   - `IOSWindowSystem.cpp` - thin wrapper matching Android interface

2. **SwiftUI Shell** (DONE)
   - Game browser view
   - Emulator view placeholder
   - Scene management (browser ↔ emulator)

3. **XcodeGen Config** (DONE)
   - `project.yml` for iOS build

### Next Steps

1. Create iOS-specific CMake toolchain
2. Configure Xcode project generation via XcodeGen
3. Link Cemu core to iOS ARM64 target
4. Implement ROM scanning + loading
5. Test CPU emulator with NES VC game

### Known Constraints

- **A-chip only:** Target iPad/iPhone with A9X minimum (2GB+ RAM)
- **No GPU yet:** Software rendering only (very slow, ~10-15 FPS expected)
- **Single game:** Start with one NES VC title to prove concept
- **Thermal management:** A-chip runs hot; monitor clock throttling

### Performance Targets (Phase 0)

| Metric | Target |
|--------|--------|
| FPS | 10-15 |
| CPU Utilization | ~60-80% |
| Memory | <500MB |
| Thermal | <45°C sustained |

### Testing

- **Test ROM:** Use a lightweight NES VC title (e.g., Donkey Kong)
- **Target Device:** iPad Air 2 (A9X) or iPhone 6s+ (A9)
- **Build:** CMake + Xcode, unsigned via live.build or XCODEGen

---

**Completion Target:** EOW (2026-07-05)
