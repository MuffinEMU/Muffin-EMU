package info.cemu.cemu.guicore.nativeenummapper

import androidx.annotation.StringRes
import info.cemu.cemu.R
import info.cemu.cemu.nativeinterface.NativeSettings

@StringRes
fun channelsToStringId(channels: Int) = when (channels) {
    NativeSettings.AUDIO_CHANNELS_MONO -> R.string.mono
    NativeSettings.AUDIO_CHANNELS_STEREO -> R.string.stereo
    NativeSettings.AUDIO_CHANNELS_SURROUND -> R.string.surround
    else -> throw IllegalArgumentException("Invalid channels type: $channels")
}

@StringRes
fun consoleLanguageToStringId(channels: Int): Int = when (channels) {
    NativeSettings.CONSOLE_LANGUAGE_JAPANESE -> R.string.console_language_japanese
    NativeSettings.CONSOLE_LANGUAGE_ENGLISH -> R.string.console_language_english
    NativeSettings.CONSOLE_LANGUAGE_FRENCH -> R.string.console_language_french
    NativeSettings.CONSOLE_LANGUAGE_GERMAN -> R.string.console_language_german
    NativeSettings.CONSOLE_LANGUAGE_ITALIAN -> R.string.console_language_italian
    NativeSettings.CONSOLE_LANGUAGE_SPANISH -> R.string.console_language_spanish
    NativeSettings.CONSOLE_LANGUAGE_CHINESE -> R.string.console_language_chinese
    NativeSettings.CONSOLE_LANGUAGE_KOREAN -> R.string.console_language_korean
    NativeSettings.CONSOLE_LANGUAGE_DUTCH -> R.string.console_language_dutch
    NativeSettings.CONSOLE_LANGUAGE_PORTUGUESE -> R.string.console_language_portuguese
    NativeSettings.CONSOLE_LANGUAGE_RUSSIAN -> R.string.console_language_russian
    NativeSettings.CONSOLE_LANGUAGE_TAIWANESE -> R.string.console_language_taiwanese
    else -> throw IllegalArgumentException("Invalid console language: $channels")
}

@StringRes
fun vsyncModeToStringId(vsyncMode: Int) = when (vsyncMode) {
    NativeSettings.VSYNC_MODE_OFF -> R.string.off
    NativeSettings.VSYNC_MODE_DOUBLE_BUFFERING -> R.string.double_buffering
    NativeSettings.VSYNC_MODE_TRIPLE_BUFFERING -> R.string.triple_buffering
    else -> throw IllegalArgumentException("Invalid vsync mode: $vsyncMode")
}

@StringRes
fun fullscreenScalingModeToStringId(fullscreenScaling: Int) = when (fullscreenScaling) {
    NativeSettings.FULLSCREEN_SCALING_KEEP_ASPECT_RATIO -> R.string.keep_aspect_ratio
    NativeSettings.FULLSCREEN_SCALING_STRETCH -> R.string.stretch
    else -> throw IllegalArgumentException("Invalid fullscreen scaling mode:  $fullscreenScaling")
}

@StringRes
fun scalingFilterToStringId(scalingFilter: Int) = when (scalingFilter) {
    NativeSettings.SCALING_FILTER_BILINEAR_FILTER -> R.string.bilinear
    NativeSettings.SCALING_FILTER_BICUBIC_FILTER -> R.string.bicubic
    NativeSettings.SCALING_FILTER_BICUBIC_HERMITE_FILTER -> R.string.hermite
    NativeSettings.SCALING_FILTER_NEAREST_NEIGHBOR_FILTER -> R.string.nearest_neighbor
    else -> throw IllegalArgumentException("Invalid scaling filter:  $scalingFilter")
}

@StringRes
fun overlayScreenPositionToStringId(overlayScreenPosition: Int) = when (overlayScreenPosition) {
    NativeSettings.OVERLAY_SCREEN_POSITION_DISABLED -> R.string.overlay_position_disabled
    NativeSettings.OVERLAY_SCREEN_POSITION_TOP_LEFT -> R.string.overlay_position_top_left
    NativeSettings.OVERLAY_SCREEN_POSITION_TOP_CENTER -> R.string.overlay_position_top_center
    NativeSettings.OVERLAY_SCREEN_POSITION_TOP_RIGHT -> R.string.overlay_position_top_right
    NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_LEFT -> R.string.overlay_position_bottom_left
    NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_CENTER -> R.string.overlay_position_bottom_center
    NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_RIGHT -> R.string.overlay_position_bottom_right
    else -> throw IllegalArgumentException("Invalid overlay position: $overlayScreenPosition")
}