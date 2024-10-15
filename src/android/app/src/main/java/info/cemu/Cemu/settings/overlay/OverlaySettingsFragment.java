package info.cemu.Cemu.settings.overlay;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.NonNull;
import androidx.fragment.app.Fragment;

import java.util.List;

import info.cemu.Cemu.R;
import info.cemu.Cemu.databinding.LayoutGenericRecyclerViewBinding;
import info.cemu.Cemu.guibasecomponents.GenericRecyclerViewAdapter;
import info.cemu.Cemu.guibasecomponents.HeaderRecyclerViewItem;
import info.cemu.Cemu.guibasecomponents.SingleSelectionRecyclerViewItem;
import info.cemu.Cemu.guibasecomponents.SliderRecyclerViewItem;
import info.cemu.Cemu.guibasecomponents.ToggleRecyclerViewItem;
import info.cemu.Cemu.nativeinterface.NativeSettings;

public class OverlaySettingsFragment extends Fragment {
    private String overlayScreenPositionToString(int overlayScreenPosition) {
        int resourceId = switch (overlayScreenPosition) {
            case NativeSettings.OVERLAY_SCREEN_POSITION_DISABLED ->
                    R.string.overlay_position_disabled;
            case NativeSettings.OVERLAY_SCREEN_POSITION_TOP_LEFT ->
                    R.string.overlay_position_top_left;
            case NativeSettings.OVERLAY_SCREEN_POSITION_TOP_CENTER ->
                    R.string.overlay_position_top_center;
            case NativeSettings.OVERLAY_SCREEN_POSITION_TOP_RIGHT ->
                    R.string.overlay_position_top_right;
            case NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_LEFT ->
                    R.string.overlay_position_bottom_left;
            case NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_CENTER ->
                    R.string.overlay_position_bottom_center;
            case NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_RIGHT ->
                    R.string.overlay_position_bottom_right;
            default ->
                    throw new IllegalArgumentException("Invalid overlay position: " + overlayScreenPosition);
        };
        return getString(resourceId);
    }

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        var binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false);

        GenericRecyclerViewAdapter genericRecyclerViewAdapter = new GenericRecyclerViewAdapter();

        var overlayPositionChoices = List.of(
                NativeSettings.OVERLAY_SCREEN_POSITION_DISABLED,
                NativeSettings.OVERLAY_SCREEN_POSITION_TOP_LEFT,
                NativeSettings.OVERLAY_SCREEN_POSITION_TOP_CENTER,
                NativeSettings.OVERLAY_SCREEN_POSITION_TOP_RIGHT,
                NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_LEFT,
                NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_CENTER,
                NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_RIGHT);

        SingleSelectionRecyclerViewItem<Integer> overlayPositionSelection = new SingleSelectionRecyclerViewItem<>(getString(R.string.overlay_position),
                NativeSettings.getOverlayPosition(),
                overlayPositionChoices,
                this::overlayScreenPositionToString,
                NativeSettings::setOverlayPosition);
        genericRecyclerViewAdapter.addRecyclerViewItem(overlayPositionSelection);

        SliderRecyclerViewItem overlayTextScale = new SliderRecyclerViewItem(getString(R.string.overlay_text_scale),
                NativeSettings.OVERLAY_TEXT_SCALE_MIN,
                NativeSettings.OVERLAY_TEXT_SCALE_MAX,
                NativeSettings.getOverlayTextScalePercentage(),
                25.0f,
                value -> NativeSettings.setOverlayTextScalePercentage((int) value),
                value -> (int) value + "%");
        genericRecyclerViewAdapter.addRecyclerViewItem(overlayTextScale);

        ToggleRecyclerViewItem overlayFps = new ToggleRecyclerViewItem(getString(R.string.fps),
                getString(R.string.fps_overlay_description), NativeSettings.isOverlayFPSEnabled(),
                NativeSettings::setOverlayFPSEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(overlayFps);

        ToggleRecyclerViewItem drawCallsToggle = new ToggleRecyclerViewItem(getString(R.string.draw_calls_per_frame),
                getString(R.string.draw_calls_per_frame_overlay_description), NativeSettings.isOverlayDrawCallsPerFrameEnabled(),
                NativeSettings::setOverlayDrawCallsPerFrameEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(drawCallsToggle);

        ToggleRecyclerViewItem cpuUsageToggle = new ToggleRecyclerViewItem(getString(R.string.cpu_usage),
                getString(R.string.cpu_usage_overlay_description), NativeSettings.isOverlayCPUUsageEnabled(),
                NativeSettings::setOverlayCPUUsageEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(cpuUsageToggle);

        ToggleRecyclerViewItem ramUsageToggle = new ToggleRecyclerViewItem(getString(R.string.ram_usage),
                getString(R.string.ram_usage_overlay_description), NativeSettings.isOverlayRAMUsageEnabled(),
                NativeSettings::setOverlayRAMUsageEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(ramUsageToggle);

        ToggleRecyclerViewItem debugToggle = new ToggleRecyclerViewItem(getString(R.string.debug),
                getString(R.string.debug_overlay_description), NativeSettings.isOverlayDebugEnabled(),
                NativeSettings::setOverlayDebugEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(debugToggle);

        genericRecyclerViewAdapter.addRecyclerViewItem(new HeaderRecyclerViewItem(R.string.notifications));

        SingleSelectionRecyclerViewItem<Integer> notificationsPositionSelection = new SingleSelectionRecyclerViewItem<>(getString(R.string.overlay_position),
                NativeSettings.getNotificationsPosition(),
                overlayPositionChoices,
                this::overlayScreenPositionToString,
                NativeSettings::setNotificationsPosition);
        genericRecyclerViewAdapter.addRecyclerViewItem(notificationsPositionSelection);

        SliderRecyclerViewItem notificationTextScale = new SliderRecyclerViewItem(getString(R.string.notifications_text_scale),
                NativeSettings.OVERLAY_TEXT_SCALE_MIN,
                NativeSettings.OVERLAY_TEXT_SCALE_MAX,
                NativeSettings.getNotificationsTextScalePercentage(),
                25.0f,
                value -> NativeSettings.setNotificationsTextScalePercentage((int) value),
                value -> (int) value + "%");
        genericRecyclerViewAdapter.addRecyclerViewItem(notificationTextScale);

        ToggleRecyclerViewItem controllerProfiles = new ToggleRecyclerViewItem(getString(R.string.controller_profiles),
                getString(R.string.controller_profiles_notification_description), NativeSettings.isNotificationControllerProfilesEnabled(),
                NativeSettings::setNotificationControllerProfilesEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(controllerProfiles);

        ToggleRecyclerViewItem shaderCompiler = new ToggleRecyclerViewItem(getString(R.string.shader_compiler),
                getString(R.string.shader_compiler_notification_description), NativeSettings.isNotificationShaderCompilerEnabled(),
                NativeSettings::setNotificationShaderCompilerEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(shaderCompiler);

        ToggleRecyclerViewItem friendList = new ToggleRecyclerViewItem(getString(R.string.friend_list),
                getString(R.string.friend_list_notification_description), NativeSettings.isNotificationFriendListEnabled(),
                NativeSettings::setNotificationFriendListEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(friendList);

        binding.recyclerView.setAdapter(genericRecyclerViewAdapter);

        return binding.getRoot();
    }
}