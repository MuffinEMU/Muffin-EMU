add_library(CemuAudio
	IAudioAPI.cpp
	IAudioAPI.h
	IAudioInputAPI.cpp
	IAudioInputAPI.h
)

set_property(TARGET CemuAudio PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

cemu_use_precompiled_header(CemuAudio)

if(WIN32)
	target_sources(CemuAudio PRIVATE
		DirectSoundAPI.cpp
		DirectSoundAPI.h
		XAudio2API.cpp
		XAudio2API.h
		XAudio27API.cpp
		XAudio27API.h
	)
endif()

if(ENABLE_CUBEB)
	target_sources(CemuAudio PRIVATE
		CubebAPI.cpp
		CubebAPI.h
		CubebInputAPI.cpp
		CubebInputAPI.h
	)
	#add_compile_definitions(HAS_CUBEB)
endif()

if(PLATFORM_IOS)
	target_sources(CemuAudio PRIVATE
		CoreAudioAPI.mm
		CoreAudioAPI.h
	)
	# The shared precompiled header is compiled as C++. clang will not apply a C++ PCH
	# to an Objective-C++ translation unit, so this one file opts out and includes
	# precompiled.h the ordinary way.
	set_source_files_properties(CoreAudioAPI.mm PROPERTIES SKIP_PRECOMPILE_HEADERS ON)
	target_link_libraries(CemuAudio PRIVATE
		"-framework AudioToolbox"
		"-framework AVFoundation"
		"-framework Foundation"
	)
endif()

target_include_directories(CemuAudio PUBLIC "../")

target_link_libraries(CemuAudio PRIVATE
	CemuCommon
	CemuGui
)

if(ENABLE_CUBEB)
	# PUBLIC because cubeb.h/cubeb.h is included in CubebAPI.h
	target_link_libraries(CemuAudio PUBLIC cubeb::cubeb)
endif()
