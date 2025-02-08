package info.cemu.cemu.settings.audio

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import info.cemu.cemu.R
import info.cemu.cemu.guicore.components.ScreenContent
import info.cemu.cemu.guicore.components.SingleSelection
import info.cemu.cemu.guicore.components.Slider
import info.cemu.cemu.guicore.components.Toggle
import info.cemu.cemu.guicore.nativeenummapper.channelsToStringId
import info.cemu.cemu.nativeinterface.NativeSettings

private const val AUDIO_LATENCY_STEPS = 22

@Composable
fun AudioSettingsScreen(navigateBack: () -> Unit) {
    ScreenContent(
        appBarText = stringResource(R.string.audio_settings),
        navigateBack = navigateBack,
    ) {
        Slider(
            label = stringResource(R.string.audio_latency),
            initialValue = NativeSettings::getAudioLatency,
            valueFrom = 0,
            steps = AUDIO_LATENCY_STEPS,
            valueTo = NativeSettings.AUDIO_LATENCY_MS_MAX,
            onValueChange = NativeSettings::setAudioLatency,
            labelFormatter = { "${it}ms" }
        )
        Toggle(
            label = stringResource(R.string.tv_audio),
            description = stringResource(R.string.tv_audio_description),
            initialCheckedState = { NativeSettings.getAudioDeviceEnabled(true) },
            onCheckedChanged = { NativeSettings.setAudioDeviceEnabled(it, true) }
        )
        SingleSelection(
            label = stringResource(R.string.tv_channels),
            initialChoice = { NativeSettings.getAudioDeviceChannels(true) },
            onChoiceChanged = { NativeSettings.setAudioDeviceChannels(it, true) },
            choiceToString = { stringResource(channelsToStringId(it)) },
            choices = listOf(
                NativeSettings.AUDIO_CHANNELS_MONO,
                NativeSettings.AUDIO_CHANNELS_STEREO,
                NativeSettings.AUDIO_CHANNELS_SURROUND,
            ),
        )
        Slider(
            label = stringResource(R.string.tv_volume),
            initialValue = { NativeSettings.getAudioDeviceVolume(true) },
            valueFrom = NativeSettings.AUDIO_MIN_VOLUME,
            valueTo = NativeSettings.AUDIO_MAX_VOLUME,
            onValueChange = { NativeSettings.setAudioDeviceVolume(it, true) },
            labelFormatter = { "$it%" }
        )
        Toggle(
            label = stringResource(R.string.gamepad_audio),
            description = stringResource(R.string.gamepad_audio_description),
            initialCheckedState = { NativeSettings.getAudioDeviceEnabled(false) },
            onCheckedChanged = { NativeSettings.setAudioDeviceEnabled(false, it) }
        )
        SingleSelection(
            label = stringResource(R.string.gamepad_channels),
            initialChoice = { NativeSettings.getAudioDeviceChannels(false) },
            onChoiceChanged = { NativeSettings.setAudioDeviceChannels(it, false) },
            choiceToString = { stringResource(channelsToStringId(it)) },
            choices = listOf(
                NativeSettings.AUDIO_CHANNELS_STEREO,
            ),
        )
        Slider(
            label = stringResource(R.string.gamepad_volume),
            initialValue = { NativeSettings.getAudioDeviceVolume(false) },
            valueFrom = NativeSettings.AUDIO_MIN_VOLUME,
            valueTo = NativeSettings.AUDIO_MAX_VOLUME,
            onValueChange = { NativeSettings.setAudioDeviceVolume(it, false) },
            labelFormatter = { "$it%" }
        )
    }
}