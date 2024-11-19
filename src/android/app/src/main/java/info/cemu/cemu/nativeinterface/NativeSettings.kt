package info.cemu.cemu.nativeinterface

object NativeSettings {
    @JvmStatic
    external fun addGamesPath(uri: String?)

    @JvmStatic
    external fun removeGamesPath(uri: String?)

    @JvmStatic
    external fun getGamesPaths(): ArrayList<String>

    @JvmStatic
    external fun getAsyncShaderCompile(): Boolean

    @JvmStatic
    external fun setAsyncShaderCompile(value: Boolean)

    const val VSYNC_MODE_OFF: Int = 0
    const val VSYNC_MODE_DOUBLE_BUFFERING: Int = 1
    const val VSYNC_MODE_TRIPLE_BUFFERING: Int = 2

    @JvmStatic
    external fun getVsyncMode(): Int

    @JvmStatic
    external fun setVsyncMode(value: Int)

    const val FULLSCREEN_SCALING_KEEP_ASPECT_RATIO: Int = 0
    const val FULLSCREEN_SCALING_STRETCH: Int = 1

    @JvmStatic
    external fun getFullscreenScaling(): Int

    @JvmStatic
    external fun setFullscreenScaling(value: Int)

    const val SCALING_FILTER_BILINEAR_FILTER: Int = 0
    const val SCALING_FILTER_BICUBIC_FILTER: Int = 1
    const val SCALING_FILTER_BICUBIC_HERMITE_FILTER: Int = 2
    const val SCALING_FILTER_NEAREST_NEIGHBOR_FILTER: Int = 3

    @JvmStatic
    external fun getUpscalingFilter(): Int

    @JvmStatic
    external fun setUpscalingFilter(value: Int)

    @JvmStatic
    external fun getDownscalingFilter(): Int

    @JvmStatic
    external fun setDownscalingFilter(value: Int)

    @JvmStatic
    external fun getAccurateBarriers(): Boolean

    @JvmStatic
    external fun setAccurateBarriers(value: Boolean)

    @JvmStatic
    external fun getAudioDeviceEnabled(tv: Boolean): Boolean

    @JvmStatic
    external fun setAudioDeviceEnabled(enabled: Boolean, tv: Boolean)

    const val AUDIO_CHANNELS_MONO: Int = 0
    const val AUDIO_CHANNELS_STEREO: Int = 1
    const val AUDIO_CHANNELS_SURROUND: Int = 2

    @JvmStatic
    external fun setAudioDeviceChannels(channels: Int, tv: Boolean)

    @JvmStatic
    external fun getAudioDeviceChannels(tv: Boolean): Int

    const val AUDIO_MIN_VOLUME: Int = 0
    const val AUDIO_MAX_VOLUME: Int = 100

    @JvmStatic
    external fun setAudioDeviceVolume(volume: Int, tv: Boolean)

    @JvmStatic
    external fun getAudioDeviceVolume(tv: Boolean): Int

    const val AUDIO_LATENCY_MS_MAX: Int = 276

    @JvmStatic
    external fun getAudioLatency(): Int

    @JvmStatic
    external fun setAudioLatency(value: Int)

    const val OVERLAY_SCREEN_POSITION_DISABLED: Int = 0
    const val OVERLAY_SCREEN_POSITION_TOP_LEFT: Int = 1
    const val OVERLAY_SCREEN_POSITION_TOP_CENTER: Int = 2
    const val OVERLAY_SCREEN_POSITION_TOP_RIGHT: Int = 3
    const val OVERLAY_SCREEN_POSITION_BOTTOM_LEFT: Int = 4
    const val OVERLAY_SCREEN_POSITION_BOTTOM_CENTER: Int = 5
    const val OVERLAY_SCREEN_POSITION_BOTTOM_RIGHT: Int = 6

    @JvmStatic
    external fun getOverlayPosition(): Int

    @JvmStatic
    external fun setOverlayPosition(value: Int)

    const val OVERLAY_TEXT_SCALE_MIN: Int = 50
    const val OVERLAY_TEXT_SCALE_MAX: Int = 300

    @JvmStatic
    external fun getOverlayTextScalePercentage(): Int

    @JvmStatic
    external fun setOverlayTextScalePercentage(value: Int)

    @JvmStatic
    external fun isOverlayFPSEnabled(): Boolean

    @JvmStatic
    external fun setOverlayFPSEnabled(value: Boolean)

    @JvmStatic
    external fun isOverlayDrawCallsPerFrameEnabled(): Boolean

    @JvmStatic
    external fun setOverlayDrawCallsPerFrameEnabled(value: Boolean)

    @JvmStatic
    external fun isOverlayCPUUsageEnabled(): Boolean

    @JvmStatic
    external fun setOverlayCPUUsageEnabled(value: Boolean)

    @JvmStatic
    external fun isOverlayRAMUsageEnabled(): Boolean

    @JvmStatic
    external fun setOverlayRAMUsageEnabled(value: Boolean)

    @JvmStatic
    external fun isOverlayDebugEnabled(): Boolean

    @JvmStatic
    external fun setOverlayDebugEnabled(value: Boolean)

    @JvmStatic
    external fun getNotificationsPosition(): Int

    @JvmStatic
    external fun setNotificationsPosition(value: Int)

    @JvmStatic
    external fun getNotificationsTextScalePercentage(): Int

    @JvmStatic
    external fun setNotificationsTextScalePercentage(value: Int)

    @JvmStatic
    external fun isNotificationControllerProfilesEnabled(): Boolean

    @JvmStatic
    external fun setNotificationControllerProfilesEnabled(value: Boolean)

    @JvmStatic
    external fun isNotificationShaderCompilerEnabled(): Boolean

    @JvmStatic
    external fun setNotificationShaderCompilerEnabled(value: Boolean)

    @JvmStatic
    external fun isNotificationFriendListEnabled(): Boolean

    @JvmStatic
    external fun setNotificationFriendListEnabled(value: Boolean)

    const val CONSOLE_LANGUAGE_JAPANESE: Int = 0
    const val CONSOLE_LANGUAGE_ENGLISH: Int = 1
    const val CONSOLE_LANGUAGE_FRENCH: Int = 2
    const val CONSOLE_LANGUAGE_GERMAN: Int = 3
    const val CONSOLE_LANGUAGE_ITALIAN: Int = 4
    const val CONSOLE_LANGUAGE_SPANISH: Int = 5
    const val CONSOLE_LANGUAGE_CHINESE: Int = 6
    const val CONSOLE_LANGUAGE_KOREAN: Int = 7
    const val CONSOLE_LANGUAGE_DUTCH: Int = 8
    const val CONSOLE_LANGUAGE_PORTUGUESE: Int = 9
    const val CONSOLE_LANGUAGE_RUSSIAN: Int = 10
    const val CONSOLE_LANGUAGE_TAIWANESE: Int = 11

    @JvmStatic
    external fun getConsoleLanguage(): Int

    @JvmStatic
    external fun setConsoleLanguage(value: Int)
}
