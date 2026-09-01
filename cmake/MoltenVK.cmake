# MoltenVK for iOS -- the Vulkan implementation the Vulkan backend runs on.
#
# vcpkg has no MoltenVK port (checked: neither `molten-vk` nor `moltenvk` exists
# upstream), so this fetches the official Khronos release artifact instead. The iOS
# tarball ships both a static libMoltenVK.a and a dynamic MoltenVK.framework.
#
# We take the STATIC one deliberately. The dynamic framework would have to be
# embedded in the .app, re-signed, and found via @rpath at runtime -- three extra
# failure points on a sideloaded build, and LiveContainer has already been observed
# mangling this app's executable layout once. Static links MoltenVK straight into
# the binary and there is nothing to embed or sign.
#
# The catch with static + Cemu's loader: VulkanAPI.cpp resolves every entry point
# through dlsym() rather than direct calls, so at link time literally nothing
# references the archive and the linker would drop all of it. -force_load pulls the
# whole archive in regardless. The loader then dlopen(nullptr)s the main image and
# dlsym finds the symbols there -- see dlopen_vulkan_loader() in VulkanAPI.cpp.

set(MOLTENVK_VERSION "1.4.2" CACHE STRING "MoltenVK release to link against on iOS")
set(MOLTENVK_URL "https://github.com/KhronosGroup/MoltenVK/releases/download/v${MOLTENVK_VERSION}/MoltenVK-ios.tar")
set(MOLTENVK_DIR "${CMAKE_BINARY_DIR}/_moltenvk")
set(MOLTENVK_LIB "${MOLTENVK_DIR}/MoltenVK/MoltenVK/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a")

if(NOT EXISTS "${MOLTENVK_LIB}")
	message(STATUS "Fetching MoltenVK ${MOLTENVK_VERSION} for iOS")
	file(MAKE_DIRECTORY "${MOLTENVK_DIR}")
	file(DOWNLOAD "${MOLTENVK_URL}" "${MOLTENVK_DIR}/MoltenVK-ios.tar"
		SHOW_PROGRESS
		STATUS MOLTENVK_DL_STATUS)
	list(GET MOLTENVK_DL_STATUS 0 MOLTENVK_DL_CODE)
	if(NOT MOLTENVK_DL_CODE EQUAL 0)
		list(GET MOLTENVK_DL_STATUS 1 MOLTENVK_DL_MSG)
		message(FATAL_ERROR "Failed to download MoltenVK: ${MOLTENVK_DL_MSG}")
	endif()
	execute_process(
		COMMAND ${CMAKE_COMMAND} -E tar xf "${MOLTENVK_DIR}/MoltenVK-ios.tar"
		WORKING_DIRECTORY "${MOLTENVK_DIR}"
		RESULT_VARIABLE MOLTENVK_TAR_RESULT)
	if(NOT MOLTENVK_TAR_RESULT EQUAL 0)
		message(FATAL_ERROR "Failed to extract MoltenVK-ios.tar")
	endif()
endif()

if(NOT EXISTS "${MOLTENVK_LIB}")
	message(FATAL_ERROR "MoltenVK static library missing after fetch: ${MOLTENVK_LIB}")
endif()

add_library(MoltenVK::MoltenVK INTERFACE IMPORTED)
target_link_options(MoltenVK::MoltenVK INTERFACE "-Wl,-force_load,${MOLTENVK_LIB}")
# MoltenVK itself needs these; the static archive does not carry them.
target_link_libraries(MoltenVK::MoltenVK INTERFACE
	"-framework Metal"
	"-framework Foundation"
	"-framework QuartzCore"
	"-framework IOSurface"
	"-framework UIKit"
	"-framework CoreGraphics"
)
message(STATUS "MoltenVK: ${MOLTENVK_LIB}")
