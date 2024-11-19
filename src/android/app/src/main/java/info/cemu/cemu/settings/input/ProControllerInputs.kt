package info.cemu.cemu.settings.input

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import info.cemu.cemu.R
import info.cemu.cemu.guicore.enumtostringmapper.native.proControllerButtonToStringId
import info.cemu.cemu.nativeinterface.NativeInput

@Composable
fun ProControllerInputs(
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
            inputIdToString = { stringResource(proControllerButtonToStringId(it)) },
            onInputClick = onInputClick,
            controlsMapping = controlsMapping,
        )
    }
    InputItemsGroup(
        groupName = stringResource(R.string.buttons),
        inputIds = listOf(
            NativeInput.PRO_BUTTON_A,
            NativeInput.PRO_BUTTON_B,
            NativeInput.PRO_BUTTON_X,
            NativeInput.PRO_BUTTON_Y,
            NativeInput.PRO_BUTTON_L,
            NativeInput.PRO_BUTTON_R,
            NativeInput.PRO_BUTTON_ZL,
            NativeInput.PRO_BUTTON_ZR,
            NativeInput.PRO_BUTTON_PLUS,
            NativeInput.PRO_BUTTON_MINUS,
            NativeInput.PRO_BUTTON_HOME
        )
    )
    InputItemsGroup(
        groupName = stringResource(R.string.d_pad),
        inputIds = listOf(
            NativeInput.PRO_BUTTON_UP,
            NativeInput.PRO_BUTTON_DOWN,
            NativeInput.PRO_BUTTON_LEFT,
            NativeInput.PRO_BUTTON_RIGHT
        )
    )
    InputItemsGroup(
        groupName = stringResource(R.string.left_axis),
        inputIds = listOf(
            NativeInput.PRO_BUTTON_STICKL,
            NativeInput.PRO_BUTTON_STICKL_UP,
            NativeInput.PRO_BUTTON_STICKL_DOWN,
            NativeInput.PRO_BUTTON_STICKL_LEFT,
            NativeInput.PRO_BUTTON_STICKL_RIGHT
        )
    )
    InputItemsGroup(
        groupName = stringResource(R.string.right_axis),
        inputIds = listOf(
            NativeInput.PRO_BUTTON_STICKR,
            NativeInput.PRO_BUTTON_STICKR_UP,
            NativeInput.PRO_BUTTON_STICKR_DOWN,
            NativeInput.PRO_BUTTON_STICKR_LEFT,
            NativeInput.PRO_BUTTON_STICKR_RIGHT
        )
    )
}
