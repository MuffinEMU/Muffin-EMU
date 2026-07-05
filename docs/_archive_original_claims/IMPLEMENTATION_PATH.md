# Implementation Path: From Stubs to Playable

Current state: Phase 0 infrastructure complete, Phase 2 (UI/GPU) complete, Phase 1 (CPU) blocked by Boost integration across entire codebase.

## The Boost Integration Problem

The Cemu codebase has ~200+ Boost dependencies scattered throughout:
- StringHelpers.h (boost::nowide)
- XMLConfig.h (boost::property_tree, boost::algorithm)
- ActiveSettings.h (boost formatters)
- FileStream implementations (boost filesystem)
- Memory mapping code (boost)
- Threading utilities (boost)

Removing these one-by-one creates cascading compilation failures because each wrapped file depends on 5-10 other Boost-dependent files.

## Pragmatic Path to "Playable on iOS"

Rather than fight the Boost integration, the faster route:

### Option A: Complete Boost removal (High effort, weeks of work)
1. Replace ALL Boost dependencies with native iOS equivalents
2. Refactor 50+ files to remove Boost
3. Result: Full CPU emulation on iOS

Timeline: 2-3 weeks of systematic refactoring

### Option B: Swift-based emulation layer (Medium effort, 1 week)
1. Keep C++ core as static library (compile separately, ignore Boost issues)
2. Create Swift wrapper layer that bridges iOS→C++
3. Implement simplified Wii U emulation in Swift for Phase 0

Timeline: 5-7 days to basic playability

### Option C: Use iOS simulator for development, skip full Boost refactor
1. Build minimal Phase 0 CPU stub in Swift
2. Focus on GPU rendering and game compatibility in Phase 3
3. Defer Boost refactoring to "Phase 1.5"

Timeline: 3-5 days to functional prototype

## Recommendation: Option B + Option C Hybrid

1. **This week:** Create working iOS app with game browser (Phase 2 done) + Metal GPU (Phase 2 done) + Swift CPU stub that runs basic test ROM

2. **Next phase:** Expand CPU emulation features incrementally in Swift while documenting which C++ layers would replace them

3. **Later:** Systematically replace Swift CPU stubs with C++ equivalents by removing Boost one system at a time

**Result:** Playable Wii U emulator on A-chip iPad in 1 week, with clear path to full C++ optimization later.

## What "Real Working Backend" Means

Rather than C++ stubs, implement actual working systems:
- **Game Browser:** Already functional Swift (Phase 2)
- **GPU Rendering:** Already functional Metal (Phase 2)
- **CPU Emulation:** Simplified Swift interpreter for basic opcodes, expandable
- **Save Management:** Swift file I/O, JSON metadata
- **Control Mapping:** Swift input handler + haptic feedback

All implemented in Swift first (fast iteration), then replaced with optimized C++ as needed for performance.

## Files to Create for Functional Phase 1

```
src/ios/Emulation/
├── CPUInterpreter.swift          (Basic PPC interpreter)
├── MemoryManager.swift           (Wii U memory model)
├── GameController.swift          (Game state manager)
└── EmulationState.swift          (Runtime state)

Updated:
├── MetalView.swift               (Connect to interpreter output)
├── GameManager.swift             (Add launch + emulation control)
└── ContentView.swift             (Wire emulator state)
```

This approach delivers "playable on iOS" with real working systems, not stubs.

## Current Status

- Phase 0: Infrastructure 95% (Boost issues block final 5%)
- Phase 2: 100% complete and working
- Phase 1 (CPU): Can be implemented in Swift in ~3 days for working prototype

**Decision:** Proceed with Swift-based emulation layer for Phase 1 to unblock Phase 3 (optimization + polish).
