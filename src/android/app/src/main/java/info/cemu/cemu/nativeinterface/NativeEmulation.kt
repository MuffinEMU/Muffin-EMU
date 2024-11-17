package info.cemu.cemu.nativeinterface

import android.view.Surface

object NativeEmulation {
    @JvmStatic
    external fun initializeActiveSettings(dataPath: String?, cachePath: String?)

    @JvmStatic
    external fun initializeEmulation()

    @JvmStatic
    external fun setDPI(dpi: Float)

    @JvmStatic
    external fun setSurface(surface: Surface?, isMainCanvas: Boolean)

    @JvmStatic
    external fun clearSurface(isMainCanvas: Boolean)

    @JvmStatic
    external fun setSurfaceSize(width: Int, height: Int, isMainCanvas: Boolean)

    @JvmStatic
    external fun initializeRenderer(surface: Surface?)

    const val START_GAME_SUCCESSFUL: Int = 0
    const val START_GAME_ERROR_GAME_BASE_FILES_NOT_FOUND: Int = 1
    const val START_GAME_ERROR_NO_DISC_KEY: Int = 2
    const val START_GAME_ERROR_NO_TITLE_TIK: Int = 3
    const val START_GAME_ERROR_UNKNOWN: Int = 4

    @JvmStatic
    external fun startGame(launchPath: String?): Int

    @JvmStatic
    external fun setReplaceTVWithPadView(swapped: Boolean)

    @JvmStatic
    external fun recreateRenderSurface(isMainCanvas: Boolean)
}
