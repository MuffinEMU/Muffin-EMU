package info.cemu.cemu.guicore.nativeenummapper

import androidx.annotation.StringRes
import info.cemu.cemu.R
import info.cemu.cemu.nativeinterface.NativeInput

@StringRes
fun controllerTypeToStringId(type: Int) = when (type) {
    NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED -> R.string.disabled
    NativeInput.EMULATED_CONTROLLER_TYPE_VPAD -> R.string.vpad_controller
    NativeInput.EMULATED_CONTROLLER_TYPE_PRO -> R.string.pro_controller
    NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE -> R.string.wiimote_controller
    NativeInput.EMULATED_CONTROLLER_TYPE_CLASSIC -> R.string.classic_controller
    else -> throw IllegalArgumentException("Invalid controller type: $type")
}

@StringRes
fun proControllerButtonToStringId(buttonId: Int) = when (buttonId) {
    NativeInput.PRO_BUTTON_A -> R.string.button_a
    NativeInput.PRO_BUTTON_B -> R.string.button_b
    NativeInput.PRO_BUTTON_X -> R.string.button_x
    NativeInput.PRO_BUTTON_Y -> R.string.button_y
    NativeInput.PRO_BUTTON_L -> R.string.button_l
    NativeInput.PRO_BUTTON_R -> R.string.button_r
    NativeInput.PRO_BUTTON_ZL -> R.string.button_zl
    NativeInput.PRO_BUTTON_ZR -> R.string.button_zr
    NativeInput.PRO_BUTTON_PLUS -> R.string.button_plus
    NativeInput.PRO_BUTTON_MINUS -> R.string.button_minus
    NativeInput.PRO_BUTTON_HOME -> R.string.button_home
    NativeInput.PRO_BUTTON_UP -> R.string.button_up
    NativeInput.PRO_BUTTON_DOWN -> R.string.button_down
    NativeInput.PRO_BUTTON_LEFT -> R.string.button_left
    NativeInput.PRO_BUTTON_RIGHT -> R.string.button_right
    NativeInput.PRO_BUTTON_STICKL -> R.string.button_stickl
    NativeInput.PRO_BUTTON_STICKR -> R.string.button_stickr
    NativeInput.PRO_BUTTON_STICKL_UP -> R.string.button_stickl_up
    NativeInput.PRO_BUTTON_STICKL_DOWN -> R.string.button_stickl_down
    NativeInput.PRO_BUTTON_STICKL_LEFT -> R.string.button_stickl_left
    NativeInput.PRO_BUTTON_STICKL_RIGHT -> R.string.button_stickl_right
    NativeInput.PRO_BUTTON_STICKR_UP -> R.string.button_stickr_up
    NativeInput.PRO_BUTTON_STICKR_DOWN -> R.string.button_stickr_down
    NativeInput.PRO_BUTTON_STICKR_LEFT -> R.string.button_stickr_left
    NativeInput.PRO_BUTTON_STICKR_RIGHT -> R.string.button_stickr_right
    else -> throw IllegalArgumentException("Invalid buttonId $buttonId for Pro controller type")
}

@StringRes
fun classicControllerButtonToStringId(buttonId: Int) = when (buttonId) {
    NativeInput.CLASSIC_BUTTON_A -> R.string.button_a
    NativeInput.CLASSIC_BUTTON_B -> R.string.button_b
    NativeInput.CLASSIC_BUTTON_X -> R.string.button_x
    NativeInput.CLASSIC_BUTTON_Y -> R.string.button_y
    NativeInput.CLASSIC_BUTTON_L -> R.string.button_l
    NativeInput.CLASSIC_BUTTON_R -> R.string.button_r
    NativeInput.CLASSIC_BUTTON_ZL -> R.string.button_zl
    NativeInput.CLASSIC_BUTTON_ZR -> R.string.button_zr
    NativeInput.CLASSIC_BUTTON_PLUS -> R.string.button_plus
    NativeInput.CLASSIC_BUTTON_MINUS -> R.string.button_minus
    NativeInput.CLASSIC_BUTTON_HOME -> R.string.button_home
    NativeInput.CLASSIC_BUTTON_UP -> R.string.button_up
    NativeInput.CLASSIC_BUTTON_DOWN -> R.string.button_down
    NativeInput.CLASSIC_BUTTON_LEFT -> R.string.button_left
    NativeInput.CLASSIC_BUTTON_RIGHT -> R.string.button_right
    NativeInput.CLASSIC_BUTTON_STICKL_UP -> R.string.button_stickl_up
    NativeInput.CLASSIC_BUTTON_STICKL_DOWN -> R.string.button_stickl_down
    NativeInput.CLASSIC_BUTTON_STICKL_LEFT -> R.string.button_stickl_left
    NativeInput.CLASSIC_BUTTON_STICKL_RIGHT -> R.string.button_stickl_right
    NativeInput.CLASSIC_BUTTON_STICKR_UP -> R.string.button_stickr_up
    NativeInput.CLASSIC_BUTTON_STICKR_DOWN -> R.string.button_stickr_down
    NativeInput.CLASSIC_BUTTON_STICKR_LEFT -> R.string.button_stickr_left
    NativeInput.CLASSIC_BUTTON_STICKR_RIGHT -> R.string.button_stickr_right
    else -> throw IllegalArgumentException("Invalid buttonId $buttonId for Classic controller type")
}

@StringRes
fun vpadButtonToStringId(buttonId: Int) = when (buttonId) {
    NativeInput.VPAD_BUTTON_A -> R.string.button_a
    NativeInput.VPAD_BUTTON_B -> R.string.button_b
    NativeInput.VPAD_BUTTON_X -> R.string.button_x
    NativeInput.VPAD_BUTTON_Y -> R.string.button_y
    NativeInput.VPAD_BUTTON_L -> R.string.button_l
    NativeInput.VPAD_BUTTON_R -> R.string.button_r
    NativeInput.VPAD_BUTTON_ZL -> R.string.button_zl
    NativeInput.VPAD_BUTTON_ZR -> R.string.button_zr
    NativeInput.VPAD_BUTTON_PLUS -> R.string.button_plus
    NativeInput.VPAD_BUTTON_MINUS -> R.string.button_minus
    NativeInput.VPAD_BUTTON_UP -> R.string.button_up
    NativeInput.VPAD_BUTTON_DOWN -> R.string.button_down
    NativeInput.VPAD_BUTTON_LEFT -> R.string.button_left
    NativeInput.VPAD_BUTTON_RIGHT -> R.string.button_right
    NativeInput.VPAD_BUTTON_STICKL -> R.string.button_stickl
    NativeInput.VPAD_BUTTON_STICKR -> R.string.button_stickr
    NativeInput.VPAD_BUTTON_STICKL_UP -> R.string.button_stickl_up
    NativeInput.VPAD_BUTTON_STICKL_DOWN -> R.string.button_stickl_down
    NativeInput.VPAD_BUTTON_STICKL_LEFT -> R.string.button_stickl_left
    NativeInput.VPAD_BUTTON_STICKL_RIGHT -> R.string.button_stickl_right
    NativeInput.VPAD_BUTTON_STICKR_UP -> R.string.button_stickr_up
    NativeInput.VPAD_BUTTON_STICKR_DOWN -> R.string.button_stickr_down
    NativeInput.VPAD_BUTTON_STICKR_LEFT -> R.string.button_stickr_left
    NativeInput.VPAD_BUTTON_STICKR_RIGHT -> R.string.button_stickr_right
    NativeInput.VPAD_BUTTON_MIC -> R.string.button_mic
    NativeInput.VPAD_BUTTON_SCREEN -> R.string.button_screen
    NativeInput.VPAD_BUTTON_HOME -> R.string.button_home
    else -> throw IllegalArgumentException("Invalid buttonId $buttonId for VPAD controller type")
}

@StringRes
fun wiimoteButtonItToStringId(buttonId: Int) = when (buttonId) {
    NativeInput.WIIMOTE_BUTTON_A -> R.string.button_a
    NativeInput.WIIMOTE_BUTTON_B -> R.string.button_b
    NativeInput.WIIMOTE_BUTTON_1 -> R.string.button_1
    NativeInput.WIIMOTE_BUTTON_2 -> R.string.button_2
    NativeInput.WIIMOTE_BUTTON_NUNCHUCK_Z -> R.string.button_nunchuck_z
    NativeInput.WIIMOTE_BUTTON_NUNCHUCK_C -> R.string.button_nunchuck_c
    NativeInput.WIIMOTE_BUTTON_PLUS -> R.string.button_plus
    NativeInput.WIIMOTE_BUTTON_MINUS -> R.string.button_minus
    NativeInput.WIIMOTE_BUTTON_UP -> R.string.button_up
    NativeInput.WIIMOTE_BUTTON_DOWN -> R.string.button_down
    NativeInput.WIIMOTE_BUTTON_LEFT -> R.string.button_left
    NativeInput.WIIMOTE_BUTTON_RIGHT -> R.string.button_right
    NativeInput.WIIMOTE_BUTTON_NUNCHUCK_UP -> R.string.button_nunchuck_up
    NativeInput.WIIMOTE_BUTTON_NUNCHUCK_DOWN -> R.string.button_nunchuck_down
    NativeInput.WIIMOTE_BUTTON_NUNCHUCK_LEFT -> R.string.button_nunchuck_left
    NativeInput.WIIMOTE_BUTTON_NUNCHUCK_RIGHT -> R.string.button_nunchuck_right
    NativeInput.WIIMOTE_BUTTON_HOME -> R.string.button_home
    else -> throw IllegalArgumentException("Invalid buttonId $buttonId for Wiimote controller type")
}
