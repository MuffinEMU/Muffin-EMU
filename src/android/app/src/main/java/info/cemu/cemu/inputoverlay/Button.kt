package info.cemu.cemu.inputoverlay

import android.content.res.Resources
import android.graphics.Canvas
import android.graphics.Rect
import android.view.MotionEvent
import androidx.annotation.DrawableRes

abstract class Button(
    resources: Resources,
    @DrawableRes buttonId: Int,
    private val onButtonStateChange: (state: Boolean) -> Unit,
    boundingRect: Rect,
) : Input(boundingRect) {


    protected val inputDrawable = InputDrawable(resources, buttonId)

    private var currentPointerId: Int = -1

    override fun onTouch(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val pointerIndex = event.actionIndex
                val x = event.getX(pointerIndex).toInt()
                val y = event.getY(pointerIndex).toInt()
                if (isInside(x, y)) {
                    currentPointerId = event.getPointerId(pointerIndex)
                    updateState(true)
                    return true
                }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                if (event.getPointerId(event.actionIndex) == currentPointerId) {
                    currentPointerId = -1
                    updateState(false)
                    return true
                }
            }
        }
        return false
    }

    override fun drawInput(canvas: Canvas) {
        inputDrawable.icon.draw(canvas)
    }

    override fun resetInput() {
        updateState(false)
    }

    private fun updateState(state: Boolean) {
        inputDrawable.setActiveState(state)
        onButtonStateChange(state)
    }
}
