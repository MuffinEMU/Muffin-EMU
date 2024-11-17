package info.cemu.cemu.drawable

import android.content.res.Resources
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.drawable.Drawable

private val INVERTED_COLOR_MATRIX = ColorMatrix(
    floatArrayOf(
        -1f, 0f, 0f, 0f, 255f,
        0f, -1f, 0f, 0f, 255f,
        0f, 0f, -1f, 0f, 255f,
        0f, 0f, 0f, 1f, 0f
    )
)

fun Drawable.getInvertedDrawable(resources: Resources?): Drawable {
    val newDrawable = this.constantState!!.newDrawable(resources)
    return newDrawable.applyInvertedColorTransform()
}

fun Drawable.applyInvertedColorTransform(): Drawable {
    this.mutate().colorFilter = ColorMatrixColorFilter(INVERTED_COLOR_MATRIX)
    return this
}
