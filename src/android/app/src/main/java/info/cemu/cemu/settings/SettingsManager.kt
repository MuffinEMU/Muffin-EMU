package info.cemu.cemu.settings

import android.content.Context
import android.content.SharedPreferences

class SettingsManager(context: Context) {
    private val sharedPreferences: SharedPreferences

    init {
        sharedPreferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    }

    companion object {
        const val PREFERENCES_NAME: String = "CEMU_PREFERENCES"
    }
}
