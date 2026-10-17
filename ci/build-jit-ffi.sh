#!/bin/bash
# MuffinEMU — code by the MuffinEMU Development Team.
# SPDX-License-Identifier: GPL-3.0-only
#
# Builds muffin-jit (MuffinEMU's own device-link crate, in jit/muffin-jit) as a
# static library for iOS arm64, for the JIT helper app extension to link. Pure Rust
# plus idevice (MIT); no C toolchain needed because the crypto backend is rustcrypto.
#
# Output:
#   jit/muffin-jit/target/aarch64-apple-ios/release/libmuffin_jit.a
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
# A quick sanity check that the exported symbols are present. Match the bare name so
# it works whether or not the platform prefixes an underscore.
if command -v nm >/dev/null 2>&1; then
  syms="$(nm -g "$OUT" 2>/dev/null || nm "$OUT" 2>/dev/null)"
  for sym in muffin_jit_connect muffin_jit_enable muffin_jit_pair_on_device; do
    printf '%s\n' "$syms" | grep -q "$sym" || { echo "::error::missing symbol $sym"; exit 1; }
  done
  echo "exported symbols present"
fi
