add_library(CemuGui INTERFACE)
target_include_directories(CemuGui INTERFACE "interface")

if(ENABLE_WXWIDGETS)
    add_subdirectory(wxgui)
    target_link_libraries(CemuGui INTERFACE CemuWxGui)
endif()

if(ANDROID)
    add_subdirectory(androidgui)
    target_link_libraries(CemuGui INTERFACE CemuAndroidGui)
endif()

if(PLATFORM_IOS)
    add_subdirectory(iosgui)
    target_link_libraries(CemuGui INTERFACE iosgui)
endif()
