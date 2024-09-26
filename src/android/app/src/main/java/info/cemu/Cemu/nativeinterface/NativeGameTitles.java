package info.cemu.Cemu.nativeinterface;

import java.util.ArrayList;

public class NativeGameTitles {
    public interface GameTitleLoadedCallback {
        void onGameTitleLoaded(String path, String title, int[] colors, int width, int height);
    }

    public static native void setGameTitleLoadedCallback(GameTitleLoadedCallback gameTitleLoadedCallback);

    public static native void reloadGameTitles();

    public static native ArrayList<Long> getInstalledGamesTitleIds();

}
