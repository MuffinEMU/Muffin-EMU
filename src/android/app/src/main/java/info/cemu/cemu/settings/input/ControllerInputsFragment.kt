package info.cemu.cemu.settings.input

import android.content.DialogInterface
import android.os.Bundle
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.annotation.StringRes
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.Fragment
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import info.cemu.cemu.R
import info.cemu.cemu.databinding.LayoutGenericRecyclerViewBinding
import info.cemu.cemu.guibasecomponents.GenericRecyclerViewAdapter
import info.cemu.cemu.guibasecomponents.HeaderRecyclerViewItem
import info.cemu.cemu.guibasecomponents.SingleSelectionRecyclerViewItem
import info.cemu.cemu.guibasecomponents.ToggleRecyclerViewItem
import info.cemu.cemu.input.InputManager
import info.cemu.cemu.nativeinterface.NativeInput
import info.cemu.cemu.nativeinterface.NativeInput.VPADControllersCount
import info.cemu.cemu.nativeinterface.NativeInput.WPADControllersCount
import info.cemu.cemu.nativeinterface.NativeInput.clearControllerMapping
import info.cemu.cemu.nativeinterface.NativeInput.getControllerMapping
import info.cemu.cemu.nativeinterface.NativeInput.getControllerMappings
import info.cemu.cemu.nativeinterface.NativeInput.getControllerType
import info.cemu.cemu.nativeinterface.NativeInput.getVPADScreenToggle
import info.cemu.cemu.nativeinterface.NativeInput.isControllerDisabled
import info.cemu.cemu.nativeinterface.NativeInput.setControllerType
import info.cemu.cemu.nativeinterface.NativeInput.setVPADScreenToggle
import info.cemu.cemu.settings.input.ControllerTypeResourceNameMapper.controllerTypeToResourceNameId
import java.util.function.Function

class ControllerInputsFragment : Fragment() {
    private var controllerIndex = 0
    private var controllerType = NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED
    private val inputManager = InputManager()
    private val genericRecyclerViewAdapter = GenericRecyclerViewAdapter()
    private val emulatedControllerTypeAdapter = EmulatedControllerTypeAdapter()
    private var buttonIdToStringResourceIdFunction: ((Int) -> Int)? = null

    private fun onTypeChanged(controllerType: Int) {
        if (this.controllerType == controllerType) {
            return
        }
        this.controllerType = controllerType
        setControllerType(controllerIndex, controllerType)
        genericRecyclerViewAdapter.clearRecyclerViewItems()
        setControllerInputs()
    }

    private fun addHeader(@StringRes resId: Int) {
        genericRecyclerViewAdapter.addRecyclerViewItem(HeaderRecyclerViewItem(resId))
    }

    private fun onInputPressed(
        inputItem: InputRecyclerViewItem,
        buttonId: Int,
        @StringRes buttonResourceIdName: Int
    ) {
        val inputDialog =
            MaterialAlertDialogBuilder(requireContext()).setTitle(R.string.inputBindingDialogTitle)
                .setMessage(
                    getString(
                        R.string.inputBindingDialogMessage,
                        getString(buttonResourceIdName)
                    )
                )
                .setNeutralButton(getString(R.string.clear)) { dialogInterface: DialogInterface, i: Int ->
                    clearControllerMapping(controllerIndex, buttonId)
                    inputItem.clearBoundInput()
                    dialogInterface.dismiss()
                }
                .setNegativeButton(
                    getString(R.string.cancel)
                ) { dialogInterface: DialogInterface, i: Int -> dialogInterface.dismiss() }
                .show()
        val messageTextView = inputDialog.requireViewById<TextView>(android.R.id.message)
        messageTextView.isFocusableInTouchMode = true
        messageTextView.requestFocus()
        messageTextView.setOnKeyListener { v: View?, keyCode: Int, event: KeyEvent? ->
            if (inputManager.mapKeyEventToMappingId(
                    controllerIndex, buttonId,
                    event!!
                )
            ) {
                inputItem.setBoundInput(getControllerMapping(controllerIndex, buttonId))
                inputDialog.dismiss()
            }
            true
        }
        messageTextView.setOnGenericMotionListener { v: View?, event: MotionEvent? ->
            if (inputManager.mapMotionEventToMappingId(
                    controllerIndex, buttonId,
                    event!!
                )
            ) {
                inputItem.setBoundInput(getControllerMapping(controllerIndex, buttonId))
                inputDialog.dismiss()
            }
            true
        }
    }

    private fun addInput(buttonId: Int, @StringRes buttonResourceIdName: Int, boundInput: String?) {
        val inputRecyclerViewItem = InputRecyclerViewItem(
            buttonResourceIdName,
            boundInput
        ) { inputItem: InputRecyclerViewItem ->
            onInputPressed(
                inputItem,
                buttonId,
                buttonResourceIdName
            )
        }
        genericRecyclerViewAdapter.addRecyclerViewItem(inputRecyclerViewItem)
    }

    fun addControllerInputsGroup(
        @StringRes groupTextResourceId: Int,
        buttonIds: List<Int>,
        boundInputsMap: Map<Int?, String?>
    ) {
        addHeader(groupTextResourceId)
        for (buttonId in buttonIds) {
            addInput(
                buttonId,
                buttonIdToStringResourceIdFunction!!(buttonId),
                boundInputsMap.getOrDefault(buttonId, "")
            )
        }
    }

    private fun setControllerInputs() {
        emulatedControllerTypeAdapter.setSelectedValue(controllerType)
        emulatedControllerTypeAdapter.setControllerTypeCounts(
            VPADControllersCount,
            WPADControllersCount
        )
        val controllerTypeName = getString(controllerTypeToResourceNameId(controllerType))
        buttonIdToStringResourceIdFunction = getButtonIdToStringResIdFn(controllerType)

        val emulatedControllerSelection = SingleSelectionRecyclerViewItem(
            getString(R.string.emulated_controller_label),
            getString(R.string.emulated_controller_selection_description, controllerTypeName),
            emulatedControllerTypeAdapter
        ) { controllerType: Int, selectionRecyclerViewItem: SingleSelectionRecyclerViewItem<Int>? ->
            onTypeChanged(
                controllerType
            )
        }
        genericRecyclerViewAdapter.addRecyclerViewItem(emulatedControllerSelection)
        when (controllerType) {
            NativeInput.EMULATED_CONTROLLER_TYPE_VPAD -> configureVPADInputs()
            NativeInput.EMULATED_CONTROLLER_TYPE_PRO -> configureProInputs()
            NativeInput.EMULATED_CONTROLLER_TYPE_CLASSIC -> configureClassicInputs()
            NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE -> configureWiimoteInputs()
        }
    }

    fun configureVPADInputs() {
        val boundInputsMap = getControllerMappings(controllerIndex)
        addControllerInputsGroup(
            R.string.buttons,
            java.util.List.of(
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
            ),
            boundInputsMap!!
        )
        addControllerInputsGroup(
            R.string.d_pad,
            java.util.List.of(
                NativeInput.VPAD_BUTTON_UP,
                NativeInput.VPAD_BUTTON_DOWN,
                NativeInput.VPAD_BUTTON_LEFT,
                NativeInput.VPAD_BUTTON_RIGHT
            ),
            boundInputsMap
        )
        addControllerInputsGroup(
            R.string.left_axis,
            java.util.List.of(
                NativeInput.VPAD_BUTTON_STICKL,
                NativeInput.VPAD_BUTTON_STICKL_UP,
                NativeInput.VPAD_BUTTON_STICKL_DOWN,
                NativeInput.VPAD_BUTTON_STICKL_LEFT,
                NativeInput.VPAD_BUTTON_STICKL_RIGHT
            ),
            boundInputsMap
        )
        addControllerInputsGroup(
            R.string.right_axis,
            java.util.List.of(
                NativeInput.VPAD_BUTTON_STICKR,
                NativeInput.VPAD_BUTTON_STICKR_UP,
                NativeInput.VPAD_BUTTON_STICKR_DOWN,
                NativeInput.VPAD_BUTTON_STICKR_LEFT,
                NativeInput.VPAD_BUTTON_STICKR_RIGHT
            ),
            boundInputsMap
        )
        addControllerInputsGroup(
            R.string.extra,
            java.util.List.of(
                NativeInput.VPAD_BUTTON_MIC,
                NativeInput.VPAD_BUTTON_HOME,
                NativeInput.VPAD_BUTTON_SCREEN
            ),
            boundInputsMap
        )
        val toggleShowScreen = ToggleRecyclerViewItem(
            getString(R.string.toggle_screen),
            getString(R.string.toggle_screen_description),
            getVPADScreenToggle(controllerIndex)
        ) { toggle: Boolean -> setVPADScreenToggle(controllerIndex, toggle) }
        genericRecyclerViewAdapter.addRecyclerViewItem(toggleShowScreen)
    }

    fun configureProInputs() {
        val boundInputsMap = getControllerMappings(controllerIndex)
        addControllerInputsGroup(
            R.string.buttons,
            java.util.List.of(
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
            ),
            boundInputsMap!!
        )
        addControllerInputsGroup(
            R.string.left_axis,
            java.util.List.of(
                NativeInput.PRO_BUTTON_STICKL,
                NativeInput.PRO_BUTTON_STICKL_UP,
                NativeInput.PRO_BUTTON_STICKL_DOWN,
                NativeInput.PRO_BUTTON_STICKL_LEFT,
                NativeInput.PRO_BUTTON_STICKL_RIGHT
            ),
            boundInputsMap
        )
        addControllerInputsGroup(
            R.string.right_axis,
            java.util.List.of(
                NativeInput.PRO_BUTTON_STICKR,
                NativeInput.PRO_BUTTON_STICKR_UP,
                NativeInput.PRO_BUTTON_STICKR_DOWN,
                NativeInput.PRO_BUTTON_STICKR_LEFT,
                NativeInput.PRO_BUTTON_STICKR_RIGHT
            ),
            boundInputsMap
        )
        addControllerInputsGroup(
            R.string.d_pad,
            java.util.List.of(
                NativeInput.PRO_BUTTON_UP,
                NativeInput.PRO_BUTTON_DOWN,
                NativeInput.PRO_BUTTON_LEFT,
                NativeInput.PRO_BUTTON_RIGHT
            ),
            boundInputsMap
        )
    }

    fun configureClassicInputs() {
        val boundInputsMap = getControllerMappings(controllerIndex)
        addControllerInputsGroup(
            R.string.buttons,
            java.util.List.of(
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
            ),
            boundInputsMap!!
        )
        addControllerInputsGroup(
            R.string.left_axis,
            java.util.List.of(
                NativeInput.CLASSIC_BUTTON_STICKL_UP,
                NativeInput.CLASSIC_BUTTON_STICKL_DOWN,
                NativeInput.CLASSIC_BUTTON_STICKL_LEFT,
                NativeInput.CLASSIC_BUTTON_STICKL_RIGHT
            ),
            boundInputsMap
        )
        addControllerInputsGroup(
            R.string.right_axis,
            java.util.List.of(
                NativeInput.CLASSIC_BUTTON_STICKR_UP,
                NativeInput.CLASSIC_BUTTON_STICKR_DOWN,
                NativeInput.CLASSIC_BUTTON_STICKR_LEFT,
                NativeInput.CLASSIC_BUTTON_STICKR_RIGHT
            ),
            boundInputsMap
        )
        addControllerInputsGroup(
            R.string.d_pad,
            java.util.List.of(
                NativeInput.CLASSIC_BUTTON_UP,
                NativeInput.CLASSIC_BUTTON_DOWN,
                NativeInput.CLASSIC_BUTTON_LEFT,
                NativeInput.CLASSIC_BUTTON_RIGHT
            ),
            boundInputsMap
        )
    }

    fun configureWiimoteInputs() {
        val boundInputsMap = getControllerMappings(controllerIndex)
        addControllerInputsGroup(
            R.string.buttons,
            java.util.List.of(
                NativeInput.WIIMOTE_BUTTON_A,
                NativeInput.WIIMOTE_BUTTON_B,
                NativeInput.WIIMOTE_BUTTON_1,
                NativeInput.WIIMOTE_BUTTON_2,
                NativeInput.WIIMOTE_BUTTON_NUNCHUCK_Z,
                NativeInput.WIIMOTE_BUTTON_NUNCHUCK_C,
                NativeInput.WIIMOTE_BUTTON_PLUS,
                NativeInput.WIIMOTE_BUTTON_MINUS,
                NativeInput.WIIMOTE_BUTTON_HOME
            ),
            boundInputsMap!!
        )
        addControllerInputsGroup(
            R.string.d_pad,
            java.util.List.of(
                NativeInput.WIIMOTE_BUTTON_UP,
                NativeInput.WIIMOTE_BUTTON_DOWN,
                NativeInput.WIIMOTE_BUTTON_LEFT,
                NativeInput.WIIMOTE_BUTTON_RIGHT
            ),
            boundInputsMap
        )
        addControllerInputsGroup(
            R.string.nunchuck,
            java.util.List.of(
                NativeInput.WIIMOTE_BUTTON_NUNCHUCK_UP,
                NativeInput.WIIMOTE_BUTTON_NUNCHUCK_DOWN,
                NativeInput.WIIMOTE_BUTTON_NUNCHUCK_LEFT,
                NativeInput.WIIMOTE_BUTTON_NUNCHUCK_RIGHT
            ),
            boundInputsMap
        )
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        super.onCreate(savedInstanceState)
        controllerIndex = requireArguments().getInt(CONTROLLER_INDEX)
        val actionBar = (requireActivity() as AppCompatActivity).supportActionBar
        if (actionBar != null) {
            actionBar.title = getString(R.string.controller_numbered, controllerIndex + 1)
        }
        if (!isControllerDisabled(controllerIndex)) {
            controllerType = getControllerType(controllerIndex)
        }
        setControllerInputs()

        val binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false)
        binding.recyclerView.adapter = genericRecyclerViewAdapter
        return binding.root
    }

    private fun getButtonIdToStringResIdFn(controllerType: Int): ((Int) -> Int)? {
        return when (controllerType) {
            NativeInput.EMULATED_CONTROLLER_TYPE_VPAD -> ::getButtonVPADResourceIdName
            NativeInput.EMULATED_CONTROLLER_TYPE_PRO -> ::getButtonProControllerResourceIdName
            NativeInput.EMULATED_CONTROLLER_TYPE_CLASSIC -> ::getButtonClassicControllerResourceIdName
            NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE -> ::getButtonWiimoteResourceIdName
            NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED -> null
            else -> throw IllegalArgumentException("Invalid controllerType $controllerType")
        }
    }

    private fun getButtonVPADResourceIdName(buttonId: Int): Int {
        return when (buttonId) {
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
    }

    private fun getButtonProControllerResourceIdName(buttonId: Int): Int {
        return when (buttonId) {
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
    }

    private fun getButtonClassicControllerResourceIdName(buttonId: Int): Int {
        return when (buttonId) {
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
    }

    private fun getButtonWiimoteResourceIdName(buttonId: Int): Int {
        return when (buttonId) {
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
    }

    companion object {
        const val CONTROLLER_INDEX: String = "ControllerIndex"
    }
}