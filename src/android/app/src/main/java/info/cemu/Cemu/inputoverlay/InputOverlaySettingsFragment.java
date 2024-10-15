package info.cemu.Cemu.inputoverlay;


import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;

import java.util.stream.Collectors;
import java.util.stream.IntStream;

import info.cemu.Cemu.R;
import info.cemu.Cemu.databinding.LayoutGenericRecyclerViewBinding;
import info.cemu.Cemu.guibasecomponents.GenericRecyclerViewAdapter;
import info.cemu.Cemu.guibasecomponents.SingleSelectionRecyclerViewItem;
import info.cemu.Cemu.guibasecomponents.SliderRecyclerViewItem;
import info.cemu.Cemu.guibasecomponents.ToggleRecyclerViewItem;
import info.cemu.Cemu.nativeinterface.NativeInput;


public class InputOverlaySettingsFragment extends Fragment {
    private InputOverlaySettingsProvider.OverlaySettings overlaySettings;

    @Override
    public void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (overlaySettings == null) {
            InputOverlaySettingsProvider inputOverlaySettingsProvider = new InputOverlaySettingsProvider(requireContext());
            overlaySettings = inputOverlaySettingsProvider.getOverlaySettings();
        }
    }

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        var binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false);
        GenericRecyclerViewAdapter genericRecyclerViewAdapter = new GenericRecyclerViewAdapter();

        ToggleRecyclerViewItem inputOverlayToggle = new ToggleRecyclerViewItem(
                getString(R.string.input_overlay),
                getString(R.string.enable_input_overlay),
                overlaySettings.isOverlayEnabled(),
                checked -> {
                    overlaySettings.setOverlayEnabled(checked);
                    overlaySettings.saveSettings();
                });
        genericRecyclerViewAdapter.addRecyclerViewItem(inputOverlayToggle);

        ToggleRecyclerViewItem vibrateOnTouchToggle = new ToggleRecyclerViewItem(
                getString(R.string.vibrate),
                getString(R.string.enable_vibrate_on_touch),
                overlaySettings.isVibrateOnTouchEnabled(),
                checked -> {
                    overlaySettings.setVibrateOnTouchEnabled(checked);
                    overlaySettings.saveSettings();
                });
        genericRecyclerViewAdapter.addRecyclerViewItem(vibrateOnTouchToggle);

        SliderRecyclerViewItem alphaSlider = new SliderRecyclerViewItem(
                getString(R.string.alpha_slider),
                0,
                255,
                overlaySettings.getAlpha(),
                value -> {
                    overlaySettings.setAlpha((int) value);
                    overlaySettings.saveSettings();
                });
        genericRecyclerViewAdapter.addRecyclerViewItem(alphaSlider);

        SingleSelectionRecyclerViewItem<Integer> controllerSelection = new SingleSelectionRecyclerViewItem<>(
                getString(R.string.overlay_controller),
                overlaySettings.getControllerIndex(),
                IntStream.range(0, NativeInput.MAX_CONTROLLERS).boxed().collect(Collectors.toList()),
                controllerIndex -> getString(R.string.controller_numbered, controllerIndex + 1),
                (controllerIndex) -> overlaySettings.setControllerIndex(controllerIndex));
        genericRecyclerViewAdapter.addRecyclerViewItem(controllerSelection);

        binding.recyclerView.setAdapter(genericRecyclerViewAdapter);

        return binding.getRoot();
    }
}