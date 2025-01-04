package info.cemu.cemu.inputoverlay

import android.content.res.Resources
import android.graphics.Rect
import android.graphics.drawable.Drawable
import androidx.annotation.DrawableRes
import androidx.core.content.res.ResourcesCompat
import info.cemu.cemu.utils.getInvertedDrawable

class InputDrawable(
    resources: Resources,
    @DrawableRes inputDrawableId: Int,
) {
    private val iconInactive: Drawable = ResourcesCompat.getDrawable(
        resources,
        inputDrawableId,
        null
    )!!
    private val iconActive: Drawable = iconInactive.getInvertedDrawable(resources)
    private var _icon = iconInactive
    val icon: Drawable
        get() = _icon

    fun setActiveState(active: Boolean) {
        _icon = if (active) iconActive else iconInactive
    }

    fun setAlpha(alpha: Int) {
        iconActive.alpha = alpha
        iconInactive.alpha = alpha
    }

    fun setBounds(bounds: Rect) {
        iconActive.bounds = bounds
        iconInactive.bounds = bounds
    }

    fun setBounds(left: Int, top: Int, right: Int, bottom: Int) {
        setBounds(Rect(left, top, right, bottom))
    }
}