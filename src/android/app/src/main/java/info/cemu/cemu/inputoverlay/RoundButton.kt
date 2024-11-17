package info.cemu.cemu.inputoverlay

import android.content.res.Resources
import android.graphics.Rect
import androidx.annotation.DrawableRes
import info.cemu.cemu.inputoverlay.InputOverlaySettingsProvider.InputOverlaySettings
import info.cemu.cemu.inputoverlay.InputOverlaySurfaceView.OverlayButton
import kotlin.math.min

class RoundButton internal constructor(
    resources: Resources,
    @DrawableRes buttonId: Int,
    buttonStateChangeListener: ButtonStateChangeListener,
    overlayButton: OverlayButton,
    settings: InputOverlaySettings
) :
    Button(resources, buttonId, buttonStateChangeListener, overlayButton, settings) {
    var centreX: Int = 0
    var centreY: Int = 0
    var radius: Int = 0

    init {
        configure()
    }

    override fun configure() {
        val rect = settings.rect
        centreX = rect.centerX()
        centreY = rect.centerY()
        radius = (min(rect.width().toDouble(), rect.height().toDouble()) / 2).toInt()
        val iconRect = Rect(
            centreX - radius,
            centreY - radius,
            centreX + radius,
            centreY + radius
        )
        iconPressed.bounds = iconRect
        iconNotPressed.bounds = iconRect
    }

    override fun isInside(x: Int, y: Int): Boolean {
        return ((x - centreX) * (x - centreX) + (y - centreY) * (y - centreY)) <= radius * radius
    }
}
