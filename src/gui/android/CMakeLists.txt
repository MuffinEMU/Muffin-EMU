add_library(CemuAndroidGui STATIC
  WindowSystem.cpp
)

cemu_use_precompiled_header(CemuAndroidGui)

target_link_libraries(CemuAndroidGui PRIVATE
  CemuCommon
  CemuCafe
  CemuInput
  CemuConfig
  # the imgui icon font and the Cafe default font (src/resource), which the iOS GUI library links the same way
  CemuResource
  log
  android
)
