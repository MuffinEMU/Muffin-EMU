# When this port is updated, the minizip port should be updated at the same time
# MuffinEMU overlay of vcpkg's zlib 1.3.1 port. The only change: the source comes from zlib's own
# release tarball (GitHub release asset, then zlib.net) instead of GitHub's generated
# archive/v1.3.1.tar.gz, which GitHub Actions runners were refused with a 404 on 2026-10-15.
# Same source files; the archive also carried .github/ and .gitignore, which the build doesn't use.
vcpkg_download_distfile(ARCHIVE
    URLS
        "https://github.com/madler/zlib/releases/download/v${VERSION}/zlib-${VERSION}.tar.gz"
        "https://zlib.net/fossils/zlib-${VERSION}.tar.gz"
        "https://www.zlib.net/fossils/zlib-${VERSION}.tar.gz"
    FILENAME "zlib-${VERSION}.tar.gz"
    SHA512 580677aad97093829090d4b605ac81c50327e74a6c2de0b85dd2e8525553f3ddde17556ea46f8f007f89e435493c9a20bc997d1ef1c1c2c23274528e3c46b94f
)
vcpkg_extract_source_archive(SOURCE_PATH
    ARCHIVE "${ARCHIVE}"
    PATCHES
        0001-Prevent-invalid-inclusions-when-HAVE_-is-set-to-0.patch
        0002-build-static-or-shared-not-both.patch
        0003-android-and-mingw-fixes.patch
)

# This is generated during the cmake build
file(REMOVE "${SOURCE_PATH}/zconf.h")

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DSKIP_INSTALL_FILES=ON
        -DZLIB_BUILD_EXAMPLES=OFF
    OPTIONS_DEBUG
        -DSKIP_INSTALL_HEADERS=ON
)

vcpkg_cmake_install()
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/vcpkg-cmake-wrapper.cmake" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")

# Install the pkgconfig file
if(NOT DEFINED VCPKG_BUILD_TYPE OR VCPKG_BUILD_TYPE STREQUAL "release")
    if(VCPKG_TARGET_IS_WINDOWS)
        vcpkg_replace_string("${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/zlib.pc" "-lz" "-lzlib")
    endif()
    file(COPY "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/zlib.pc" DESTINATION "${CURRENT_PACKAGES_DIR}/lib/pkgconfig")
endif()
if(NOT DEFINED VCPKG_BUILD_TYPE OR VCPKG_BUILD_TYPE STREQUAL "debug")
    if(VCPKG_TARGET_IS_WINDOWS)
        vcpkg_replace_string("${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-dbg/zlib.pc" "-lz" "-lzlibd")
    endif()
    file(COPY "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-dbg/zlib.pc" DESTINATION "${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig")
endif()

vcpkg_fixup_pkgconfig()
vcpkg_copy_pdbs()

if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/zconf.h" "ifdef ZLIB_DLL" "if 0")
else()
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/zconf.h" "ifdef ZLIB_DLL" "if 1")
endif()

file(COPY "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
file(INSTALL "${SOURCE_PATH}/LICENSE" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)
