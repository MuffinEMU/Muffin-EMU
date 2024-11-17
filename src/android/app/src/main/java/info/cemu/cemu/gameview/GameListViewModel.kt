package info.cemu.cemu.gameview

import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import info.cemu.cemu.nativeinterface.NativeGameTitles.Game
import info.cemu.cemu.nativeinterface.NativeGameTitles.GameTitleLoadedCallback
import info.cemu.cemu.nativeinterface.NativeGameTitles.reloadGameTitles
import info.cemu.cemu.nativeinterface.NativeGameTitles.setGameTitleFavorite
import info.cemu.cemu.nativeinterface.NativeGameTitles.setGameTitleLoadedCallback
import java.util.TreeSet

class GameListViewModel : ViewModel() {
    private val gamesData =
        MutableLiveData<List<Game>?>()

    private val games = TreeSet<Game>()

    fun getGames(): LiveData<List<Game>?> {
        return gamesData
    }

    init {
        setGameTitleLoadedCallback(GameTitleLoadedCallback { game: Game? ->
            if (game == null || !isGameValid(game)) {
                return@GameTitleLoadedCallback
            }
            synchronized(this@GameListViewModel) {
                games.add(game)
                gamesData.postValue(ArrayList(games))
            }
        })
    }

    private fun isGameValid(game: Game): Boolean {
        return game.path != null && game.name != null
    }

    fun setGameTitleFavorite(game: Game, isFavorite: Boolean) {
        synchronized(this) {
            if (!games.contains(game)) {
                return
            }
            setGameTitleFavorite(game.titleId, isFavorite)
            games.remove(game)
            games.add(game.copy(isFavorite = isFavorite))
            gamesData.postValue(ArrayList(games))
        }
    }

    override fun onCleared() {
        setGameTitleLoadedCallback(null)
    }

    fun refreshGames() {
        games.clear()
        gamesData.value = null
        reloadGameTitles()
    }
}
