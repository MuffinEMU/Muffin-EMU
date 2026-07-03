#!/bin/bash
set -e

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="${REPO_DIR}/build_ios_a_chip"

echo "Building Cemu for iOS (A-chip, ARM64)..."

# Create build directory
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Configure with iOS toolchain (minimal Phase 0 build)
cmake -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="${REPO_DIR}/cmake/ios.cmake" \
    -DPLATFORM_IOS=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SKIP_RPATH=ON \
    -S "${REPO_DIR}" \
    -B "${BUILD_DIR}"

echo "Build configured at: ${BUILD_DIR}"
echo ""
echo "To build, run:"
echo "  cd ${BUILD_DIR}"
echo "  make -j$(sysctl -n hw.ncpu)"
