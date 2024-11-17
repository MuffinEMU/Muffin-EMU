package info.cemu.cemu.emulation

import android.annotation.SuppressLint
import android.content.res.Configuration
import android.graphics.SurfaceTexture
import android.os.Bundle
import android.view.LayoutInflater
import android.view.MenuItem
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.View.OnTouchListener
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.Toast
import androidx.annotation.StringRes
import androidx.appcompat.widget.PopupMenu
import androidx.fragment.app.Fragment
import info.cemu.cemu.R
import info.cemu.cemu.databinding.FragmentEmulationBinding
import info.cemu.cemu.input.SensorManager
import info.cemu.cemu.inputoverlay.InputOverlaySettingsProvider
import info.cemu.cemu.inputoverlay.InputOverlaySettingsProvider.OverlaySettings
import info.cemu.cemu.inputoverlay.InputOverlaySurfaceView
import info.cemu.cemu.nativeinterface.NativeEmulation
import info.cemu.cemu.nativeinterface.NativeEmulation.clearSurface
import info.cemu.cemu.nativeinterface.NativeEmulation.initializeRenderer
import info.cemu.cemu.nativeinterface.NativeEmulation.setReplaceTVWithPadView
import info.cemu.cemu.nativeinterface.NativeEmulation.setSurface
import info.cemu.cemu.nativeinterface.NativeEmulation.setSurfaceSize
import info.cemu.cemu.nativeinterface.NativeEmulation.startGame
import info.cemu.cemu.nativeinterface.NativeException
import info.cemu.cemu.nativeinterface.NativeInput.onTouchDown
import info.cemu.cemu.nativeinterface.NativeInput.onTouchMove
import info.cemu.cemu.nativeinterface.NativeInput.onTouchUp

@SuppressLint("ClickableViewAccessibility")
class EmulationFragment(private val launchPath: String) : Fragment(),
    PopupMenu.OnMenuItemClickListener {
    private class OnSurfaceTouchListener(val isTV: Boolean) : OnTouchListener {
        var currentPointerId: Int = -1

        override fun onTouch(v: View, event: MotionEvent): Boolean {
            val pointerIndex = event.actionIndex
            val pointerId = event.getPointerId(pointerIndex)
            if (currentPointerId != -1 && pointerId != currentPointerId) {
                return false
            }
            val x = event.getX(pointerIndex).toInt()
            val y = event.getY(pointerIndex).toInt()
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                    onTouchDown(x, y, isTV)
                    return true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                    currentPointerId = -1
                    onTouchUp(x, y, isTV)
                    return true
                }

                MotionEvent.ACTION_MOVE -> {
                    onTouchMove(x, y, isTV)
                    return true
                }
            }
            return false
        }
    }

    private inner class SurfaceHolderCallback(val isMainCanvas: Boolean) : SurfaceHolder.Callback {
        var surfaceSet: Boolean = false

        override fun surfaceCreated(surfaceHolder: SurfaceHolder) {
        }

        override fun surfaceChanged(
            surfaceHolder: SurfaceHolder,
            format: Int,
            width: Int,
            height: Int
        ) {
            try {
                setSurfaceSize(width, height, isMainCanvas)
                if (surfaceSet) {
                    return
                }
                setSurface(surfaceHolder.surface, isMainCanvas)
                surfaceSet = true
            } catch (exception: NativeException) {
                onEmulationError(getString(R.string.failed_create_surface_error, exception.message))
            }
        }

        override fun surfaceDestroyed(surfaceHolder: SurfaceHolder) {
            clearSurface(isMainCanvas)
            surfaceSet = false
        }
    }

    fun interface OnEmulationErrorCallback {
        fun onEmulationError(errorMessage: String?)
    }

    private var isGameRunning = false
    private var padCanvas: SurfaceView? = null
    private var toast: Toast? = null
    private var binding: FragmentEmulationBinding? = null
    private var isMotionEnabled = false
    private var settingsMenu: PopupMenu? = null
    private var inputOverlaySurfaceView: InputOverlaySurfaceView? = null
    private var sensorManager: SensorManager? = null
    private var onEmulationErrorCallback: OnEmulationErrorCallback? = null
    private var hasEmulationError = false
    private var overlaySettings: OverlaySettings? = null

    fun setOnEmulationErrorCallback(onEmulationErrorCallback: OnEmulationErrorCallback) {
        this.onEmulationErrorCallback = onEmulationErrorCallback
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val inputOverlaySettingsProvider = InputOverlaySettingsProvider(requireContext())
        if (sensorManager == null) {
            sensorManager = SensorManager(requireContext())
        }
        sensorManager!!.setIsLandscape(resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE)
        overlaySettings = inputOverlaySettingsProvider.overlaySettings
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (sensorManager != null) {
            sensorManager!!.setIsLandscape(newConfig.orientation == Configuration.ORIENTATION_LANDSCAPE)
        }
    }

    override fun onPause() {
        super.onPause()
        sensorManager!!.pauseListening()
    }

    override fun onResume() {
        super.onResume()
        if (isMotionEnabled) {
            sensorManager!!.startListening()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (sensorManager != null) {
            sensorManager!!.pauseListening()
        }
    }

    private fun createPadCanvas() {
        if (padCanvas != null) {
            return
        }
        padCanvas = SurfaceView(requireContext())
        binding!!.canvasesLayout.addView(
            padCanvas,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1.0f)
        )
        padCanvas!!.holder.addCallback(SurfaceHolderCallback(false))
        padCanvas!!.setOnTouchListener(OnSurfaceTouchListener(false))
    }

    private fun toastMessage(@StringRes toastTextResId: Int) {
        if (toast != null) {
            toast!!.cancel()
        }
        toast = Toast.makeText(requireContext(), toastTextResId, Toast.LENGTH_SHORT)
        toast!!.show()
    }

    private fun destroyPadCanvas() {
        if (padCanvas == null) {
            return
        }
        binding!!.canvasesLayout.removeView(padCanvas)
        padCanvas = null
    }

    private fun setPadViewVisibility(visible: Boolean) {
        if (visible) {
            createPadCanvas()
            return
        }
        destroyPadCanvas()
    }

    override fun onMenuItemClick(item: MenuItem): Boolean {
        val itemId = item.itemId
        if (itemId == R.id.show_pad) {
            val padVisibility = !item.isChecked
            setPadViewVisibility(padVisibility)
            item.setChecked(padVisibility)
            return true
        }
        if (itemId == R.id.edit_inputs) {
            binding!!.editInputsLayout.visibility = View.VISIBLE
            binding!!.finishEditInputsButton.visibility = View.VISIBLE
            binding!!.moveInputsButton.performClick()
            return true
        }
        if (itemId == R.id.replace_tv_with_pad) {
            val replaceTVWithPad = !item.isChecked
            setReplaceTVWithPadView(replaceTVWithPad)
            item.setChecked(replaceTVWithPad)
            return true
        }
        if (itemId == R.id.reset_inputs) {
            inputOverlaySurfaceView!!.resetInputs()
            return true
        }
        if (itemId == R.id.enable_motion) {
            isMotionEnabled = !item.isChecked
            if (isMotionEnabled) {
                sensorManager!!.startListening()
            } else {
                sensorManager!!.pauseListening()
            }
            item.setChecked(isMotionEnabled)
            return true
        }
        if (itemId == R.id.exit_emulation) {
            requireActivity().onBackPressedDispatcher.onBackPressed()
            return true
        }
        if (itemId == R.id.show_input_overlay) {
            val showInputOverlay = !item.isChecked
            val menu = settingsMenu!!.menu
            menu.findItem(R.id.edit_inputs).setEnabled(showInputOverlay)
            menu.findItem(R.id.reset_inputs).setEnabled(showInputOverlay)
            item.setChecked(showInputOverlay)
            inputOverlaySurfaceView!!.visibility =
                if (showInputOverlay) View.VISIBLE else View.GONE
            return true
        }
        return false
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        binding = FragmentEmulationBinding.inflate(inflater, container, false)
        inputOverlaySurfaceView = binding!!.inputOverlay

        binding!!.moveInputsButton.setOnClickListener { v: View? ->
            if (inputOverlaySurfaceView!!.getInputMode() == InputOverlaySurfaceView.InputMode.EDIT_POSITION) {
                return@setOnClickListener
            }
            binding!!.resizeInputsButton.alpha = 0.5f
            binding!!.moveInputsButton.alpha = 1.0f
            toastMessage(R.string.input_mode_edit_position)
            inputOverlaySurfaceView!!.setInputMode(InputOverlaySurfaceView.InputMode.EDIT_POSITION)
        }
        binding!!.resizeInputsButton.setOnClickListener { v: View? ->
            if (inputOverlaySurfaceView!!.getInputMode() == InputOverlaySurfaceView.InputMode.EDIT_SIZE) {
                return@setOnClickListener
            }
            binding!!.moveInputsButton.alpha = 0.5f
            binding!!.resizeInputsButton.alpha = 1.0f
            toastMessage(R.string.input_mode_edit_size)
            inputOverlaySurfaceView!!.setInputMode(InputOverlaySurfaceView.InputMode.EDIT_SIZE)
        }
        binding!!.finishEditInputsButton.setOnClickListener { v: View? ->
            inputOverlaySurfaceView!!.setInputMode(InputOverlaySurfaceView.InputMode.DEFAULT)
            binding!!.finishEditInputsButton.visibility = View.GONE
            binding!!.editInputsLayout.visibility = View.GONE
            toastMessage(R.string.input_mode_default)
        }
        settingsMenu = PopupMenu(requireContext(), binding!!.emulationSettingsButton)
        settingsMenu!!.menuInflater.inflate(R.menu.emulation, settingsMenu!!.menu)
        settingsMenu!!.setOnMenuItemClickListener(this@EmulationFragment)
        binding!!.emulationSettingsButton.setOnClickListener { v: View? -> settingsMenu!!.show() }
        val menu = settingsMenu!!.menu
        menu.findItem(R.id.show_input_overlay).setChecked(overlaySettings!!.isOverlayEnabled)
        if (!overlaySettings!!.isOverlayEnabled) {
            menu.findItem(R.id.reset_inputs).setEnabled(false)
            menu.findItem(R.id.edit_inputs).setEnabled(false)
            inputOverlaySurfaceView!!.visibility = View.GONE
        }
        val mainCanvas = binding!!.mainCanvas
        try {
            val testSurfaceTexture = SurfaceTexture(0)
            val testSurface = Surface(testSurfaceTexture)
            initializeRenderer(testSurface)
            testSurface.release()
            testSurfaceTexture.release()
        } catch (exception: NativeException) {
            onEmulationError(
                getString(
                    R.string.failed_initialize_renderer_error,
                    exception.message
                )
            )
            return binding!!.root
        }

        val mainCanvasHolder = mainCanvas.holder
        mainCanvasHolder.addCallback(SurfaceHolderCallback(true))
        mainCanvasHolder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
            }

            override fun surfaceChanged(
                holder: SurfaceHolder,
                format: Int,
                width: Int,
                height: Int
            ) {
                if (hasEmulationError) {
                    return
                }
                if (!isGameRunning) {
                    isGameRunning = true
                    startGame()
                }
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {
            }
        })
        mainCanvas.setOnTouchListener(OnSurfaceTouchListener(true))
        return binding!!.root
    }

    private fun startGame() {
        val result = startGame(launchPath)
        if (result == NativeEmulation.START_GAME_SUCCESSFUL) {
            return
        }
        val errorMessage = when (result) {
            NativeEmulation.START_GAME_ERROR_GAME_BASE_FILES_NOT_FOUND -> getString(R.string.game_not_found)
            NativeEmulation.START_GAME_ERROR_NO_DISC_KEY -> getString(R.string.no_disk_key)
            NativeEmulation.START_GAME_ERROR_NO_TITLE_TIK -> getString(R.string.no_title_tik)
            else -> getString(R.string.game_files_unknown_error, launchPath)
        }
        onEmulationError(errorMessage)
    }

    private fun onEmulationError(errorMessage: String) {
        hasEmulationError = true
        if (onEmulationErrorCallback != null) {
            onEmulationErrorCallback!!.onEmulationError(errorMessage)
        }
    }
}