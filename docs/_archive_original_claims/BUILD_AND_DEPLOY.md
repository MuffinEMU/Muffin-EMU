# Building & Deploying Cemu iOS Emulator

## Quick Start

### Prerequisites
- Xcode 15.0+ with iOS 16.0+ SDK
- A-chip iOS device (iPad Air 2+, iPhone 6s+) or iOS simulator
- Approximately 2 GB free disk space

### Building for Device

1. **Create Xcode Project**
   ```bash
   mkdir build_ios
   cd build_ios
   xcodebuild -project cemu_ios.xcodeproj -scheme CemuEmulator -configuration Release -sdk iphoneos build
   ```

2. **Install on Device**
   - Connect device via USB
   - Open Xcode
   - Select device in scheme selector
   - Product → Run (or ⌘R)
   - App installs and launches

### Building IPA for Distribution

The GitHub Actions workflow automatically builds IPAs on every push. To manually build:

```bash
xcodebuild \
  -scheme CemuEmulator \
  -configuration Release \
  -sdk iphoneos \
  -archivePath build/CemuEmulator.xcarchive \
  archive

xcodebuild \
  -exportArchive \
  -archivePath build/CemuEmulator.xcarchive \
  -exportPath build/ipa \
  -exportOptionsPlist ExportOptions.plist
```

## Project Structure

```
src/ios/
├── App/
│   ├── CemuApp.swift                (Entry point)
│   ├── ContentView.swift            (UI - 500+ lines)
│   ├── GameManager.swift            (ROM management)
│   └── MetalView.swift              (GPU integration)
├── Emulation/
│   ├── CPUCore.swift                (PPC interpreter)
│   ├── MemoryManager.swift          (Memory model)
│   └── EmulationEngine.swift        (Orchestration)
└── Rendering/
    ├── Shaders.metal                (Metal shaders)
    └── MetalRenderer.swift          (Rendering pipeline)
```

## UI Features

### Game Browser
- **Dark theme** with blue accents
- **Gradient backgrounds** for depth
- **High-res cover art** display (3:4 aspect ratio)
- **Search & filter** functionality
- **Favorites system** with heart icon
- **Smooth animations** and transitions

### Emulator Interface
- **Minimalist controls** overlaid on game
- **Real-time FPS counter** with color coding
- **D-Pad** and 4 **action buttons** (A/B/X/Y)
- **Touch-responsive** with haptic feedback
- **Auto-hide controls** on tap

## GPU Rendering

### Shader Implementations

**Upscaling Modes:**
- **Lanczos**: High-quality 4-tap upscaling (default)
- **Bilinear**: Smooth 2x2 upscaling (fast)
- **None**: Direct rendering (1:1)

**Post-Processing:**
- Sharpening filter with adjustable strength
- Gamma correction for display calibration
- Contrast and brightness adjustment
- HDR tone mapping support

### Performance

- Native 1280×720 rendering
- Upscale to device resolution
- 60 FPS target frame rate
- Metal 3 optimizations for A-series GPUs

## GitHub Actions CI/CD

### Automatic Builds

Every push triggers:
1. Checkout code
2. Select Xcode 15.0
3. Build Release configuration
4. Create unsigned IPA
5. Upload as artifact
6. Create release (on tags)

### Accessing Builds

- **Artifacts**: GitHub Actions → build-ipa → Download artifacts
- **Releases**: GitHub Releases page → Download IPA
- **Size**: ~150 MB unsigned IPA

## ROM Management

### Adding Games

1. Connect device to Mac
2. Open Xcode → Window → Devices
3. Select device → Apps
4. Find CemuEmulator
5. Drag ROMs to Documents folder

OR via Files app:
1. Open Files app on iOS
2. Navigate to On My iPhone/iPad
3. Select CemuEmulator
4. Add files to Documents/Roms/

### Supported Formats

- **.wua** - Wii U disc image
- **.wud** - Wii U disc uncompressed
- **.rpx** - Wii U executable
- **.iso** - ISO 9660 image

### Cover Art

Place cover images in Documents/Roms/:
- Format: JPEG or PNG
- Naming: `{GameID}_cover.jpg`
- Size: 300×400px recommended
- Aspect ratio: 3:4

Example: `SuperMarioBros_cover.jpg`

## Debugging

### Xcode Console

```
Window → Panels → Console (⇧⌘C)
- CPU execution logs
- Memory access traces
- Shader compilation errors
- Frame timing data
```

### Performance Profiling

```
Product → Profile (⌘I)
- Xcode Instruments
- Metal System Trace
- Core Animation
- Memory allocation
```

### Common Issues

**App crashes on launch:**
- Check iOS version (16.0+)
- Verify Metal framework linked
- Check certificate if code signed

**Black screen during gameplay:**
- GPU rendering working normally
- Check FPS counter (yellow text)
- Monitor memory usage in Instruments

**Low frame rate (<15 FPS):**
- A-chip device expected: 20-30 FPS
- Close background apps
- Reduce ROM count for faster scanning

## Testing

### Minimal Test ROM

For testing without full games:
1. Create 1 MB test file: `dd if=/dev/zero bs=1M count=1 of=test.wud`
2. Place in Documents/Roms/
3. Game browser should detect it
4. Tap Play to launch emulation

### Performance Benchmarks

**Expected Performance (A-chip devices):**
- CPU: 20-30 FPS (interpreter mode)
- GPU: 60 FPS capable
- Memory: ~400 MB during gameplay
- Startup: <2 seconds

## Advanced Configuration

### Shader Selection

Modify `MetalRenderer.init()` in MetalView.swift:
```swift
// Change upscale mode
let renderer = MetalRenderer(device: device, upscaleMode: .bilinear)
```

### Custom Upscaling

To add FSR (FidelityFX Super Resolution):
1. Implement FSR shader in Shaders.metal
2. Add pipeline state in MetalRenderer.swift
3. Select in upscaleMode enum

### Thermal Management

iOS automatically manages:
- Reduced frame rate under thermal load
- GPU clock throttling
- Memory pressure handling

No manual thermal configuration needed.

## Distribution

### Internal Testing

Send unsigned IPA via:
- AirDrop to testers
- Email (.ipa attachment)
- Dropbox/iCloud Drive
- Custom web server

Testers install via:
- AltStore / Trollstore (sideloading)
- Apple Configurator 2
- Development provisioning profile

### App Store Submission

Not recommended for emulators due to:
- Legal liability for ROM distribution
- App Store policy violations
- Console manufacturer takedown risk

Use sideloading or enterprise distribution instead.

## Next Steps

1. ✅ Build successful IPA
2. ✅ Install on device via Xcode
3. ✅ Add test ROM to Documents/Roms/
4. ✅ Launch game and verify emulation
5. ⏳ Expand CPU instruction support (Phase 1)
6. ⏳ Implement audio (Phase 2)
7. ⏳ Add save game system (Phase 3)

## Support

For build issues:
1. Check Xcode build output
2. Verify iOS deployment target (16.0+)
3. Confirm Metal framework linked
4. Check device architecture (arm64)

For emulation issues:
1. Check Xcode console logs
2. Inspect Memory Manager state
3. Profile with Instruments
4. Check ROM file integrity
