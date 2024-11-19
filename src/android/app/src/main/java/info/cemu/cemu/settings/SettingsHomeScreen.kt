package info.cemu.cemu.settings

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.dropUnlessResumed
import info.cemu.cemu.R
import info.cemu.cemu.guicore.Button
import info.cemu.cemu.guicore.ScreenContent

data class SettingsHomeScreenActions(
    val goToGeneralSettings: () -> Unit,
    val goToInputSettings: () -> Unit,
    val goToGraphicsSettings: () -> Unit,
    val goToAudioSettings: () -> Unit,
    val goToOverlaySettings: () -> Unit,
)

@Composable
fun SettingsHomeScreen(navigateBack: () -> Unit, actions: SettingsHomeScreenActions) {
    ScreenContent(
        appBarText = stringResource(R.string.settings),
        navigateBack = navigateBack,
    ) {
        Button(
            label = stringResource(R.string.general_settings),
            onClick = dropUnlessResumed(block = actions.goToGeneralSettings)
        )
        Button(
            label = stringResource(R.string.input_settings),
            onClick = dropUnlessResumed(block = actions.goToInputSettings)
        )
        Button(
            label = stringResource(R.string.graphics_settings),
            onClick = dropUnlessResumed(block = actions.goToGraphicsSettings)
        )
        Button(
            label = stringResource(R.string.audio_settings),
            onClick = dropUnlessResumed(block = actions.goToAudioSettings)
        )
        Button(
            label = stringResource(R.string.overlay_settings),
            onClick = dropUnlessResumed(block = actions.goToOverlaySettings)
        )
    }
}