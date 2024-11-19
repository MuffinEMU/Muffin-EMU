package info.cemu.cemu.settings.graphics

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import info.cemu.cemu.R
import info.cemu.cemu.guicore.ScreenContent
import info.cemu.cemu.guicore.SingleSelection
import info.cemu.cemu.guicore.Toggle
import info.cemu.cemu.guicore.enumtostringmapper.native.fullscreenScalingModeToStringId
import info.cemu.cemu.guicore.enumtostringmapper.native.scalingFilterToStringId
import info.cemu.cemu.guicore.enumtostringmapper.native.vsyncModeToStringId
import info.cemu.cemu.nativeinterface.NativeSettings


val ScalingFilterChoices = listOf(
    NativeSettings.SCALING_FILTER_BILINEAR_FILTER,
    NativeSettings.SCALING_FILTER_BICUBIC_FILTER,
    NativeSettings.SCALING_FILTER_BICUBIC_HERMITE_FILTER,
    NativeSettings.SCALING_FILTER_NEAREST_NEIGHBOR_FILTER
)

@Composable
fun GraphicsSettingsScreen(navigateBack: () -> Unit) {
    ScreenContent(
        appBarText = stringResource(R.string.general_settings),
        navigateBack = navigateBack,
    ) {
        Toggle(
            label = stringResource(R.string.async_shader_compile),
            description = stringResource(R.string.async_shader_compile_description),
            initialCheckedState = NativeSettings::getAsyncShaderCompile,
            onCheckedChanged = NativeSettings::setAsyncShaderCompile,
        )
        SingleSelection(
            label = stringResource(R.string.vsync),
            initialChoice = NativeSettings::getVsyncMode,
            onChoiceChanged = NativeSettings::setVsyncMode,
            choiceToString = { stringResource(vsyncModeToStringId(it)) },
            choices = listOf(
                NativeSettings.VSYNC_MODE_OFF,
                NativeSettings.VSYNC_MODE_DOUBLE_BUFFERING,
                NativeSettings.VSYNC_MODE_TRIPLE_BUFFERING
            ),
        )
        Toggle(
            label = stringResource(R.string.accurate_barriers),
            description = stringResource(R.string.accurate_barriers_description),
            initialCheckedState = NativeSettings::getAccurateBarriers,
            onCheckedChanged = NativeSettings::setAccurateBarriers,
        )
        SingleSelection(
            label = stringResource(R.string.fullscreen_scaling),
            initialChoice = NativeSettings::getFullscreenScaling,
            onChoiceChanged = NativeSettings::setFullscreenScaling,
            choiceToString = { stringResource(fullscreenScalingModeToStringId(it)) },
            choices = listOf(
                NativeSettings.FULLSCREEN_SCALING_KEEP_ASPECT_RATIO,
                NativeSettings.FULLSCREEN_SCALING_STRETCH
            ),
        )
        SingleSelection(
            label = stringResource(R.string.upscale_filter),
            initialChoice = NativeSettings::getUpscalingFilter,
            onChoiceChanged = NativeSettings::setUpscalingFilter,
            choiceToString = { stringResource(scalingFilterToStringId(it)) },
            choices = ScalingFilterChoices,
        )
        SingleSelection(
            label = stringResource(R.string.downscale_filter),
            initialChoice = NativeSettings::getDownscalingFilter,
            onChoiceChanged = NativeSettings::setDownscalingFilter,
            choiceToString = { stringResource(scalingFilterToStringId(it)) },
            choices = ScalingFilterChoices,
        )
    }
}