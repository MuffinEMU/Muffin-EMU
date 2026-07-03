if(PLATFORM_IOS)
    add_library(iosgui STATIC)

    target_sources(iosgui PRIVATE
        IOSWindowSystem.cpp
    )

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
