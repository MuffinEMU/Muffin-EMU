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

        binding.recyclerView.setAdapter(genericRecyclerViewAdapter);
        return binding.getRoot();
    }
}