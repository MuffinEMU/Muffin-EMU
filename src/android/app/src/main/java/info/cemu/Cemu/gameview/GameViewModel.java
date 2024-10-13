package info.cemu.Cemu.gameview;

import static info.cemu.Cemu.nativeinterface.NativeGameTitles.*;

import androidx.lifecycle.ViewModel;

public class GameViewModel extends ViewModel {
    private Game game = null;

    public Game getGame() {
        return game;
    }

    public void setGame(Game game) {
        this.game = game;
    }
}
