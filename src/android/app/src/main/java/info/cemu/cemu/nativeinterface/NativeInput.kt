package info.cemu.cemu.nativeinterface

object NativeInput {
    const val VPAD_BUTTON_NONE: Int = 0
    const val VPAD_BUTTON_A: Int = 1
    const val VPAD_BUTTON_B: Int = 2
    const val VPAD_BUTTON_X: Int = 3
    const val VPAD_BUTTON_Y: Int = 4
    const val VPAD_BUTTON_L: Int = 5
    const val VPAD_BUTTON_R: Int = 6
    const val VPAD_BUTTON_ZL: Int = 7
    const val VPAD_BUTTON_ZR: Int = 8
    const val VPAD_BUTTON_PLUS: Int = 9
    const val VPAD_BUTTON_MINUS: Int = 10
    const val VPAD_BUTTON_UP: Int = 11
    const val VPAD_BUTTON_DOWN: Int = 12
    const val VPAD_BUTTON_LEFT: Int = 13
    const val VPAD_BUTTON_RIGHT: Int = 14
    const val VPAD_BUTTON_STICKL: Int = 15
    const val VPAD_BUTTON_STICKR: Int = 16
    const val VPAD_BUTTON_STICKL_UP: Int = 17
    const val VPAD_BUTTON_STICKL_DOWN: Int = 18
    const val VPAD_BUTTON_STICKL_LEFT: Int = 19
    const val VPAD_BUTTON_STICKL_RIGHT: Int = 20
    const val VPAD_BUTTON_STICKR_UP: Int = 21
    const val VPAD_BUTTON_STICKR_DOWN: Int = 22
    const val VPAD_BUTTON_STICKR_LEFT: Int = 23
    const val VPAD_BUTTON_STICKR_RIGHT: Int = 24
    const val VPAD_BUTTON_MIC: Int = 25
    const val VPAD_BUTTON_SCREEN: Int = 26
    const val VPAD_BUTTON_HOME: Int = 27
    const val VPAD_BUTTON_MAX: Int = 28

    const val PRO_BUTTON_NONE: Int = 0
    const val PRO_BUTTON_A: Int = 1
    const val PRO_BUTTON_B: Int = 2
    const val PRO_BUTTON_X: Int = 3
    const val PRO_BUTTON_Y: Int = 4
    const val PRO_BUTTON_L: Int = 5
    const val PRO_BUTTON_R: Int = 6
    const val PRO_BUTTON_ZL: Int = 7
    const val PRO_BUTTON_ZR: Int = 8
    const val PRO_BUTTON_PLUS: Int = 9
    const val PRO_BUTTON_MINUS: Int = 10
    const val PRO_BUTTON_HOME: Int = 11
    const val PRO_BUTTON_UP: Int = 12
    const val PRO_BUTTON_DOWN: Int = 13
    const val PRO_BUTTON_LEFT: Int = 14
    const val PRO_BUTTON_RIGHT: Int = 15
    const val PRO_BUTTON_STICKL: Int = 16
    const val PRO_BUTTON_STICKR: Int = 17
    const val PRO_BUTTON_STICKL_UP: Int = 18
    const val PRO_BUTTON_STICKL_DOWN: Int = 19
    const val PRO_BUTTON_STICKL_LEFT: Int = 20
    const val PRO_BUTTON_STICKL_RIGHT: Int = 21
    const val PRO_BUTTON_STICKR_UP: Int = 22
    const val PRO_BUTTON_STICKR_DOWN: Int = 23
    const val PRO_BUTTON_STICKR_LEFT: Int = 24
    const val PRO_BUTTON_STICKR_RIGHT: Int = 25
    const val PRO_BUTTON_MAX: Int = 26

    const val CLASSIC_BUTTON_NONE: Int = 0
    const val CLASSIC_BUTTON_A: Int = 1
    const val CLASSIC_BUTTON_B: Int = 2
    const val CLASSIC_BUTTON_X: Int = 3
    const val CLASSIC_BUTTON_Y: Int = 4
    const val CLASSIC_BUTTON_L: Int = 5
    const val CLASSIC_BUTTON_R: Int = 6
    const val CLASSIC_BUTTON_ZL: Int = 7
    const val CLASSIC_BUTTON_ZR: Int = 8
    const val CLASSIC_BUTTON_PLUS: Int = 9
    const val CLASSIC_BUTTON_MINUS: Int = 10
    const val CLASSIC_BUTTON_HOME: Int = 11
    const val CLASSIC_BUTTON_UP: Int = 12
    const val CLASSIC_BUTTON_DOWN: Int = 13
    const val CLASSIC_BUTTON_LEFT: Int = 14
    const val CLASSIC_BUTTON_RIGHT: Int = 15
    const val CLASSIC_BUTTON_STICKL_UP: Int = 16
    const val CLASSIC_BUTTON_STICKL_DOWN: Int = 17
    const val CLASSIC_BUTTON_STICKL_LEFT: Int = 18
    const val CLASSIC_BUTTON_STICKL_RIGHT: Int = 19
    const val CLASSIC_BUTTON_STICKR_UP: Int = 20
    const val CLASSIC_BUTTON_STICKR_DOWN: Int = 21
    const val CLASSIC_BUTTON_STICKR_LEFT: Int = 22
    const val CLASSIC_BUTTON_STICKR_RIGHT: Int = 23
    const val CLASSIC_BUTTON_MAX: Int = 24

    const val WIIMOTE_BUTTON_NONE: Int = 0
    const val WIIMOTE_BUTTON_A: Int = 1
    const val WIIMOTE_BUTTON_B: Int = 2
    const val WIIMOTE_BUTTON_1: Int = 3
    const val WIIMOTE_BUTTON_2: Int = 4
    const val WIIMOTE_BUTTON_NUNCHUCK_Z: Int = 5
    const val WIIMOTE_BUTTON_NUNCHUCK_C: Int = 6
    const val WIIMOTE_BUTTON_PLUS: Int = 7
    const val WIIMOTE_BUTTON_MINUS: Int = 8
    const val WIIMOTE_BUTTON_UP: Int = 9
    const val WIIMOTE_BUTTON_DOWN: Int = 10
    const val WIIMOTE_BUTTON_LEFT: Int = 11
    const val WIIMOTE_BUTTON_RIGHT: Int = 12
    const val WIIMOTE_BUTTON_NUNCHUCK_UP: Int = 13
    const val WIIMOTE_BUTTON_NUNCHUCK_DOWN: Int = 14
    const val WIIMOTE_BUTTON_NUNCHUCK_LEFT: Int = 15
    const val WIIMOTE_BUTTON_NUNCHUCK_RIGHT: Int = 16
    const val WIIMOTE_BUTTON_HOME: Int = 17
    const val WIIMOTE_BUTTON_MAX: Int = 18

    const val EMULATED_CONTROLLER_TYPE_VPAD: Int = 0
    const val EMULATED_CONTROLLER_TYPE_PRO: Int = 1
    const val EMULATED_CONTROLLER_TYPE_CLASSIC: Int = 2
    const val EMULATED_CONTROLLER_TYPE_WIIMOTE: Int = 3
    const val EMULATED_CONTROLLER_TYPE_DISABLED: Int = -1

    const val DPAD_UP: Int = 34
    const val DPAD_DOWN: Int = 35
    const val DPAD_LEFT: Int = 36
    const val DPAD_RIGHT: Int = 37
    const val AXIS_X_POS: Int = 38
    const val AXIS_Y_POS: Int = 39
    const val ROTATION_X_POS: Int = 40
    const val ROTATION_Y_POS: Int = 41
    const val TRIGGER_X_POS: Int = 42
    const val TRIGGER_Y_POS: Int = 43
    const val AXIS_X_NEG: Int = 44
    const val AXIS_Y_NEG: Int = 45
    const val ROTATION_X_NEG: Int = 46
    const val ROTATION_Y_NEG: Int = 47

    const val MAX_CONTROLLERS: Int = 8
    const val MAX_VPAD_CONTROLLERS: Int = 2
    const val MAX_WPAD_CONTROLLERS: Int = 7

    @JvmStatic
    external fun onNativeKey(
        deviceDescriptor: String?,
        deviceName: String?,
        key: Int,
        isPressed: Boolean
    )

    @JvmStatic
    external fun onNativeAxis(
        deviceDescriptor: String?,
        deviceName: String?,
        axis: Int,
        value: Float
    )

    @JvmStatic
    external fun setControllerType(index: Int, emulatedControllerType: Int)

    @JvmStatic
    external fun isControllerDisabled(index: Int): Boolean

    @JvmStatic
    external fun getControllerType(index: Int): Int

    @JvmStatic
    val WPADControllersCount: Int
        external get

    @JvmStatic
    val VPADControllersCount: Int
        external get

    @JvmStatic
    external fun setVPADScreenToggle(index: Int, enabled: Boolean)

    @JvmStatic
    external fun getVPADScreenToggle(index: Int): Boolean

    @JvmStatic
    external fun setControllerMapping(
        deviceDescriptor: String?,
        deviceName: String?,
        index: Int,
        mappingId: Int,
        buttonId: Int
    )

    @JvmStatic
    external fun clearControllerMapping(index: Int, mappingId: Int)

    @JvmStatic
    external fun getControllerMapping(index: Int, mappingId: Int): String

    @JvmStatic
    external fun getControllerMappings(index: Int): Map<Int, String>

    @JvmStatic
    external fun onTouchDown(x: Int, y: Int, isTV: Boolean)

    @JvmStatic
    external fun onTouchMove(x: Int, y: Int, isTV: Boolean)

    @JvmStatic
    external fun onTouchUp(x: Int, y: Int, isTV: Boolean)

    @JvmStatic
    external fun onMotion(
        timestamp: Long,
        gyroX: Float,
        gyroY: Float,
        gyroZ: Float,
        accelX: Float,
        accelY: Float,
        accelZ: Float
    )

    @JvmStatic
    external fun setMotionEnabled(motionEnabled: Boolean)

    @JvmStatic
    external fun onOverlayButton(controllerIndex: Int, mappingId: Int, value: Boolean)

    @JvmStatic
    external fun onOverlayAxis(controllerIndex: Int, mappingId: Int, value: Float)
}
