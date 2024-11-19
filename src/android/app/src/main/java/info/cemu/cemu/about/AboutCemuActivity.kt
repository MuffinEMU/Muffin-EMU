package info.cemu.cemu.about

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import info.cemu.cemu.guicore.ActivityContent


class AboutCemuActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            ActivityContent {
                AboutCemuScreen(::onNavigateUp)
            }
        }
    }
}