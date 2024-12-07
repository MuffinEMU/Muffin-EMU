package info.cemu.cemu.inputoverlay

import android.content.res.Resources
import android.graphics.Rect
import androidx.annotation.DrawableRes

class RectangleButton(
    resources: Resources,
    @DrawableRes buttonId: Int,
    onButtonStateChange: (state: Boolean) -> Unit,
    private val alpha: Int,
    rect: Rect,
) : Button(resources, buttonId, onButtonStateChange, rect) {
    var left: Int = 0
    var top: Int = 0
    var right: Int = 0
    var bottom: Int = 0

    init {
        configure()
    }

    override fun configure() {
        this.left = rect.left
        this.top = rect.top
        this.right = rect.right
        this.bottom = rect.bottom
        inputDrawable.setAlpha(alpha)
        inputDrawable.setBounds(left, top, right, bottom)
    }

    override fun isInside(x: Int, y: Int): Boolean {
        return x in left..<right && y in top..<bottom
    }
}
