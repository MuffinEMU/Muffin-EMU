#!/bin/bash
# MuffinEMU — code by the MuffinEMU Development Team.
# SPDX-License-Identifier: GPL-3.0-only
#
# Builds muffin-jit (MuffinEMU's own device-link crate, in jit/muffin-jit) as a
# static library for iOS arm64, for the JIT helper app extension to link, plus the
# framework the app opens for on-device pairing and MuffinInstaller. idevice (MIT) and
# isideload (MIT); ring (via isideload) compiles a little C with Xcode's clang.
#
# Output:
#   jit/muffin-jit/target/aarch64-apple-ios/release/libmuffin_jit.a   (linked by the helper extension)
#   jit/muffin-jit/target/MuffinJITPairing.framework                  (embedded in the app for on-device pairing)
#
# Run on the macOS runner before xcodegen. `rustup` is present on GitHub's macOS
# images; this adds the iOS target if it isn't already there.
set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRATE="$ROOT/jit/muffin-jit"
TARGET="aarch64-apple-ios"

# The helper extension's floor. The library is only ever loaded there, never in the
# host app, so it can require 17.4 without affecting the app's iOS 15 minimum.
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-17.4}"

echo "== rustup target =="
rustup target add "$TARGET"

echo "== cargo build ($TARGET, release) =="
cd "$CRATE"
cargo build --release --target "$TARGET" --locked || cargo build --release --target "$TARGET"

OUT="$CRATE/target/$TARGET/release/libmuffin_jit.a"
if [ ! -f "$OUT" ]; then
  echo "::error::muffin-jit static library was not produced at $OUT"
  exit 1
fi
echo "built $(du -h "$OUT" | cut -f1): $OUT"
# Advisory symbol check. With LTO the archive holds LLVM bitcode, which system `nm`
# can't read (llvm-nm can), so a miss here means nothing — the real proof is the app
# link step. Report what's visible; never fail the build on it.
if command -v nm >/dev/null 2>&1; then
  syms="$(nm -g "$OUT" 2>/dev/null || true)"
  for sym in muffin_jit_connect muffin_jit_enable muffin_jit_pair_on_device; do
    if printf '%s\n' "$syms" | grep -q "$sym"; then echo "symbol present: $sym"; else echo "note: $sym not visible to nm (LTO bitcode archive)"; fi
  done
fi
echo "muffin-jit static library ready"

# On-device pairing (iOS 27+) runs in the app itself, not the helper: the code iOS asks for has to
# appear on screen while it waits. The app supports iOS 15 and this library needs 17.4, so the app
# can't link it. It gets the pairing entry points as a small framework instead, embedded but not
# linked, which JIT/JITOnDevicePairing.swift opens with dlopen only on iOS 27.
FW="$CRATE/target/MuffinJITPairing.framework"
echo "== MuffinJITPairing.framework =="
rm -rf "$FW"
mkdir -p "$FW"
xcrun -sdk iphoneos clang -arch arm64 -dynamiclib \
  -miphoneos-version-min="$IPHONEOS_DEPLOYMENT_TARGET" \
  -install_name @rpath/MuffinJITPairing.framework/MuffinJITPairing \
  -Wl,-force_load,"$OUT" \
  -Wl,-exported_symbol,_muffin_jit_pair_on_device \
  -Wl,-exported_symbol,_muffin_jit_bytes_free \
  -Wl,-exported_symbol,_muffin_jit_string_free \
  -Wl,-exported_symbol,_muffin_jit_connect \
  -Wl,-exported_symbol,_muffin_jit_link_free \
  -Wl,-exported_symbol,_muffin_installer_sign_in \
  -Wl,-exported_symbol,_muffin_installer_sign_and_install \
  -Wl,-exported_symbol,_muffin_installer_install_signed \
  -Wl,-dead_strip \
  -framework Security \
  -o "$FW/MuffinJITPairing"
# MinimumOSVersion is the APP's floor (15.0), not the library's 17.4: installd checks every embedded
# bundle against it, and a higher one could refuse the whole app on iOS 15 to 17.3. The binary is only
# ever opened (dlopen) on iOS 27, so nothing older loads it.
cat > "$FW/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>MuffinJITPairing</string>
	<key>CFBundleIdentifier</key><string>com.void.muffinemu.jitpairing</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>MuffinJITPairing</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
	<key>MinimumOSVersion</key><string>15.0</string>
</dict>
</plist>
PLIST
exported="$(nm -gU "$FW/MuffinJITPairing" 2>/dev/null || true)"
for sym in _muffin_jit_pair_on_device _muffin_jit_bytes_free _muffin_jit_string_free _muffin_jit_connect _muffin_jit_link_free _muffin_installer_sign_in _muffin_installer_sign_and_install _muffin_installer_install_signed; do
  if ! printf '%s\n' "$exported" | grep -q " T $sym$"; then
    echo "::error::MuffinJITPairing.framework does not export $sym"
    exit 1
  fi
done
echo "built $(du -h "$FW/MuffinJITPairing" | cut -f1): $FW"
