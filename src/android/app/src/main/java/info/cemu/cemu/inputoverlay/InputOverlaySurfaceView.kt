package info.cemu.cemu.inputoverlay

import android.content.Context
import android.graphics.Canvas
import android.graphics.Rect
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
import androidx.annotation.DrawableRes
import info.cemu.cemu.R
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
    private var pixelDensity = 1
    private var currentAlpha = 255
    private var currentConfiguredInput: Input? = null
    private var nativeControllerType = -1
    var controllerIndex: Int = 0

    private var inputs: MutableList<Pair<OverlayInput, Input>>? = null
    private val settingsProvider: InputOverlaySettingsManager
    private val vibrator: Vibrator?
    private val buttonTouchVibrationEffect =
        VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK)
    private var vibrateOnTouch: Boolean = false
    private var inputsMinWidthHeight: Int = -1

    init {
        pixelDensity = context.resources.displayMetrics.densityDpi
        inputsMinWidthHeight =
            Math.round(INPUTS_MIN_WIDTH_HEIGHT_DP * (context.resources.displayMetrics.densityDpi.toFloat() / DisplayMetrics.DENSITY_DEFAULT))
        vibrator = getVibrator(context)
        setOnTouchListener(this)
        settingsProvider = InputOverlaySettingsManager(context)
        val overlaySettings = settingsProvider.overlaySettings
        controllerIndex = overlaySettings.controllerIndex
        currentAlpha = overlaySettings.alpha
        vibrateOnTouch = vibrator.hasVibrator() && overlaySettings.isVibrateOnTouchEnabled
    }

    fun resetInputs() {
        if (inputs == null) {
            return
        }
        for (input in OverlayInputList) {
            settingsProvider.clearSavedRectangle(input)
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
        for ((overlayInput, input) in inputs!!) {
            input.reset()
            settingsProvider.saveRectangle(overlayInput, input.getBoundingRectangle())
        }
    }

    fun getInputMode(): InputMode {
        return inputMode
    }

    private fun getVibrator(context: Context): Vibrator {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager =
                context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            return vibratorManager.defaultVibrator
        }
        @Suppress("DEPRECATION")
        return context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }

    private fun overlayButtonToVPADButton(button: OverlayInput): Int {
        return when (button) {
            OverlayButton.A -> NativeInput.VPAD_BUTTON_A
            OverlayButton.B -> NativeInput.VPAD_BUTTON_B
            OverlayButton.X -> NativeInput.VPAD_BUTTON_X
            OverlayButton.Y -> NativeInput.VPAD_BUTTON_Y
            OverlayButton.PLUS -> NativeInput.VPAD_BUTTON_PLUS
            OverlayButton.MINUS -> NativeInput.VPAD_BUTTON_MINUS
            OverlayDpad.DPAD_UP -> NativeInput.VPAD_BUTTON_UP
            OverlayDpad.DPAD_DOWN -> NativeInput.VPAD_BUTTON_DOWN
            OverlayDpad.DPAD_LEFT -> NativeInput.VPAD_BUTTON_LEFT
            OverlayDpad.DPAD_RIGHT -> NativeInput.VPAD_BUTTON_RIGHT
            OverlayButton.L_STICK_CLICK -> NativeInput.VPAD_BUTTON_STICKL
            OverlayButton.R_STICK_CLICK -> NativeInput.VPAD_BUTTON_STICKR
            OverlayButton.L -> NativeInput.VPAD_BUTTON_L
            OverlayButton.R -> NativeInput.VPAD_BUTTON_R
            OverlayButton.ZR -> NativeInput.VPAD_BUTTON_ZR
            OverlayButton.ZL -> NativeInput.VPAD_BUTTON_ZL
            else -> -1
        }
    }

    private fun overlayButtonToClassicButton(button: OverlayInput): Int {
        return when (button) {
            OverlayButton.A -> NativeInput.CLASSIC_BUTTON_A
            OverlayButton.B -> NativeInput.CLASSIC_BUTTON_B
            OverlayButton.X -> NativeInput.CLASSIC_BUTTON_X
            OverlayButton.Y -> NativeInput.CLASSIC_BUTTON_Y
            OverlayButton.PLUS -> NativeInput.CLASSIC_BUTTON_PLUS
            OverlayButton.MINUS -> NativeInput.CLASSIC_BUTTON_MINUS
            OverlayDpad.DPAD_UP -> NativeInput.CLASSIC_BUTTON_UP
            OverlayDpad.DPAD_DOWN -> NativeInput.CLASSIC_BUTTON_DOWN
            OverlayDpad.DPAD_LEFT -> NativeInput.CLASSIC_BUTTON_LEFT
            OverlayDpad.DPAD_RIGHT -> NativeInput.CLASSIC_BUTTON_RIGHT
            OverlayButton.L -> NativeInput.CLASSIC_BUTTON_L
            OverlayButton.R -> NativeInput.CLASSIC_BUTTON_R
            OverlayButton.ZR -> NativeInput.CLASSIC_BUTTON_ZR
            OverlayButton.ZL -> NativeInput.CLASSIC_BUTTON_ZL
            else -> -1
        }
    }

    private fun overlayButtonToProButton(button: OverlayInput): Int {
        return when (button) {
            OverlayButton.A -> NativeInput.PRO_BUTTON_A
            OverlayButton.B -> NativeInput.PRO_BUTTON_B
            OverlayButton.X -> NativeInput.PRO_BUTTON_X
            OverlayButton.Y -> NativeInput.PRO_BUTTON_Y
            OverlayButton.PLUS -> NativeInput.PRO_BUTTON_PLUS
            OverlayButton.MINUS -> NativeInput.PRO_BUTTON_MINUS
            OverlayDpad.DPAD_UP -> NativeInput.PRO_BUTTON_UP
            OverlayDpad.DPAD_DOWN -> NativeInput.PRO_BUTTON_DOWN
            OverlayDpad.DPAD_LEFT -> NativeInput.PRO_BUTTON_LEFT
            OverlayDpad.DPAD_RIGHT -> NativeInput.PRO_BUTTON_RIGHT
            OverlayButton.L_STICK_CLICK -> NativeInput.PRO_BUTTON_STICKL
            OverlayButton.R_STICK_CLICK -> NativeInput.PRO_BUTTON_STICKR
            OverlayButton.L -> NativeInput.PRO_BUTTON_L
            OverlayButton.R -> NativeInput.PRO_BUTTON_R
            OverlayButton.ZR -> NativeInput.PRO_BUTTON_ZR
            OverlayButton.ZL -> NativeInput.PRO_BUTTON_ZL
            else -> -1
        }
    }

    private fun overlayButtonToWiimoteButton(button: OverlayInput): Int {
        return when (button) {
            OverlayButton.A -> NativeInput.WIIMOTE_BUTTON_A
            OverlayButton.B -> NativeInput.WIIMOTE_BUTTON_B
            OverlayButton.ONE -> NativeInput.WIIMOTE_BUTTON_1
            OverlayButton.TWO -> NativeInput.WIIMOTE_BUTTON_2
            OverlayButton.PLUS -> NativeInput.WIIMOTE_BUTTON_PLUS
            OverlayButton.MINUS -> NativeInput.WIIMOTE_BUTTON_MINUS
            OverlayButton.HOME -> NativeInput.WIIMOTE_BUTTON_HOME
            OverlayDpad.DPAD_UP -> NativeInput.WIIMOTE_BUTTON_UP
            OverlayDpad.DPAD_DOWN -> NativeInput.WIIMOTE_BUTTON_DOWN
            OverlayDpad.DPAD_LEFT -> NativeInput.WIIMOTE_BUTTON_LEFT
            OverlayDpad.DPAD_RIGHT -> NativeInput.WIIMOTE_BUTTON_RIGHT
            OverlayButton.C -> NativeInput.WIIMOTE_BUTTON_NUNCHUCK_C
            OverlayButton.Z -> NativeInput.WIIMOTE_BUTTON_NUNCHUCK_Z
            else -> -1
        }
    }

    private fun onButtonStateChange(button: OverlayInput, state: Boolean) {
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

    private fun onOverlayAxis(axis: Int, value: Float) {
        onOverlayAxis(controllerIndex, axis, value)
    }

    private fun onVPADJoystickStateChange(
        joystick: OverlayInput,
        up: Float,
        down: Float,
        left: Float,
        right: Float,
    ) {
        if (joystick == OverlayJoystick.LEFT) {
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKL_UP, up)
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKL_DOWN, down)
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKL_LEFT, left)
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKL_RIGHT, right)
        } else if (joystick == OverlayJoystick.RIGHT) {
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKR_UP, up)
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKR_DOWN, down)
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKR_LEFT, left)
            onOverlayAxis(NativeInput.VPAD_BUTTON_STICKR_RIGHT, right)
        }
    }

    private fun onProJoystickStateChange(
        joystick: OverlayInput,
        up: Float,
        down: Float,
        left: Float,
        right: Float,
    ) {
        if (joystick == OverlayJoystick.LEFT) {
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKL_UP, up)
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKL_DOWN, down)
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKL_LEFT, left)
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKL_RIGHT, right)
        } else if (joystick == OverlayJoystick.RIGHT) {
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKR_UP, up)
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKR_DOWN, down)
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKR_LEFT, left)
            onOverlayAxis(NativeInput.PRO_BUTTON_STICKR_RIGHT, right)
        }
    }

    private fun onClassicJoystickStateChange(
        joystick: OverlayInput,
        up: Float,
        down: Float,
        left: Float,
        right: Float,
    ) {
        if (joystick == OverlayJoystick.LEFT) {
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKL_UP, up)
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKL_DOWN, down)
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKL_LEFT, left)
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKL_RIGHT, right)
        } else if (joystick == OverlayJoystick.RIGHT) {
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKR_UP, up)
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKR_DOWN, down)
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKR_LEFT, left)
            onOverlayAxis(NativeInput.CLASSIC_BUTTON_STICKR_RIGHT, right)
        }
    }

    private fun onWiimoteJoystickStateChange(
        joystick: OverlayInput,
        up: Float,
        down: Float,
        left: Float,
        right: Float,
    ) {
        if (joystick == OverlayJoystick.RIGHT) {
            onOverlayAxis(NativeInput.WIIMOTE_BUTTON_NUNCHUCK_UP, up)
            onOverlayAxis(NativeInput.WIIMOTE_BUTTON_NUNCHUCK_DOWN, down)
            onOverlayAxis(NativeInput.WIIMOTE_BUTTON_NUNCHUCK_LEFT, left)
            onOverlayAxis(NativeInput.WIIMOTE_BUTTON_NUNCHUCK_RIGHT, right)
        }
    }

    private fun onJoystickStateChange(joystick: OverlayInput, x: Float, y: Float) {
        val onJoystickChange = when (nativeControllerType) {
            NativeInput.EMULATED_CONTROLLER_TYPE_VPAD -> ::onVPADJoystickStateChange
            NativeInput.EMULATED_CONTROLLER_TYPE_PRO -> ::onProJoystickStateChange
            NativeInput.EMULATED_CONTROLLER_TYPE_CLASSIC -> ::onClassicJoystickStateChange
            NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE -> ::onWiimoteJoystickStateChange
            else -> return
        }
        val (up, down) = if (y < 0) Pair(-y, 0f) else Pair(0f, y)
        val (left, right) = if (x < 0) Pair(-x, 0f) else Pair(0f, x)
        onJoystickChange(joystick, up, down, left, right)
    }

    private fun getBoundingRectangleForInput(input: OverlayInput): Rect {
        return settingsProvider.getInputOverlayRectangle(input, width, height, pixelDensity)
    }


    private fun MutableList<Pair<OverlayInput, Input>>.addRoundButton(
        button: OverlayButton,
        @DrawableRes buttonDrawable: Int,
    ) {
        add(
            button to RoundButton(
                resources,
                buttonDrawable,
                { onButtonStateChange(button, it) },
                currentAlpha,
                getBoundingRectangleForInput(button),
            )
        )
    }

    private fun MutableList<Pair<OverlayInput, Input>>.addJoystick(
        joystick: OverlayJoystick,
        @DrawableRes joystickInnerCircleDrawable: Int = R.drawable.stick_inner,
        @DrawableRes joystickBackgroundDrawable: Int = R.drawable.stick_background,
    ) {
        add(
            joystick to Joystick(
                resources,
                joystickBackgroundDrawable,
                joystickInnerCircleDrawable,
                { x, y -> onJoystickStateChange(joystick, x, y) },
                currentAlpha,
                getBoundingRectangleForInput(joystick)
            )
        )
    }

    private fun MutableList<Pair<OverlayInput, Input>>.addDpad() {
        add(
            OverlayDpad.DPAD_UP to DPadInput(
                resources,
                R.drawable.dpad_background,
                R.drawable.dpad_button,
                ::onButtonStateChange,
                currentAlpha,
                getBoundingRectangleForInput(OverlayDpad.DPAD_UP)
            )
        )
    }

    private fun MutableList<Pair<OverlayInput, Input>>.addRectangleButton(
        button: OverlayButton,
        @DrawableRes buttonDrawable: Int,
    ) {
        add(
            button to RectangleButton(
                resources,
                buttonDrawable,
                { onButtonStateChange(button, it) },
                currentAlpha,
                getBoundingRectangleForInput(button)
            )
        )
    }


    private fun setInputs() {
        if (inputs != null) {
            return
        }
        if (isControllerDisabled(controllerIndex)) {
            inputs = mutableListOf()
            return
        }

        nativeControllerType = getControllerType(controllerIndex)
        inputs = mutableListOf<Pair<OverlayInput, Input>>().apply {
            addRoundButton(
                OverlayButton.MINUS,
                R.drawable.button_minus,
            )
            addRoundButton(
                OverlayButton.PLUS,
                R.drawable.button_plus,
            )
            addDpad()
            addRoundButton(
                OverlayButton.A,
                R.drawable.button_a,
            )
            addRoundButton(
                OverlayButton.B,
                R.drawable.button_b,
            )
            addJoystick(OverlayJoystick.RIGHT)
            if (nativeControllerType != NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE) {
                addRoundButton(
                    OverlayButton.X,
                    R.drawable.button_x,
                )
                addRoundButton(
                    OverlayButton.Y,
                    R.drawable.button_y,
                )
                addRectangleButton(
                    OverlayButton.ZL,
                    R.drawable.button_zl,
                )
                addRectangleButton(
                    OverlayButton.ZR,
                    R.drawable.button_zr,
                )
                addRectangleButton(
                    OverlayButton.L,
                    R.drawable.button_l,
                )
                addRectangleButton(
                    OverlayButton.R,
                    R.drawable.button_r,
                )
                addJoystick(OverlayJoystick.LEFT)
            }
            if (nativeControllerType == NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE) {
                addRoundButton(
                    OverlayButton.ONE,
                    R.drawable.button_one,
                )
                addRoundButton(
                    OverlayButton.TWO,
                    R.drawable.button_two,
                )
                addRoundButton(
                    OverlayButton.C,
                    R.drawable.button_c,
                )
                addRectangleButton(
                    OverlayButton.Z,
                    R.drawable.button_z,
                )
                addRoundButton(
                    OverlayButton.HOME,
                    R.drawable.button_home,
                )
            }
            if (nativeControllerType != NativeInput.EMULATED_CONTROLLER_TYPE_CLASSIC
                && nativeControllerType != NativeInput.EMULATED_CONTROLLER_TYPE_WIIMOTE
            ) {
                addRoundButton(
                    OverlayButton.L_STICK_CLICK,
                    R.drawable.button_stick,
                )
                addRoundButton(
                    OverlayButton.R_STICK_CLICK,
                    R.drawable.button_stick,
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
        for ((_, input) in inputs!!) {
            input.draw(canvas)
        }
    }


    private fun onEditPosition(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val x = event.x.toInt()
                val y = event.y.toInt()
                for ((_, input) in inputs!!) {
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
                for ((_, input) in inputs!!) {
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
        when (inputMode) {
            InputMode.DEFAULT -> {
                for ((_, input) in inputs!!) {
                    if (input.onTouch(event)) {
                        touchEventProcessed = true
                    }
                }
            }

            InputMode.EDIT_POSITION -> {
                touchEventProcessed = onEditPosition(event)
            }

            InputMode.EDIT_SIZE -> {
                touchEventProcessed = onEditSize(event)
            }
        }

        if (touchEventProcessed) {
            invalidate()
        }

        return touchEventProcessed
    }

    companion object {
        private const val INPUTS_MIN_WIDTH_HEIGHT_DP = 20
    }
}
