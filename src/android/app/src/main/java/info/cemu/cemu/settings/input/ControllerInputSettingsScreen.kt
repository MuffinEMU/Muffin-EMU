package info.cemu.cemu.settings.input

import android.content.Context
import android.view.KeyEvent
import android.view.MotionEvent
import android.widget.TextView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.viewmodel.MutableCreationExtras
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import info.cemu.cemu.R
import info.cemu.cemu.guicore.components.ScreenContent
import info.cemu.cemu.guicore.components.SingleSelection
import info.cemu.cemu.guicore.nativeenummapper.controllerTypeToStringId
import info.cemu.cemu.nativeinterface.NativeInput

@Composable
fun ControllerInputSettingsScreen(
    navigateBack: () -> Unit,
    controllerIndex: Int,
    controllersViewModel: ControllersViewModel = viewModel(
        factory = ControllersViewModel.Factory,
        extras = MutableCreationExtras().apply {
            set(ControllersViewModel.CONTROLLER_INDEX_KEY, controllerIndex)
        }
    ),
) {
    val context = LocalContext.current
    val controllerType by controllersViewModel.controllerType.collectAsState()
    val controls by controllersViewModel.controls.collectAsState()

    fun onInputClick(buttonName: String, buttonId: Int) {
        openInputDialog(
            context = context,
            buttonName = buttonName,
            onClear = { controllersViewModel.clearButtonMapping(buttonId) },
            tryMapKeyEvent = { controllersViewModel.tryMapKeyEvent(it, buttonId) },
            tryMapMotionEvent = { controllersViewModel.tryMapMotionEvent(it, buttonId) },
        )
    }

    ScreenContent(
        appBarText = stringResource(R.string.controller_numbered, controllerIndex + 1),
        navigateBack = navigateBack,
    ) {
        SingleSelection(
            isChoiceEnabled = controllersViewModel::isControllerTypeAllowed,
            label = stringResource(R.string.emulated_controller),
            initialChoice = { controllerType },
            choices = listOf(
                NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED,
                NativeInput.EMULATED_CONTROLLER_TYPE_VPAD,
                NativeInput.EMULATED_CONTROLLER_TYPE_PRO,
                NativeInput.EMULATED_CONTROLLER_TYPE_CLASSIC,
                NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE
            ),
            choiceToString = { stringResource(controllerTypeToStringId(it)) },
            onChoiceChanged = controllersViewModel::setControllerType
        )
        when (controllerType) {
            NativeInput.EMULATED_CONTROLLER_TYPE_VPAD -> VPADInputs(
                controllerIndex = controllerIndex,
                onInputClick = ::onInputClick,
                controlsMapping = controls,
            )

            NativeInput.EMULATED_CONTROLLER_TYPE_PRO -> ProControllerInputs(
                onInputClick = ::onInputClick,
                controlsMapping = controls,
            )

            NativeInput.EMULATED_CONTROLLER_TYPE_CLASSIC -> ClassicControllerInputs(
                onInputClick = ::onInputClick,
                controlsMapping = controls,
            )

            NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE -> WiimoteControllerInputs(
                onInputClick = ::onInputClick,
                controlsMapping = controls,
            )
        }
    }
}

fun openInputDialog(
    context: Context,
    buttonName: String,
    onClear: () -> Unit,
    tryMapKeyEvent: (KeyEvent) -> Boolean,
    tryMapMotionEvent: (MotionEvent) -> Boolean,
) {
    MaterialAlertDialogBuilder(context).setTitle(R.string.inputBindingDialogTitle)
        .setMessage(context.getString(R.string.inputBindingDialogMessage, buttonName))
        .setNeutralButton(context.getString(R.string.clear)) { _, _ -> onClear() }
        .setNegativeButton(context.getString(R.string.cancel)) { _, _ -> }
        .show()
        .also { alertDialog ->
            alertDialog.requireViewById<TextView>(android.R.id.message).apply {
                isFocusableInTouchMode = true
                requestFocus()
                setOnKeyListener { _, _, keyEvent: KeyEvent ->
                    if (tryMapKeyEvent(keyEvent)) {
                        alertDialog.dismiss()
                    }
                    true
                }
                setOnGenericMotionListener { _, motionEvent: MotionEvent? ->
                    if (motionEvent != null && tryMapMotionEvent(motionEvent)) {
                        alertDialog.dismiss()
                    }
                    true
                }
            }
        }
}
