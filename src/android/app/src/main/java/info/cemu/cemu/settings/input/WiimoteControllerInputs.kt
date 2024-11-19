package info.cemu.cemu.settings.input

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import info.cemu.cemu.R
import info.cemu.cemu.guicore.enumtostringmapper.native.wiimoteButtonItToStringId
import info.cemu.cemu.nativeinterface.NativeInput

@Composable
fun WiimoteControllerInputs(
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
            inputIdToString = { stringResource(wiimoteButtonItToStringId(it)) },
            onInputClick = onInputClick,
            controlsMapping = controlsMapping,
        )
    }
    InputItemsGroup(
        groupName = stringResource(R.string.buttons),
        inputIds = listOf(
            NativeInput.WIIMOTE_BUTTON_A,
            NativeInput.WIIMOTE_BUTTON_B,
            NativeInput.WIIMOTE_BUTTON_1,
            NativeInput.WIIMOTE_BUTTON_2,
            NativeInput.WIIMOTE_BUTTON_NUNCHUCK_Z,
            NativeInput.WIIMOTE_BUTTON_NUNCHUCK_C,
            NativeInput.WIIMOTE_BUTTON_PLUS,
            NativeInput.WIIMOTE_BUTTON_MINUS,
            NativeInput.WIIMOTE_BUTTON_HOME
        )
    )
    InputItemsGroup(
        groupName = stringResource(R.string.nunchuck),
        inputIds = listOf(
            NativeInput.WIIMOTE_BUTTON_UP,
            NativeInput.WIIMOTE_BUTTON_DOWN,
            NativeInput.WIIMOTE_BUTTON_LEFT,
            NativeInput.WIIMOTE_BUTTON_RIGHT
        )
    )
    InputItemsGroup(
        groupName = stringResource(R.string.right_axis),
        inputIds = listOf(
            NativeInput.WIIMOTE_BUTTON_NUNCHUCK_UP,
            NativeInput.WIIMOTE_BUTTON_NUNCHUCK_DOWN,
            NativeInput.WIIMOTE_BUTTON_NUNCHUCK_LEFT,
            NativeInput.WIIMOTE_BUTTON_NUNCHUCK_RIGHT
        )
    )
}
