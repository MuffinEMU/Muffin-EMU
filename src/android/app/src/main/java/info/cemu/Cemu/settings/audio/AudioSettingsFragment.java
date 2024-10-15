package info.cemu.Cemu.settings.audio;

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
import info.cemu.Cemu.guibasecomponents.SingleSelectionRecyclerViewItem;
import info.cemu.Cemu.guibasecomponents.SliderRecyclerViewItem;
import info.cemu.Cemu.guibasecomponents.ToggleRecyclerViewItem;
import info.cemu.Cemu.nativeinterface.NativeSettings;

public class AudioSettingsFragment extends Fragment {

    private String channelsToString(int channels) {
        int resourceNameId = switch (channels) {
            case NativeSettings.AUDIO_CHANNELS_MONO -> R.string.mono;
            case NativeSettings.AUDIO_CHANNELS_STEREO -> R.string.stereo;
            case NativeSettings.AUDIO_CHANNELS_SURROUND -> R.string.surround;
            default -> throw new IllegalArgumentException("Invalid channels type: " + channels);
        };
        return getString(resourceNameId);
    }

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        var binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false);

        GenericRecyclerViewAdapter genericRecyclerViewAdapter = new GenericRecyclerViewAdapter();

        SliderRecyclerViewItem latencySlider = new SliderRecyclerViewItem(getString(R.string.audio_latency),
                0,
                NativeSettings.AUDIO_BLOCK_COUNT - 1,
                NativeSettings.getAudioLatency(),
                value -> NativeSettings.setAudioLatency((int) value),
                value -> (int) (value * 12) + "ms");
        genericRecyclerViewAdapter.addRecyclerViewItem(latencySlider);

        ToggleRecyclerViewItem tvDeviceToggle = new ToggleRecyclerViewItem(getString(R.string.tv),
                getString(R.string.tv_audio_description), NativeSettings.getAudioDeviceEnabled(true),
                checked -> NativeSettings.setAudioDeviceEnabled(checked, true));
        genericRecyclerViewAdapter.addRecyclerViewItem(tvDeviceToggle);

        SingleSelectionRecyclerViewItem<Integer> tvChannelsModeSelection = new SingleSelectionRecyclerViewItem<>(getString(R.string.tv_channels),
                NativeSettings.getAudioDeviceChannels(true),
                List.of(NativeSettings.AUDIO_CHANNELS_MONO,
                        NativeSettings.AUDIO_CHANNELS_STEREO,
                        NativeSettings.AUDIO_CHANNELS_SURROUND),
                this::channelsToString,
                channels -> NativeSettings.setAudioDeviceChannels(channels, true));
        genericRecyclerViewAdapter.addRecyclerViewItem(tvChannelsModeSelection);

        SliderRecyclerViewItem tvVolumeSlider = new SliderRecyclerViewItem(getString(R.string.tv_volume),
                NativeSettings.AUDIO_MIN_VOLUME,
                NativeSettings.AUDIO_MAX_VOLUME,
                NativeSettings.getAudioDeviceVolume(true),
                value -> NativeSettings.setAudioDeviceVolume((int) value, true),
                value -> (int) value + "%");
        genericRecyclerViewAdapter.addRecyclerViewItem(tvVolumeSlider);

        ToggleRecyclerViewItem padDeviceToggle = new ToggleRecyclerViewItem(getString(R.string.gamepad),
                getString(R.string.gamepad_audio_description), NativeSettings.getAudioDeviceEnabled(false),
                checked -> NativeSettings.setAudioDeviceEnabled(checked, false));
        genericRecyclerViewAdapter.addRecyclerViewItem(padDeviceToggle);

        SingleSelectionRecyclerViewItem<Integer> gamepadChannelsModeSelection = new SingleSelectionRecyclerViewItem<>(getString(R.string.gamepad_channels),
                NativeSettings.getAudioDeviceChannels(false),
                List.of(NativeSettings.AUDIO_CHANNELS_STEREO),
                this::channelsToString,
                channels -> NativeSettings.setAudioDeviceChannels(channels, false)
        );
        genericRecyclerViewAdapter.addRecyclerViewItem(gamepadChannelsModeSelection);

        SliderRecyclerViewItem padVolumeSlider = new SliderRecyclerViewItem(getString(R.string.pad_volume),
                NativeSettings.AUDIO_MIN_VOLUME,
                NativeSettings.AUDIO_MAX_VOLUME,
                NativeSettings.getAudioDeviceVolume(false),
                value -> NativeSettings.setAudioDeviceVolume((int) value, false),
                value -> (int) value + "%");
        genericRecyclerViewAdapter.addRecyclerViewItem(padVolumeSlider);

        binding.recyclerView.setAdapter(genericRecyclerViewAdapter);

        return binding.getRoot();
    }
}