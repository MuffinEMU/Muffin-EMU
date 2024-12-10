package info.cemu.cemu.gamelist

import androidx.lifecycle.ViewModel
import info.cemu.cemu.nativeinterface.NativeGameTitles.Game
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

class GameViewModel : ViewModel() {
    private val _game = MutableStateFlow<Game?>(null)
    val game = _game.asStateFlow()

    fun setCurrentGame(game: Game?) {
        _game.value = game
    }
}
