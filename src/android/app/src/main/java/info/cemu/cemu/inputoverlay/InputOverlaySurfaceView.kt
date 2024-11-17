package info.cemu.cemu.inputoverlay

import android.content.Context
import android.graphics.Canvas
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.AttributeSet
import android.util.DisplayMetrics
import android.view.MotionEvent
import android.view.SurfaceView
import android.view.View
import android.view.View.OnTouchListener
import info.cemu.cemu.R
import info.cemu.cemu.inputoverlay.InputOverlaySettingsProvider.InputOverlaySettings
import info.cemu.cemu.nativeinterface.NativeInput
import info.cemu.cemu.nativeinterface.NativeInput.getControllerType
import info.cemu.cemu.nativeinterface.NativeInput.isControllerDisabled
import info.cemu.cemu.nativeinterface.NativeInput.onOverlayAxis
import info.cemu.cemu.nativeinterface.NativeInput.onOverlayButton

class InputOverlaySurfaceView(context: Context, attrs: AttributeSet?) :
    SurfaceView(context, attrs), OnTouchListener {
    enum class InputMode {
        DEFAULT,
        EDIT_POSITION,
        EDIT_SIZE,
    }

    private var inputMode = InputMode.DEFAULT

    fun resetInputs() {
        if (inputs == null) {
            return
        }
        val width = width
        val height = height

        for (input in InputOverlaySettingsProvider.Input.entries) {
            val inputSettings = settingsProvider.getOverlaySettingsForInput(input, width, height)
            inputSettings.rect = settingsProvider.getDefaultRectangle(input, width, height)
            inputSettings.saveSettings()
        }
        inputs!!.clear()
        inputs = null
        setInputs()
        invalidate()
    }

    fun setInputMode(inputMode: InputMode) {
        this.inputMode = inputMode
        if (inputs == null) {
            return
        }
        if (this.inputMode != InputMode.DEFAULT) {
            return
        }
        for (input in inputs!!) {
            input.reset()
            input.saveConfiguration()
        }
    }

    fun getInputMode(): InputMode {
        return inputMode
    }

    enum class OverlayButton {
        A,
        B,
        ONE,
        TWO,
        C,
        Z,
        HOME,
        DPAD_DOWN,
        DPAD_LEFT,
        DPAD_RIGHT,
        DPAD_UP,
        L,
        L_STICK,
        MINUS,
        PLUS,
        R,
        R_STICK,
        X,
        Y,
        ZL,
        ZR,
    }


    enum class OverlayJoystick {
        LEFT,
        RIGHT,
    }

    private var nativeControllerType = -1
    var controllerIndex: Int

    private var inputs: MutableList<Input>? = null
    private val settingsProvider: InputOverlaySettingsProvider
    private val vibrator: Vibrator?
    private val buttonTouchVibrationEffect =
        VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK)
    private val vibrateOnTouch: Boolean
    private val inputsMinWidthHeight: Int

    private fun getVibrator(context: Context): Vibrator {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager =
                context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            return vibratorManager.defaultVibrator
        }
        return context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }

    fun overlayButtonToVPADButton(button: OverlayButton): Int {
        return when (button) {
            OverlayButton.A -> NativeInput.VPAD_BUTTON_A
            OverlayButton.B -> NativeInput.VPAD_BUTTON_B
            OverlayButton.X -> NativeInput.VPAD_BUTTON_X
            OverlayButton.Y -> NativeInput.VPAD_BUTTON_Y
            OverlayButton.PLUS -> NativeInput.VPAD_BUTTON_PLUS
            OverlayButton.MINUS -> NativeInput.VPAD_BUTTON_MINUS
            OverlayButton.DPAD_UP -> NativeInput.VPAD_BUTTON_UP
            OverlayButton.DPAD_DOWN -> NativeInput.VPAD_BUTTON_DOWN
            OverlayButton.DPAD_LEFT -> NativeInput.VPAD_BUTTON_LEFT
            OverlayButton.DPAD_RIGHT -> NativeInput.VPAD_BUTTON_RIGHT
            OverlayButton.L_STICK -> NativeInput.VPAD_BUTTON_STICKL
            OverlayButton.R_STICK -> NativeInput.VPAD_BUTTON_STICKR
            OverlayButton.L -> NativeInput.VPAD_BUTTON_L
            OverlayButton.R -> NativeInput.VPAD_BUTTON_R
            OverlayButton.ZR -> NativeInput.VPAD_BUTTON_ZR
            OverlayButton.ZL -> NativeInput.VPAD_BUTTON_ZL
            else -> -1
        }
    }

    fun overlayButtonToClassicButton(button: OverlayButton): Int {
        return when (button) {
            OverlayButton.A -> NativeInput.CLASSIC_BUTTON_A
            OverlayButton.B -> NativeInput.CLASSIC_BUTTON_B
            OverlayButton.X -> NativeInput.CLASSIC_BUTTON_X
            OverlayButton.Y -> NativeInput.CLASSIC_BUTTON_Y
            OverlayButton.PLUS -> NativeInput.CLASSIC_BUTTON_PLUS
            OverlayButton.MINUS -> NativeInput.CLASSIC_BUTTON_MINUS
            OverlayButton.DPAD_UP -> NativeInput.CLASSIC_BUTTON_UP
            OverlayButton.DPAD_DOWN -> NativeInput.CLASSIC_BUTTON_DOWN
            OverlayButton.DPAD_LEFT -> NativeInput.CLASSIC_BUTTON_LEFT
            OverlayButton.DPAD_RIGHT -> NativeInput.CLASSIC_BUTTON_RIGHT
            OverlayButton.L -> NativeInput.CLASSIC_BUTTON_L
            OverlayButton.R -> NativeInput.CLASSIC_BUTTON_R
            OverlayButton.ZR -> NativeInput.CLASSIC_BUTTON_ZR
            OverlayButton.ZL -> NativeInput.CLASSIC_BUTTON_ZL
            else -> -1
        }
    }

    fun overlayButtonToProButton(button: OverlayButton): Int {
        return when (button) {
            OverlayButton.A -> NativeInput.PRO_BUTTON_A
            OverlayButton.B -> NativeInput.PRO_BUTTON_B
            OverlayButton.X -> NativeInput.PRO_BUTTON_X
            OverlayButton.Y -> NativeInput.PRO_BUTTON_Y
            OverlayButton.PLUS -> NativeInput.PRO_BUTTON_PLUS
            OverlayButton.MINUS -> NativeInput.PRO_BUTTON_MINUS
            OverlayButton.DPAD_UP -> NativeInput.PRO_BUTTON_UP
            OverlayButton.DPAD_DOWN -> NativeInput.PRO_BUTTON_DOWN
            OverlayButton.DPAD_LEFT -> NativeInput.PRO_BUTTON_LEFT
            OverlayButton.DPAD_RIGHT -> NativeInput.PRO_BUTTON_RIGHT
            OverlayButton.L_STICK -> NativeInput.PRO_BUTTON_STICKL
            OverlayButton.R_STICK -> NativeInput.PRO_BUTTON_STICKR
            OverlayButton.L -> NativeInput.PRO_BUTTON_L
            OverlayButton.R -> NativeInput.PRO_BUTTON_R
            OverlayButton.ZR -> NativeInput.PRO_BUTTON_ZR
            OverlayButton.ZL -> NativeInput.PRO_BUTTON_ZL
            else -> -1
        }
    }

    fun overlayButtonToWiimoteButton(button: OverlayButton): Int {
        return when (button) {
            OverlayButton.A -> NativeInput.WIIMOTE_BUTTON_A
            OverlayButton.B -> NativeInput.WIIMOTE_BUTTON_B
            OverlayButton.ONE -> NativeInput.WIIMOTE_BUTTON_1
            OverlayButton.TWO -> NativeInput.WIIMOTE_BUTTON_2
            OverlayButton.PLUS -> NativeInput.WIIMOTE_BUTTON_PLUS
            OverlayButton.MINUS -> NativeInput.WIIMOTE_BUTTON_MINUS
            OverlayButton.HOME -> NativeInput.WIIMOTE_BUTTON_HOME
            OverlayButton.DPAD_UP -> NativeInput.WIIMOTE_BUTTON_UP
            OverlayButton.DPAD_DOWN -> NativeInput.WIIMOTE_BUTTON_DOWN
            OverlayButton.DPAD_LEFT -> NativeInput.WIIMOTE_BUTTON_LEFT
            OverlayButton.DPAD_RIGHT -> NativeInput.WIIMOTE_BUTTON_RIGHT
            OverlayButton.C -> NativeInput.WIIMOTE_BUTTON_NUNCHUCK_C
            OverlayButton.Z -> NativeInput.WIIMOTE_BUTTON_NUNCHUCK_Z
            else -> -1
        }
    }

    fun onButtonStateChange(button: OverlayButton?, state: Boolean) {
        if (button == null) {
            return
        }
        val nativeButtonId = when (nativeControllerType) {
            NativeInput.EMULATED_CONTROLLER_TYPE_VPAD -> overlayButtonToVPADButton(button)
            NativeInput.EMULATED_CONTROLLER_TYPE_CLASSIC -> overlayButtonToClassicButton(button)
            NativeInput.EMULATED_CONTROLLER_TYPE_PRO -> overlayButtonToProButton(button)
            NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE -> overlayButtonToWiimoteButton(button)
            else -> -1
        }
        if (nativeButtonId == -1) {
            return
        }
        if (vibrateOnTouch && state) {
            vibrator!!.vibrate(buttonTouchVibrationEffect)
        }
        onOverlayButton(controllerIndex, nativeButtonId, state)
    }

    fun onOverlayAxis(axis: Int, value: Float) {
        onOverlayAxis(controllerIndex, axis, value)
    }

    fun onVPADJoystickStateChange(
        joystick: OverlayJoystick,
        up: Float,
        down: Float,
        left: Float,
        right: Float
    ) {
        if (joystick == OverlayJoystick.LEFT) {
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKL_UP, up)
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKL_DOWN, down)
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKL_LEFT, left)
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKL_RIGHT, right)
        } else {
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKR_UP, up)
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKR_DOWN, down)
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKR_LEFT, left)
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKR_RIGHT, right)
        }
    }

    fun onProJoystickStateChange(
        joystick: OverlayJoystick,
        up: Float,
        down: Float,
        left: Float,
        right: Float
    ) {
        if (joystick == OverlayJoystick.LEFT) {
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKL_UP, up)
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKL_DOWN, down)
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKL_LEFT, left)
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKL_RIGHT, right)
        } else {
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKR_UP, up)
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKR_DOWN, down)
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKR_LEFT, left)
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKR_RIGHT, right)
        }
    }

    fun onClassicJoystickStateChange(
        joystick: OverlayJoystick,
        up: Float,
        down: Float,
        left: Float,
        right: Float
    ) {
        if (joystick == OverlayJoystick.LEFT) {
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKL_UP, up)
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKL_DOWN, down)
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKL_LEFT, left)
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKL_RIGHT, right)
        } else {
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKR_UP, up)
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKR_DOWN, down)
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKR_LEFT, left)
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKR_RIGHT, right)
        }
    }

    fun onWiimoteJoystickStateChange(
        joystick: OverlayJoystick,
        up: Float,
        down: Float,
        left: Float,
        right: Float
    ) {
        if (joystick == OverlayJoystick.LEFT) {
            onOverlayAxis(NativeInput.WIIMOTE_BUTTON_NUNCHUCK_UP, up)
            onOverlayAxis(NativeInput.WIIMOTE_BUTTON_NUNCHUCK_DOWN, down)
            onOverlayAxis(NativeInput.WIIMOTE_BUTTON_NUNCHUCK_LEFT, left)
            onOverlayAxis(NativeInput.WIIMOTE_BUTTON_NUNCHUCK_RIGHT, right)
        }
    }

    fun onJoystickStateChange(joystick: OverlayJoystick, x: Float, y: Float) {
        val (up, down) = if (y < 0) Pair(-y, 0f) else Pair(0f, y)
        val (left, right) = if (x < 0) Pair(-x, 0f) else Pair(0f, x)
        val onJoystickChange = when (nativeControllerType) {
            NativeInput.EMULATED_CONTROLLER_TYPE_VPAD -> ::onVPADJoystickStateChange
            NativeInput.EMULATED_CONTROLLER_TYPE_PRO -> ::onProJoystickStateChange
            NativeInput.EMULATED_CONTROLLER_TYPE_CLASSIC -> ::onClassicJoystickStateChange
            NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE -> ::onWiimoteJoystickStateChange
            else -> return
        }
        onJoystickChange(joystick, up, down, left, right)
    }

    private fun getOverlaySettingsForInput(input: InputOverlaySettingsProvider.Input): InputOverlaySettings {
        return settingsProvider.getOverlaySettingsForInput(input, width, height)
    }

    private fun MutableList<Input>.addAll(vararg inputs: Input): Unit =
        inputs.forEach { add(it) }

    private fun setInputs() {
        if (inputs != null) {
            return
        }
        if (isControllerDisabled(controllerIndex)) {
            inputs = mutableListOf()
            return
        }
        val resources = resources
        nativeControllerType = getControllerType(controllerIndex)
        inputs = mutableListOf(
            RoundButton(
                resources,
                R.drawable.button_minus,
                ::onButtonStateChange,
                OverlayButton.MINUS,
                getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.MINUS)
            ),
            RoundButton(
                resources,
                R.drawable.button_plus,
                ::onButtonStateChange,
                OverlayButton.PLUS,
                getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.PLUS)
            ),
            DPadInput(
                resources,
                R.drawable.dpad_background,
                R.drawable.dpad_button,
                ::onButtonStateChange,
                getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.DPAD)
            ),
            Joystick(
                resources,
                R.drawable.stick_background,
                R.drawable.stick_inner,
                ::onJoystickStateChange,
                OverlayJoystick.LEFT,
                getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.LEFT_AXIS)
            ),
            RoundButton(
                resources,
                R.drawable.button_a,
                ::onButtonStateChange,
                OverlayButton.A,
                getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.A)
            ),
            RoundButton(
                resources,
                R.drawable.button_b,
                ::onButtonStateChange,
                OverlayButton.B,
                getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.B)
            )
        ).apply {
            if (nativeControllerType != NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE) {
                addAll(
                    RoundButton(
                        resources,
                        R.drawable.button_x,
                        ::onButtonStateChange,
                        OverlayButton.X,
                        getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.X)
                    ),
                    RoundButton(
                        resources,
                        R.drawable.button_y,
                        ::onButtonStateChange,
                        OverlayButton.Y,
                        getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.Y)
                    ),
                    RectangleButton(
                        resources,
                        R.drawable.button_zl,
                        ::onButtonStateChange,
                        OverlayButton.ZL,
                        getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.ZL)
                    ),
                    RectangleButton(
                        resources,
                        R.drawable.button_l,
                        ::onButtonStateChange,
                        OverlayButton.L,
                        getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.L)
                    ),
                    RectangleButton(
                        resources,
                        R.drawable.button_zr,
                        ::onButtonStateChange,
                        OverlayButton.ZR,
                        getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.ZR)
                    ),
                    RectangleButton(
                        resources,
                        R.drawable.button_r,
                        ::onButtonStateChange,
                        OverlayButton.R,
                        getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.R)
                    ),
                    Joystick(
                        resources,
                        R.drawable.stick_background,
                        R.drawable.stick_inner,
                        ::onJoystickStateChange,
                        OverlayJoystick.RIGHT,
                        getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.RIGHT_AXIS)
                    )
                )
            }
            if (nativeControllerType == NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE) {
                addAll(
                    RoundButton(
                        resources,
                        R.drawable.button_c,
                        ::onButtonStateChange,
                        OverlayButton.C,
                        getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.C)
                    ),
                    RoundButton(
                        resources,
                        R.drawable.button_z,
                        ::onButtonStateChange,
                        OverlayButton.Z,
                        getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.Z)
                    ),
                    RoundButton(
                        resources,
                        R.drawable.button_home,
                        ::onButtonStateChange,
                        OverlayButton.HOME,
                        getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.HOME)
                    )
                )
            }
            if (nativeControllerType != NativeInput.EMULATED_CONTROLLER_TYPE_CLASSIC
                && nativeControllerType != NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE
            ) {
                addAll(
                    RoundButton(
                        resources,
                        R.drawable.button_stick,
                        ::onButtonStateChange,
                        OverlayButton.L_STICK,
                        getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.L_STICK)
                    ),
                    RoundButton(
                        resources,
                        R.drawable.button_stick,
                        ::onButtonStateChange,
                        OverlayButton.R_STICK,
                        getOverlaySettingsForInput(InputOverlaySettingsProvider.Input.R_STICK)
                    )
                )
            }
        }
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        setWillNotDraw(false)
        setInputs()
        requestFocus()
    }

    override fun draw(canvas: Canvas) {
        super.draw(canvas)
        for (input in inputs!!) {
            input.draw(canvas)
        }
    }

    var currentConfiguredInput: Input? = null

    init {
        inputsMinWidthHeight =
            Math.round(INPUTS_MIN_WIDTH_HEIGHT_DP * (context.resources.displayMetrics.densityDpi.toFloat() / DisplayMetrics.DENSITY_DEFAULT))
        vibrator = getVibrator(context)
        setOnTouchListener(this)
        settingsProvider = InputOverlaySettingsProvider(context)
        val overlaySettings = settingsProvider.overlaySettings
        controllerIndex = overlaySettings.controllerIndex
        vibrateOnTouch = vibrator.hasVibrator() && overlaySettings.isVibrateOnTouchEnabled
    }

    private fun onEditPosition(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val x = event.x.toInt()
                val y = event.y.toInt()
                for (input in inputs!!) {
                    if (input.isInside(x, y)) {
                        currentConfiguredInput = input
                        input.enableDrawingBoundingRect(
                            resources.getColor(
                                R.color.purple,
                                context.theme
                            )
                        )
                        return true
                    }
                }
            }

            MotionEvent.ACTION_UP -> {
                if (currentConfiguredInput != null) {
                    currentConfiguredInput!!.disableDrawingBoundingRect()
                    currentConfiguredInput = null
                    return true
                }
            }

            MotionEvent.ACTION_MOVE -> {
                if (currentConfiguredInput != null) {
                    val x = event.x.toInt()
                    val y = event.y.toInt()
                    currentConfiguredInput!!.moveInput(x, y, width, height)
                    return true
                }
            }
        }
        return false
    }

    private fun onEditSize(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val x = event.x.toInt()
                val y = event.y.toInt()
                for (input in inputs!!) {
                    if (input.isInside(x, y)) {
                        currentConfiguredInput = input
                        input.enableDrawingBoundingRect(
                            resources.getColor(
                                R.color.red,
                                context.theme
                            )
                        )
                        return true
                    }
                }
            }

            MotionEvent.ACTION_UP -> {
                if (currentConfiguredInput != null) {
                    currentConfiguredInput!!.disableDrawingBoundingRect()
                    currentConfiguredInput = null
                    return true
                }
            }

            MotionEvent.ACTION_MOVE -> {
                if (currentConfiguredInput != null) {
                    val histSize = event.historySize
                    if (event.historySize >= 2) {
                        val x1 = event.getHistoricalX(0)
                        val y1 = event.getHistoricalY(0)
                        val x2 = event.getHistoricalX(histSize - 1)
                        val y2 = event.getHistoricalY(histSize - 1)
                        currentConfiguredInput!!.resize(
                            (x2 - x1).toInt(),
                            (y2 - y1).toInt(),
                            width,
                            height,
                            inputsMinWidthHeight
                        )
                    }
                    return true
                }
            }
        }
        return false
    }

    override fun onTouch(v: View, event: MotionEvent): Boolean {
        var touchEventProcessed = false
        if (inputMode == InputMode.DEFAULT) {
            for (input in inputs!!) {
                if (input.onTouch(event)) {
                    touchEventProcessed = true
                }
            }
        } else if (inputMode == InputMode.EDIT_POSITION) {
            touchEventProcessed = onEditPosition(event)
        } else if (inputMode == InputMode.EDIT_SIZE) {
            touchEventProcessed = onEditSize(event)
        }

        if (touchEventProcessed) {
            invalidate()
        }

        return touchEventProcessed
    }

    companion object {
        private const val INPUTS_MIN_WIDTH_HEIGHT_DP = 40
    }
}
