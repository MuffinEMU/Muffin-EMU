package info.cemu.cemu.inputoverlay

import android.content.res.Resources
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.view.MotionEvent
import androidx.annotation.DrawableRes
import androidx.core.content.res.ResourcesCompat
import info.cemu.cemu.drawable.applyInvertedColorTransform
import info.cemu.cemu.inputoverlay.InputOverlaySettingsProvider.InputOverlaySettings
import kotlin.math.atan2
import kotlin.math.min

class DPadInput(
    resources: Resources,
    @DrawableRes backgroundId: Int,
    @DrawableRes buttonId: Int,
    private val buttonStateChangeListener: ButtonStateChangeListener,
    settings: InputOverlaySettings
) :
    Input(settings) {
    var iconDpadUp: Drawable
    var iconDpadUpPressed: Drawable
    var iconDpadUpNotPressed: Drawable

    var iconDpadDown: Drawable
    var iconDpadDownPressed: Drawable
    var iconDpadDownNotPressed: Drawable

    var iconDpadLeft: Drawable
    var iconDpadLeftPressed: Drawable
    var iconDpadLeftNotPressed: Drawable

    var iconDpadRight: Drawable
    var iconDpadRightPressed: Drawable
    var iconDpadRightNotPressed: Drawable
    var background: Drawable = ResourcesCompat.getDrawable(resources, backgroundId, null)!!

    enum class DpadState {
        NONE, UP, DOWN, LEFT, RIGHT, UP_LEFT, UP_RIGHT, DOWN_LEFT, DOWN_RIGHT,
    }

    var dpadState: DpadState = DpadState.NONE

    var centreX: Int = 0
    var centreY: Int = 0
    var radius: Int = 0
    var currentPointerId: Int = -1

    override fun configure() {
        val rect = settings.rect
        this.centreX = rect.centerX()
        this.centreY = rect.centerY()
        this.radius = (min(rect.width(), rect.height()) / 2.0f).toInt()
        background.alpha = settings.alpha
        background.setBounds(
            centreX - radius,
            centreY - radius,
            centreX + radius,
            centreY + radius
        )

        val buttonSize = (radius * 0.5f).toInt()
        val configureButton =
            { circleXPos: Int, circleYPos: Int, pressedButton: Drawable, notPressedButton: Drawable ->
                pressedButton.alpha =
                    settings.alpha
                notPressedButton.alpha = settings.alpha
                val left = circleXPos - buttonSize / 2
                val top = circleYPos - buttonSize / 2
                pressedButton.setBounds(left, top, left + buttonSize, top + buttonSize)
                notPressedButton.setBounds(left, top, left + buttonSize, top + buttonSize)
            }
        configureButton(
            centreX,
            centreY - 2 * radius / 3,
            iconDpadUpPressed,
            iconDpadUp
        )
        configureButton(
            centreX,
            centreY + 2 * radius / 3,
            iconDpadDownPressed,
            iconDpadDownNotPressed
        )
        configureButton(
            centreX - 2 * radius / 3,
            centreY,
            iconDpadLeftPressed,
            iconDpadLeftNotPressed
        )
        configureButton(
            centreX + 2 * radius / 3,
            centreY,
            iconDpadRightPressed,
            iconDpadRightNotPressed
        )
    }

    init {
        val getNotPressedButtonIcon = {
            ResourcesCompat.getDrawable(resources, buttonId, null)!!
        }
        val getPressedButtonIcon = {
            ResourcesCompat.getDrawable(resources, buttonId, null)!!
                .applyInvertedColorTransform()
        }

        iconDpadUpPressed = getPressedButtonIcon()
        iconDpadUpNotPressed = getNotPressedButtonIcon()
        iconDpadUp = iconDpadUpNotPressed

        iconDpadDownPressed = getPressedButtonIcon()
        iconDpadDownNotPressed = getNotPressedButtonIcon()
        iconDpadDown = iconDpadDownNotPressed

        iconDpadLeftPressed = getPressedButtonIcon()
        iconDpadLeftNotPressed = getNotPressedButtonIcon()
        iconDpadLeft = iconDpadLeftNotPressed

        iconDpadRightPressed = getPressedButtonIcon()
        iconDpadRightNotPressed = getNotPressedButtonIcon()
        iconDpadRight = iconDpadRightNotPressed

        configure()
    }

    private fun updateState(nextDpadState: DpadState) {
        when (dpadState) {
            DpadState.NONE -> {}

            DpadState.UP -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_UP,
                    false
                )
                iconDpadUp = iconDpadUpNotPressed
            }

            DpadState.DOWN -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_DOWN,
                    false
                )
                iconDpadDown = iconDpadDownNotPressed
            }

            DpadState.LEFT -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_LEFT,
                    false
                )
                iconDpadLeft = iconDpadLeftNotPressed
            }

            DpadState.RIGHT -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_RIGHT,
                    false
                )
                iconDpadRight = iconDpadRightNotPressed
            }

            DpadState.UP_LEFT -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_UP,
                    false
                )
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_LEFT,
                    false
                )
                iconDpadUp = iconDpadUpNotPressed
                iconDpadLeft = iconDpadLeftNotPressed
            }

            DpadState.UP_RIGHT -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_UP,
                    false
                )
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_RIGHT,
                    false
                )
                iconDpadUp = iconDpadUpNotPressed
                iconDpadRight = iconDpadRightNotPressed
            }

            DpadState.DOWN_LEFT -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_DOWN,
                    false
                )
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_LEFT,
                    false
                )
                iconDpadDown = iconDpadDownNotPressed
                iconDpadLeft = iconDpadLeftNotPressed
            }

            DpadState.DOWN_RIGHT -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_DOWN,
                    false
                )
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_RIGHT,
                    false
                )
                iconDpadDown = iconDpadDownNotPressed
                iconDpadRight = iconDpadRightNotPressed
            }
        }
        dpadState = nextDpadState
        when (nextDpadState) {
            DpadState.NONE -> {}
            DpadState.UP -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_UP,
                    true
                )
                iconDpadUp = iconDpadUpPressed
            }

            DpadState.DOWN -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_DOWN,
                    true
                )
                iconDpadDown = iconDpadDownPressed
            }

            DpadState.LEFT -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_LEFT,
                    true
                )
                iconDpadLeft = iconDpadLeftPressed
            }

            DpadState.RIGHT -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_RIGHT,
                    true
                )
                iconDpadRight = iconDpadRightPressed
            }

            DpadState.UP_LEFT -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_UP,
                    true
                )
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_LEFT,
                    true
                )
                iconDpadUp = iconDpadUpPressed
                iconDpadLeft = iconDpadLeftPressed
            }

            DpadState.UP_RIGHT -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_UP,
                    true
                )
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_RIGHT,
                    true
                )
                iconDpadUp = iconDpadUpPressed
                iconDpadRight = iconDpadRightPressed
            }

            DpadState.DOWN_LEFT -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_DOWN,
                    true
                )
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_LEFT,
                    true
                )
                iconDpadDown = iconDpadDownPressed
                iconDpadLeft = iconDpadLeftPressed
            }

            DpadState.DOWN_RIGHT -> {
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_DOWN,
                    true
                )
                buttonStateChangeListener.onButtonStateChange(
                    InputOverlaySurfaceView.OverlayButton.DPAD_RIGHT,
                    true
                )
                iconDpadDown = iconDpadDownPressed
                iconDpadRight = iconDpadRightPressed
            }
        }
    }

    override fun onTouch(event: MotionEvent): Boolean {
        var nextState = dpadState
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val pointerIndex = event.actionIndex
                val x = event.getX(pointerIndex).toInt()
                val y = event.getY(pointerIndex).toInt()
                val pointerId = event.getPointerId(pointerIndex)
                if (isInside(x, y)) {
                    currentPointerId = pointerId
                    val angle = atan2((y - centreY).toDouble(), (x - centreX).toDouble())
                    nextState = getStateByAngle(angle)
                }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val pointerId = event.getPointerId(event.actionIndex)
                if (pointerId == currentPointerId) {
                    currentPointerId = -1
                    nextState = DpadState.NONE
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
                    val norm2 = ((x - centreX) * (x - centreX) + (y - centreY) * (y - centreY))
                    if (norm2 <= radius * radius * 0.1f) {
                        nextState = DpadState.NONE
                        break
                    }
                    val angle = atan2((y - centreY).toDouble(), (x - centreX).toDouble())
                    nextState = getStateByAngle(angle)
                    break
                }
            }
        }
        if (nextState != dpadState) {
            updateState(nextState)
            return true
        }
        return false
    }

    override fun resetInput() {
        updateState(DpadState.NONE)
    }

    private fun getStateByAngle(angle: Double): DpadState {
        if (-0.125 * Math.PI <= angle && angle < 0.125 * Math.PI) {
            return DpadState.RIGHT
        }
        if (0.125 * Math.PI <= angle && angle < 0.375 * Math.PI) {
            return DpadState.DOWN_RIGHT
        }
        if (0.375 * Math.PI <= angle && angle < 0.625 * Math.PI) {
            return DpadState.DOWN
        }
        if (0.625 * Math.PI <= angle && angle < 0.875 * Math.PI) {
            return DpadState.DOWN_LEFT
        }
        if (-0.875 * Math.PI <= angle && angle < -0.625 * Math.PI) {
            return DpadState.UP_LEFT
        }
        if (-0.625 * Math.PI <= angle && angle < -0.375 * Math.PI) {
            return DpadState.UP
        }
        if (-0.375 * Math.PI <= angle && angle < -0.125 * Math.PI) {
            return DpadState.UP_RIGHT
        }
        return DpadState.LEFT
    }

    override fun isInside(x: Int, y: Int): Boolean {
        return ((x - centreX) * (x - centreX) + (y - centreY) * (y - centreY)) <= radius * radius
    }

    override fun drawInput(canvas: Canvas) {
        background.draw(canvas)
        iconDpadUp.draw(canvas)
        iconDpadDown.draw(canvas)
        iconDpadLeft.draw(canvas)
        iconDpadRight.draw(canvas)
    }
}
