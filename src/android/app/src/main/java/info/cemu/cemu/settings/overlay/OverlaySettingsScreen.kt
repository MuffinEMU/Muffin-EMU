package info.cemu.cemu.settings.overlay

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import info.cemu.cemu.R
import info.cemu.cemu.guicore.components.Header
import info.cemu.cemu.guicore.components.ScreenContent
import info.cemu.cemu.guicore.components.SingleSelection
import info.cemu.cemu.guicore.components.Slider
import info.cemu.cemu.guicore.components.Toggle
import info.cemu.cemu.guicore.nativeenummapper.overlayScreenPositionToStringId
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
    var overlayPosition by rememberSaveable { mutableIntStateOf(NativeSettings.getOverlayPosition()) }
    var notificationsPosition by rememberSaveable { mutableIntStateOf(NativeSettings.getNotificationsPosition()) }
    ScreenContent(
        appBarText = stringResource(R.string.overlay_settings),
        navigateBack = navigateBack,
    ) {
        Header(stringResource(R.string.overlay))
        SingleSelection(
            label = stringResource(R.string.overlay_position),
            choice = overlayPosition,
            choices = OverlayPositionChoices,
            choiceToString = { stringResource(overlayScreenPositionToStringId(it)) },
            onChoiceChanged = {
                overlayPosition = it
                NativeSettings.setOverlayPosition(it)
            },
        )
        if (overlayPosition != NativeSettings.OVERLAY_SCREEN_POSITION_DISABLED)
            OverlaySettings()
        Header(stringResource(R.string.notifications))
        SingleSelection(
            label = stringResource(R.string.overlay_position),
            choice = notificationsPosition,
            choices = OverlayPositionChoices,
            choiceToString = { stringResource(overlayScreenPositionToStringId(it)) },
            onChoiceChanged = {
                notificationsPosition = it
                NativeSettings.setNotificationsPosition(it)
            },
        )
        if (notificationsPosition != NativeSettings.OVERLAY_SCREEN_POSITION_DISABLED)
            NotificationSettings()
    }
}

@Composable
private fun OverlaySettings() {
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
}

@Composable
private fun NotificationSettings() {
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