# MuffinEMU

Wii U emulation on iOS and iPadOS: the **Muffin** app running **MeloCafe**'s Cemu core.

MuffinEMU pairs two projects that are each strongest at a different half of the job:

- **The app is Muffin's** ([kiddreads/cemu-ios-muffin](https://github.com/kiddreads/cemu-ios-muffin)): the SwiftUI library, importer, keys.txt handling, decrypt-to-files and WUA, DLC and update install, graphic packs, the measured Wii U GamePad on-screen controls with skins and themes, external-display routing, the in-app launch log, and the crash and memory trail.
- **The emulator is MeloCafe's** ([stossy11/MeloCafe](https://github.com/stossy11/MeloCafe)): the PowerPC interpreters, the AArch64 recompiler with iOS 26 dual-mapped JIT, the Metal and Vulkan (MoltenVK) renderers and shader emitters, ASTC texture decoding, and the iOS audio, input and window systems.

Both are built on [Cemu](https://github.com/cemu-project/Cemu).

## How the two fit together

```
src/ios/App, Emulation, Rendering   Muffin's SwiftUI app
src/ios/Bridge/CemuBridge.h         the only thing the app knows about the engine (plain C)
src/ios/Bridge/CemuBridge.mm        that API, implemented on MeloCafe's core
src/ios/Bridge/Core/                title launch, decrypt, DLC/update, graphic packs, pause
src/  (everything else)             MeloCafe's Cemu core, unmodified
```

The bridge and its glue are compiled into `Cemu.framework` together with the core, so they build against the core's own headers. The Xcode app compiles Swift only and embeds that framework. Nothing under `src/` outside `src/ios` differs from MeloCafe apart from the few lines in `src/CMakeLists.txt` that add the bridge to the framework.

## Installing

Every push to `main` publishes a release with two IPAs:

- `Cemu.ipa` for SideStore, AltStore or LiveContainer, which re-sign it with your Apple ID.
- `Cemu-fakesigned.ipa` for TrollStore or a jailbroken device, with the JIT entitlements embedded.

MuffinEMU uses its own bundle identifier, so it installs next to Muffin rather than replacing it.

**Keys.** Encrypted games need the `keys.txt` dumped from your own Wii U. Drop it into the `keys` folder MuffinEMU creates in the Files app, or import it in Settings. Nothing is bundled.

**JIT.** The recompiler needs a JIT enabler (StikJIT, SideStore or LiveContainer) and the recompiler switch in Settings. Without both, MuffinEMU runs the multi-core interpreter, and Settings says which one this launch got and why.

## Building

CI is the build: `.github/workflows/build-ios-app.yml` runs the whole thing on a macOS runner. To do it by hand on a Mac with full Xcode:

```sh
git clone --recursive https://github.com/kiddreads/MuffinEMU.git
cd MuffinEMU
cmake -S . -B build-ios -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DVCPKG_TARGET_TRIPLET=arm64-ios \
  -DBUILD_HEADLESS_DYLIB=ON -DCMAKE_MACOSX_BUNDLE=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build-ios --target CemuBin
mkdir -p build-ios/out && cp -R "$(find build-ios bin -type d -name Cemu.framework -not -path '*/CMakeFiles/*' | head -n1)" build-ios/out/
cd src/ios && xcodegen generate
xcodebuild -project Cemu-iOS.xcodeproj -scheme Cemu -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO build
```

## License

MPL-2.0, like Cemu and MeloCafe. See `LICENSE.txt`.
