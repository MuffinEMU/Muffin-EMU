package info.cemu.cemu.input

import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import info.cemu.cemu.nativeinterface.NativeInput
import info.cemu.cemu.nativeinterface.NativeInput.onNativeAxis
import info.cemu.cemu.nativeinterface.NativeInput.onNativeKey
import info.cemu.cemu.nativeinterface.NativeInput.setControllerMapping
import kotlin.math.abs

class InputManager {
    private class InvalidAxisException(axis: Int) : Exception("Invalid axis $axis")

    @Throws(InvalidAxisException::class)
    private fun getNativeAxisKey(axis: Int, isPositive: Boolean): Int {
        return if (isPositive) {
            when (axis) {
                MotionEvent.AXIS_X -> NativeInput.AXIS_X_POS
                MotionEvent.AXIS_Y -> NativeInput.AXIS_Y_POS
                MotionEvent.AXIS_RX, MotionEvent.AXIS_Z -> NativeInput.ROTATION_X_POS
                MotionEvent.AXIS_RY, MotionEvent.AXIS_RZ -> NativeInput.ROTATION_Y_POS
                MotionEvent.AXIS_LTRIGGER -> NativeInput.TRIGGER_X_POS
                MotionEvent.AXIS_RTRIGGER -> NativeInput.TRIGGER_Y_POS
                MotionEvent.AXIS_HAT_X -> NativeInput.DPAD_RIGHT
                MotionEvent.AXIS_HAT_Y -> NativeInput.DPAD_DOWN
                else -> throw InvalidAxisException(axis)
            }
        } else {
            when (axis) {
                MotionEvent.AXIS_X -> NativeInput.AXIS_X_NEG
                MotionEvent.AXIS_Y -> NativeInput.AXIS_Y_NEG
                MotionEvent.AXIS_RX, MotionEvent.AXIS_Z -> NativeInput.ROTATION_X_NEG
                MotionEvent.AXIS_RY, MotionEvent.AXIS_RZ -> NativeInput.ROTATION_Y_NEG
                MotionEvent.AXIS_HAT_X -> NativeInput.DPAD_LEFT
                MotionEvent.AXIS_HAT_Y -> NativeInput.DPAD_UP
                else -> throw InvalidAxisException(axis)
            }
        }
    }

    private fun isMotionEventFromJoystickOrGamepad(event: MotionEvent): Boolean {
        return (event.source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK || (event.source and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD
    }

    fun mapMotionEventToMappingId(
        controllerIndex: Int,
        mappingId: Int,
        event: MotionEvent
    ): Boolean {
        if (!isMotionEventFromJoystickOrGamepad(event)) {
            return false
        }
        val device = event.device
        var maxAbsAxisValue = 0.0f
        var maxAxis = -1
        val actionPointerIndex = event.actionIndex
        for (motionRange in device.motionRanges) {
            val axisValue = event.getAxisValue(motionRange.axis, actionPointerIndex)
            var axis: Int
            try {
                axis = getNativeAxisKey(motionRange.axis, axisValue > 0)
            } catch (e: InvalidAxisException) {
                continue
            }
            if (abs(axisValue.toDouble()) > maxAbsAxisValue) {
                maxAxis = axis
                maxAbsAxisValue = abs(axisValue.toDouble()).toFloat()
            }
        }
        if (maxAbsAxisValue > MIN_ABS_AXIS_VALUE) {
            setControllerMapping(
                device.descriptor,
                device.name,
                controllerIndex,
                mappingId,
                maxAxis
            )
            return true
        }
        return false
    }

    private fun isSpecialKey(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        return keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_CAMERA || keyCode == KeyEvent.KEYCODE_ZOOM_IN || keyCode == KeyEvent.KEYCODE_ZOOM_OUT
    }

    private fun isController(inputDevice: InputDevice): Boolean {
        val sources = inputDevice.sources
        return (sources and InputDevice.SOURCE_CLASS_JOYSTICK) != 0 ||
                ((sources and InputDevice.SOURCE_DPAD) == InputDevice.SOURCE_DPAD) ||
                ((sources and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD)
    }

    fun onKeyEvent(event: KeyEvent): Boolean {
        if (isSpecialKey(event)) {
            return false
        }
        if (event.deviceId < 0) {
            return false
        }
        val device = event.device
        if (!isController(device)) {
            return false
        }
        onNativeKey(
            device.descriptor,
            device.name,
            event.keyCode,
            event.action == KeyEvent.ACTION_DOWN
        )
        return true
    }

    fun onMotionEvent(event: MotionEvent): Boolean {
        if (!isMotionEventFromJoystickOrGamepad(event)) {
            return false
        }
        val device = event.device
        val actionPointerIndex = event.actionIndex
        for (motionRange in device.motionRanges) {
            val axisValue = event.getAxisValue(motionRange.axis, actionPointerIndex)
            val axis = motionRange.axis
            onNativeAxis(device.descriptor, device.name, axis, axisValue)
        }
        return true
    }

    fun mapKeyEventToMappingId(controllerIndex: Int, mappingId: Int, event: KeyEvent): Boolean {
        val device = event.device
        setControllerMapping(
            device.descriptor,
            device.name,
            controllerIndex,
            mappingId,
            event.keyCode
        )
        return true
    }

    companion object {
        private const val MIN_ABS_AXIS_VALUE = 0.33f
    }
}
