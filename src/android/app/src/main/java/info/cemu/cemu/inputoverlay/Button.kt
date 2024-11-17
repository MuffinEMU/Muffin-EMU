package info.cemu.cemu.inputoverlay

import android.content.res.Resources
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.view.MotionEvent
import androidx.annotation.DrawableRes
import androidx.core.content.res.ResourcesCompat
import info.cemu.cemu.drawable.getInvertedDrawable
import info.cemu.cemu.inputoverlay.InputOverlaySettingsProvider.InputOverlaySettings
import info.cemu.cemu.inputoverlay.InputOverlaySurfaceView.OverlayButton
import java.util.Objects

abstract class Button(
    resources: Resources,
    @DrawableRes buttonId: Int,
    buttonStateChangeListener: ButtonStateChangeListener,
    button: OverlayButton,
    settings: InputOverlaySettings
) :
    Input(settings) {
    @JvmField
    protected var iconPressed: Drawable

    @JvmField
    protected var iconNotPressed: Drawable = ResourcesCompat.getDrawable(
        resources,
        buttonId,
        null
    )!!

    @JvmField
    protected var icon: Drawable

    @JvmField
    protected var currentPointerId: Int = -1
    private val buttonStateChangeListener: ButtonStateChangeListener
    private val button: OverlayButton

    init {
        iconPressed = iconNotPressed.getInvertedDrawable(resources)
        iconPressed.alpha = settings.alpha
        iconNotPressed.alpha = settings.alpha
        icon = iconNotPressed
        this.buttonStateChangeListener = buttonStateChangeListener
        this.button = button
    }

    override fun onTouch(event: MotionEvent): Boolean {
        var stateUpdated = false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val pointerIndex = event.actionIndex
                val x = event.getX(pointerIndex).toInt()
                val y = event.getY(pointerIndex).toInt()
                if (isInside(x, y)) {
                    currentPointerId = event.getPointerId(pointerIndex)
                    updateState(true)
                    stateUpdated = true
                }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                if (event.getPointerId(event.actionIndex) == currentPointerId) {
                    currentPointerId = -1
                    updateState(false)
                    stateUpdated = true
                }
            }
        }
        return stateUpdated
    }

    override fun drawInput(canvas: Canvas) {
        icon.draw(canvas)
    }

    override fun resetInput() {
        updateState(false)
    }

    protected fun updateState(state: Boolean) {
        icon = if (state) {
            iconPressed
        } else {
            iconNotPressed
        }
        buttonStateChangeListener.onButtonStateChange(button, state)
    }
}
