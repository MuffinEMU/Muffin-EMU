package info.cemu.cemu.inputoverlay

import android.content.res.Resources
import android.graphics.Canvas
import android.graphics.Rect
import android.view.MotionEvent
import androidx.annotation.DrawableRes
import androidx.core.content.res.ResourcesCompat
import kotlin.math.atan2
import kotlin.math.min

class DPadInput(
    resources: Resources,
    @DrawableRes backgroundId: Int,
    @DrawableRes buttonId: Int,
    private val onButtonStateChange: (button: OverlayDpad, state: Boolean) -> Unit,
    private val alpha: Int,
    rect: Rect,
) : Input(rect) {
    private val dpadUpDrawable = InputDrawable(resources, buttonId)
    private val dpadDownDrawable = InputDrawable(resources, buttonId)
    private val dpadLeftDrawable = InputDrawable(resources, buttonId)
    private val dpadRightDrawable = InputDrawable(resources, buttonId)
    private val background = ResourcesCompat.getDrawable(resources, backgroundId, null)!!

    private var dpadState: Int = NONE

    private var centerX: Int = 0
    private var centerY: Int = 0
    private var radius2: Int = 0
    private var currentPointerId: Int = -1

    override fun configure() {
        this.centerX = rect.centerX()
        this.centerY = rect.centerY()
        val radius = min(rect.width(), rect.height()) / 2
        radius2 = radius * radius
        background.alpha = alpha
        background.setBounds(
            centerX - radius,
            centerY - radius,
            centerX + radius,
            centerY + radius
        )

        val buttonSize = radius / 2
        val configureButton = { circleXPos: Int, circleYPos: Int, inputDrawable: InputDrawable ->
            inputDrawable.setAlpha(alpha)
            val left = circleXPos - buttonSize / 2
            val top = circleYPos - buttonSize / 2
            inputDrawable.setBounds(left, top, left + buttonSize, top + buttonSize)
        }
        configureButton(
            centerX,
            centerY - 2 * radius / 3,
            dpadUpDrawable
        )
        configureButton(
            centerX,
            centerY + 2 * radius / 3,
            dpadDownDrawable
        )
        configureButton(
            centerX - 2 * radius / 3,
            centerY,
            dpadLeftDrawable
        )
        configureButton(
            centerX + 2 * radius / 3,
            centerY,
            dpadRightDrawable
        )
    }

    init {
        configure()
    }

    private fun updateState(nextDpadState: Int) {
        if (nextDpadState == dpadState) return
        updateState(dpadState and nextDpadState.inv(), false)
        updateState(nextDpadState and dpadState.inv(), true)
        dpadState = nextDpadState
    }

    private fun updateState(dpadState: Int, pressed: Boolean) {
        if (dpadState == NONE) return
        if ((dpadState and UP) != 0) {
            onButtonStateChange(OverlayDpad.DPAD_UP, pressed)
            dpadUpDrawable.setActiveState(pressed)
        }
        if ((dpadState and DOWN) != 0) {
            onButtonStateChange(OverlayDpad.DPAD_DOWN, pressed)
            dpadDownDrawable.setActiveState(pressed)
        }
        if ((dpadState and LEFT) != 0) {
            onButtonStateChange(OverlayDpad.DPAD_LEFT, pressed)
            dpadLeftDrawable.setActiveState(pressed)
        }
        if ((dpadState and RIGHT) != 0) {
            onButtonStateChange(OverlayDpad.DPAD_RIGHT, pressed)
            dpadRightDrawable.setActiveState(pressed)
        }
    }

    private fun getStateByPosition(x: Int, y: Int): Int {
        val norm2 = (x - centerX) * (x - centerX) + (y - centerY) * (y - centerY)
        if (norm2 <= radius2 * 0.1f) {
            return NONE
        }
        val angle = atan2((y - centerY).toDouble(), (x - centerX).toDouble())
        return when (angle) {
            in -0.875 * Math.PI..<-0.625 * Math.PI -> UP or LEFT
            in -0.625 * Math.PI..<-0.375 * Math.PI -> UP
            in -0.375 * Math.PI..<-0.125 * Math.PI -> UP or RIGHT
            in -0.125 * Math.PI..<0.125 * Math.PI -> RIGHT
            in 0.125 * Math.PI..<0.375 * Math.PI -> DOWN or RIGHT
            in 0.375 * Math.PI..<0.625 * Math.PI -> DOWN
            in 0.625 * Math.PI..<0.875 * Math.PI -> DOWN or LEFT
            else -> LEFT // in [-pi, -0.875*pi) or [0.875*pi, pi]
        }
    }

    override fun onTouch(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (currentPointerId != -1) {
                    return false
                }
                val pointerIndex = event.actionIndex
                val x = event.getX(pointerIndex).toInt()
                val y = event.getY(pointerIndex).toInt()
                val pointerId = event.getPointerId(pointerIndex)
                if (isInside(x, y)) {
                    currentPointerId = pointerId
                    updateState(getStateByPosition(x, y))
                    return true
                }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val pointerId = event.getPointerId(event.actionIndex)
                if (pointerId == currentPointerId) {
                    currentPointerId = -1
                    updateState(NONE)
                    return true
                }
            }

            MotionEvent.ACTION_MOVE -> {
                if (currentPointerId == -1) {
                    return false
                }
                for (i in 0 until event.pointerCount) {
                    if (currentPointerId != event.getPointerId(i)) {
                        continue
                    }
                    val x = event.getX(i).toInt()
                    val y = event.getY(i).toInt()
                    updateState(getStateByPosition(x, y))
                    return true
                }
            }
        }
        return false
    }

    override fun resetInput() {
        updateState(NONE)
    }

    override fun isInside(x: Int, y: Int): Boolean {
        return (x - centerX) * (x - centerX) + (y - centerY) * (y - centerY) <= radius2
    }

    override fun drawInput(canvas: Canvas) {
        background.draw(canvas)
        dpadUpDrawable.icon.draw(canvas)
        dpadDownDrawable.icon.draw(canvas)
        dpadLeftDrawable.icon.draw(canvas)
        dpadRightDrawable.icon.draw(canvas)
    }

    companion object {
        private const val NONE = 0
        private const val UP = 1 shl 0
        private const val DOWN = 1 shl 1
        private const val LEFT = 1 shl 2
        private const val RIGHT = 1 shl 3
    }
}
