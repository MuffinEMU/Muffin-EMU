package info.cemu.cemu.guicore

import android.content.Context
import android.util.AttributeSet
import android.view.View
import androidx.drawerlayout.widget.DrawerLayout as AndroidxDrawerLayout

class DrawerLayout @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null,
) : AndroidxDrawerLayout(context, attrs) {
    init {
        setDrawerLockMode(LOCK_MODE_LOCKED_CLOSED)
        addDrawerListener(object : DrawerListener {
            override fun onDrawerSlide(drawerView: View, slideOffset: Float) {}

            override fun onDrawerOpened(drawerView: View) {
                setDrawerLockMode(LOCK_MODE_UNLOCKED)
            }

            override fun onDrawerClosed(drawerView: View) {
                setDrawerLockMode(LOCK_MODE_LOCKED_CLOSED)
            }

            override fun onDrawerStateChanged(newState: Int) {}
        })
    }

}