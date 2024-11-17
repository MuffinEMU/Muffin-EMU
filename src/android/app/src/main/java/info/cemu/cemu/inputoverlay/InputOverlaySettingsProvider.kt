package info.cemu.cemu.inputoverlay

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Rect
import info.cemu.cemu.nativeinterface.NativeInput
import java.util.Optional
import java.util.function.Consumer
import kotlin.math.max
import kotlin.math.min


class InputOverlaySettingsProvider(context: Context) {
    enum class Input {
        A,
        B,
        ONE,
        TWO,
        C,
        Z,
        HOME,
        DPAD,
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
        NUN_CHUCK_AXIS,
        LEFT_AXIS,
        RIGHT_AXIS,
    }

    private val sharedPreferences: SharedPreferences

    init {
        this.sharedPreferences = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
    }

    val overlaySettings: OverlaySettings
        get() = OverlaySettings(
            isVibrateOnTouchEnabled,
            isOverlayEnabled,
            controllerIndex,
            alpha,
            { settings: OverlaySettings ->
                val editor: SharedPreferences.Editor = sharedPreferences.edit()
                editor.putInt("controllerIndex", settings.controllerIndex)
                editor.putInt("alpha", settings.alpha)
                editor.putBoolean("overlayEnabled", settings.isOverlayEnabled)
                editor.putBoolean("vibrateOnTouchEnabled", settings.isVibrateOnTouchEnabled)
                editor.apply()
            }
        )

    fun getOverlaySettingsForInput(input: Input, width: Int, height: Int): InputOverlaySettings {
        return InputOverlaySettings(
            getRectangle(input).orElseGet({ getDefaultRectangle(input, width, height) }),
            alpha,
            { settings: InputOverlaySettings ->
                val editor: SharedPreferences.Editor = sharedPreferences.edit()
                val rect: Rect? = settings.rect
                editor.putInt(input.toString() + "left", rect!!.left)
                editor.putInt(input.toString() + "top", rect.top)
                editor.putInt(input.toString() + "right", rect.right)
                editor.putInt(input.toString() + "bottom", rect.bottom)
                editor.putInt(input.toString() + "alpha", settings.alpha)
                editor.apply()
            }
        )
    }

    private val isOverlayEnabled: Boolean
        get() {
            return sharedPreferences.getBoolean("overlayEnabled", true)
        }

    private val isVibrateOnTouchEnabled: Boolean
        get() {
            return sharedPreferences.getBoolean("vibrateOnTouchEnabled", true)
        }

    private val controllerIndex: Int
        get() {
            return sharedPreferences.getInt("controllerIndex", 0)
        }

    private val alpha: Int
        get() {
            return sharedPreferences.getInt(
                "alpha",
                DEFAULT_ALPHA
            )
        }

    private fun getRectangle(input: Input): Optional<Rect> {
        val left: Int = sharedPreferences.getInt(input.toString() + "left", -1)
        val top: Int = sharedPreferences.getInt(input.toString() + "top", -1)
        val right: Int = sharedPreferences.getInt(input.toString() + "right", -1)
        val bottom: Int = sharedPreferences.getInt(input.toString() + "bottom", -1)
        if (left == -1 || top == -1 || right == -1 || bottom == -1) {
            return Optional.empty()
        }
        return Optional.of(Rect(left, top, right, bottom))
    }

    fun getDefaultRectangle(input: Input, width: Int, height: Int): Rect {
        val pmButtonRadius: Int = (height * 0.065f).toInt()
        val pmButtonsCentreX: Int = (width * 0.5f).toInt()
        val pmButtonsCentreY: Int = (height * 0.875f).toInt()

        val roundButtonRadius: Int = (height * 0.065f).toInt()
        val abxyButtonsCentreX: Int = width - roundButtonRadius * 4
        val abxyButtonsCentreY: Int = height - roundButtonRadius * 4

        val rectangleButtonsHeight: Int = (height * 0.10f).toInt()
        val rectangleButtonsWidth: Int = rectangleButtonsHeight * 2

        val triggersLLeft: Int = (width * 0.05f).toInt()
        val triggersRLeft: Int = (width * 0.95f - rectangleButtonsWidth).toInt()
        val triggersTop: Int = (height * 0.05f).toInt()

        val dpadRadius: Int = (height * 0.20f).toInt()
        val dpadCentreX: Int = dpadRadius
        val dpadCentreY: Int = (height * 0.75f).toInt()

        val joystickRadius: Int = (height * 0.10f).toInt()
        val rightJoystickCentreX: Int = (width * 0.75f).toInt()
        val leftJoystickCentreX: Int = (width * 0.25f).toInt()
        val joystickCentreY: Int = (height * 0.55f).toInt()
        val joystickClickRadius: Int = (joystickRadius * 0.7f).toInt()
        // TODO: move this to res?
        return when (input) {
            Input.A -> Rect(
                abxyButtonsCentreX + roundButtonRadius,
                abxyButtonsCentreY - roundButtonRadius,
                abxyButtonsCentreX + roundButtonRadius * 3,
                abxyButtonsCentreY + roundButtonRadius
            )

            Input.B -> Rect(
                abxyButtonsCentreX - roundButtonRadius,
                abxyButtonsCentreY + roundButtonRadius,
                abxyButtonsCentreX + roundButtonRadius,
                abxyButtonsCentreY + roundButtonRadius * 3
            )

            Input.X, Input.ONE -> Rect(
                abxyButtonsCentreX - roundButtonRadius,
                abxyButtonsCentreY - roundButtonRadius * 3,
                abxyButtonsCentreX + roundButtonRadius,
                abxyButtonsCentreY - roundButtonRadius
            )

            Input.Y, Input.TWO -> Rect(
                abxyButtonsCentreX - roundButtonRadius * 3,
                abxyButtonsCentreY - roundButtonRadius,
                abxyButtonsCentreX - roundButtonRadius,
                abxyButtonsCentreY + roundButtonRadius
            )

            Input.MINUS -> Rect(
                pmButtonsCentreX - pmButtonRadius * 3,
                pmButtonsCentreY - pmButtonRadius,
                pmButtonsCentreX - pmButtonRadius,
                pmButtonsCentreY + pmButtonRadius
            )

            Input.PLUS -> Rect(
                pmButtonsCentreX + pmButtonRadius,
                pmButtonsCentreY - pmButtonRadius,
                pmButtonsCentreX + pmButtonRadius * 3,
                pmButtonsCentreY + pmButtonRadius
            )

            Input.L -> Rect(
                triggersLLeft,
                triggersTop,
                triggersLLeft + rectangleButtonsWidth,
                triggersTop + rectangleButtonsHeight
            )

            Input.ZL -> Rect(
                triggersLLeft,
                (triggersTop + rectangleButtonsHeight * 1.5f).toInt(),
                triggersLLeft + rectangleButtonsWidth,
                (triggersTop + rectangleButtonsHeight * 2.5f).toInt()
            )

            Input.R -> Rect(
                triggersRLeft,
                triggersTop,
                triggersRLeft + rectangleButtonsWidth,
                triggersTop + rectangleButtonsHeight
            )

            Input.ZR -> Rect(
                triggersRLeft,
                (triggersTop + rectangleButtonsHeight * 1.5f).toInt(),
                triggersRLeft + rectangleButtonsWidth,
                (triggersTop + rectangleButtonsHeight * 2.5f).toInt()
            )

            Input.C, Input.HOME, Input.Z, Input.NUN_CHUCK_AXIS -> Rect()
            Input.DPAD -> Rect(
                dpadCentreX - dpadRadius,
                dpadCentreY - dpadRadius,
                dpadCentreX + dpadRadius,
                dpadCentreY + dpadRadius
            )

            Input.LEFT_AXIS -> Rect(
                leftJoystickCentreX - joystickRadius,
                joystickCentreY - joystickRadius,
                leftJoystickCentreX + joystickRadius,
                joystickCentreY + joystickRadius
            )

            Input.RIGHT_AXIS -> Rect(
                rightJoystickCentreX - joystickRadius,
                joystickCentreY - joystickRadius,
                rightJoystickCentreX + joystickRadius,
                joystickCentreY + joystickRadius
            )

            Input.L_STICK -> Rect(
                (leftJoystickCentreX + joystickRadius * 1.5f - joystickClickRadius).toInt(),
                (joystickCentreY + joystickRadius * 1.5f - joystickClickRadius).toInt(),
                (leftJoystickCentreX + joystickRadius * 1.5f + joystickClickRadius).toInt(),
                (joystickCentreY + joystickRadius * 1.5f + joystickClickRadius).toInt()
            )

            Input.R_STICK -> Rect(
                (rightJoystickCentreX - joystickRadius * 1.5f - joystickClickRadius).toInt(),
                (joystickCentreY + joystickRadius * 1.5f - joystickClickRadius).toInt(),
                (rightJoystickCentreX - joystickRadius * 1.5f + joystickClickRadius).toInt(),
                (joystickCentreY + joystickRadius * 1.5f + joystickClickRadius).toInt()
            )
        }
    }

    class OverlaySettings internal constructor(
        var isVibrateOnTouchEnabled: Boolean,
        var isOverlayEnabled: Boolean,
        controllerIndex: Int,
        alpha: Int,
        private val overlaySettingsConsumer: (OverlaySettings) -> Unit
    ) {
        var controllerIndex: Int = 0
            set(controllerIndex) {
                require(controllerIndex in 0..<NativeInput.MAX_CONTROLLERS) { "Invalid controller index $controllerIndex" }
                field = controllerIndex
            }
        var alpha: Int = 0
            set(alpha) {
                field = max(0, min(255, alpha))
            }


        init {
            this.controllerIndex = controllerIndex
            this.alpha = alpha
        }

        fun saveSettings() {
            overlaySettingsConsumer(this)
        }
    }

    class InputOverlaySettings(
        var rect: Rect,
        var alpha: Int,
        val inputOverlaySettingsConsumer: (InputOverlaySettings) -> Unit
    ) {
        fun saveSettings() {
            inputOverlaySettingsConsumer(this)
        }
    }

    companion object {
        private const val DEFAULT_ALPHA: Int = 64
    }
}
