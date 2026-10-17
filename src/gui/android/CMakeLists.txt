add_library(CemuAndroidGui STATIC
  WindowSystem.cpp
)

cemu_use_precompiled_header(CemuAndroidGui)

target_link_libraries(CemuAndroidGui PRIVATE
  CemuCommon
  CemuCafe
  CemuInput
  CemuConfig
  log
  android
)
