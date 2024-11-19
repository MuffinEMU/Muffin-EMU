package info.cemu.cemu.settings.inputoverlay

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.viewmodel.compose.viewModel
import info.cemu.cemu.R
import info.cemu.cemu.guicore.ScreenContent
import info.cemu.cemu.guicore.SingleSelection
import info.cemu.cemu.guicore.Slider
import info.cemu.cemu.guicore.Toggle
import info.cemu.cemu.nativeinterface.NativeInput
import kotlinx.serialization.Serializable

private val ControllerIndexChoices = (0..<NativeInput.MAX_CONTROLLERS).toList()

@Composable
fun InputOverlaySettingsScreen(
    inputOverlaySettingsViewModel: InputOverlaySettingsViewModel = viewModel(factory = InputOverlaySettingsViewModel.Factory),
    navigateBack: () -> Unit
) {
    val overlaySettings = inputOverlaySettingsViewModel.overlaySettings
    ScreenContent(
        appBarText = stringResource(
            R.string.input_overlay_settings,
        ),
        navigateBack = navigateBack
    )
    {
        Toggle(
            label = stringResource(R.string.input_overlay),
            description = stringResource(R.string.enable_input_overlay),
            initialCheckedState = { overlaySettings.isOverlayEnabled },
            onCheckedChanged = { overlaySettings.isOverlayEnabled = it }
        )
        Toggle(
            label = stringResource(R.string.vibrate),
            description = stringResource(R.string.enable_vibrate_on_touch),
            initialCheckedState = { overlaySettings.isVibrateOnTouchEnabled },
            onCheckedChanged = { overlaySettings.isVibrateOnTouchEnabled = it }
        )
        Slider(
            label = stringResource(R.string.alpha_slider),
            initialValue = { overlaySettings.alpha },
            valueFrom = 0,
            valueTo = 255,
            onValueChange = { overlaySettings.alpha = it },
            labelFormatter = { it.toString() },
        )
        SingleSelection(
            label = stringResource(R.string.overlay_controller),
            initialChoice = { overlaySettings.controllerIndex },
            choices = ControllerIndexChoices,
            choiceToString = { stringResource(R.string.controller_numbered, it + 1) },
            onChoiceChanged = { overlaySettings.controllerIndex = it }
        )
    }
}
