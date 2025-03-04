package info.cemu.cemu.inputoverlay.inputs.innerdrawing

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import kotlin.math.min

class HomeButtonInnerDrawing : ButtonInnerDrawing {
    private var activeFillColor = 0
    private var inactiveFillColor = 0
    private val paint = Paint()
    private var path = Path()
    override fun draw(canvas: Canvas, state: Boolean) {
        paint.color = if (state) activeFillColor else inactiveFillColor
        canvas.drawPath(path, paint)
    }

    override fun configure(boundingRect: Rect, alpha: Int) {
        activeFillColor = Color.argb(alpha, 0, 0, 0)
        inactiveFillColor = Color.argb(alpha, 255, 255, 255)

        path = Path()
        val firstPoint = IconPathPoints[0]
        path.moveTo(firstPoint.first, firstPoint.second)
        for (i in 1..<IconPathPoints.size) {
            val point = IconPathPoints[i]
            path.lineTo(point.first, point.second)
        }
        val transformMatrix = Matrix()
        val rectSize = min(boundingRect.width(), boundingRect.height()).toFloat()
        val scale = rectSize / CANVAS_SIZE
        transformMatrix.setScale(scale, scale)
        transformMatrix.postTranslate(
            boundingRect.exactCenterX() - rectSize * 0.5f,
            boundingRect.exactCenterY() - rectSize * 0.5f
        )
        path.transform(transformMatrix)
    }

    companion object {
        const val CANVAS_SIZE = 24f
        val IconPathPoints = listOf(
            6.735f to 19f,
            6.735f to 11.85f,
            4.675f to 11.85f,
            12.175f to 5.15f,
            19.675f to 11.85f,
            17.615f to 11.85f,
            17.615f to 19f,
        )
    }
}