package info.cemu.cemu.settings.input

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import info.cemu.cemu.R
import info.cemu.cemu.guicore.enumtostringmapper.native.classicControllerButtonToStringId
import info.cemu.cemu.nativeinterface.NativeInput

@Composable
fun ClassicControllerInputs(
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
            inputIdToString = { stringResource(classicControllerButtonToStringId(it)) },
            onInputClick = onInputClick,
            controlsMapping = controlsMapping,
        )
    }
    InputItemsGroup(
        groupName = stringResource(R.string.buttons),
        inputIds = listOf(
            NativeInput.CLASSIC_BUTTON_A,
            NativeInput.CLASSIC_BUTTON_B,
            NativeInput.CLASSIC_BUTTON_X,
            NativeInput.CLASSIC_BUTTON_Y,
            NativeInput.CLASSIC_BUTTON_L,
            NativeInput.CLASSIC_BUTTON_R,
            NativeInput.CLASSIC_BUTTON_ZL,
            NativeInput.CLASSIC_BUTTON_ZR,
            NativeInput.CLASSIC_BUTTON_PLUS,
            NativeInput.CLASSIC_BUTTON_MINUS,
            NativeInput.CLASSIC_BUTTON_HOME
        )
    )
    InputItemsGroup(
        groupName = stringResource(R.string.d_pad),
        inputIds = listOf(
            NativeInput.CLASSIC_BUTTON_UP,
            NativeInput.CLASSIC_BUTTON_DOWN,
            NativeInput.CLASSIC_BUTTON_LEFT,
            NativeInput.CLASSIC_BUTTON_RIGHT
        )
    )
    InputItemsGroup(
        groupName = stringResource(R.string.left_axis),
        inputIds = listOf(
            NativeInput.CLASSIC_BUTTON_STICKL_UP,
            NativeInput.CLASSIC_BUTTON_STICKL_DOWN,
            NativeInput.CLASSIC_BUTTON_STICKL_LEFT,
            NativeInput.CLASSIC_BUTTON_STICKL_RIGHT
        )
    )
    InputItemsGroup(
        groupName = stringResource(R.string.right_axis),
        inputIds = listOf(
            NativeInput.CLASSIC_BUTTON_STICKR_UP,
            NativeInput.CLASSIC_BUTTON_STICKR_DOWN,
            NativeInput.CLASSIC_BUTTON_STICKR_LEFT,
            NativeInput.CLASSIC_BUTTON_STICKR_RIGHT
        )
    )
}
