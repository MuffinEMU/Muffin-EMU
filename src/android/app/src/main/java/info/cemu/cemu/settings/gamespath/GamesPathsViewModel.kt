package info.cemu.cemu.settings.gamespath

import androidx.compose.runtime.mutableStateListOf
import androidx.lifecycle.ViewModel
import info.cemu.cemu.nativeinterface.NativeSettings



class GamesPathsViewModel : ViewModel() {
    private val _gamesPaths = mutableStateListOf<String>().apply {
        addAll(NativeSettings.getGamesPaths())
    }
    val gamesPaths: List<String>
        get() = _gamesPaths

    fun addGamesPath(gamesPath: String) {
        if (!_gamesPaths.contains(gamesPath)) {
            _gamesPaths.add(gamesPath)
            NativeSettings.addGamesPath(gamesPath)
        }
    }

    fun removeGamesPath(gamesPath: String) {
        if (_gamesPaths.remove(gamesPath)) {
            NativeSettings.removeGamesPath(gamesPath)
        }
    }
}