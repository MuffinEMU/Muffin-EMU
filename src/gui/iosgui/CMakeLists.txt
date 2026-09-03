if(PLATFORM_IOS)
    add_library(iosgui STATIC)

    target_sources(iosgui PRIVATE
        IOSWindowSystem.cpp
        IOSTitleLaunch.cpp
        IOSTitleDecrypt.cpp
        IOSCoverArt.cpp
    )

    # Without this, IOSWindowSystem.cpp never sees precompiled.h's aarch64 wrappers
    # (_mm_pause, __rdtsc, ...) or Cemu's core type aliases (uint32, MPTR, ...) that
    # ControllerState.h and friends assume are already visible.
    cemu_use_precompiled_header(iosgui)

    target_include_directories(iosgui PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/..
        ${CMAKE_CURRENT_SOURCE_DIR}/../..
    )

    # Link core emulation
    target_link_libraries(iosgui PUBLIC
        CemuCafe
        CemuCommon
        CemuConfig
        CemuInput
    )

    # IOSTitleDecrypt.cpp and IOSCoverArt.cpp both need TitleInfo.h, which pulls in
    # <zarchive/...> headers directly (for the WUA writer and for verifying a written
    # archive). CemuCafe already links ZArchive::zarchive, but PRIVATEly - a PRIVATE
    # link's usage requirements (its include directories included) don't propagate to
    # iosgui just because iosgui links CemuCafe PUBLIC, so iosgui needs its own direct
    # link to pick up the same include path.
    target_link_libraries(iosgui PRIVATE
        ZArchive::zarchive
    )

    # iOS frameworks
    target_link_libraries(iosgui PRIVATE
        "-framework Foundation"
        "-framework Metal"
        "-framework MetalKit"
        "-framework UIKit"
    )
endif()
