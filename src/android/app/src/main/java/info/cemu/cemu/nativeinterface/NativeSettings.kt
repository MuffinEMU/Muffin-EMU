package info.cemu.cemu.nativeinterface

object NativeSettings {
    @JvmStatic
    external fun addGamesPath(uri: String?)

    @JvmStatic
    external fun removeGamesPath(uri: String?)

    @JvmStatic
    val gamesPaths: ArrayList<String>
        external get

    @JvmStatic
    var asyncShaderCompile: Boolean
        external get
        external set

    const val VSYNC_MODE_OFF: Int = 0
    const val VSYNC_MODE_DOUBLE_BUFFERING: Int = 1
    const val VSYNC_MODE_TRIPLE_BUFFERING: Int = 2

    @JvmStatic
    var vSyncMode: Int
        external get
        external set

    const val FULLSCREEN_SCALING_KEEP_ASPECT_RATIO: Int = 0
    const val FULLSCREEN_SCALING_STRETCH: Int = 1

    @JvmStatic
    var fullscreenScaling: Int
        external get
        external set

    const val SCALING_FILTER_BILINEAR_FILTER: Int = 0
    const val SCALING_FILTER_BICUBIC_FILTER: Int = 1
    const val SCALING_FILTER_BICUBIC_HERMITE_FILTER: Int = 2
    const val SCALING_FILTER_NEAREST_NEIGHBOR_FILTER: Int = 3

    @JvmStatic
    var upscalingFilter: Int
        external get
        external set

    @JvmStatic
    var downscalingFilter: Int
        external get
        external set

    @JvmStatic
    var accurateBarriers: Boolean
        external get
        external set

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

    const val AUDIO_BLOCK_COUNT: Int = 24

    @JvmStatic
    var audioLatency: Int
        external get
        external set

    const val OVERLAY_SCREEN_POSITION_DISABLED: Int = 0
    const val OVERLAY_SCREEN_POSITION_TOP_LEFT: Int = 1
    const val OVERLAY_SCREEN_POSITION_TOP_CENTER: Int = 2
    const val OVERLAY_SCREEN_POSITION_TOP_RIGHT: Int = 3
    const val OVERLAY_SCREEN_POSITION_BOTTOM_LEFT: Int = 4
    const val OVERLAY_SCREEN_POSITION_BOTTOM_CENTER: Int = 5
    const val OVERLAY_SCREEN_POSITION_BOTTOM_RIGHT: Int = 6

    @JvmStatic
    var overlayPosition: Int
        external get
        external set

    const val OVERLAY_TEXT_SCALE_MIN: Int = 50
    const val OVERLAY_TEXT_SCALE_MAX: Int = 300

    @JvmStatic
    var overlayTextScalePercentage: Int
        external get
        external set


    @JvmStatic
    var isOverlayFPSEnabled: Boolean
        external get
        external set

    @JvmStatic
    var isOverlayDrawCallsPerFrameEnabled: Boolean
        external get
        external set

    @JvmStatic
    var isOverlayCPUUsageEnabled: Boolean
        external get
        external set

    var isOverlayCPUPerCoreUsageEnabled: Boolean
        external get
        external set

    @JvmStatic
    var isOverlayRAMUsageEnabled: Boolean
        external get
        external set

    @JvmStatic
    var isOverlayDebugEnabled: Boolean
        external get
        external set

    @JvmStatic
    var notificationsPosition: Int
        external get
        external set

    @JvmStatic
    var notificationsTextScalePercentage: Int
        external get
        external set

    @JvmStatic
    var isNotificationControllerProfilesEnabled: Boolean
        external get
        external set

    @JvmStatic
    var isNotificationShaderCompilerEnabled: Boolean
        external get
        external set

    @JvmStatic
    var isNotificationFriendListEnabled: Boolean
        external get
        external set

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
    var consoleLanguage: Int
        external get
        external set
}
