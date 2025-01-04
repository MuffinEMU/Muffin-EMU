package info.cemu.cemu.titlemanager

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import info.cemu.cemu.guicore.ActivityContent


class TitleManagerActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            ActivityContent {
                TitleManagerScreen(::onNavigateUp)
            }
        }
    }
}