package info.cemu.cemu.inputoverlay

import android.content.res.Resources
import androidx.annotation.DrawableRes
import info.cemu.cemu.inputoverlay.InputOverlaySettingsProvider.InputOverlaySettings
import info.cemu.cemu.inputoverlay.InputOverlaySurfaceView.OverlayButton

class RectangleButton(
    resources: Resources,
    @DrawableRes buttonId: Int,
    buttonStateChangeListener: ButtonStateChangeListener,
    overlayButton: OverlayButton,
    settings: InputOverlaySettings
) :
    Button(resources, buttonId, buttonStateChangeListener, overlayButton, settings) {
    var left: Int = 0
    var top: Int = 0
    var right: Int = 0
    var bottom: Int = 0

    init {
        configure()
    }

    override fun configure() {
        val rect = settings.rect
        this.left = rect.left
        this.top = rect.top
        this.right = rect.right
        this.bottom = rect.bottom
        iconPressed.setBounds(left, top, right, bottom)
        iconNotPressed.setBounds(left, top, right, bottom)
    }

    override fun isInside(x: Int, y: Int): Boolean {
        return x in left..<right && y in top..<bottom
    }
}
