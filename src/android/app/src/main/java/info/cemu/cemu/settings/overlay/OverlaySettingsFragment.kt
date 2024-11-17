package info.cemu.cemu.settings.overlay

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import info.cemu.cemu.R
import info.cemu.cemu.databinding.LayoutGenericRecyclerViewBinding
import info.cemu.cemu.guibasecomponents.GenericRecyclerViewAdapter
import info.cemu.cemu.guibasecomponents.HeaderRecyclerViewItem
import info.cemu.cemu.guibasecomponents.SingleSelectionRecyclerViewItem
import info.cemu.cemu.guibasecomponents.SliderRecyclerViewItem
import info.cemu.cemu.guibasecomponents.ToggleRecyclerViewItem
import info.cemu.cemu.nativeinterface.NativeSettings

import java.util.List

class OverlaySettingsFragment : Fragment() {
    private fun overlayScreenPositionToString(overlayScreenPosition: Int): String {
        val resourceId = when (overlayScreenPosition) {
            NativeSettings.OVERLAY_SCREEN_POSITION_DISABLED -> R.string.overlay_position_disabled
            NativeSettings.OVERLAY_SCREEN_POSITION_TOP_LEFT -> R.string.overlay_position_top_left
            NativeSettings.OVERLAY_SCREEN_POSITION_TOP_CENTER -> R.string.overlay_position_top_center
            NativeSettings.OVERLAY_SCREEN_POSITION_TOP_RIGHT -> R.string.overlay_position_top_right
            NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_LEFT -> R.string.overlay_position_bottom_left
            NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_CENTER -> R.string.overlay_position_bottom_center
            NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_RIGHT -> R.string.overlay_position_bottom_right
            else -> throw IllegalArgumentException("Invalid overlay position: $overlayScreenPosition")
        }
        return getString(resourceId)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false)

        val genericRecyclerViewAdapter = GenericRecyclerViewAdapter()

        val overlayPositionChoices = List.of(
            NativeSettings.OVERLAY_SCREEN_POSITION_DISABLED,
            NativeSettings.OVERLAY_SCREEN_POSITION_TOP_LEFT,
            NativeSettings.OVERLAY_SCREEN_POSITION_TOP_CENTER,
            NativeSettings.OVERLAY_SCREEN_POSITION_TOP_RIGHT,
            NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_LEFT,
            NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_CENTER,
            NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_RIGHT
        )

        val overlayPositionSelection = SingleSelectionRecyclerViewItem(
            getString(R.string.overlay_position),
            NativeSettings.overlayPosition,
            overlayPositionChoices,
            { overlayScreenPosition: Int -> this.overlayScreenPositionToString(overlayScreenPosition) },
            NativeSettings::overlayPosition::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(overlayPositionSelection)

        val overlayTextScale = SliderRecyclerViewItem(getString(R.string.overlay_text_scale),
            NativeSettings.OVERLAY_TEXT_SCALE_MIN.toFloat(),
            NativeSettings.OVERLAY_TEXT_SCALE_MAX.toFloat(),
            NativeSettings.overlayTextScalePercentage.toFloat(),
            25.0f,
            { value: Float ->
                NativeSettings.overlayTextScalePercentage =
                    value.toInt()
            },
            { value: Float -> value.toInt().toString() + "%" })
        genericRecyclerViewAdapter.addRecyclerViewItem(overlayTextScale)

        val overlayFps = ToggleRecyclerViewItem(
            getString(R.string.fps),
            getString(R.string.fps_overlay_description),
            NativeSettings.isOverlayFPSEnabled,
            NativeSettings::isOverlayFPSEnabled::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(overlayFps)

        val drawCallsToggle = ToggleRecyclerViewItem(
            getString(R.string.draw_calls_per_frame),
            getString(R.string.draw_calls_per_frame_overlay_description),
            NativeSettings.isOverlayDrawCallsPerFrameEnabled,
            NativeSettings::isOverlayDrawCallsPerFrameEnabled::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(drawCallsToggle)

        val cpuUsageToggle = ToggleRecyclerViewItem(
            getString(R.string.cpu_usage),
            getString(R.string.cpu_usage_overlay_description),
            NativeSettings.isOverlayCPUUsageEnabled,
            NativeSettings::isOverlayCPUUsageEnabled::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(cpuUsageToggle)

        val ramUsageToggle = ToggleRecyclerViewItem(
            getString(R.string.ram_usage),
            getString(R.string.ram_usage_overlay_description),
            NativeSettings.isOverlayRAMUsageEnabled,
            NativeSettings::isOverlayRAMUsageEnabled::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(ramUsageToggle)

        val debugToggle = ToggleRecyclerViewItem(
            getString(R.string.debug),
            getString(R.string.debug_overlay_description),
            NativeSettings.isOverlayDebugEnabled,
            NativeSettings::isOverlayDebugEnabled::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(debugToggle)

        genericRecyclerViewAdapter.addRecyclerViewItem(HeaderRecyclerViewItem(R.string.notifications))

        val notificationsPositionSelection = SingleSelectionRecyclerViewItem(
            getString(R.string.overlay_position),
            NativeSettings.notificationsPosition,
            overlayPositionChoices,
            { overlayScreenPosition: Int -> this.overlayScreenPositionToString(overlayScreenPosition) },
            NativeSettings::notificationsPosition::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(notificationsPositionSelection)

        val notificationTextScale =
            SliderRecyclerViewItem(getString(R.string.notifications_text_scale),
                NativeSettings.OVERLAY_TEXT_SCALE_MIN.toFloat(),
                NativeSettings.OVERLAY_TEXT_SCALE_MAX.toFloat(),
                NativeSettings.notificationsTextScalePercentage.toFloat(),
                25.0f,
                { value: Float ->
                    NativeSettings.notificationsTextScalePercentage =
                        value.toInt()
                },
                { value: Float -> value.toInt().toString() + "%" })
        genericRecyclerViewAdapter.addRecyclerViewItem(notificationTextScale)

        val controllerProfiles = ToggleRecyclerViewItem(
            getString(R.string.controller_profiles),
            getString(R.string.controller_profiles_notification_description),
            NativeSettings.isNotificationControllerProfilesEnabled,
            NativeSettings::isNotificationControllerProfilesEnabled::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(controllerProfiles)

        val shaderCompiler = ToggleRecyclerViewItem(
            getString(R.string.shader_compiler),
            getString(R.string.shader_compiler_notification_description),
            NativeSettings.isNotificationShaderCompilerEnabled,
            NativeSettings::isNotificationShaderCompilerEnabled::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(shaderCompiler)

        val friendList = ToggleRecyclerViewItem(
            getString(R.string.friend_list),
            getString(R.string.friend_list_notification_description),
            NativeSettings.isNotificationFriendListEnabled,
            NativeSettings::isNotificationFriendListEnabled::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(friendList)

        binding.recyclerView.adapter = genericRecyclerViewAdapter

        return binding.root
    }
}