if(PLATFORM_IOS)
    add_library(iosgui STATIC)

    target_sources(iosgui PRIVATE
        IOSWindowSystem.cpp
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

    # iOS frameworks
    target_link_libraries(iosgui PRIVATE
        "-framework Foundation"
        "-framework Metal"
        "-framework MetalKit"
        "-framework UIKit"
    )
endif()
