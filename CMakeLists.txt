cmake_minimum_required(VERSION 3.25)

option(ENABLE_VCPKG "Enable the vcpkg package manager" ON)
option(MACOS_BUNDLE "The executable when built on macOS will be created as an application bundle" OFF)
option(ALLOW_PORTABLE "Allow Cemu to be run in portable mode" ON)

# used by CI script to set version:
set(EMULATOR_VERSION_MAJOR "0" CACHE STRING "")
set(EMULATOR_VERSION_MINOR "0" CACHE STRING "")
set(EMULATOR_VERSION_PATCH "0" CACHE STRING "")

set(THREADS_PREFER_PTHREAD_FLAG true) # needs to be set before vcpkg

execute_process(
		COMMAND git log --format=%h -1
		WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
		OUTPUT_VARIABLE GIT_HASH
		OUTPUT_STRIP_TRAILING_WHITESPACE
)
add_definitions(-DEMULATOR_HASH=${GIT_HASH})

if (ENABLE_VCPKG)
	# check if vcpkg is shallow and unshallow it if necessary
	execute_process(
	COMMAND git rev-parse --is-shallow-repository
	WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/dependencies/vcpkg
	OUTPUT_VARIABLE is_vcpkg_shallow
	OUTPUT_STRIP_TRAILING_WHITESPACE
    )

	if(is_vcpkg_shallow STREQUAL "true")
		message(STATUS "vcpkg is shallow. Unshallowing it now...")
		execute_process(
			COMMAND git fetch --unshallow
			WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/dependencies/vcpkg"
			RESULT_VARIABLE result
			OUTPUT_VARIABLE output
		)
	endif()


	if(UNIX AND NOT APPLE AND NOT VCPKG_TARGET_ANDROID)
		set(VCPKG_OVERLAY_PORTS "${CMAKE_CURRENT_LIST_DIR}/dependencies/vcpkg_overlay_ports_linux;${CMAKE_CURRENT_LIST_DIR}/dependencies/vcpkg_overlay_ports")
	elseif(APPLE)
		set(VCPKG_OVERLAY_PORTS "${CMAKE_CURRENT_LIST_DIR}/dependencies/vcpkg_overlay_ports_mac;${CMAKE_CURRENT_LIST_DIR}/dependencies/vcpkg_overlay_ports")
	else()
		set(VCPKG_OVERLAY_PORTS "${CMAKE_CURRENT_LIST_DIR}/dependencies/vcpkg_overlay_ports_win;${CMAKE_CURRENT_LIST_DIR}/dependencies/vcpkg_overlay_ports")
	endif()
	if(VCPKG_TARGET_ANDROID)
		set(ENV{ANDROID_NDK_HOME} ${ANDROID_NDK})
        set(ENV{VCPKG_ROOT} "${CMAKE_CURRENT_SOURCE_DIR}/dependencies/vcpkg")
		include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/vcpkg_android.cmake")
	else()
		set(CMAKE_TOOLCHAIN_FILE "${CMAKE_CURRENT_SOURCE_DIR}/dependencies/vcpkg/scripts/buildsystems/vcpkg.cmake"
			CACHE STRING "Vcpkg toolchain file")
	endif()
	# Set this so that all the various find_package() calls don't need an explicit
	# CONFIG option
	set(CMAKE_FIND_PACKAGE_PREFER_CONFIG TRUE)
	if (WIN32)
		set(VCPKG_TARGET_TRIPLET "x64-windows-static" CACHE STRING "")
	endif()
endif()

project(Cemu VERSION 2.0.0)

# Detect iOS build
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
	set(PLATFORM_IOS ON)
	add_compile_definitions(CEMU_PLATFORM_IOS=1)
	message(STATUS "✓ Building for iOS - platform defines set")
endif()

list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_compile_definitions($<$<CONFIG:Debug>:CEMU_DEBUG_ASSERT>) # if build type is debug, set CEMU_DEBUG_ASSERT

add_definitions(-DEMULATOR_VERSION_MAJOR=${EMULATOR_VERSION_MAJOR})
add_definitions(-DEMULATOR_VERSION_MINOR=${EMULATOR_VERSION_MINOR})
add_definitions(-DEMULATOR_VERSION_PATCH=${EMULATOR_VERSION_PATCH})

set_property(GLOBAL PROPERTY USE_FOLDERS ON)

# enable link time optimization for release builds
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE ON)
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELWITHDEBINFO ON)

if (MSVC)
	set_property(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR} PROPERTY VS_STARTUP_PROJECT CemuBin)
	# floating point model: precise, fiber safe optimizations
	add_compile_options(/EHsc /fp:precise)
	if (CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
		# Speeds up static linking (especially helpful in incremental compilation)
		if((CMAKE_LINKER MATCHES ".*lld-link.*") AND (CMAKE_AR MATCHES ".*llvm-lib.*"))
			set_property(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR} PROPERTY STATIC_LIBRARY_OPTIONS /llvmlibthin)
		endif()
  	else()
	  add_compile_options(/GT)
	endif()
	# enable additional optimization flags for release builds
	add_compile_options($<$<CONFIG:Release,RelWithDebInfo>:/Oi>) # enable intrinsic functions
	add_compile_options($<$<CONFIG:Release,RelWithDebInfo>:/Ot>) # favor speed
endif()

if (APPLE)
    enable_language(OBJC OBJCXX)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "13.4")
endif()

if (UNIX AND NOT APPLE)
	option(ENABLE_WAYLAND "Build with Wayland support" ON)
	option(ENABLE_FERAL_GAMEMODE "Enables Feral Interactive GameMode Support" ON)
	option(ENABLE_BLUEZ "Build with Bluez support" ON)
endif()

if (APPLE)
    set(ENABLE_METAL_DEFAULT ON)
else()
    set(ENABLE_METAL_DEFAULT OFF)
endif()

option(ENABLE_OPENGL "Enables the OpenGL backend" ON)
option(ENABLE_VULKAN "Enables the Vulkan backend" ON)
option(ENABLE_METAL "Enables the Metal backend" ${ENABLE_METAL_DEFAULT})
option(ENABLE_DISCORD_RPC "Enables the Discord Rich Presence feature" ON)

if (ENABLE_METAL AND NOT APPLE)
    message(FATAL_ERROR "Metal backend is only supported on Apple platforms")
endif()

# input backends
if (WIN32)
	option(ENABLE_XINPUT "Enables the usage of XInput" ON)
	option(ENABLE_DIRECTINPUT "Enables the usage of DirectInput" ON)
	add_compile_definitions(HAS_DIRECTINPUT)
endif()

option(ENABLE_HIDAPI "Build with HIDAPI" ON)
option(ENABLE_SDL "Enables the SDLController backend" ON)

# audio backends
if (WIN32)
	option(ENABLE_DIRECTAUDIO "Enables the directaudio backend" ON)
	option(ENABLE_XAUDIO "Enables the xaudio backend" ON)
endif()
option(ENABLE_CUBEB "Enabled cubeb backend" ON)

option(ENABLE_WXWIDGETS "Build with wxWidgets UI (Currently required)" ON)

# iOS: disable desktop-only / non-iOS backends. Metal is the renderer; there is no
# wxWidgets UI, no OpenGL, and no Vulkan loader on iOS. Discord RPC / HIDAPI are also
# unavailable. (Metal itself is enabled below via ENABLE_METAL default-on for Apple.)
if(PLATFORM_IOS)
	set(ENABLE_WXWIDGETS OFF CACHE BOOL "" FORCE)
	set(ENABLE_VULKAN OFF CACHE BOOL "" FORCE)
	set(ENABLE_OPENGL OFF CACHE BOOL "" FORCE)
	set(ENABLE_DISCORD_RPC OFF CACHE BOOL "" FORCE)
	set(ENABLE_HIDAPI OFF CACHE BOOL "" FORCE)
	# No cubeb on iOS yet (audio backend comes later — CoreAudio/AudioUnit). Without
	# this, src/audio would compile CubebAPI.cpp and link a cubeb::cubeb target that
	# isn't created on iOS. Silent audio is fine for bring-up.
	set(ENABLE_CUBEB OFF CACHE BOOL "" FORCE)
endif()

find_package(Threads REQUIRED)

# Real dependencies for all platforms INCLUDING iOS. iOS gets the same libraries via
# vcpkg's arm64-ios triplet (see vcpkg.json). The previous iOS branch used empty stub
# IMPORTED targets that provided no headers and could never actually compile the core.
if(TRUE)
	if(ENABLE_SDL)
		find_package(SDL2 REQUIRED)
		add_compile_definitions("HAS_SDL=1")
	endif()
	find_package(CURL REQUIRED)
	find_package(pugixml REQUIRED)
	find_package(RapidJSON REQUIRED)
	find_package(Boost COMPONENTS program_options filesystem nowide REQUIRED)
	if(ANDROID)
		find_package(Boost COMPONENTS context iostreams REQUIRED)
	endif()
	find_package(libzip REQUIRED)
	find_package(glslang REQUIRED)
	find_package(ZLIB REQUIRED)
	find_package(zstd MODULE REQUIRED) # MODULE so that zstd::zstd is available
	find_package(OpenSSL COMPONENTS Crypto SSL REQUIRED)
	find_package(glm REQUIRED)
	find_package(fmt 9 REQUIRED)
	find_package(PNG REQUIRED)

	# glslang versions older than 11.11.0 define targets without a namespace
	if (NOT TARGET glslang::SPIRV AND TARGET SPIRV)
		add_library(glslang::SPIRV ALIAS SPIRV)
	endif()
else()
	message(STATUS "iOS build: Phase 1 - Hybrid dependency resolution")

	# Use macOS SDK where possible
	find_package(ZLIB QUIET)
	if(NOT ZLIB_FOUND)
		add_library(ZLIB::ZLIB INTERFACE IMPORTED)
		set_target_properties(ZLIB::ZLIB PROPERTIES
			INTERFACE_LINK_LIBRARIES "-lz")
	endif()

	find_package(OpenSSL QUIET)
	if(NOT OpenSSL_FOUND)
		add_library(OpenSSL::Crypto INTERFACE IMPORTED)
		add_library(OpenSSL::SSL INTERFACE IMPORTED)
		set_target_properties(OpenSSL::Crypto PROPERTIES
			INTERFACE_LINK_LIBRARIES "-lSystem")
		set_target_properties(OpenSSL::SSL PROPERTIES
			INTERFACE_LINK_LIBRARIES "-lSystem")
	endif()

	# Create minimal stubs for everything else
	# (These are just placeholders - actual functionality Phase 2+)
	add_library(pugixml::pugixml INTERFACE IMPORTED)
	add_library(fmt::fmt INTERFACE IMPORTED)
	add_library(Boost::program_options INTERFACE IMPORTED)
	add_library(Boost::filesystem INTERFACE IMPORTED)
	add_library(Boost::nowide INTERFACE IMPORTED)
	add_library(Boost::headers INTERFACE IMPORTED)
	add_library(hidapi::hidapi INTERFACE IMPORTED)
	add_library(cubeb::cubeb INTERFACE IMPORTED)
	add_library(libzip::zip INTERFACE IMPORTED)
	add_library(glm::glm INTERFACE IMPORTED)
	add_library(SDL2::SDL2 INTERFACE IMPORTED)
	add_library(CURL::libcurl INTERFACE IMPORTED)
	add_library(RapidJSON::RapidJSON INTERFACE IMPORTED)
	add_library(Vulkan::Vulkan INTERFACE IMPORTED)
	add_library(glslang::SPIRV INTERFACE IMPORTED)
	add_library(zstd::zstd INTERFACE IMPORTED)
	add_library(PNG::PNG INTERFACE IMPORTED)
	add_library(wxWidgets::wxWidgets INTERFACE IMPORTED)
	add_library(imgui::imgui INTERFACE IMPORTED)

	message(STATUS "✓ iOS dependencies: macOS SDK + minimal stubs")
endif()

if (UNIX AND NOT APPLE AND NOT ANDROID)
	find_package(X11 REQUIRED)
	if (ENABLE_WAYLAND)
		find_package(Wayland REQUIRED Client)
		find_package(WaylandScanner REQUIRED)
		find_package(WaylandProtocols 1.15 REQUIRED)

		ecm_add_wayland_client_protocol(WAYLAND_PROTOCOL_SRCS
			PROTOCOL "${WaylandProtocols_DATADIR}/stable/viewporter/viewporter.xml"
			BASENAME viewporter)
		add_library(CemuWaylandProtocols STATIC ${WAYLAND_PROTOCOL_SRCS})
		target_include_directories(CemuWaylandProtocols PUBLIC "${CMAKE_CURRENT_BINARY_DIR}")
		target_include_directories(CemuWaylandProtocols PRIVATE ${Wayland_INCLUDE_DIRS})
		add_compile_definitions(HAS_WAYLAND)
	endif()
	find_package(GTK3 REQUIRED)

	if(ENABLE_BLUEZ)
		find_package(bluez REQUIRED)
		set(SUPPORTS_WIIMOTE ON)
		add_compile_definitions(HAS_BLUEZ)
	endif()

endif()

if (ENABLE_VULKAN OR PLATFORM_IOS)
	# iOS doesn't build/link Vulkan, but ~15 files #include VulkanAPI.h for shared
	# declarations (e.g. g_vulkan_available). With VK_NO_PROTOTYPES the headers are
	# declaration-only, so providing them lets those files parse without a loader.
	include_directories("dependencies/Vulkan-Headers/include")
endif()

if (ENABLE_OPENGL AND NOT PLATFORM_IOS)
	find_package(OpenGL REQUIRED)
endif()

if (ENABLE_METAL)
    # Metal is the iOS renderer too — metal-cpp is header-only and works on iOS.
    include_directories(${CMAKE_SOURCE_DIR}/dependencies/metal-cpp)
    add_definitions(-DENABLE_METAL=1)
endif()

if (ENABLE_DISCORD_RPC AND NOT PLATFORM_IOS)
	add_compile_definitions(ENABLE_DISCORD_RPC)
endif()

if (ENABLE_HIDAPI AND NOT PLATFORM_IOS)
	find_package(hidapi REQUIRED)
	set(SUPPORTS_WIIMOTE ON)
	add_compile_definitions(HAS_HIDAPI)
endif()

if(UNIX AND NOT APPLE AND NOT ANDROID)
	if(ENABLE_FERAL_GAMEMODE)
		add_compile_definitions(ENABLE_FERAL_GAMEMODE)
		add_subdirectory(dependencies/gamemode EXCLUDE_FROM_ALL)
		target_include_directories(gamemode INTERFACE ./dependencies/gamemode/lib)
	endif()
endif()

if (ENABLE_WXWIDGETS AND NOT PLATFORM_IOS)
	find_package(wxWidgets 3.3 REQUIRED COMPONENTS base core gl propgrid xrc)
endif()

if (ENABLE_CUBEB AND NOT PLATFORM_IOS)
	if (NOT ENABLE_VCPKG)
	    find_package(cubeb)
	endif()
	if (NOT cubeb_FOUND)
		option(BUILD_TESTS "" OFF)
		option(BUILD_TOOLS "" OFF)
		option(BUNDLE_SPEEX "" OFF)
		set(USE_WINMM OFF CACHE BOOL "")
		add_subdirectory("dependencies/cubeb" EXCLUDE_FROM_ALL SYSTEM)
		set_property(TARGET cubeb PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
		add_library(cubeb::cubeb ALIAS cubeb)
	endif()
	add_compile_definitions("HAS_CUBEB=1")
endif()

add_subdirectory("dependencies/ih264d" EXCLUDE_FROM_ALL)

if (CMAKE_OSX_ARCHITECTURES)
	set(CEMU_ARCHITECTURE ${CMAKE_OSX_ARCHITECTURES})
else()
	set(CEMU_ARCHITECTURE ${CMAKE_SYSTEM_PROCESSOR})
endif()
if(CEMU_ARCHITECTURE MATCHES "(aarch64)|(AARCH64)|(arm64)|(ARM64)")
	add_subdirectory("dependencies/xbyak_aarch64" EXCLUDE_FROM_ALL)
endif()

# ZArchive is needed on iOS too — it reads .wua game archives (fscDeviceWua.cpp).
# It's portable C++ and uses zstd, which iOS has via vcpkg.
find_package(ZArchive)
if (NOT ZArchive_FOUND)
	add_subdirectory("dependencies/ZArchive" EXCLUDE_FROM_ALL)
endif()

if(ANDROID)
	if(CMAKE_SYSTEM_PROCESSOR MATCHES "(aarch64)|(AARCH64)")
		add_subdirectory("dependencies/libadrenotools" EXCLUDE_FROM_ALL)
	endif()
	add_subdirectory("dependencies/stb" EXCLUDE_FROM_ALL)
endif()

add_subdirectory(src)
