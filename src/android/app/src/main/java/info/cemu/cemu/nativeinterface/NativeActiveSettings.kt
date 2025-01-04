package info.cemu.cemu.nativeinterface

object NativeActiveSettings {
    @JvmStatic
    external fun getMLCPath(): String

    @JvmStatic
    external fun getUserDataPath(): String
}
