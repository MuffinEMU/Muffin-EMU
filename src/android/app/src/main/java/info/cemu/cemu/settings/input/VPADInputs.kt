package info.cemu.cemu.settings.input

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import info.cemu.cemu.R
import info.cemu.cemu.guicore.components.Toggle
import info.cemu.cemu.guicore.nativeenummapper.vpadButtonToStringId
import info.cemu.cemu.nativeinterface.NativeInput

@Composable
fun VPADInputs(
    controllerIndex: Int,
    onInputClick: (String, Int) -> Unit,
    controlsMapping: Map<Int, String>,
) {
    @Composable
    fun InputItemsGroup(
        groupName: String,
        inputIds: List<Int>,
    ) {
        InputItemsGroup(
            groupName = groupName,
            inputIds = inputIds,
            inputIdToString = { stringResource(vpadButtonToStringId(it)) },
            onInputClick = onInputClick,
            controlsMapping = controlsMapping,
        )
    }
    InputItemsGroup(
        groupName = stringResource(R.string.buttons),
        inputIds = listOf(
            NativeInput.VPAD_BUTTON_A,
            NativeInput.VPAD_BUTTON_B,
            NativeInput.VPAD_BUTTON_X,
            NativeInput.VPAD_BUTTON_Y,
            NativeInput.VPAD_BUTTON_L,
            NativeInput.VPAD_BUTTON_R,
            NativeInput.VPAD_BUTTON_ZL,
            NativeInput.VPAD_BUTTON_ZR,
            NativeInput.VPAD_BUTTON_PLUS,
            NativeInput.VPAD_BUTTON_MINUS
        )
    )
    InputItemsGroup(
        groupName = stringResource(R.string.d_pad),
        inputIds = listOf(
            NativeInput.VPAD_BUTTON_UP,
            NativeInput.VPAD_BUTTON_DOWN,
            NativeInput.VPAD_BUTTON_LEFT,
            NativeInput.VPAD_BUTTON_RIGHT
        )
    )
    InputItemsGroup(
        groupName = stringResource(R.string.left_axis),
        inputIds = listOf(
            NativeInput.VPAD_BUTTON_STICKL,
            NativeInput.VPAD_BUTTON_STICKL_UP,
            NativeInput.VPAD_BUTTON_STICKL_DOWN,
            NativeInput.VPAD_BUTTON_STICKL_LEFT,
            NativeInput.VPAD_BUTTON_STICKL_RIGHT
        )
    )
    InputItemsGroup(
        groupName = stringResource(R.string.right_axis),
        inputIds = listOf(
            NativeInput.VPAD_BUTTON_STICKR,
            NativeInput.VPAD_BUTTON_STICKR_UP,
            NativeInput.VPAD_BUTTON_STICKR_DOWN,
            NativeInput.VPAD_BUTTON_STICKR_LEFT,
            NativeInput.VPAD_BUTTON_STICKR_RIGHT
        )
    )
    InputItemsGroup(
        groupName = stringResource(R.string.extra),
        inputIds = listOf(
            NativeInput.VPAD_BUTTON_MIC,
            NativeInput.VPAD_BUTTON_HOME,
            NativeInput.VPAD_BUTTON_SCREEN
        )
    )
    Toggle(
        label = stringResource(R.string.toggle_screen),
        description = stringResource(R.string.toggle_screen_description),
        initialCheckedState = { NativeInput.getVPADScreenToggle(controllerIndex) },
        onCheckedChanged = { NativeInput.setVPADScreenToggle(controllerIndex, it) }
    )
}
