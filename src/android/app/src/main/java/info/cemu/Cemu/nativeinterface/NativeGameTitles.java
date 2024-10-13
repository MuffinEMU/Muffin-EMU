package info.cemu.Cemu.nativeinterface;

import android.graphics.Bitmap;

import java.util.ArrayList;

public class NativeGameTitles {
    public static final int CONSOLE_REGION_JPN = 0x1;
    public static final int CONSOLE_REGION_USA = 0x2;
    public static final int CONSOLE_REGION_EUR = 0x4;
    public static final int CONSOLE_REGION_AUS_DEPR = 0x8;
    public static final int CONSOLE_REGION_CHN = 0x10;
    public static final int CONSOLE_REGION_KOR = 0x20;
    public static final int CONSOLE_REGION_TWN = 0x40;
    public static final int CONSOLE_REGION_AUTO = 0xFF;

    public record Game(
            long titleId,
            String path,
            String name,
            short version,
            short dlc,
            int region,
            short lastPlayedYear,
            short lastPlayedMonth,
            short lastPlayedDay,
            int minutesPlayed,
            boolean isFavorite,
            Bitmap icon
    ) implements Comparable<Game> {
        @Override
        public int compareTo(Game other) {
            if (titleId == other.titleId) {
                return 0;
            }
            if (isFavorite && !other.isFavorite) {
                return -1;
            }
            if (!isFavorite && other.isFavorite) {
                return 1;
            }
            if (name.equals(other.name)) {
                return Long.compare(titleId, other.titleId);
            }
            return name.compareTo(other.name);
        }
    }

    public interface GameTitleLoadedCallback {
        void onGameTitleLoaded(Game game);
    }

    public static native boolean isLoadingSharedLibrariesForTitleEnabled(long gameTitleId);

    public static native void setLoadingSharedLibrariesForTitleEnabled(long gameTitleId, boolean enabled);

    public final static int CPU_MODE_SINGLECOREINTERPRETER = 0;
    public final static int CPU_MODE_SINGLECORERECOMPILER = 1;
    public final static int CPU_MODE_MULTICORERECOMPILER = 3;
    public final static int CPU_MODE_AUTO = 4;

    public static native int getCpuModeForTitle(long gameTitleId);

    public static native void setCpuModeForTitle(long gameTitleId, int cpuMode);

    public static final int[] THREAD_QUANTUM_VALUES = new int[]{
            20000,
            45000,
            60000,
            80000,
            100000,
    };

    public static native int getThreadQuantumForTitle(long gameTitleId);

    public static native void setThreadQuantumForTitle(long gameTitleId, int threadQuantum);

    public static native boolean isShaderMultiplicationAccuracyForTitleEnabled(long gameTitleId);

    public static native void setShaderMultiplicationAccuracyForTitleEnabled(long gameTitleId, boolean enabled);

    public static native boolean titleHasShaderCacheFiles(long gameTitleId);

    public static native void removeShaderCacheFilesForTitle(long gameTitleId);

    public static native void setGameTitleFavorite(long gameTitleId, boolean isFavorite);

    public static native void setGameTitleLoadedCallback(GameTitleLoadedCallback gameTitleLoadedCallback);

    public static native void reloadGameTitles();

    public static native ArrayList<Long> getInstalledGamesTitleIds();

}
