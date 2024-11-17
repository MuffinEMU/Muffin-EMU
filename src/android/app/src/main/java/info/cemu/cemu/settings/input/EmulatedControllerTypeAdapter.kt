package info.cemu.cemu.settings.input

import android.widget.TextView
import info.cemu.cemu.guibasecomponents.SelectionAdapter
import info.cemu.cemu.nativeinterface.NativeInput
import info.cemu.cemu.settings.input.ControllerTypeResourceNameMapper.controllerTypeToResourceNameId
import java.util.stream.Collectors
import java.util.stream.Stream


class EmulatedControllerTypeAdapter : SelectionAdapter<Int>() {
    private var vpadCount = 0
    private var wpadCount = 0

    init {
        choiceItems = listOf(
            NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED,
            NativeInput.EMULATED_CONTROLLER_TYPE_VPAD,
            NativeInput.EMULATED_CONTROLLER_TYPE_PRO,
            NativeInput.EMULATED_CONTROLLER_TYPE_CLASSIC,
            NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE
        ).map { type: Int ->
            ChoiceItem({ t: TextView ->
                t.setText(
                    controllerTypeToResourceNameId(type)
                )
            }, type)
        }.toList()
        setSelectedValue(NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED)
    }

    fun setControllerTypeCounts(vpadCount: Int, wpadCount: Int) {
        this.vpadCount = vpadCount
        this.wpadCount = wpadCount
        notifyDataSetChanged()
    }

    override fun isEnabled(position: Int): Boolean {
        val currentControllerType = getItem(selectedPosition)!!
        val type = getItem(position)!!
        if (type == NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED) {
            return true
        }
        if (type == NativeInput.EMULATED_CONTROLLER_TYPE_VPAD) {
            return currentControllerType == NativeInput.EMULATED_CONTROLLER_TYPE_VPAD || vpadCount < NativeInput.MAX_VPAD_CONTROLLERS
        }
        val isWPAD =
            currentControllerType != NativeInput.EMULATED_CONTROLLER_TYPE_VPAD && currentControllerType != NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED
        return isWPAD || wpadCount < NativeInput.MAX_WPAD_CONTROLLERS
    }
}
