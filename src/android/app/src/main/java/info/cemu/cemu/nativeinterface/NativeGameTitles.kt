package info.cemu.cemu.nativeinterface

import android.graphics.Bitmap

object NativeGameTitles {
    const val CONSOLE_REGION_JPN: Int = 0x1
    const val CONSOLE_REGION_USA: Int = 0x2
    const val CONSOLE_REGION_EUR: Int = 0x4
    const val CONSOLE_REGION_AUS_DEPR: Int = 0x8
    const val CONSOLE_REGION_CHN: Int = 0x10
    const val CONSOLE_REGION_KOR: Int = 0x20
    const val CONSOLE_REGION_TWN: Int = 0x40
    const val CONSOLE_REGION_AUTO: Int = 0xFF

    @JvmStatic
    external fun isLoadingSharedLibrariesForTitleEnabled(gameTitleId: Long): Boolean

    @JvmStatic
    external fun setLoadingSharedLibrariesForTitleEnabled(gameTitleId: Long, enabled: Boolean)

    const val CPU_MODE_SINGLECOREINTERPRETER: Int = 0
    const val CPU_MODE_SINGLECORERECOMPILER: Int = 1
    const val CPU_MODE_MULTICORERECOMPILER: Int = 3
    const val CPU_MODE_AUTO: Int = 4

    @JvmStatic
    external fun getCpuModeForTitle(gameTitleId: Long): Int

    @JvmStatic
    external fun setCpuModeForTitle(gameTitleId: Long, cpuMode: Int)

    @JvmField
    val THREAD_QUANTUM_VALUES: IntArray = intArrayOf(
        20000,
        45000,
        60000,
        80000,
        100000,
    )

    @JvmStatic
    external fun getThreadQuantumForTitle(gameTitleId: Long): Int

    @JvmStatic
    external fun setThreadQuantumForTitle(gameTitleId: Long, threadQuantum: Int)

    @JvmStatic
    external fun isShaderMultiplicationAccuracyForTitleEnabled(gameTitleId: Long): Boolean

    @JvmStatic
    external fun setShaderMultiplicationAccuracyForTitleEnabled(gameTitleId: Long, enabled: Boolean)

    @JvmStatic
    external fun titleHasShaderCacheFiles(gameTitleId: Long): Boolean

    @JvmStatic
    external fun removeShaderCacheFilesForTitle(gameTitleId: Long)

    @JvmStatic
    external fun setGameTitleFavorite(gameTitleId: Long, isFavorite: Boolean)

    @JvmStatic
    external fun setGameTitleLoadedCallback(gameTitleLoadedCallback: GameTitleLoadedCallback?)

    @JvmStatic
    external fun reloadGameTitles()

    @JvmStatic
    val installedGamesTitleIds: ArrayList<Long?>?
        external get

    @JvmRecord
    data class Game(
        @JvmField val titleId: Long,
        @JvmField val path: String?,
        @JvmField val name: String?,
        @JvmField val version: Short,
        @JvmField val dlc: Short,
        @JvmField val region: Int,
        @JvmField val lastPlayedYear: Short,
        @JvmField val lastPlayedMonth: Short,
        @JvmField val lastPlayedDay: Short,
        @JvmField val minutesPlayed: Int,
        @JvmField val isFavorite: Boolean,
        @JvmField val icon: Bitmap?
    ) : Comparable<Game> {
        override fun compareTo(other: Game): Int {
            if (titleId == other.titleId) {
                return 0
            }
            if (isFavorite && !other.isFavorite) {
                return -1
            }
            if (!isFavorite && other.isFavorite) {
                return 1
            }
            if (name == other.name) {
                return titleId.compareTo(other.titleId)
            }
            return name?.compareTo(other.name ?: "") ?: 0
        }
    }

    fun interface GameTitleLoadedCallback {
        fun onGameTitleLoaded(game: Game?)
    }
}
