package info.cemu.cemu.emulation

import android.content.DialogInterface
import android.os.Bundle
import android.text.InputFilter.LengthFilter
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import androidx.activity.OnBackPressedCallback
import androidx.annotation.Keep
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import info.cemu.cemu.BuildConfig
import info.cemu.cemu.R
import info.cemu.cemu.databinding.ActivityEmulationBinding
import info.cemu.cemu.emulation.EmulationFragment.OnEmulationErrorCallback
import info.cemu.cemu.input.InputManager
import info.cemu.cemu.nativeinterface.NativeSwkbd.setCurrentInputText
import java.util.Objects
import kotlin.system.exitProcess

class EmulationActivity : AppCompatActivity() {
    private var hasEmulationError = false
    private val inputManager = InputManager()
    private var emulationTextInputDialog: AlertDialog? = null

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (inputManager.onMotionEvent(event)) {
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (inputManager.onKeyEvent(event)) {
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        emulationActivityInstance = this
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                showExitConfirmationDialog()
            }
        })

        val intent = intent
        val extras = intent.extras
        val data = intent.data
        var launchPath: String? = null
        if (extras != null) {
            launchPath = extras.getString(EXTRA_LAUNCH_PATH)
        }
        if (launchPath == null && data != null) {
            launchPath = data.toString()
        }
        if (launchPath == null) {
            throw RuntimeException("launchPath is null")
        }
        setFullscreen()
        val binding = ActivityEmulationBinding.inflate(
            layoutInflater
        )
        setContentView(binding.root)
        var emulationFragment =
            supportFragmentManager.findFragmentById(R.id.emulation_frame) as EmulationFragment?
        if (emulationFragment == null) {
            emulationFragment = EmulationFragment(launchPath)
            emulationFragment.setOnEmulationErrorCallback(OnEmulationErrorCallback { emulationError: String? ->
                this.onEmulationError(
                    emulationError
                )
            })
            supportFragmentManager
                .beginTransaction()
                .add(R.id.emulation_frame, emulationFragment)
                .commit()
        }
    }

    private fun showExitConfirmationDialog() {
        val builder = MaterialAlertDialogBuilder(this)
        builder.setTitle(R.string.exit_confirmation_title)
            .setMessage(R.string.exit_confirm_message)
            .setPositiveButton(R.string.yes) { _, _ -> quit() }
            .setNegativeButton(R.string.no) { _, _ -> }
            .show()
    }

    private fun onEmulationError(emulationError: String?) {
        if (hasEmulationError) {
            return
        }
        hasEmulationError = true
        val builder = MaterialAlertDialogBuilder(this)
        builder.setTitle(R.string.error)
            .setMessage(emulationError)
            .setNeutralButton(R.string.quit) { _, _ -> }
            .setOnDismissListener { _ -> quit() }
            .show()
    }

    private fun setFullscreen() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }

    private fun quit() {
        finishAffinity()
        exitProcess(0)
    }

    companion object {
        const val EXTRA_LAUNCH_PATH: String = BuildConfig.APPLICATION_ID + ".LaunchPath"
        private var emulationActivityInstance: EmulationActivity? = null

        /**
         * This method is called by swkbd using JNI.
         */
        @Keep
        @JvmStatic
        fun showEmulationTextInput(initialText: String?, maxLength: Int) {
            if (emulationActivityInstance == null || emulationActivityInstance!!.emulationTextInputDialog != null) {
                return
            }
            setCurrentInputText(initialText)
            emulationActivityInstance!!.runOnUiThread {
                val inputEditTextLayout =
                    emulationActivityInstance!!.layoutInflater.inflate(
                        R.layout.layout_emulation_input,
                        null
                    )
                val inputEditText =
                    inputEditTextLayout.requireViewById<EmulationTextInputEditText>(R.id.emulation_input_text)
                inputEditText.updateText(initialText)
                val dialog = MaterialAlertDialogBuilder(
                    emulationActivityInstance!!
                )
                    .setView(inputEditTextLayout)
                    .setCancelable(false)
                    .setPositiveButton(
                        R.string.done
                    ) { d: DialogInterface?, w: Int -> }.show()
                val doneButton = Objects.requireNonNull(
                    dialog.getButton(DialogInterface.BUTTON_POSITIVE)
                )
                doneButton.isEnabled = false
                doneButton.setOnClickListener { _: View? -> inputEditText.onFinishedEdit() }
                inputEditText.setOnTextChangedListener {
                    doneButton.isEnabled = it.isNotEmpty()
                }
                if (maxLength > 0) {
                    inputEditText.appendFilter(LengthFilter(maxLength))
                }
                emulationActivityInstance!!.emulationTextInputDialog = dialog
            }
        }

        /**
         * This method is called by swkbd using JNI.
         */
        @Keep
        @JvmStatic
        fun hideEmulationTextInput() {
            if (emulationActivityInstance?.emulationTextInputDialog == null) {
                return
            }
            val textInputDialog = emulationActivityInstance!!.emulationTextInputDialog!!
            emulationActivityInstance!!.emulationTextInputDialog = null
            emulationActivityInstance!!.runOnUiThread { textInputDialog.dismiss() }
        }
    }
}