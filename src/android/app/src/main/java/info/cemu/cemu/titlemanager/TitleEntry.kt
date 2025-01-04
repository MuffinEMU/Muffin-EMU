package info.cemu.cemu.titlemanager

import info.cemu.cemu.nativeinterface.NativeGameTitles

data class TitleEntry(
    val titleId: Long,
    val name: String,
    val path: String,
    val isInMLC: Boolean,
    val locationUID: Long,
    val version: Short,
    val region: Int,
    val type: EntryType,
    val format: EntryFormat,
) {
    init {
        if (type == EntryType.Save || format == EntryFormat.SaveFolder) {
            require(type == EntryType.Save && format == EntryFormat.SaveFolder)
        }
    }
}

enum class EntryType {
    Base,
    Update,
    Dlc,
    Save,
    System,
}

fun nativeTitleTypeToEnum(titleType: Int) = when (titleType) {
    NativeGameTitles.TITLE_TYPE_BASE_TITLE_UPDATE -> EntryType.Update
    NativeGameTitles.TITLE_TYPE_AOC -> EntryType.Dlc
    NativeGameTitles.TITLE_TYPE_SYSTEM_OVERLAY_TITLE, NativeGameTitles.TITLE_TYPE_SYSTEM_DATA, NativeGameTitles.TITLE_TYPE_SYSTEM_TITLE -> EntryType.System
    else -> EntryType.Base
}

enum class EntryFormat {
    SaveFolder,
    Folder,
    WUD,
    NUS,
    WUA,
    WUHB,
}

fun nativeTitleFormatToEnum(titleFormat: Int) = when (titleFormat) {
    NativeGameTitles.TITLE_DATA_FORMAT_WUD -> EntryFormat.WUD
    NativeGameTitles.TITLE_DATA_FORMAT_WIIU_ARCHIVE -> EntryFormat.WUA
    NativeGameTitles.TITLE_DATA_FORMAT_NUS -> EntryFormat.NUS
    NativeGameTitles.TITLE_DATA_FORMAT_WUHB -> EntryFormat.WUHB
    else -> EntryFormat.Folder
}
