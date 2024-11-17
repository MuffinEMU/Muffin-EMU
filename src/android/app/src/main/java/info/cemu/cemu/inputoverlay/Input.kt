package info.cemu.cemu.inputoverlay

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.view.MotionEvent
import androidx.annotation.ColorInt
import info.cemu.cemu.inputoverlay.InputOverlaySettingsProvider.InputOverlaySettings
import kotlin.math.max
import kotlin.math.min

abstract class Input protected constructor(@JvmField protected val settings: InputOverlaySettings) {
    private var drawBoundingRectangle = false
    private var boundingRectangle: Rect
    private val boundingRectanglePaint = Paint()

    init {
        boundingRectangle = settings.rect
    }

    abstract fun onTouch(event: MotionEvent): Boolean

    fun moveInput(x: Int, y: Int, maxWidth: Int, maxHeight: Int) {
        val rect = settings.rect
        val width = rect.width()
        val height = rect.height()
        val left = min(
            max(x - width / 2.0f, 0.0f),
            (maxWidth - width).toFloat()
        ).toInt()
        val top = min(
            max(y - height / 2.0f, 0.0f),
            (maxHeight - height).toFloat()
        ).toInt()
        boundingRectangle = Rect(
            left,
            top,
            left + width,
            top + height
        )
        settings.rect = boundingRectangle
        configure()
    }

    fun resize(diffX: Int, diffY: Int, maxWidth: Int, maxHeight: Int, minWidthHeight: Int) {
        val rect = settings.rect
        val newRight = rect.right + diffX
        val newBottom = rect.bottom + diffY
        if (newRight - rect.left < minWidthHeight || newBottom - rect.top < minWidthHeight || newRight > maxWidth || newBottom > maxHeight) {
            return
        }
        boundingRectangle = Rect(
            rect.left,
            rect.top,
            newRight,
            newBottom
        )
        settings.rect = boundingRectangle
        configure()
    }

    protected abstract fun resetInput()

    fun reset() {
        drawBoundingRectangle = false
    }

    fun saveConfiguration() {
        settings.saveSettings()
    }

    protected abstract fun configure()

    protected abstract fun drawInput(canvas: Canvas)

    fun draw(canvas: Canvas) {
        if (drawBoundingRectangle) {
            canvas.drawRect(boundingRectangle, boundingRectanglePaint)
        }
        drawInput(canvas)
    }

    fun enableDrawingBoundingRect(@ColorInt color: Int) {
        drawBoundingRectangle = true
        boundingRectanglePaint.color = color
    }

    fun disableDrawingBoundingRect() {
        drawBoundingRectangle = false
    }

    abstract fun isInside(x: Int, y: Int): Boolean
}
