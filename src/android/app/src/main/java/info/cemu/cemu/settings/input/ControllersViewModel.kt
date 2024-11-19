package info.cemu.cemu.settings.input

import android.view.KeyEvent
import android.view.MotionEvent
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.CreationExtras
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import info.cemu.cemu.input.InputManager
import info.cemu.cemu.nativeinterface.NativeInput

class ControllersViewModel(val controllerIndex: Int) : ViewModel() {
    private val inputManager = InputManager()
    private var _controllerType = mutableIntStateOf(
        if (NativeInput.isControllerDisabled(controllerIndex)) NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED
        else NativeInput.getControllerType(controllerIndex)
    )
    val controllerType: Int
        get() = _controllerType.intValue

    private var _controls = mutableStateMapOf<Int, String>()
    val controls: Map<Int, String>
        get() = _controls

    private var vpadCount = 0
    private var wpadCount = 0


    fun setControllerType(controllerType: Int) {
        if (!isControllerTypeAllowed(controllerType) || _controllerType.intValue == controllerType)
            return
        _controllerType.intValue = controllerType
        NativeInput.setControllerType(controllerIndex, controllerType)
        refreshControllerData()
    }

    fun tryMapKeyEvent(keyEvent: KeyEvent, buttonId: Int): Boolean {
        if (inputManager.mapKeyEventToMappingId(controllerIndex, buttonId, keyEvent)) {
            _controls[buttonId] = NativeInput.getControllerMapping(controllerIndex, buttonId)
            return true
        }
        return false
    }

    fun tryMapMotionEvent(motionEvent: MotionEvent, buttonId: Int): Boolean {
        if (inputManager.mapMotionEventToMappingId(controllerIndex, buttonId, motionEvent)) {
            _controls[buttonId] = NativeInput.getControllerMapping(controllerIndex, buttonId)
            return true
        }
        return false
    }

    fun clearButtonMapping(buttonId: Int) {
        _controls.remove(buttonId)
        NativeInput.clearControllerMapping(controllerIndex, buttonId)
    }

    private fun refreshControllerData() {
        vpadCount = NativeInput.VPADControllersCount
        wpadCount = NativeInput.WPADControllersCount
        _controls.apply {
            clear()
            putAll(NativeInput.getControllerMappings(controllerIndex))
        }
    }

    fun isControllerTypeAllowed(controllerType: Int): Boolean {
        val currentControllerType = this.controllerType
        if (controllerType == NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED) {
            return true
        }
        if (controllerType == NativeInput.EMULATED_CONTROLLER_TYPE_VPAD) {
            return this.controllerType == NativeInput.EMULATED_CONTROLLER_TYPE_VPAD || vpadCount < NativeInput.MAX_VPAD_CONTROLLERS
        }
        val isWPAD = currentControllerType != NativeInput.EMULATED_CONTROLLER_TYPE_VPAD
                && currentControllerType != NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED
        return isWPAD || wpadCount < NativeInput.MAX_WPAD_CONTROLLERS
    }

    init {
        refreshControllerData()
    }

    companion object {
        val CONTROLLER_INDEX_KEY = object : CreationExtras.Key<Int> {}
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                ControllersViewModel(
                    this[CONTROLLER_INDEX_KEY] as Int
                )
            }
        }
    }
}