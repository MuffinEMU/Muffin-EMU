# MuffinEMU for Android

The same core as the iOS app (`Cemu.framework` there, `libCemu.so` here), with a Kotlin app around it.

- **Renderer:** Vulkan, the core's own backend, straight on the device's driver (no translation layer).
- **CPU:** the AArch64 recompiler. Android lets an app run code it generates, so there is no JIT enabler step.
- **Audio:** cubeb's Android backends (AAudio, OpenSL).
- **Input:** the on-screen pad in `TouchPad.kt`, and any Bluetooth or USB controller Android reports.
- **Minimum:** Android 10 (API 29), arm64, a Vulkan 1.1 GPU.

## Layout

| Path | What |
|---|---|
| `src/android/Bridge/` | The JNI bridge the app calls (`io.github.muffinemu.NativeBridge`). |
| `src/gui/android/` | The core's window system for Android: one `ANativeWindow`, the Vulkan swapchain's surface. |
| `src/ios/Bridge/Core/` | Shared with iOS: title launch, pause, the CafeSystem host implementation. |
| `src/android/app/` | The Kotlin app (Jetpack Compose). |
| `ci/build-core-android.sh` | Builds `libCemu.so` with the NDK (CMake + vcpkg, triplet `arm64-android`). |
| `.github/workflows/build-android-apk.yml` | Core, then APK, as a run artifact. |

## Where files go on the device

`Android/data/io.github.muffinemu/files/` (the Files app shows it; no permission needed):
`Roms/` for games (.wua, .wud, .wux, .rpx or an extracted folder), `mlc/` for the console's storage, saves and `keys.txt`.

## Building

Only on GitHub Actions (`Build Android APK`): the core takes the vcpkg dependencies with it, and the first
run builds all of them (around half an hour); later runs reuse the cache.
