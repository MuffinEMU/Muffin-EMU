package info.cemu.cemu.guicore.enumtostringmapper.native

import androidx.annotation.StringRes
import info.cemu.cemu.R
import info.cemu.cemu.nativeinterface.NativeGameTitles

@StringRes
fun cpuModeToStringId(cpuMode: Int): Int = when (cpuMode) {
    NativeGameTitles.CPU_MODE_SINGLECOREINTERPRETER -> R.string.cpu_mode_single_core_interpreter
    NativeGameTitles.CPU_MODE_SINGLECORERECOMPILER -> R.string.cpu_mode_single_core_recompiler
    NativeGameTitles.CPU_MODE_MULTICORERECOMPILER -> R.string.cpu_mode_multi_core_recompiler
    else -> R.string.cpu_mode_auto
}

@StringRes
fun regionToStringId(region: Int): Int = when (region) {
    NativeGameTitles.CONSOLE_REGION_JPN -> R.string.console_region_japan
    NativeGameTitles.CONSOLE_REGION_USA -> R.string.console_region_usa
    NativeGameTitles.CONSOLE_REGION_EUR -> R.string.console_region_europe
    NativeGameTitles.CONSOLE_REGION_AUS_DEPR -> R.string.console_region_australia
    NativeGameTitles.CONSOLE_REGION_CHN -> R.string.console_region_china
    NativeGameTitles.CONSOLE_REGION_KOR -> R.string.console_region_korea
    NativeGameTitles.CONSOLE_REGION_TWN -> R.string.console_region_taiwan
    NativeGameTitles.CONSOLE_REGION_AUTO -> R.string.console_region_auto
    else -> R.string.console_region_many
}
