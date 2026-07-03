#----------------------------------------------------------------
# Generated CMake target import file for configuration "Release".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "xbyak_aarch64::xbyak_aarch64" for configuration "Release"
set_property(TARGET xbyak_aarch64::xbyak_aarch64 APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(xbyak_aarch64::xbyak_aarch64 PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_RELEASE "CXX"
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib/libxbyak_aarch64.a"
  )

list(APPEND _cmake_import_check_targets xbyak_aarch64::xbyak_aarch64 )
list(APPEND _cmake_import_check_files_for_xbyak_aarch64::xbyak_aarch64 "${_IMPORT_PREFIX}/lib/libxbyak_aarch64.a" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
