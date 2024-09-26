add_library(CemuAndroid SHARED
        AndroidAudio.cpp
        AndroidEmulatedController.cpp
        CMakeLists.txt
        GameTitleLoader.cpp
        Image.cpp
        JNIUtils.cpp
        NativeEmulation.cpp
        NativeGameTitles.cpp
        NativeGraphicPacks.cpp
        NativeInput.cpp
        NativeLib.cpp
        NativeSettings.cpp
)

target_link_libraries(CemuAndroid PRIVATE
        -landroid
        CemuCommon
        CemuAudio
        CemuComponents
        CemuCafe
        CemuBin
)
