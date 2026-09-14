# MuffinEMU

Wii U emulation for iPhone and iPad, built on [Cemu](https://github.com/cemu-project/Cemu).

MuffinEMU is its own emulator. The SwiftUI app grew out of Muffin ([kiddreads/cemu-ios-muffin](https://github.com/kiddreads/cemu-ios-muffin)), and the Cemu core underneath it is maintained here, with MuffinEMU's own fixes and a curated set of upstream Cemu fixes on top.

Some MeloCafe cores and bug fixes have been brought over to MuffinEMU: the PowerPC interpreters, the AArch64 recompiler with iOS 26 dual-mapped JIT, the Metal and Vulkan (MoltenVK) renderers and shader emitters, ASTC texture decoding, and the iOS audio, input and window systems came from [stossy11/MeloCafe](https://github.com/stossy11/MeloCafe).

## What's in it

- **The app:** the library, importer, keys.txt handling, decrypt-to-files and WUA, DLC and update install, graphic packs, the measured Wii U GamePad on-screen controls with skins, themes and comfort controls, external-display routing, the in-app launch log, and the crash and memory trail.
- **The core:** Cemu, with the iOS layers above, MuffinEMU's fixes, and selected upstream Cemu fixes.

## Layout

```
src/ios/App, Emulation, Rendering   the SwiftUI app
src/ios/Bridge/CemuBridge.h         the only thing the app knows about the engine (plain C)
src/ios/Bridge/CemuBridge.mm        that API, implemented on the core
src/ios/Bridge/Core/                title launch, decrypt, DLC/update, graphic packs, pause
src/  (everything else)             the Cemu core
```

The bridge and its glue are compiled into `Cemu.framework` together with the core, so they build against the core's own headers. The Xcode app compiles Swift only and embeds that framework.

## Installing

Every build of `main` is published as a numbered release. Each release goes up by 0.1, and after .9 comes the next whole number: 1.0, 1.1 ... 1.9, 2.0.

- `MuffinEMU.ipa` for SideStore, AltStore or LiveContainer, which re-sign it with your Apple ID.
- `MuffinEMU-fakesigned.ipa` for TrollStore or a jailbroken device, with the JIT entitlements embedded.

MuffinEMU uses its own bundle identifier (`com.kiddreads.MuffinEMU`), so it installs next to Muffin rather than replacing it.

**Keys.** Encrypted games need the `keys.txt` dumped from your own Wii U. Drop it into the `keys` folder MuffinEMU creates in the Files app, or import it in Settings. Nothing is bundled.

**MoltenVK.** The Vulkan renderer can use MoltenVK 1.4.3 (the default) or 1.2.8, the build 64Touch uses (Settings > Graphics). The choice applies on the next launch. Metal, the default renderer, does not use MoltenVK.

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
xcodebuild -project MuffinEMU.xcodeproj -scheme MuffinEMU -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO build
```

## Credits and license

- [Cemu](https://github.com/cemu-project/Cemu) (MPL-2.0), the emulator MuffinEMU is built on.
- [MeloCafe](https://github.com/stossy11/MeloCafe) by stossy11 (MPL-2.0). Some MeloCafe cores and bug fixes have been brought over to MuffinEMU.
- [Melo-Controller](https://github.com/stossy11/Melo-Controller) by stossy11 (GPL-3.0), the optional "Use melo-controls" pad.
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK) (Apache-2.0).

MuffinEMU's source is MPL-2.0, like Cemu and MeloCafe; see `LICENSE.txt`. Source files keep their original copyright and authorship notices.

The app links Melo-Controller in every build, whether or not the switch is on. MPL-2.0 code may be combined into a GPL work, so a MuffinEMU IPA as a whole is distributed under GPL-3.0, with this repository as its source.
