package info.cemu.cemu.gamelist

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import info.cemu.cemu.nativeinterface.NativeGameTitles
import info.cemu.cemu.nativeinterface.NativeGameTitles.Game
import info.cemu.cemu.nativeinterface.NativeSettings
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

class GameListViewModel : ViewModel() {
    private var gamePaths = NativeSettings.getGamesPaths().toSet()
    private val _filterText = MutableStateFlow("")
    private val filterText = _filterText.asStateFlow()
    fun setFilterText(filterText: String) {
        _filterText.value = filterText
    }

    private val _games = MutableStateFlow<Set<Game>>(emptySet())
    val games: StateFlow<List<Game>> = filterText.combine(_games) { filter, games ->
        if (filter.isBlank()) {
            games
        } else {
            games.filter { it.name?.contains(filter, true) ?: false }
        }
    }.map {
        it.sorted()
    }.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5000),
        emptyList()
    )

    init {
        NativeGameTitles.setGameTitleLoadedCallback(NativeGameTitles.GameTitleLoadedCallback { game: Game? ->
            if (game == null || !isGameValid(game))
                return@GameTitleLoadedCallback
            if (_games.value.any { it.titleId == game.titleId })
                return@GameTitleLoadedCallback
            _games.value += game
        })
        refreshGames()
    }

    private val _gameToRemoveShaders = MutableStateFlow<Game?>(null)
    val gameToRemoveShaders = _gameToRemoveShaders.asStateFlow()
    fun removeShadersForSelectedGame() {
        if (_gameToRemoveShaders.value == null) return
        NativeGameTitles.removeShaderCacheFilesForTitle(_gameToRemoveShaders.value!!.titleId)
        _gameToRemoveShaders.value = null
    }

    fun setGameForShadersRemoval(game: Game) {
        _gameToRemoveShaders.value = game
    }

    fun clearSelectedGameForShaderRemoval() {
        _gameToRemoveShaders.value = null
    }

    private fun isGameValid(game: Game): Boolean {
        return !game.path.isNullOrEmpty() && !game.name.isNullOrEmpty()
    }

    fun setGameTitleFavorite(game: Game, isFavorite: Boolean) {
        if (!_games.value.contains(game)) {
            return
        }
        NativeGameTitles.setGameTitleFavorite(game.titleId, isFavorite)
        _games.value = _games.value.toMutableSet().apply {
            remove(game)
            add(game.copy(isFavorite = isFavorite))
        }
    }

    override fun onCleared() {
        NativeGameTitles.setGameTitleLoadedCallback(null)
    }

    fun checkIfGamePathsHaveChanged(): Boolean {
        val newGamePaths = NativeSettings.getGamesPaths().toSet()
        if (newGamePaths != gamePaths) {
            gamePaths = newGamePaths
            return true
        }
        return false
    }

    fun refreshGames() {
        _games.value = emptySet()
        NativeGameTitles.reloadGameTitles()
    }
}
