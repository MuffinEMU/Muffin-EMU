package info.cemu.cemu.inputoverlay

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Rect
import androidx.annotation.IntRange
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import info.cemu.cemu.CemuApplication
import info.cemu.cemu.nativeinterface.NativeInput
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.util.Optional

private const val INPUT_DATA_STORE_NAME = "input-settings22"
private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = INPUT_DATA_STORE_NAME)
private fun <T> Preferences.get(key: Preferences.Key<T>, default: T) =
    this[key] ?: default

class OverlaySettings(
    var isVibrateOnTouchEnabled: Boolean,
    var isOverlayEnabled: Boolean,
    @IntRange(0, (NativeInput.MAX_CONTROLLERS - 1L))
    var controllerIndex: Int,
    @IntRange(0, 255)
    var alpha: Int,
) {
    companion object {
        private const val DEFAULT_ALPHA: Int = 64
        private const val IS_VIBRATE_ON_TOUCH_ENABLED_KEY = "IS_VIBRATE_ON_TOUCH_ENABLED"
        private const val IS_OVERLAY_ENABLED_KEY = "IS_OVERLAY_ENABLED"
        private const val CONTROLLER_INDEX_KEY = "CONTROLLER_INDEX"
        private const val ALPHA_KEY = "ALPHA"
    }

    internal constructor(sharedPreferences: SharedPreferences) : this(
        isVibrateOnTouchEnabled = sharedPreferences.getBoolean(
            IS_VIBRATE_ON_TOUCH_ENABLED_KEY,
            false
        ),
        isOverlayEnabled = sharedPreferences.getBoolean(IS_OVERLAY_ENABLED_KEY, false),
        controllerIndex = sharedPreferences.getInt(CONTROLLER_INDEX_KEY, 0),
        alpha = sharedPreferences.getInt(ALPHA_KEY, DEFAULT_ALPHA),
    )

    internal fun save(sharedPreferences: SharedPreferences) {
        sharedPreferences.edit().apply {
            putBoolean(IS_VIBRATE_ON_TOUCH_ENABLED_KEY, isVibrateOnTouchEnabled)
            putBoolean(IS_OVERLAY_ENABLED_KEY, isOverlayEnabled)
            putInt(CONTROLLER_INDEX_KEY, controllerIndex)
            putInt(ALPHA_KEY, alpha)
            apply()
        }
    }
}

class InputOverlaySettingsProvider(context: Context) {
    enum class OverlayInput {
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

    val sharedPreferences: SharedPreferences =
        context.getSharedPreferences("input-overlay-settings", Context.MODE_PRIVATE);

    var overlaySettings: OverlaySettings
        get() = OverlaySettings(sharedPreferences)
        set(value) = value.save(sharedPreferences)


//    private val sharedPreferences: SharedPreferences =
//        context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    fun getOverlaySettingsForInput(
        input: OverlayInput,
        width: Int,
        height: Int
    ): InputOverlaySettings {
        return InputOverlaySettings(
            getRectangle(input).orElseGet({ getDefaultRectangle(input, width, height) }),
            100,
            { settings: InputOverlaySettings ->
//                val editor: SharedPreferences.Editor = sharedPreferences.edit()
//                val rect: Rect? = settings.rect
//                editor.putInt(input.toString() + "left", rect!!.left)
//                editor.putInt(input.toString() + "top", rect.top)
//                editor.putInt(input.toString() + "right", rect.right)
//                editor.putInt(input.toString() + "bottom", rect.bottom)
//                editor.putInt(input.toString() + "alpha", settings.alpha)
//                editor.apply()
            }
        )
    }


    private fun getRectangle(input: OverlayInput): Optional<Rect> {
//        val left: Int = sharedPreferences.getInt(input.toString() + "left", -1)
//        val top: Int = sharedPreferences.getInt(input.toString() + "top", -1)
//        val right: Int = sharedPreferences.getInt(input.toString() + "right", -1)
//        val bottom: Int = sharedPreferences.getInt(input.toString() + "bottom", -1)
//        if (left == -1 || top == -1 || right == -1 || bottom == -1) {
//        }
        return Optional.empty()
//        return Optional.of(Rect(left, top, right, bottom))
    }

    fun getDefaultRectangle(input: OverlayInput, width: Int, height: Int): Rect {
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
            OverlayInput.A -> Rect(
                abxyButtonsCentreX + roundButtonRadius,
                abxyButtonsCentreY - roundButtonRadius,
                abxyButtonsCentreX + roundButtonRadius * 3,
                abxyButtonsCentreY + roundButtonRadius
            )

            OverlayInput.B -> Rect(
                abxyButtonsCentreX - roundButtonRadius,
                abxyButtonsCentreY + roundButtonRadius,
                abxyButtonsCentreX + roundButtonRadius,
                abxyButtonsCentreY + roundButtonRadius * 3
            )

            OverlayInput.X, OverlayInput.ONE -> Rect(
                abxyButtonsCentreX - roundButtonRadius,
                abxyButtonsCentreY - roundButtonRadius * 3,
                abxyButtonsCentreX + roundButtonRadius,
                abxyButtonsCentreY - roundButtonRadius
            )

            OverlayInput.Y, OverlayInput.TWO -> Rect(
                abxyButtonsCentreX - roundButtonRadius * 3,
                abxyButtonsCentreY - roundButtonRadius,
                abxyButtonsCentreX - roundButtonRadius,
                abxyButtonsCentreY + roundButtonRadius
            )

            OverlayInput.MINUS -> Rect(
                pmButtonsCentreX - pmButtonRadius * 3,
                pmButtonsCentreY - pmButtonRadius,
                pmButtonsCentreX - pmButtonRadius,
                pmButtonsCentreY + pmButtonRadius
            )

            OverlayInput.PLUS -> Rect(
                pmButtonsCentreX + pmButtonRadius,
                pmButtonsCentreY - pmButtonRadius,
                pmButtonsCentreX + pmButtonRadius * 3,
                pmButtonsCentreY + pmButtonRadius
            )

            OverlayInput.L -> Rect(
                triggersLLeft,
                triggersTop,
                triggersLLeft + rectangleButtonsWidth,
                triggersTop + rectangleButtonsHeight
            )

            OverlayInput.ZL -> Rect(
                triggersLLeft,
                (triggersTop + rectangleButtonsHeight * 1.5f).toInt(),
                triggersLLeft + rectangleButtonsWidth,
                (triggersTop + rectangleButtonsHeight * 2.5f).toInt()
            )

            OverlayInput.R -> Rect(
                triggersRLeft,
                triggersTop,
                triggersRLeft + rectangleButtonsWidth,
                triggersTop + rectangleButtonsHeight
            )

            OverlayInput.ZR -> Rect(
                triggersRLeft,
                (triggersTop + rectangleButtonsHeight * 1.5f).toInt(),
                triggersRLeft + rectangleButtonsWidth,
                (triggersTop + rectangleButtonsHeight * 2.5f).toInt()
            )

            OverlayInput.C, OverlayInput.HOME, OverlayInput.Z, OverlayInput.NUN_CHUCK_AXIS -> Rect()
            OverlayInput.DPAD -> Rect(
                dpadCentreX - dpadRadius,
                dpadCentreY - dpadRadius,
                dpadCentreX + dpadRadius,
                dpadCentreY + dpadRadius
            )

            OverlayInput.LEFT_AXIS -> Rect(
                leftJoystickCentreX - joystickRadius,
                joystickCentreY - joystickRadius,
                leftJoystickCentreX + joystickRadius,
                joystickCentreY + joystickRadius
            )

            OverlayInput.RIGHT_AXIS -> Rect(
                rightJoystickCentreX - joystickRadius,
                joystickCentreY - joystickRadius,
                rightJoystickCentreX + joystickRadius,
                joystickCentreY + joystickRadius
            )

            OverlayInput.L_STICK -> Rect(
                (leftJoystickCentreX + joystickRadius * 1.5f - joystickClickRadius).toInt(),
                (joystickCentreY + joystickRadius * 1.5f - joystickClickRadius).toInt(),
                (leftJoystickCentreX + joystickRadius * 1.5f + joystickClickRadius).toInt(),
                (joystickCentreY + joystickRadius * 1.5f + joystickClickRadius).toInt()
            )

            OverlayInput.R_STICK -> Rect(
                (rightJoystickCentreX - joystickRadius * 1.5f - joystickClickRadius).toInt(),
                (joystickCentreY + joystickRadius * 1.5f - joystickClickRadius).toInt(),
                (rightJoystickCentreX - joystickRadius * 1.5f + joystickClickRadius).toInt(),
                (joystickCentreY + joystickRadius * 1.5f + joystickClickRadius).toInt()
            )
        }
    }


//    class OverlaySettings internal constructor(
//        var isVibrateOnTouchEnabled: Boolean,
//        var isOverlayEnabled: Boolean,
//        controllerIndex: Int,
//        alpha: Int,
//        private val overlaySettingsConsumer: (OverlaySettings) -> Unit
//    ) {
//        var controllerIndex: Int = 0
//            set(controllerIndex) {
//                require(controllerIndex in 0..<NativeInput.MAX_CONTROLLERS) { "Invalid controller index $controllerIndex" }
//                field = controllerIndex
//            }
//        var alpha: Int = 0
//            set(alpha) {
//                field = max(0, min(255, alpha))
//            }
//
//
//        init {
//            this.controllerIndex = controllerIndex
//            this.alpha = alpha
//        }
//
//        fun saveSettings() {
//            overlaySettingsConsumer(this)
//        }
//    }

    class InputOverlaySettings(
        var rect: Rect,
        var alpha: Int,
        val inputOverlaySettingsConsumer: (InputOverlaySettings) -> Unit
    ) {
        fun saveSettings() {
            inputOverlaySettingsConsumer(this)
        }
    }


}
