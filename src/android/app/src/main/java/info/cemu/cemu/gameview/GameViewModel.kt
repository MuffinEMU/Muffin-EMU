package info.cemu.cemu.gameview

import androidx.lifecycle.ViewModel
import info.cemu.cemu.nativeinterface.NativeGameTitles.Game

class GameViewModel : ViewModel() {
    @JvmField
    var game: Game? = null
}
