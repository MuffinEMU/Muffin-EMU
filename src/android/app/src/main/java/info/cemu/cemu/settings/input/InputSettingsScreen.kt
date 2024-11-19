package info.cemu.cemu.settings.input

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.dropUnlessResumed
import info.cemu.cemu.R
import info.cemu.cemu.guicore.Button
import info.cemu.cemu.guicore.ScreenContent
import info.cemu.cemu.nativeinterface.NativeInput
import kotlinx.serialization.Serializable

data class InputSettingsScreenActions(
    val goToInputOverlaySettings: () -> Unit,
    val goToControllerSettings: (controllerIndex: Int) -> Unit,
)

@Composable
fun InputSettingsScreen(navigateBack: () -> Unit, actions: InputSettingsScreenActions) {
    val controllers by remember {
        mutableStateOf(ControllerList)
    }
    ScreenContent(
        appBarText = stringResource(R.string.overlay_settings),
        navigateBack = navigateBack,
    ) {
        Button(
            label = stringResource(R.string.input_overlay_settings),
            onClick = dropUnlessResumed { actions.goToInputOverlaySettings() },
        )
        controllers.forEach { controllerTypePair ->
            val (controllerIndex, controllerEmulatedType) = controllerTypePair
            Button(
                label = stringResource(R.string.controller_numbered, controllerIndex + 1),
                description = stringResource(
                    R.string.emulated_controller_with_type,
                    stringResource(controllerTypeToStringId(controllerEmulatedType))
                ),
                onClick = dropUnlessResumed { actions.goToControllerSettings(controllerIndex) },
            )
        }
    }
}

val ControllerList: List<Pair<Int, Int>>
    get() = (0..<NativeInput.MAX_CONTROLLERS).map { controllerIndex ->
        controllerIndex to getControllerType(controllerIndex)
    }

private fun getControllerType(index: Int): Int =
    if (NativeInput.isControllerDisabled(index))
        NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED
    else NativeInput.getControllerType(index)
