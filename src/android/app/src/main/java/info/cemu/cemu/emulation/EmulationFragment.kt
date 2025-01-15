package info.cemu.cemu.emulation

import android.annotation.SuppressLint
import android.content.res.Configuration
import android.graphics.SurfaceTexture
import android.os.Bundle
import android.view.LayoutInflater
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
import androidx.fragment.app.Fragment
import info.cemu.cemu.R
import info.cemu.cemu.databinding.FragmentEmulationBinding
import info.cemu.cemu.databinding.LayoutSideMenuCheckboxItemBinding
import info.cemu.cemu.databinding.LayoutSideMenuEmulationBinding
import info.cemu.cemu.databinding.LayoutSideMenuTextItemBinding
import info.cemu.cemu.input.SensorManager
import info.cemu.cemu.inputoverlay.InputOverlaySettingsManager
import info.cemu.cemu.inputoverlay.InputOverlaySurfaceView
import info.cemu.cemu.inputoverlay.OverlaySettings
import info.cemu.cemu.nativeinterface.NativeEmulation
import info.cemu.cemu.nativeinterface.NativeException
import info.cemu.cemu.nativeinterface.NativeInput

private class CanvasOnTouchListener(val isTV: Boolean) : OnTouchListener {
    var currentPointerId: Int = -1

    @SuppressLint("ClickableViewAccessibility")
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
                NativeInput.onTouchDown(x, y, isTV)
                return true
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                currentPointerId = -1
                NativeInput.onTouchUp(x, y, isTV)
                return true
            }

            MotionEvent.ACTION_MOVE -> {
                NativeInput.onTouchMove(x, y, isTV)
                return true
            }
        }
        return false
    }
}

class EmulationFragment(private val launchPath: String) : Fragment() {
    private inner class CanvasSurfaceHolderCallback(val isMainCanvas: Boolean) :
        SurfaceHolder.Callback {
        var surfaceSet: Boolean = false

        override fun surfaceCreated(surfaceHolder: SurfaceHolder) {}

        override fun surfaceChanged(
            surfaceHolder: SurfaceHolder,
            format: Int,
            width: Int,
            height: Int,
        ) {
            try {
                NativeEmulation.setSurfaceSize(width, height, isMainCanvas)
                if (surfaceSet) {
                    return
                }
                NativeEmulation.setSurface(surfaceHolder.surface, isMainCanvas)
                surfaceSet = true
            } catch (exception: NativeException) {
                onEmulationError(getString(R.string.failed_create_surface_error, exception.message))
            }
        }

        override fun surfaceDestroyed(surfaceHolder: SurfaceHolder) {
            NativeEmulation.clearSurface(isMainCanvas)
            surfaceSet = false
        }
    }

    fun interface OnEmulationErrorCallback {
        fun onEmulationError(errorMessage: String)
    }

    private var isGameRunning = false
    private var padCanvas: SurfaceView? = null
    private var toast: Toast? = null
    private lateinit var binding: FragmentEmulationBinding
    private var isMotionEnabled = false
    private lateinit var overlaySettings: OverlaySettings
    private lateinit var inputOverlaySurfaceView: InputOverlaySurfaceView
    private lateinit var sensorManager: SensorManager
    private var onEmulationErrorCallback: OnEmulationErrorCallback? = null
    private var hasEmulationError = false

    fun setOnEmulationErrorCallback(onEmulationErrorCallback: OnEmulationErrorCallback) {
        this.onEmulationErrorCallback = onEmulationErrorCallback
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val inputOverlaySettingsManager = InputOverlaySettingsManager(requireContext())
        overlaySettings = inputOverlaySettingsManager.overlaySettings
        sensorManager = SensorManager(requireContext())
        sensorManager.setIsLandscape(resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        sensorManager.setIsLandscape(newConfig.orientation == Configuration.ORIENTATION_LANDSCAPE)
    }

    override fun onPause() {
        super.onPause()
        sensorManager.pauseListening()
    }

    override fun onResume() {
        super.onResume()
        if (isMotionEnabled) {
            sensorManager.startListening()
        }
    }


    override fun onDestroy() {
        super.onDestroy()
        sensorManager.pauseListening()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createPadCanvas() {
        if (padCanvas != null) {
            return
        }
        padCanvas = SurfaceView(requireContext())
        binding.canvasesLayout.addView(
            padCanvas,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1.0f)
        )
        padCanvas!!.holder.addCallback(CanvasSurfaceHolderCallback(false))
        padCanvas!!.setOnTouchListener(CanvasOnTouchListener(false))
    }

    private fun toastMessage(@StringRes toastTextResId: Int) {
        toast?.cancel()
        toast = Toast.makeText(requireContext(), toastTextResId, Toast.LENGTH_SHORT)
            .also { it.show() }
    }

    private fun destroyPadCanvas() {
        if (padCanvas == null) {
            return
        }
        binding.canvasesLayout.removeView(padCanvas)
        padCanvas = null
    }

    private fun setPadViewVisibility(visible: Boolean) {
        if (visible) {
            createPadCanvas()
        } else {
            destroyPadCanvas()
        }
    }

    private fun setMotionEnabled(enabled: Boolean) {
        isMotionEnabled = enabled
        if (isMotionEnabled) {
            sensorManager.startListening()
        } else {
            sensorManager.pauseListening()
        }
    }

    private fun LayoutSideMenuTextItemBinding.setEnabled(isEnabled: Boolean) {
        textItem.isEnabled = isEnabled
        textItem.alpha = if (isEnabled) 1f else 0.7f
    }

    private fun LayoutSideMenuTextItemBinding.configure(
        isEnabled: Boolean = true,
        onClick: () -> Unit,
    ) {
        setEnabled(isEnabled)
        textItem.setOnClickListener {
            onClick()
            binding.drawerLayout.close()
        }
    }

    private fun LayoutSideMenuCheckboxItemBinding.configure(
        initialCheckedStatus: Boolean = false,
        onCheckChanged: (Boolean) -> Unit,
    ) {
        checkbox.isChecked = initialCheckedStatus
        checkboxItem.setOnClickListener {
            checkbox.isChecked = !checkbox.isChecked
            onCheckChanged(checkbox.isChecked)
            binding.drawerLayout.close()
        }
    }

    private fun LayoutSideMenuEmulationBinding.configureSideMenu(isInputOverlayEnabled: Boolean) {
        enableMotionCheckbox.configure(onCheckChanged = ::setMotionEnabled)
        replaceTvWithPadCheckbox.configure(onCheckChanged = NativeEmulation::setReplaceTVWithPadView)
        showPadCheckbox.configure(onCheckChanged = ::setPadViewVisibility)
        showInputOverlayCheckbox.configure(initialCheckedStatus = isInputOverlayEnabled) { showInputOverlay ->
            editInputsMenuItem.setEnabled(showInputOverlay)
            resetInputOverlayMenuItem.setEnabled(showInputOverlay)
            inputOverlaySurfaceView.setVisible(showInputOverlay)
            this@EmulationFragment.view?.invalidate()
        }
        editInputsMenuItem.configure(isEnabled = isInputOverlayEnabled) {
            binding.editInputsLayout.visibility = View.VISIBLE
            binding.finishEditInputsButton.visibility = View.VISIBLE
            binding.moveInputsButton.performClick()
        }
        resetInputOverlayMenuItem.configure(
            isEnabled = isInputOverlayEnabled,
            onClick = inputOverlaySurfaceView::resetInputs
        )
        exitMenuItem.configure { requireActivity().onBackPressedDispatcher.onBackPressed() }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        binding = FragmentEmulationBinding.inflate(inflater, container, false)
        inputOverlaySurfaceView = binding.inputOverlay
        binding.sideMenu.configureSideMenu(isInputOverlayEnabled = overlaySettings.isOverlayEnabled)
        inputOverlaySurfaceView.setVisible(overlaySettings.isOverlayEnabled)
        binding.moveInputsButton.setOnClickListener { _ ->
            if (inputOverlaySurfaceView.getInputMode() == InputOverlaySurfaceView.InputMode.EDIT_POSITION) {
                return@setOnClickListener
            }
            binding.resizeInputsButton.alpha = 0.5f
            binding.moveInputsButton.alpha = 1.0f
            toastMessage(R.string.input_mode_edit_position)
            inputOverlaySurfaceView.setInputMode(InputOverlaySurfaceView.InputMode.EDIT_POSITION)
        }
        binding.resizeInputsButton.setOnClickListener { _ ->
            if (inputOverlaySurfaceView.getInputMode() == InputOverlaySurfaceView.InputMode.EDIT_SIZE) {
                return@setOnClickListener
            }
            binding.moveInputsButton.alpha = 0.5f
            binding.resizeInputsButton.alpha = 1.0f
            toastMessage(R.string.input_mode_edit_size)
            inputOverlaySurfaceView.setInputMode(InputOverlaySurfaceView.InputMode.EDIT_SIZE)
        }
        binding.finishEditInputsButton.setOnClickListener { _ ->
            inputOverlaySurfaceView.setInputMode(InputOverlaySurfaceView.InputMode.DEFAULT)
            binding.finishEditInputsButton.visibility = View.GONE
            binding.editInputsLayout.visibility = View.GONE
            toastMessage(R.string.input_mode_default)
        }
        binding.emulationSettingsButton.setOnClickListener { binding.drawerLayout.open() }
        val mainCanvas = binding.mainCanvas
        try {
            val testSurfaceTexture = SurfaceTexture(0)
            val testSurface = Surface(testSurfaceTexture)
            NativeEmulation.initializeRenderer(testSurface)
            testSurface.release()
            testSurfaceTexture.release()
        } catch (exception: NativeException) {
            onEmulationError(
                getString(
                    R.string.failed_initialize_renderer_error,
                    exception.message
                )
            )
            return binding.root
        }

        val mainCanvasHolder = mainCanvas.holder
        mainCanvasHolder.addCallback(CanvasSurfaceHolderCallback(isMainCanvas = true))
        mainCanvasHolder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
            }

            override fun surfaceChanged(
                holder: SurfaceHolder,
                format: Int,
                width: Int,
                height: Int,
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
        mainCanvas.setOnTouchListener(CanvasOnTouchListener(isTV = true))
        return binding.root
    }

    private fun startGame() {
        val result = NativeEmulation.startGame(launchPath)
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
        onEmulationErrorCallback?.onEmulationError(errorMessage)
    }
}