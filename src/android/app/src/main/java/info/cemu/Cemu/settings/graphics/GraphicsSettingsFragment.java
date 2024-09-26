package info.cemu.Cemu.settings.graphics;

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
import info.cemu.Cemu.guibasecomponents.SelectionAdapter;
import info.cemu.Cemu.guibasecomponents.SingleSelectionRecyclerViewItem;
import info.cemu.Cemu.nativeinterface.NativeSettings;

public class GraphicsSettingsFragment extends Fragment {
    private static int vsyncModeToResourceNameId(int vsyncMode) {
        return switch (vsyncMode) {
            case NativeSettings.VSYNC_MODE_OFF -> R.string.off;
            case NativeSettings.VSYNC_MODE_DOUBLE_BUFFERING -> R.string.double_buffering;
            case NativeSettings.VSYNC_MODE_TRIPLE_BUFFERING -> R.string.triple_buffering;
            default -> throw new IllegalArgumentException("Invalid vsync mode: " + vsyncMode);
        };
    }

    private static int fullscreenScalingModeToResourceNameId(int fullscreenScaling) {
        return switch (fullscreenScaling) {
            case NativeSettings.FULLSCREEN_SCALING_KEEP_ASPECT_RATIO -> R.string.keep_aspect_ratio;
            case NativeSettings.FULLSCREEN_SCALING_STRETCH -> R.string.stretch;
            default ->
                    throw new IllegalArgumentException("Invalid fullscreen scaling mode:  " + fullscreenScaling);
        };
    }

    private static int scalingFilterToResourceNameId(int fullscreenScaling) {
        return switch (fullscreenScaling) {
            case NativeSettings.SCALING_FILTER_BILINEAR_FILTER -> R.string.bilinear;
            case NativeSettings.SCALING_FILTER_BICUBIC_FILTER -> R.string.bicubic;
            case NativeSettings.SCALING_FILTER_BICUBIC_HERMITE_FILTER -> R.string.hermite;
            case NativeSettings.SCALING_FILTER_NEAREST_NEIGHBOR_FILTER -> R.string.nearest_neighbor;
            default ->
                    throw new IllegalArgumentException("Invalid fullscreen scaling mode:  " + fullscreenScaling);
        };
    }

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        var binding = GenericRecyclerViewLayoutBinding.inflate(inflater, container, false);

        GenericRecyclerViewAdapter genericRecyclerViewAdapter = new GenericRecyclerViewAdapter();

        CheckboxRecyclerViewItem asyncShaderCheckbox = new CheckboxRecyclerViewItem(getString(R.string.async_shader_compile), getString(R.string.async_shader_compile_description), NativeSettings.getAsyncShaderCompile(), NativeSettings::setAsyncShaderCompile);
        genericRecyclerViewAdapter.addRecyclerViewItem(asyncShaderCheckbox);

        int vsyncMode = NativeSettings.getVSyncMode();
        var vsyncChoices = Stream.of(NativeSettings.VSYNC_MODE_OFF, NativeSettings.VSYNC_MODE_DOUBLE_BUFFERING, NativeSettings.VSYNC_MODE_TRIPLE_BUFFERING)
                .map(vsync -> new SelectionAdapter.ChoiceItem<>(t -> t.setText(vsyncModeToResourceNameId(vsync)), vsync))
                .collect(Collectors.toList());
        SelectionAdapter<Integer> vsyncSelectionAdapter = new SelectionAdapter<>(vsyncChoices, vsyncMode);
        SingleSelectionRecyclerViewItem<Integer> vsyncModeSelection = new SingleSelectionRecyclerViewItem<>(getString(R.string.vsync),
                getString(vsyncModeToResourceNameId(vsyncMode)), vsyncSelectionAdapter,
                (vsync, selectionRecyclerViewItem) -> {
                    NativeSettings.setVSyncMode(vsync);
                    selectionRecyclerViewItem.setDescription(getString(vsyncModeToResourceNameId(vsync)));
                });
        genericRecyclerViewAdapter.addRecyclerViewItem(vsyncModeSelection);

        CheckboxRecyclerViewItem accurateBarriersCheckbox = new CheckboxRecyclerViewItem(getString(R.string.accurate_barriers), getString(R.string.accurate_barriers_description), NativeSettings.getAccurateBarriers(), NativeSettings::setAccurateBarriers);
        genericRecyclerViewAdapter.addRecyclerViewItem(accurateBarriersCheckbox);

        int fullscreenScalingMode = NativeSettings.getFullscreenScaling();
        var fullscreenScalingChoices = Stream.of(NativeSettings.FULLSCREEN_SCALING_KEEP_ASPECT_RATIO, NativeSettings.FULLSCREEN_SCALING_STRETCH)
                .map(fullScreenScaling -> new SelectionAdapter.ChoiceItem<>(t -> t.setText(fullscreenScalingModeToResourceNameId(fullScreenScaling)), fullScreenScaling))
                .collect(Collectors.toList());
        SelectionAdapter<Integer> fullscreenScalingSelectionAdapter = new SelectionAdapter<>(fullscreenScalingChoices, fullscreenScalingMode);
        SingleSelectionRecyclerViewItem<Integer> fullscreenScalingSelection = new SingleSelectionRecyclerViewItem<>(getString(R.string.fullscreen_scaling),
                getString(fullscreenScalingModeToResourceNameId(fullscreenScalingMode)), fullscreenScalingSelectionAdapter,
                (fullscreenScaling, selectionRecyclerViewItem) -> {
                    NativeSettings.setFullscreenScaling(fullscreenScaling);
                    selectionRecyclerViewItem.setDescription(getString(fullscreenScalingModeToResourceNameId(fullscreenScaling)));
                });
        genericRecyclerViewAdapter.addRecyclerViewItem(fullscreenScalingSelection);

        var scalingFilterChoices = Stream.of(
                        NativeSettings.SCALING_FILTER_BILINEAR_FILTER,
                        NativeSettings.SCALING_FILTER_BICUBIC_FILTER,
                        NativeSettings.SCALING_FILTER_BICUBIC_HERMITE_FILTER,
                        NativeSettings.SCALING_FILTER_NEAREST_NEIGHBOR_FILTER
                ).map(scalingFilter -> new SelectionAdapter.ChoiceItem<>(t -> t.setText(scalingFilterToResourceNameId(scalingFilter)), scalingFilter))
                .collect(Collectors.toList());

        var upscaleFilterMode = NativeSettings.getUpscalingFilter();
        SelectionAdapter<Integer> upscaleFilterSelectionAdapter = new SelectionAdapter<>(scalingFilterChoices, upscaleFilterMode);
        SingleSelectionRecyclerViewItem<Integer> upscaleFilterSelection = new SingleSelectionRecyclerViewItem<>(getString(R.string.upscale_filter),
                getString(scalingFilterToResourceNameId(upscaleFilterMode)), upscaleFilterSelectionAdapter,
                (upscaleFilter, selectionRecyclerViewItem) -> {
                    NativeSettings.setUpscalingFilter(upscaleFilter);
                    selectionRecyclerViewItem.setDescription(getString(scalingFilterToResourceNameId(upscaleFilter)));
                });
        genericRecyclerViewAdapter.addRecyclerViewItem(upscaleFilterSelection);

        var downscaleFilterMode = NativeSettings.getDownscalingFilter() ;
        SelectionAdapter<Integer> downscaleFilterSelectionAdapter = new SelectionAdapter<>(scalingFilterChoices, downscaleFilterMode);
        SingleSelectionRecyclerViewItem<Integer> downscaleFilterSelection = new SingleSelectionRecyclerViewItem<>(getString(R.string.downscale_filter),
                getString(scalingFilterToResourceNameId(downscaleFilterMode)), downscaleFilterSelectionAdapter,
                (downscaleFilter, selectionRecyclerViewItem) -> {
                    NativeSettings.setDownscalingFilter(downscaleFilter);
                    selectionRecyclerViewItem.setDescription(getString(scalingFilterToResourceNameId(downscaleFilter)));
                });
        genericRecyclerViewAdapter.addRecyclerViewItem(downscaleFilterSelection);

        binding.recyclerView.setAdapter(genericRecyclerViewAdapter);
        return binding.getRoot();
    }
}