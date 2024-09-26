package info.cemu.Cemu.gameview;

import android.graphics.Bitmap;

import androidx.lifecycle.LiveData;
import androidx.lifecycle.MutableLiveData;
import androidx.lifecycle.ViewModel;

import java.util.ArrayList;
import java.util.List;

import info.cemu.Cemu.nativeinterface.NativeGameTitles;

public class GameViewModel extends ViewModel {
    private final MutableLiveData<List<Game>> gamesData;

    private final ArrayList<Game> games = new ArrayList<>();

    public LiveData<List<Game>> getGames() {
        return gamesData;
    }

    public GameViewModel() {
        this.gamesData = new MutableLiveData<>();
        NativeGameTitles.setGameTitleLoadedCallback((path, title, colors, width, height) -> {
            Bitmap icon = null;
            if (colors != null)
                icon = Bitmap.createBitmap(colors, width, height, Bitmap.Config.ARGB_8888);
            Game game = new Game(path, title, icon);
            synchronized (GameViewModel.this) {
                games.add(game);
                gamesData.postValue(new ArrayList<>(games));
            }
        });
    }

    @Override
    protected void onCleared() {
        NativeGameTitles.setGameTitleLoadedCallback(null);
    }

    public void refreshGames() {
        games.clear();
        gamesData.setValue(null);
        NativeGameTitles.reloadGameTitles();
    }
}
