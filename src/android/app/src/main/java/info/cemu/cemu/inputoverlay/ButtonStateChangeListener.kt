package info.cemu.cemu.inputoverlay

import info.cemu.cemu.inputoverlay.InputOverlaySurfaceView.OverlayButton

fun interface ButtonStateChangeListener {
    fun onButtonStateChange(button: OverlayButton?, state: Boolean)
}
