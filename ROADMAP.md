# Roadmap

## Done

- Core compiles for iOS arm64 (upstream Cemu C++ engine).
- App links, boots, and runs a title to its entry point.
- Metal renderer presents a frame on device.
- A retail game (FAST Racing NEO) runs end to end at playable speed, rendering correctly,
  on an iPad Pro A12Z.

## Ahead

### Recompiler
The ARM64 JIT backend exists and compiles, but its capability probe has never succeeded on
iOS — it's never run. Get the probe passing, then validate actual JIT execution.

### Audio
Backend initializes. No sound confirmed on a device yet.

### Controller input
Works at a basic level. Needs a systematic pass across on-screen controls and MFi/Bluetooth
controllers.

### Compatibility
Only one game confirmed. Test more titles.

### Performance
Interpreter measured at 50–190 MIPS. Faster or more demanding titles may need the
recompiler working, further interpreter optimization, or both.

### Save states / persistent saves
Through the iOS sandbox. Not yet addressed.

### Stability across install methods
Two IPAs ship: ad-hoc signed for TrollStore, unsigned for SideStore/AltStore/LiveContainer.
Test stability across all of them.

### Dual-screen output
Display routing picks device-only, mirrored, or dual-screen placement at runtime.
Dual-screen (TV on an external display, GamePad screen on device) is implemented but has
never been exercised with a second display attached.
