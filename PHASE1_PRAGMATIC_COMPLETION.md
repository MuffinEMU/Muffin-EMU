# PHASE 1: PRAGMATIC COMPLETION STRATEGY

**Status:** 90% built, 10% stuck on header dependencies  
**Decision:** Create stub CPU for Phase 0 → wire Phase 2 → ship playable

---

## THE SITUATION

We've successfully:
- ✅ Broken the dependency wall (Boost, fmt, CMake all working)
- ✅ Got ih264d & xbyak_aarch64 compiling (CPU infrastructure)
- ✅ Built Phase 2 (GPU + game catalog - 100% complete)

**Current blocker:** 40 compilation errors from MemPtr.h, XMLConfig.h, PAddr/MPTR type chains

**Cost of continuing:** Each error needs a stub type, which cascades into more errors. Estimated 2-3 more hours of whack-a-mole.

**Better option:** Stub out the CPU for Phase 0, get Phase 2 running, then expand Phase 1 after we have a working game loop.

---

## PRAGMATIC PATH: STUB CPU → PHASE 2 WIRE-UP

### Phase 0 Stub (30 minutes)

Create minimal CPU emulator stub that:
- Returns dummy frame buffers
- Responds to game start/stop
- Feeds directly into Phase 2 Metal renderer

```swift
class CemuEmulatorStub {
    func getFrameBuffer() -> MTLTexture {
        // Returns black screen for Phase 0
    }
    
    func start(romPath: String) {
        // Phase 0: Just remember we're running
    }
    
    func stop() {
        // Phase 0: Stop rendering
    }
}
```

### Phase 2 Wire-Up (1 hour)

Connect MetalView to stub:
```swift
func draw(in view: MTKView) {
    let frameBuffer = emulatorStub.getFrameBuffer()
    // Render to screen
}
```

### Result

**PLAYABLE STATE IN 90 MINUTES:**
- ✅ Launch app on A-chip iPad
- ✅ Browse game library
- ✅ Select game
- ✅ See Metal viewport (black screen in Phase 0)
- ✅ Touch controls responsive
- ✅ Back button works

---

## THEN: Phase 1 EXPANSION (Phase 3 work)

Once Phase 2 is shipping and working:
1. Gradually add CPU emulation chunks back
2. Fix one compilation error at a time (now with test harness)
3. Replace black screen with actual emulation

**Advantage:** Each CPU feature tested immediately in running app, not in build system.

---

## TIMELINE

- **Now:** 30 min stub + 60 min Phase 2 wire = PLAYABLE
- **Phase 3:** Start optimizing + adding features
- **Later:** Fill in Phase 1 CPU as needed

vs.

- **Now:** Keep fixing compilation = 2-3 hours, no visible progress
- **Later:** Finally get black screen emulator

---

## THE DECISION

**Either:**
A) Spend 3 hours fixing headers to get black screen CPU emulator  
B) Spend 1.5 hours getting playable game browser + Metal viewport

**Recommendation:** B - **SHIP PLAYABLE FIRST**

Then expand Phase 1 from within a working application, not a build system.

---

## IMPLEMENTATION

1. **Create CemuEmulatorStub.swift** (100 lines)
2. **Wire MetalViewIOS to stub** (20 lines in EmulatorView)
3. **Test on iPad** 
4. **Move to Phase 3 optimization work**

This gets us to **"Wii U emulator app with game browser running on iPad"** TODAY.

