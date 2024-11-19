package info.cemu.cemu.settings.overlay

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import info.cemu.cemu.R
import info.cemu.cemu.guicore.Header
import info.cemu.cemu.guicore.ScreenContent
import info.cemu.cemu.guicore.SingleSelection
import info.cemu.cemu.guicore.Slider
import info.cemu.cemu.guicore.Toggle
import info.cemu.cemu.guicore.enumtostringmapper.native.overlayScreenPositionToStringId
import info.cemu.cemu.nativeinterface.NativeSettings


private val OverlayPositionChoices = listOf(
    NativeSettings.OVERLAY_SCREEN_POSITION_DISABLED,
    NativeSettings.OVERLAY_SCREEN_POSITION_TOP_LEFT,
    NativeSettings.OVERLAY_SCREEN_POSITION_TOP_CENTER,
    NativeSettings.OVERLAY_SCREEN_POSITION_TOP_RIGHT,
    NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_LEFT,
    NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_CENTER,
    NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_RIGHT
)

private const val OVERLAY_TEXT_SCALE_STEPS = 9

@Composable
fun OverlaySettingsScreen(navigateBack: () -> Unit) {
    ScreenContent(
        appBarText = stringResource(R.string.overlay_settings),
        navigateBack = navigateBack,
    ) {
        Header(stringResource(R.string.overlay))
        SingleSelection(
            label = stringResource(R.string.overlay_position),
            initialChoice = NativeSettings::getOverlayPosition,
            choices = OverlayPositionChoices,
            choiceToString = { stringResource(overlayScreenPositionToStringId(it)) },
            onChoiceChanged = NativeSettings::setOverlayPosition,
        )
        Slider(
            label = stringResource(R.string.overlay_text_scale),
            initialValue = NativeSettings::getOverlayTextScalePercentage,
            steps = OVERLAY_TEXT_SCALE_STEPS,
            valueFrom = NativeSettings.OVERLAY_TEXT_SCALE_MIN,
            valueTo = NativeSettings.OVERLAY_TEXT_SCALE_MAX,
            onValueChange = NativeSettings::setOverlayTextScalePercentage,
            labelFormatter = { "${it}%" }
        )
        Toggle(
            label = stringResource(R.string.fps),
            description = stringResource(R.string.fps_overlay_description),
            initialCheckedState = NativeSettings::isOverlayFPSEnabled,
            onCheckedChanged = NativeSettings::setOverlayFPSEnabled,
        )
        Toggle(
            label = stringResource(R.string.draw_calls_per_frame),
            description = stringResource(R.string.draw_calls_per_frame_overlay_description),
            initialCheckedState = NativeSettings::isOverlayDrawCallsPerFrameEnabled,
            onCheckedChanged = NativeSettings::setOverlayDrawCallsPerFrameEnabled,
        )
        Toggle(
            label = stringResource(R.string.cpu_usage),
            description = stringResource(R.string.cpu_usage_overlay_description),
            initialCheckedState = NativeSettings::isOverlayCPUUsageEnabled,
            onCheckedChanged = NativeSettings::setOverlayCPUUsageEnabled,
        )
        Toggle(
            label = stringResource(R.string.ram_usage),
            description = stringResource(R.string.ram_usage_overlay_description),
            initialCheckedState = NativeSettings::isOverlayRAMUsageEnabled,
            onCheckedChanged = NativeSettings::setOverlayRAMUsageEnabled,
        )
        Toggle(
            label = stringResource(R.string.debug),
            description = stringResource(R.string.debug_overlay_description),
            initialCheckedState = NativeSettings::isOverlayDebugEnabled,
            onCheckedChanged = NativeSettings::setOverlayDebugEnabled,
        )
        Header(stringResource(R.string.notifications))
        SingleSelection(
            label = stringResource(R.string.overlay_position),
            initialChoice = NativeSettings::getNotificationsPosition,
            choices = OverlayPositionChoices,
            choiceToString = { stringResource(overlayScreenPositionToStringId(it)) },
            onChoiceChanged = NativeSettings::setNotificationsPosition,
        )
        Slider(
            label = stringResource(R.string.notifications_text_scale),
            initialValue = NativeSettings::getNotificationsTextScalePercentage,
            steps = OVERLAY_TEXT_SCALE_STEPS,
            valueFrom = NativeSettings.OVERLAY_TEXT_SCALE_MIN,
            valueTo = NativeSettings.OVERLAY_TEXT_SCALE_MAX,
            onValueChange = NativeSettings::setNotificationsTextScalePercentage,
            labelFormatter = { "$it%" }
        )
        Toggle(
            label = stringResource(R.string.controller_profiles),
            description = stringResource(R.string.controller_profiles_notification_description),
            initialCheckedState = NativeSettings::isNotificationControllerProfilesEnabled,
            onCheckedChanged = NativeSettings::setNotificationControllerProfilesEnabled,
        )
        Toggle(
            label = stringResource(R.string.shader_compiler),
            description = stringResource(R.string.shader_compiler_notification_description),
            initialCheckedState = NativeSettings::isNotificationShaderCompilerEnabled,
            onCheckedChanged = NativeSettings::setNotificationShaderCompilerEnabled,
        )
        Toggle(
            label = stringResource(R.string.friend_list),
            description = stringResource(R.string.friend_list_notification_description),
            initialCheckedState = NativeSettings::isNotificationFriendListEnabled,
            onCheckedChanged = NativeSettings::setNotificationFriendListEnabled,
        )
    }
}