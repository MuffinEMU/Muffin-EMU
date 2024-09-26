package info.cemu.Cemu.settings.overlay;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.NonNull;
import androidx.fragment.app.Fragment;

import java.util.stream.Collectors;
import java.util.stream.Stream;

import info.cemu.Cemu.R;
import info.cemu.Cemu.databinding.GenericRecyclerViewLayoutBinding;
import info.cemu.Cemu.guibasecomponents.CheckboxRecyclerViewItem;
import info.cemu.Cemu.guibasecomponents.GenericRecyclerViewAdapter;
import info.cemu.Cemu.guibasecomponents.HeaderRecyclerViewItem;
import info.cemu.Cemu.guibasecomponents.SelectionAdapter;
import info.cemu.Cemu.guibasecomponents.SingleSelectionRecyclerViewItem;
import info.cemu.Cemu.guibasecomponents.SliderRecyclerViewItem;
import info.cemu.Cemu.nativeinterface.NativeSettings;

public class OverlaySettingsFragment extends Fragment {
    private static int overlayScreenPositionToResourceNameId(int overlayScreenPosition) {
        return switch (overlayScreenPosition) {
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
    }

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        var binding = GenericRecyclerViewLayoutBinding.inflate(inflater, container, false);

        GenericRecyclerViewAdapter genericRecyclerViewAdapter = new GenericRecyclerViewAdapter();

        var overlayPositionChoices = Stream.of(
                        NativeSettings.OVERLAY_SCREEN_POSITION_DISABLED,
                        NativeSettings.OVERLAY_SCREEN_POSITION_TOP_LEFT,
                        NativeSettings.OVERLAY_SCREEN_POSITION_TOP_CENTER,
                        NativeSettings.OVERLAY_SCREEN_POSITION_TOP_RIGHT,
                        NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_LEFT,
                        NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_CENTER,
                        NativeSettings.OVERLAY_SCREEN_POSITION_BOTTOM_RIGHT)
                .map(position -> new SelectionAdapter.ChoiceItem<>(t -> t.setText(overlayScreenPositionToResourceNameId(position)), position))
                .collect(Collectors.toList());
        int overlayPosition = NativeSettings.getOverlayPosition();

        genericRecyclerViewAdapter.addRecyclerViewItem(new HeaderRecyclerViewItem(R.string.overlay));
        SelectionAdapter<Integer> overlayPositionSelectionAdapter = new SelectionAdapter<>(overlayPositionChoices, overlayPosition);
        SingleSelectionRecyclerViewItem<Integer> overlayPositionSelection = new SingleSelectionRecyclerViewItem<>(getString(R.string.overlay_position),
                getString(overlayScreenPositionToResourceNameId(overlayPosition)), overlayPositionSelectionAdapter,
                (position, selectionRecyclerViewItem) -> {
                    NativeSettings.setOverlayPosition(position);
                    selectionRecyclerViewItem.setDescription(getString(overlayScreenPositionToResourceNameId(position)));
                });
        genericRecyclerViewAdapter.addRecyclerViewItem(overlayPositionSelection);

        SliderRecyclerViewItem overlayTextScale = new SliderRecyclerViewItem(getString(R.string.overlay_text_scale),
                NativeSettings.OVERLAY_TEXT_SCALE_MIN,
                NativeSettings.OVERLAY_TEXT_SCALE_MAX,
                NativeSettings.getOverlayTextScalePercentage(),
                25.0f,
                value -> NativeSettings.setOverlayTextScalePercentage((int) value),
                value -> (int) value + "%");
        genericRecyclerViewAdapter.addRecyclerViewItem(overlayTextScale);

        CheckboxRecyclerViewItem overlayFps = new CheckboxRecyclerViewItem(getString(R.string.fps),
                getString(R.string.fps_overlay_description), NativeSettings.isOverlayFPSEnabled(),
                NativeSettings::setOverlayFPSEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(overlayFps);

        CheckboxRecyclerViewItem drawCallsCheckbox = new CheckboxRecyclerViewItem(getString(R.string.draw_calls_per_frame),
                getString(R.string.draw_calls_per_frame_overlay_description), NativeSettings.isOverlayDrawCallsPerFrameEnabled(),
                NativeSettings::setOverlayDrawCallsPerFrameEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(drawCallsCheckbox);

        CheckboxRecyclerViewItem cpuUsageCheckbox = new CheckboxRecyclerViewItem(getString(R.string.cpu_usage),
                getString(R.string.cpu_usage_overlay_description), NativeSettings.isOverlayCPUUsageEnabled(),
                NativeSettings::setOverlayCPUUsageEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(cpuUsageCheckbox);

        CheckboxRecyclerViewItem ramUsageCheckbox = new CheckboxRecyclerViewItem(getString(R.string.ram_usage),
                getString(R.string.ram_usage_overlay_description), NativeSettings.isOverlayRAMUsageEnabled(),
                NativeSettings::setOverlayRAMUsageEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(ramUsageCheckbox);

        CheckboxRecyclerViewItem debugCheckbox = new CheckboxRecyclerViewItem(getString(R.string.debug),
                getString(R.string.debug_overlay_description), NativeSettings.isOverlayDebugEnabled(),
                NativeSettings::setOverlayDebugEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(debugCheckbox);

        genericRecyclerViewAdapter.addRecyclerViewItem(new HeaderRecyclerViewItem(R.string.notifications));
        int notificationsPosition = NativeSettings.getNotificationsPosition();
        SelectionAdapter<Integer> notificationsPositionSelectionAdapter = new SelectionAdapter<>(overlayPositionChoices, notificationsPosition);
        SingleSelectionRecyclerViewItem<Integer> notificationsPositionSelection = new SingleSelectionRecyclerViewItem<>(getString(R.string.overlay_position),
                getString(overlayScreenPositionToResourceNameId(notificationsPosition)), notificationsPositionSelectionAdapter,
                (position, selectionRecyclerViewItem) -> {
                    NativeSettings.setNotificationsPosition(position);
                    selectionRecyclerViewItem.setDescription(getString(overlayScreenPositionToResourceNameId(position)));
                });
        genericRecyclerViewAdapter.addRecyclerViewItem(notificationsPositionSelection);

        SliderRecyclerViewItem notificationTextScale = new SliderRecyclerViewItem(getString(R.string.notifications_text_scale),
                NativeSettings.OVERLAY_TEXT_SCALE_MIN,
                NativeSettings.OVERLAY_TEXT_SCALE_MAX,
                NativeSettings.getNotificationsTextScalePercentage(),
                25.0f,
                value -> NativeSettings.setNotificationsTextScalePercentage((int) value),
                value -> (int) value + "%");
        genericRecyclerViewAdapter.addRecyclerViewItem(notificationTextScale);

        CheckboxRecyclerViewItem controllerProfiles = new CheckboxRecyclerViewItem(getString(R.string.controller_profiles),
                getString(R.string.controller_profiles_notification_description), NativeSettings.isNotificationControllerProfilesEnabled(),
                NativeSettings::setNotificationControllerProfilesEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(controllerProfiles);

        CheckboxRecyclerViewItem shaderCompiler = new CheckboxRecyclerViewItem(getString(R.string.shader_compiler),
                getString(R.string.shader_compiler_notification_description), NativeSettings.isNotificationShaderCompilerEnabled(),
                NativeSettings::setNotificationShaderCompilerEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(shaderCompiler);

        CheckboxRecyclerViewItem friendList = new CheckboxRecyclerViewItem(getString(R.string.friend_list),
                getString(R.string.friend_list_notification_description), NativeSettings.isNotificationFriendListEnabled(),
                NativeSettings::setNotificationFriendListEnabled);
        genericRecyclerViewAdapter.addRecyclerViewItem(friendList);

        binding.recyclerView.setAdapter(genericRecyclerViewAdapter);

        return binding.getRoot();
    }
}