package info.cemu.cemu.settings.audio

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import info.cemu.cemu.R
import info.cemu.cemu.databinding.LayoutGenericRecyclerViewBinding
import info.cemu.cemu.guibasecomponents.GenericRecyclerViewAdapter
import info.cemu.cemu.guibasecomponents.SingleSelectionRecyclerViewItem
import info.cemu.cemu.guibasecomponents.SliderRecyclerViewItem
import info.cemu.cemu.guibasecomponents.ToggleRecyclerViewItem
import info.cemu.cemu.nativeinterface.NativeSettings
import info.cemu.cemu.nativeinterface.NativeSettings.audioLatency
import info.cemu.cemu.nativeinterface.NativeSettings.getAudioDeviceChannels
import info.cemu.cemu.nativeinterface.NativeSettings.getAudioDeviceEnabled
import info.cemu.cemu.nativeinterface.NativeSettings.getAudioDeviceVolume
import info.cemu.cemu.nativeinterface.NativeSettings.setAudioDeviceChannels
import info.cemu.cemu.nativeinterface.NativeSettings.setAudioDeviceEnabled
import info.cemu.cemu.nativeinterface.NativeSettings.setAudioDeviceVolume
import java.util.List

class AudioSettingsFragment : Fragment() {
    private fun channelsToString(channels: Int): String {
        val resourceNameId = when (channels) {
            NativeSettings.AUDIO_CHANNELS_MONO -> R.string.mono
            NativeSettings.AUDIO_CHANNELS_STEREO -> R.string.stereo
            NativeSettings.AUDIO_CHANNELS_SURROUND -> R.string.surround
            else -> throw IllegalArgumentException("Invalid channels type: $channels")
        }
        return getString(resourceNameId)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false)

        val genericRecyclerViewAdapter = GenericRecyclerViewAdapter()

        val latencySlider = SliderRecyclerViewItem(getString(R.string.audio_latency),
            0f,
            (NativeSettings.AUDIO_BLOCK_COUNT - 1).toFloat(),
            audioLatency.toFloat(),
            SliderRecyclerViewItem.OnChangeListener { value: Float -> audioLatency = value.toInt() }
        ) { value: Float -> (value * 12).toInt().toString() + "ms" }
        genericRecyclerViewAdapter.addRecyclerViewItem(latencySlider)

        val tvDeviceToggle = ToggleRecyclerViewItem(getString(R.string.tv),
            getString(R.string.tv_audio_description), getAudioDeviceEnabled(true),
            ToggleRecyclerViewItem.OnCheckedChangeListener { checked: Boolean ->
                setAudioDeviceEnabled(
                    checked,
                    true
                )
            })
        genericRecyclerViewAdapter.addRecyclerViewItem(tvDeviceToggle)

        val tvChannelsModeSelection =
            SingleSelectionRecyclerViewItem(getString(R.string.tv_channels),
                getAudioDeviceChannels(true),
                List.of(
                    NativeSettings.AUDIO_CHANNELS_MONO,
                    NativeSettings.AUDIO_CHANNELS_STEREO,
                    NativeSettings.AUDIO_CHANNELS_SURROUND
                ),
                { channels: Int -> this.channelsToString(channels) },
                { channels: Int? ->
                    setAudioDeviceChannels(
                        channels!!, true
                    )
                })
        genericRecyclerViewAdapter.addRecyclerViewItem(tvChannelsModeSelection)

        val tvVolumeSlider = SliderRecyclerViewItem(getString(R.string.tv_volume),
            NativeSettings.AUDIO_MIN_VOLUME.toFloat(),
            NativeSettings.AUDIO_MAX_VOLUME.toFloat(),
            getAudioDeviceVolume(true).toFloat(),
            SliderRecyclerViewItem.OnChangeListener { value: Float ->
                setAudioDeviceVolume(
                    value.toInt(),
                    true
                )
            }
        ) { value: Float -> value.toInt().toString() + "%" }
        genericRecyclerViewAdapter.addRecyclerViewItem(tvVolumeSlider)

        val padDeviceToggle = ToggleRecyclerViewItem(getString(R.string.gamepad),
            getString(R.string.gamepad_audio_description), getAudioDeviceEnabled(false),
            ToggleRecyclerViewItem.OnCheckedChangeListener { checked: Boolean ->
                setAudioDeviceEnabled(
                    checked,
                    false
                )
            })
        genericRecyclerViewAdapter.addRecyclerViewItem(padDeviceToggle)

        val gamepadChannelsModeSelection =
            SingleSelectionRecyclerViewItem(getString(R.string.gamepad_channels),
                getAudioDeviceChannels(false),
                List.of(NativeSettings.AUDIO_CHANNELS_STEREO),
                { channels: Int -> this.channelsToString(channels) },
                { channels: Int? ->
                    setAudioDeviceChannels(
                        channels!!, false
                    )
                }
            )
        genericRecyclerViewAdapter.addRecyclerViewItem(gamepadChannelsModeSelection)

        val padVolumeSlider = SliderRecyclerViewItem(getString(R.string.pad_volume),
            NativeSettings.AUDIO_MIN_VOLUME.toFloat(),
            NativeSettings.AUDIO_MAX_VOLUME.toFloat(),
            getAudioDeviceVolume(false).toFloat(),
            SliderRecyclerViewItem.OnChangeListener { value: Float ->
                setAudioDeviceVolume(
                    value.toInt(),
                    false
                )
            }
        ) { value: Float -> value.toInt().toString() + "%" }
        genericRecyclerViewAdapter.addRecyclerViewItem(padVolumeSlider)

        binding.recyclerView.adapter = genericRecyclerViewAdapter

        return binding.root
    }
}