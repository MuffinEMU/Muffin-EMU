@file:OptIn(
    ExperimentalMaterial3Api::class,
    ExperimentalLayoutApi::class
)

package info.cemu.cemu.titlemanager

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.StringRes
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.TextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.documentfile.provider.DocumentFile
import androidx.lifecycle.viewmodel.compose.viewModel
import info.cemu.cemu.R
import info.cemu.cemu.guicore.components.ScreenContentLazy
import info.cemu.cemu.guicore.format.formatBytes
import info.cemu.cemu.guicore.nativeenummapper.regionToStringId
import info.cemu.cemu.nativeinterface.NativeGameTitles
import kotlinx.coroutines.launch

@Composable
fun TitleManagerScreen(
    navigateBack: () -> Unit,
    titleListViewModel: TitleListViewModel = viewModel(),
) {
    val coroutineScope = rememberCoroutineScope()
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    var showFilterSheet by remember { mutableStateOf(false) }
    val titleEntries by titleListViewModel.titleEntries.collectAsState()
    val queuedTitleToInstallError by titleListViewModel.queuedTitleToInstallError.collectAsState()
    val queuedTitleToCompress by titleListViewModel.queuedTitleToCompress.collectAsState()
    val showTitleInstallProgress by titleListViewModel.titleInstallInProgress.collectAsState()
    val titleInstallProgress by titleListViewModel.titleInstallProgress.collectAsState()
    val compressTitleInProgress by titleListViewModel.compressInProgress.collectAsState()
    val currentCompressProgress by titleListViewModel.compressProgress.collectAsState()
    val titleToBeDeleted by titleListViewModel.titleToBeDeleted.collectAsState()

    fun showNotificationMessage(@StringRes stringId: Int) {
        coroutineScope.launch {
            snackbarHostState.currentSnackbarData?.dismiss()
            snackbarHostState.showSnackbar(context.getString(stringId))
        }
    }

    fun installQueuedTitle() {
        titleListViewModel.installQueuedTitle(
            context = context,
            titleInstallCallbacks = object : TitleInstallCallbacks {
                override fun onInstallFinished() {
                    showNotificationMessage(R.string.install_title_finished)
                }

                override fun onError() {
                    showNotificationMessage(R.string.install_title_error)
                }
            }
        )
    }

    val installTitleLauncher =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
            if (uri == null) return@rememberLauncherForActivityResult
            context.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            val documentFile =
                DocumentFile.fromTreeUri(context, uri) ?: return@rememberLauncherForActivityResult
            titleListViewModel.queueTitleToInstall(
                titlePath = documentFile.uri,
                onInvalidTitle = {
                    showNotificationMessage(R.string.install_title_invalid_title)
                })
        }

    val compressFileLauncher =
        rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("*/*")) { uri ->
            if (uri == null) return@rememberLauncherForActivityResult
            titleListViewModel.compressQueuedTitle(
                context = context,
                uri = uri,
                onFinished = {
                    showNotificationMessage(R.string.wua_convert_finished)
                },
                onError = {
                    showNotificationMessage(R.string.wua_convert_error)
                }
            )
        }

    ScreenContentLazy(
        snackbarHost = { SnackbarHost(hostState = snackbarHostState) },
        appBarText = stringResource(R.string.title_manager_screen_label),
        navigateBack = navigateBack,
        actions = {
            IconButton(onClick = {
                titleListViewModel.refresh()
                showNotificationMessage(R.string.titles_refreshing_notification)
            }) {
                Icon(
                    imageVector = Icons.Filled.Refresh,
                    contentDescription = stringResource(R.string.title_manager_refresh_titles_description),
                )
            }
            IconButton(onClick = { showFilterSheet = true }) {
                Icon(
                    painter = painterResource(R.drawable.ic_filter),
                    contentDescription = stringResource(R.string.title_manager_filter_titles_description),
                )
            }
            IconButton(onClick = { installTitleLauncher.launch(null) }) {
                Icon(
                    painter = painterResource(R.drawable.ic_add),
                    contentDescription = stringResource(R.string.title_manager_install_title_description)
                )
            }
        }
    ) {
        items(items = titleEntries, key = { it.locationUID }) {
            TitleEntryListItem(
                titleEntry = it,
                onDeleteRequest = {
                    titleListViewModel.deleteTitleEntry(
                        titleEntry = it,
                        context = context,
                        deleteCallbacks = object : TitleDeleteCallbacks {
                            override fun onDeleteFinished() {
                                showNotificationMessage(R.string.title_entry_delete_notification)
                            }

                            override fun onError() {
                                showNotificationMessage(R.string.title_entry_failed_delete_notification)
                            }
                        })
                },
                onCompressRequested = {
                    titleListViewModel.queueTitleForCompression(it)
                }
            )
        }
    }
    if (showFilterSheet)
        TitleFilterBottomSheet(
            onDismissRequest = { showFilterSheet = false },
            titleListViewModel = titleListViewModel
        )

    queuedTitleToInstallError?.let { titleToInstallError ->
        TitleInstallConfirmDialog(
            error = titleToInstallError,
            onDismissRequest = { titleListViewModel.removedQueuedTitleToInstall() },
            onConfirm = { installQueuedTitle() }
        )
    }

    if (showTitleInstallProgress)
        TitleInstallProgressDialog(
            progress = titleInstallProgress,
            onCancel = {
                titleListViewModel.cancelInstall()
            }
        )

    queuedTitleToCompress?.let { titleToCompressInfo ->
        TitleCompressConfirmationDialog(
            onDismiss = { titleListViewModel.removeQueuedTitleForCompression() },
            onConfirm = {
                val fileName = titleListViewModel.getCompressedFileNameForQueuedTitle()
                    ?: return@TitleCompressConfirmationDialog
                compressFileLauncher.launch(fileName)
            },
            compressTitleInfo = titleToCompressInfo,
        )
    }

    if (compressTitleInProgress)
        TitleCompressProgressDialog(
            bytesWritten = currentCompressProgress,
            onCancel = titleListViewModel::cancelCompression,
        )

    titleToBeDeleted?.let { titleEntry ->
        DeleteTitleProgressDialog(titleEntry)
    }
}

@Composable
private fun TitleCompressProgressDialog(bytesWritten: Long?, onCancel: () -> Unit) {
    var showCancelConfirmDialog by remember { mutableStateOf(false) }

    AlertDialog(
        title = { Text(stringResource(R.string.wua_convert_title)) },
        text = {
            Column(
                modifier = Modifier.padding(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                LinearProgressIndicator()
                if (bytesWritten != null)
                    Text(
                        stringResource(
                            R.string.wua_convert_current_progress,
                            bytesWritten.formatBytes()
                        )
                    )
            }
        },
        onDismissRequest = {},
        confirmButton = {},
        dismissButton = {
            TextButton(
                onClick = { showCancelConfirmDialog = true },
                content = { Text(stringResource(R.string.cancel)) },
            )
        }
    )

    if (showCancelConfirmDialog)
        AlertDialog(
            title = { Text(stringResource(R.string.wua_convert_cancel_title)) },
            text = { Text(stringResource(R.string.wua_convert_cancel_text)) },
            onDismissRequest = { showCancelConfirmDialog = false },
            confirmButton = {
                TextButton(onClick = onCancel) {
                    Text(stringResource(R.string.yes))
                }
            },
            dismissButton = {
                TextButton(onClick = { showCancelConfirmDialog = false }) {
                    Text(stringResource(R.string.no))
                }
            }
        )
}

@Composable
private fun TitleCompressConfirmationDialog(
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
    compressTitleInfo: NativeGameTitles.CompressTitleInfo,
) {
    @Composable
    fun EntryInfo(entryName: String, entryPrintPath: String?) {
        Text(
            modifier = Modifier.padding(top = 4.dp, bottom = 2.dp),
            fontSize = 16.sp,
            fontWeight = FontWeight.Medium,
            text = entryName,
        )
        Text(
            modifier = Modifier.padding(bottom = 4.dp),
            fontSize = 14.sp,
            text = entryPrintPath ?: stringResource(R.string.wua_convert_title_not_installed)
        )
    }
    AlertDialog(
        title = { Text(stringResource(R.string.wua_convert_confirmation_title)) },
        text = {
            Column(
                modifier = Modifier
                    .padding(horizontal = 8.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                Text(
                    modifier = Modifier.padding(vertical = 8.dp),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    text = stringResource(R.string.wua_convert_confirmation_description),
                )
                EntryInfo(
                    stringResource(R.string.wua_convert_base_game_title_entry),
                    compressTitleInfo.basePrintPath
                )
                EntryInfo(
                    stringResource(R.string.wua_convert_update_title_entry),
                    compressTitleInfo.updatePrintPath
                )
                EntryInfo(
                    stringResource(R.string.wua_convert_dlc_title_entry),
                    compressTitleInfo.aocPrintPath
                )
            }
        },
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = onConfirm) { Text(stringResource(R.string.ok)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        }
    )
}

@Composable
private fun TitleInstallProgressDialog(
    progress: Pair<Long, Long>?,
    onCancel: () -> Unit,
) {
    var showCancelConfirmDialog by remember { mutableStateOf(false) }

    AlertDialog(
        title = { Text(stringResource(R.string.install_title_progress_title)) },
        text = {
            val progressModifiers = Modifier
                .fillMaxWidth()
                .padding(8.dp)
            Column {
                if (progress == null) {
                    LinearProgressIndicator(modifier = progressModifiers)
                    Text(
                        modifier = Modifier.padding(8.dp),
                        text = stringResource(R.string.install_title_parsing_content)
                    )
                } else {
                    val (bytesWritten, maxBytes) = progress
                    LinearProgressIndicator(
                        modifier = progressModifiers,
                        progress = {
                            bytesWritten.toFloat() / maxBytes.toFloat()
                        },
                    )
                    Text(
                        modifier = Modifier.padding(8.dp),
                        text = "${bytesWritten.formatBytes()}/${maxBytes.formatBytes()}"
                    )
                }
            }
        },
        onDismissRequest = {},
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = { showCancelConfirmDialog = true }) {
                Text(stringResource(R.string.cancel))
            }
        }
    )

    if (showCancelConfirmDialog)
        AlertDialog(
            title = { Text(stringResource(R.string.install_title_cancel_title)) },
            text = {
                Text(stringResource(R.string.install_title_cancel_text))
            },
            onDismissRequest = { showCancelConfirmDialog = false },
            confirmButton = {
                TextButton(onClick = onCancel) {
                    Text(stringResource(R.string.yes))
                }
            },
            dismissButton = {
                TextButton(onClick = { showCancelConfirmDialog = false }) {
                    Text(stringResource(R.string.no))
                }
            }
        )
}


@Composable
private fun TitleInstallConfirmDialog(
    error: NativeGameTitles.TitleExistsError,
    onDismissRequest: () -> Unit,
    onConfirm: () -> Unit,
) {
    val errorMessage = when (error) {
        is NativeGameTitles.TitleExistsError.DifferentType -> stringResource(
            R.string.title_exists_error_different_type,
            error.oldType,
            error.toInstallType
        )

        NativeGameTitles.TitleExistsError.NewVersion -> stringResource(R.string.title_exists_error_new_version)
        NativeGameTitles.TitleExistsError.SameVersion -> stringResource(R.string.title_exists_error_same_version)

        NativeGameTitles.TitleExistsError.None -> {
            onConfirm()
            return
        }
    }

    AlertDialog(
        icon = {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null
            )
        },
        title = { Text(stringResource(R.string.warning)) },
        text = {
            Text(
                text = errorMessage,
                modifier = Modifier,
            )
        },
        onDismissRequest = onDismissRequest,
        confirmButton = {
            TextButton(onClick = onConfirm) { Text(stringResource(R.string.yes)) }
        },
        dismissButton = {
            TextButton(onClick = onDismissRequest) { Text(stringResource(R.string.no)) }
        }
    )
}

@Composable
private fun TitleFilterBottomSheet(
    onDismissRequest: () -> Unit,
    titleListViewModel: TitleListViewModel,
) {
    val filter by titleListViewModel.filter.collectAsState()

    ModalBottomSheet(
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        onDismissRequest = onDismissRequest,
    ) {
        Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
            TextField(
                modifier = Modifier
                    .padding(16.dp)
                    .fillMaxWidth(),
                singleLine = true,
                value = filter.query,
                onValueChange = titleListViewModel::setFilterQuery,
                label = { Text(stringResource(R.string.title_manager_search_label)) }
            )
            FilterRow(
                filterRowLabel = stringResource(R.string.title_manager_filter_types_label),
                filterValues = EntryType.entries.map { (it to (it in filter.types)) },
                valueToLabel = { stringResource(entryTypeToStringId(it)) },
                onFilterAdded = titleListViewModel.typesFilter::add,
                onFilterRemoved = titleListViewModel.typesFilter::remove,
            )
            FilterRow(
                filterRowLabel = stringResource(R.string.title_manager_filter_formats_label),
                filterValues = EntryFormat.entries.map { (it to (it in filter.formats)) },
                valueToLabel = { stringResource(formatToStringId(it)) },
                onFilterAdded = titleListViewModel.formatsFilter::add,
                onFilterRemoved = titleListViewModel.formatsFilter::remove,
            )
            FilterRow(
                filterRowLabel = stringResource(R.string.title_manager_filter_locations_label),
                filterValues = EntryPath.entries.map { (it to (it in filter.paths)) },
                valueToLabel = { stringResource(pathToStringId(it)) },
                onFilterAdded = titleListViewModel.pathsFilter::add,
                onFilterRemoved = titleListViewModel.pathsFilter::remove,
            )
        }
    }
}

@Composable
private fun <T> FilterRow(
    filterRowLabel: String,
    filterValues: List<Pair<T, Boolean>>,
    valueToLabel: @Composable (T) -> String,
    onFilterAdded: (T) -> Unit,
    onFilterRemoved: (T) -> Unit,
) {
    var showOptions by remember { mutableStateOf(false) }
    Column(
        modifier = Modifier
            .padding(8.dp)
            .fillMaxWidth()
            .animateContentSize()
    ) {
        TextButton(
            modifier = Modifier.fillMaxWidth(),
            onClick = { showOptions = !showOptions }) {
            Text(text = filterRowLabel, modifier = Modifier.weight(1f))
            Icon(
                modifier = Modifier.rotate(if (showOptions) 180f else 0f),
                imageVector = Icons.Filled.ArrowDropDown,
                contentDescription = null,
            )
        }
        if (showOptions)
            FlowRow(
                modifier = Modifier.padding(8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                filterValues.forEach { (value, selected) ->
                    FilterChip(
                        label = valueToLabel(value),
                        selected = selected,
                        onAdd = { onFilterAdded(value) },
                        onRemove = { onFilterRemoved(value) },
                    )
                }
            }
    }
}

@Composable
fun FilterChip(label: String, selected: Boolean, onAdd: () -> Unit, onRemove: () -> Unit) {
    FilterChip(
        leadingIcon = {
            if (selected)
                Icon(
                    imageVector = Icons.Filled.Check,
                    contentDescription = null
                )
        },
        selected = selected,
        onClick = {
            if (selected) onRemove()
            else onAdd()
        },
        label = { Text(label) }
    )
}

@Composable
private fun TitleEntryListItem(
    titleEntry: TitleEntry,
    onDeleteRequest: () -> Unit,
    onCompressRequested: () -> Unit,
) {
    var showDeleteConfirmationDialog by rememberSaveable { mutableStateOf(false) }

    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
        ),
        modifier = Modifier
            .fillMaxWidth()
            .animateContentSize()
            .padding(8.dp),
    ) {
        var showTitleInfo by remember { mutableStateOf(false) }
        Row(
            modifier = Modifier.padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TitleEntryIcon(titleEntry.type)
            Text(
                modifier = Modifier
                    .padding(horizontal = 4.dp)
                    .basicMarquee(iterations = Int.MAX_VALUE)
                    .weight(1.0f),
                text = titleEntry.name,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
            )
            TitleDropDownMenu(
                titleEntry = titleEntry,
                onDeleteClicked = { showDeleteConfirmationDialog = true },
                onCompressClicked = onCompressRequested
            )
            IconButton(
                onClick = { showTitleInfo = !showTitleInfo }) {
                Icon(
                    modifier = Modifier.rotate(if (showTitleInfo) 180f else 0f),
                    imageVector = Icons.Filled.ArrowDropDown,
                    contentDescription = stringResource(R.string.title_manager_show_info_description)
                )
            }
        }
        if (showTitleInfo) {
            TitleEntryData(titleEntry)
        }
    }

    if (showDeleteConfirmationDialog)
        DeleteTitleConfirmationDialog(
            titleEntry = titleEntry,
            onDismissRequest = { showDeleteConfirmationDialog = false },
            onConfirmDelete = onDeleteRequest
        )
}

@Composable
private fun TitleDropDownMenu(
    titleEntry: TitleEntry,
    onDeleteClicked: () -> Unit,
    onCompressClicked: () -> Unit,
) {
    var expandMenu by remember { mutableStateOf(false) }

    @Composable
    fun DropdownMenuItem(text: String, onClick: () -> Unit) {
        DropdownMenuItem(
            text = { Text(text) },
            onClick = {
                expandMenu = false
                onClick()
            }
        )
    }

    Box {
        IconButton(onClick = { expandMenu = true }) {
            Icon(
                imageVector = Icons.Filled.MoreVert,
                contentDescription = stringResource(R.string.title_dropdown_menu_description)
            )
        }
        DropdownMenu(
            expanded = expandMenu,
            onDismissRequest = { expandMenu = false }) {
            DropdownMenuItem(stringResource(R.string.delete), onDeleteClicked)
            if (titleEntry.type != EntryType.Save && titleEntry.format != EntryFormat.WUA)
                DropdownMenuItem(
                    stringResource(R.string.wua_convert_action_label),
                    onCompressClicked
                )
        }
    }
}

@Composable
private fun DeleteTitleProgressDialog(titleEntry: TitleEntry) {
    AlertDialog(
        icon = {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null
            )
        },
        title = {
            Text(stringResource(R.string.delete_title_progress_dialog_title))
        },
        text = {
            val titleEntryInfo = stringResource(
                R.string.title_entry_delete_info,
                titleEntry.name,
                stringResource(regionToStringId(titleEntry.region)),
                stringResource(entryTypeToStringId(titleEntry.type))
            )
            Column(
                modifier = Modifier.padding(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(stringResource(R.string.delete_title_title_info, titleEntryInfo))
                LinearProgressIndicator(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 8.dp)
                )
            }
        },
        onDismissRequest = {},
        confirmButton = {},
        dismissButton = {}
    )
}

@Composable
private fun DeleteTitleConfirmationDialog(
    titleEntry: TitleEntry,
    onDismissRequest: () -> Unit,
    onConfirmDelete: () -> Unit,
) {
    AlertDialog(
        icon = {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null
            )
        },
        title = { Text(stringResource(R.string.warning)) },
        text = {
            val titleEntryInfo = stringResource(
                R.string.title_entry_delete_info,
                titleEntry.name,
                stringResource(regionToStringId(titleEntry.region)),
                stringResource(entryTypeToStringId(titleEntry.type))
            )
            Column(
                modifier = Modifier.padding(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(stringResource(R.string.title_entry_delete_confirmation))
                Text(titleEntryInfo)
            }
        },
        onDismissRequest = onDismissRequest,
        confirmButton = {
            TextButton(
                onClick = {
                    onDismissRequest()
                    onConfirmDelete()
                },
                content = { Text(stringResource(R.string.yes)) },
            )
        },
        dismissButton = {
            TextButton(onClick = onDismissRequest) { Text(stringResource(R.string.no)) }
        }
    )
}

@Composable
private fun TitleEntryIcon(entryType: EntryType, modifier: Modifier = Modifier) {
    val iconId = when (entryType) {
        EntryType.Base -> R.drawable.ic_controller
        EntryType.Update -> R.drawable.ic_upgrade
        EntryType.Dlc -> R.drawable.ic_box
        EntryType.Save -> R.drawable.ic_save
        EntryType.System -> R.drawable.ic_build
    }
    Icon(
        modifier = modifier,
        painter = painterResource(iconId),
        contentDescription = stringResource(entryTypeToStringId(entryType))
    )
}

@Composable
private fun TitleEntryData(titleEntry: TitleEntry) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(8.dp)
    ) {
        TitleEntryInfo(
            name = stringResource(R.string.title_info_id_label),
            value = formatTitleId(titleEntry.titleId)
        )
        TitleEntryInfo(
            name = stringResource(R.string.title_info_type_label),
            value = stringResource(entryTypeToStringId(titleEntry.type)),
        )
        TitleEntryInfo(
            name = stringResource(R.string.title_info_version_label),
            value = titleEntry.version.toString(),
        )
        TitleEntryInfo(
            name = stringResource(R.string.title_info_region_label),
            value = stringResource(regionToStringId(titleEntry.region)),
        )
        TitleEntryInfo(
            name = stringResource(R.string.title_info_format_label),
            value = stringResource(formatToStringId(titleEntry.format)),
        )
        TitleEntryInfo(
            name = stringResource(R.string.title_info_location_label),
            value = if (titleEntry.isInMLC) stringResource(R.string.location_mlc)
            else stringResource(R.string.location_game_paths)
        )
    }
}

@Composable
private fun TitleEntryInfo(name: String, value: String) {
    Text(
        modifier = Modifier
            .padding(
                top = 2.dp,
                start = 8.dp,
                end = 8.dp,
            ),
        fontSize = 16.sp,
        fontWeight = FontWeight.Medium,
        text = name,
    )
    Text(
        modifier = Modifier.padding(
            start = 8.dp,
            end = 8.dp,
            bottom = 2.dp,
        ),
        fontSize = 14.sp,
        text = value
    )
}

@StringRes
private fun formatToStringId(entryFormat: EntryFormat) = when (entryFormat) {
    EntryFormat.Folder -> R.string.entry_format_folder
    EntryFormat.WUD -> R.string.entry_format_wud
    EntryFormat.NUS -> R.string.entry_format_nus
    EntryFormat.WUA -> R.string.entry_format_wua
    EntryFormat.WUHB -> R.string.entry_format_wuhb
    EntryFormat.SaveFolder -> R.string.entry_format_save_folder
}

@StringRes
private fun pathToStringId(entryPath: EntryPath) = when (entryPath) {
    EntryPath.MLC -> R.string.location_mlc
    EntryPath.GamePaths -> R.string.location_game_paths
}

@StringRes
private fun entryTypeToStringId(entryType: EntryType) = when (entryType) {
    EntryType.Base -> R.string.entry_type_base
    EntryType.Update -> R.string.entry_type_update
    EntryType.Dlc -> R.string.entry_type_dlc
    EntryType.Save -> R.string.entry_type_save
    EntryType.System -> R.string.entry_type_system
}

private fun formatTitleId(titleId: Long) =
    String.format("%08x-%08x", titleId shr 32, titleId and 0xFFFFFFFF)
