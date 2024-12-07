package info.cemu.cemu.inputoverlay

import android.content.res.Resources
import android.graphics.Canvas
import android.graphics.Rect
import android.graphics.drawable.Drawable
import android.view.MotionEvent
import androidx.annotation.DrawableRes
import androidx.core.content.res.ResourcesCompat
import kotlin.math.min
import kotlin.math.sqrt

class Joystick(
    resources: Resources,
    @DrawableRes joystickBackgroundId: Int,
    @DrawableRes innerStickId: Int,
    private val onStickStateChange: (x: Float, y: Float) -> Unit,
    private val alpha: Int,
    boundingRectangle: Rect,
) : Input(boundingRectangle) {
    private val joystickBackground: Drawable =
        ResourcesCompat.getDrawable(resources, joystickBackgroundId, null)!!
    private val joystickDrawable = InputDrawable(resources, innerStickId)
    private var currentPointerId = -1
    private var centerX = 0
    private var centerY = 0
    private var originalCenterX = 0
    private var originalCenterY = 0
    private var radius = 0
    private var innerRadius = 0

    init {
        configure()
    }

    private fun updateState(pressed: Boolean, x: Float, y: Float) {
        joystickDrawable.setActiveState(pressed)
        onStickStateChange(x, y)
        val newCentreX = (centerX + radius * x).toInt()
        val newCentreY = (centerY + radius * y).toInt()
        joystickDrawable.setBounds(
            newCentreX - innerRadius,
            newCentreY - innerRadius,
            newCentreX + innerRadius,
            newCentreY + innerRadius
        )
    }

    override fun configure() {
        centerX = rect.centerX()
        originalCenterX = centerX
        centerY = rect.centerY()
        originalCenterY = centerY
        radius = min(rect.width(), rect.height()) / 2
        innerRadius = (radius * 0.65f).toInt()
        joystickBackground.setBounds(
            centerX - radius,
            centerY - radius,
            centerX + radius,
            centerY + radius
        )
        joystickBackground.alpha = alpha
        joystickDrawable.setAlpha(alpha)
        joystickDrawable.setBounds(
            centerX - innerRadius,
            centerY - innerRadius,
            centerX + innerRadius,
            centerY + innerRadius
        )
    }

    override fun onTouch(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val pointerIndex = event.actionIndex
                val x = event.getX(pointerIndex).toInt()
                val y = event.getY(pointerIndex).toInt()
                if (isInside(x, y)) {
                    centerX = x
                    centerY = y
                    joystickBackground.setBounds(
                        centerX - radius,
                        centerY - radius,
                        centerX + radius,
                        centerY + radius
                    )
                    currentPointerId = event.getPointerId(pointerIndex)
                    updateState(true, 0.0f, 0.0f)
                    return true
                }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                if (currentPointerId == event.getPointerId(event.actionIndex)) {
                    centerX = originalCenterX
                    centerY = originalCenterY
                    joystickBackground.setBounds(
                        centerX - radius,
                        centerY - radius,
                        centerX + radius,
                        centerY + radius
                    )
                    currentPointerId = -1
                    updateState(false, 0.0f, 0.0f)
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
                    var x: Float = (event.getX(i) - centerX) / radius
                    var y: Float = (event.getY(i) - centerY) / radius
                    val norm = sqrt(x * x + y * y)
                    if (norm > 1.0f) {
                        x /= norm
                        y /= norm
                    }
                    updateState(true, x, y)
                    return true
                }
            }
        }
        return false
    }

    override fun resetInput() {
        updateState(false, 0f, 0f)
    }

    override fun drawInput(canvas: Canvas) {
        joystickBackground.draw(canvas)
        joystickDrawable.icon.draw(canvas)
    }

    override fun isInside(x: Int, y: Int): Boolean {
        return ((x - originalCenterX) * (x - originalCenterX) + (y - originalCenterY) * (y - originalCenterY)) <= radius * radius
    }
}
