package info.cemu.cemu.settings.input

import info.cemu.cemu.R
import info.cemu.cemu.nativeinterface.NativeInput

object ControllerTypeResourceNameMapper {
    @JvmStatic
    fun controllerTypeToResourceNameId(type: Int): Int {
        return when (type) {
            NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED -> R.string.disabled
            NativeInput.EMULATED_CONTROLLER_TYPE_VPAD -> R.string.vpad_controller
            NativeInput.EMULATED_CONTROLLER_TYPE_PRO -> R.string.pro_controller
            NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE -> R.string.wiimote_controller
            NativeInput.EMULATED_CONTROLLER_TYPE_CLASSIC -> R.string.classic_controller
            else -> throw IllegalArgumentException("Invalid controller type: $type")
        }
    }
}
