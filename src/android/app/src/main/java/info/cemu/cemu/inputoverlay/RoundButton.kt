package info.cemu.cemu.inputoverlay

import android.content.res.Resources
import android.graphics.Rect
import androidx.annotation.DrawableRes
import kotlin.math.min

class RoundButton internal constructor(
    resources: Resources,
    @DrawableRes buttonId: Int,
    onButtonStateChange: (state: Boolean) -> Unit,
    private val alpha: Int,
    rect: Rect,
) : Button(resources, buttonId, onButtonStateChange, rect) {
    private var centreX: Int = 0
    private var centreY: Int = 0
    private var radius2: Int = 0

    init {
        configure()
    }

    override fun configure() {
        centreX = rect.centerX()
        centreY = rect.centerY()
        val radius = min(rect.width(), rect.height()) / 2
        inputDrawable.setBounds(
            centreX - radius,
            centreY - radius,
            centreX + radius,
            centreY + radius
        )
        inputDrawable.setAlpha(alpha)
        radius2 = radius * radius
    }

    override fun isInside(x: Int, y: Int): Boolean {
        return ((x - centreX) * (x - centreX) + (y - centreY) * (y - centreY)) <= radius2
    }
}
