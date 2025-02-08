@file:OptIn(ExperimentalMaterial3Api::class)

package info.cemu.cemu.graphicpacks

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.contentColorFor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.dropUnlessResumed
import androidx.lifecycle.viewmodel.compose.viewModel
import info.cemu.cemu.R
import info.cemu.cemu.guicore.components.DefaultAppBarTitle
import info.cemu.cemu.guicore.components.ScreenContentLazy
import info.cemu.cemu.guicore.components.SearchToolbarInput
import info.cemu.cemu.guicore.components.SingleSelection
import kotlinx.coroutines.launch


@Composable
fun GraphicPacksRootSectionScreen(
    navigateBack: () -> Unit,
    graphicPackNodeNavigate: (GraphicPackNode) -> Unit,
    graphicPacksListViewModel: GraphicPacksListViewModel = viewModel(),
) {
    val graphicPackNodes by graphicPacksListViewModel.graphicPackNodes.collectAsState()
    val graphicPackDataNodes by graphicPacksListViewModel.graphicPackDataNodes.collectAsState()
    val query by graphicPacksListViewModel.filterText.collectAsState()
    val installedOnly by graphicPacksListViewModel.installedOnly.collectAsState()
    var showGraphicPackSearch by rememberSaveable { mutableStateOf(false) }
    val downloadStatus by graphicPacksListViewModel.downloadStatus.collectAsState()
    val snackbarScope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    var downloadDialogText by rememberSaveable { mutableStateOf<String?>(null) }
    val context = LocalContext.current

    downloadStatus?.let { status ->
        downloadDialogText =
            downloadStatusToDialogTextStringId(status)?.let { stringResource(it) }
        LaunchedEffect(status) {
            graphicPacksListViewModel.downloadStatusRead()

            val downloadNotificationText =
                downloadStatusToNotificationStringId(status)?.let(context::getString)
                    ?: return@LaunchedEffect
            snackbarScope.launch {
                snackbarHostState.currentSnackbarData?.dismiss()
                snackbarHostState.showSnackbar(downloadNotificationText)
            }
        }
    }
    fun onNavigateBack() {
        if (showGraphicPackSearch) {
            showGraphicPackSearch = false
        } else {
            navigateBack()
        }
    }

    ScreenContentLazy(
        snackbarHost = { SnackbarHost(hostState = snackbarHostState) },
        actions = {
            GraphicPacksRootSectionActions(
                showMainActions = !showGraphicPackSearch,
                onSearchClicked = {
                    showGraphicPackSearch = true
                },
                onDownloadClicked = { graphicPacksListViewModel.downloadNewUpdate(context) },
                installedOnlyChecked = installedOnly,
                installedOnlyValueChange = graphicPacksListViewModel::setInstalledOnly,
            )
        },
        appBarTitle = {
            Box(
                modifier = Modifier
                    .height(IntrinsicSize.Min)
                    .padding(8.dp),
            ) {
                if (showGraphicPackSearch) {
                    SearchToolbarInput(
                        value = query,
                        onValueChange = graphicPacksListViewModel::setFilterText,
                        hint = stringResource(R.string.search_graphic_packs),
                    )
                } else {
                    DefaultAppBarTitle(stringResource(R.string.graphic_packs))
                }
            }
        },
        navigateBack = ::onNavigateBack,
    ) {
        if (showGraphicPackSearch) {
            graphicPackDataSearchItems(
                nodes = graphicPackDataNodes,
                onClick = graphicPackNodeNavigate,
            )
        } else {
            graphicPackSectionItems(
                nodes = graphicPackNodes,
                onClick = graphicPackNodeNavigate,
            )
        }
    }
    if (downloadDialogText != null) {
        GraphicPacksDownloadDialog(
            onCancelRequest = {
                graphicPacksListViewModel.cancelDownload()
            },
            text = downloadDialogText!!,
        )
    }
}

@StringRes
private fun downloadStatusToDialogTextStringId(downloadStatus: GraphicPacksDownloadStatus?): Int? =
    when (downloadStatus) {
        GraphicPacksDownloadStatus.CheckingForUpdates -> R.string.checking_version_download_text
        GraphicPacksDownloadStatus.Downloading -> R.string.graphic_packs_download_text
        else -> null
    }

@StringRes
private fun downloadStatusToNotificationStringId(downloadStatus: GraphicPacksDownloadStatus?): Int? =
    when (downloadStatus) {
        GraphicPacksDownloadStatus.Error -> R.string.download_graphic_packs_error_text
        GraphicPacksDownloadStatus.FinishedDownloading -> R.string.download_graphic_packs_finish_text
        GraphicPacksDownloadStatus.NoUpdatesAvailable -> R.string.graphic_packs_no_updates_text
        else -> null
    }

@Composable
fun GraphicPacksDownloadDialog(
    onCancelRequest: () -> Unit,
    text: String,
) {
    AlertDialog(
        title = {
            Text(text = stringResource(R.string.graphic_packs_download_dialog_title))
        },
        text = {
            Column(modifier = Modifier.padding(vertical = 8.dp)) {
                Text(
                    text = text,
                    modifier = Modifier.padding(bottom = 16.dp)
                )
                LinearProgressIndicator(
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        onDismissRequest = {},
        confirmButton = {
            TextButton(
                onClick = {
                    onCancelRequest()
                }
            ) {
                Text(stringResource(R.string.cancel))
            }
        }
    )
}

@Composable
fun GraphicPacksRootSectionActions(
    showMainActions: Boolean,
    onSearchClicked: () -> Unit,
    onDownloadClicked: () -> Unit,
    installedOnlyChecked: Boolean,
    installedOnlyValueChange: (Boolean) -> Unit,
) {
    if (showMainActions) {
        IconButton(
            onClick = onSearchClicked
        ) {
            Icon(
                imageVector = Icons.Filled.Search,
                contentDescription = stringResource(R.string.search_graphic_packs)
            )
        }
        IconButton(
            onClick = onDownloadClicked
        ) {
            Icon(
                painter = painterResource(R.drawable.ic_download),
                contentDescription = stringResource(R.string.download_graphic_packs)
            )
        }
    }
    var showMoreOptions by rememberSaveable { mutableStateOf(false) }
    IconButton(
        onClick = { showMoreOptions = true }
    ) {
        Icon(
            imageVector = Icons.Filled.MoreVert,
            contentDescription = stringResource(R.string.more_options)
        )
    }
    DropdownMenu(
        expanded = showMoreOptions,
        onDismissRequest = { showMoreOptions = false }
    ) {
        DropdownMenuItem(
            onClick = {
                installedOnlyValueChange(!installedOnlyChecked)
            },
            text = {
                Text(text = stringResource(R.string.graphic_packs_installed_only))
            },
            trailingIcon = {
                Checkbox(
                    checked = installedOnlyChecked,
                    onCheckedChange = null
                )
            }
        )
    }
}

fun LazyListScope.graphicPackDataSearchItems(
    nodes: List<GraphicPackDataNode>,
    onClick: (GraphicPackDataNode) -> Unit,
) {
    items(nodes) {
        Row(
            modifier = Modifier
                .animateItem()
                .clickable(onClick = dropUnlessResumed { onClick(it) })
                .padding(8.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            GraphicPackDataListItemIcon(it.enabled)
            Column {
                Text(
                    modifier = Modifier.padding(horizontal = 8.dp),
                    text = it.name ?: "",
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    modifier = Modifier.padding(horizontal = 8.dp),
                    text = it.path,
                )
            }
        }
    }
}

@Composable
fun GraphicPacksSectionScreen(
    navigateBack: () -> Unit,
    graphicPackNodeNavigate: (GraphicPackNode) -> Unit,
    graphicPackSectionNode: GraphicPackSectionNode,
) {
    val appBarText = graphicPackSectionNode.name ?: stringResource(R.string.graphic_packs)
    ScreenContentLazy(
        appBarText = appBarText,
        navigateBack = navigateBack,
    ) {
        graphicPackSectionItems(
            nodes = graphicPackSectionNode.children,
            onClick = graphicPackNodeNavigate,
        )
    }
}

@Composable
fun GraphicPackDataScreen(
    navigateBack: () -> Unit,
    graphicPackDataViewModel: GraphicPackDataViewModel,
) {
    val appBarText = graphicPackDataViewModel.name ?: stringResource(R.string.graphic_packs)
    val enabled by graphicPackDataViewModel.enabled.collectAsState()
    val presets by graphicPackDataViewModel.presets.collectAsState()

    ScreenContentLazy(
        appBarText = appBarText,
        navigateBack = navigateBack,
    ) {
        item {
            Row(
                modifier = Modifier.padding(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(text = stringResource(R.string.graphic_pack_enabled_checkbox_label))
                Switch(
                    modifier = Modifier.padding(horizontal = 8.dp),
                    checked = enabled,
                    onCheckedChange = graphicPackDataViewModel::setEnabled,
                )
            }
        }
        item {
            Text(
                modifier = Modifier.padding(8.dp),
                text = graphicPackDataViewModel.description
            )
        }
        items(items = presets) {
            SingleSelection(
                modifier = Modifier.animateItem(),
                label = it.category ?: stringResource(R.string.active_preset_category),
                choices = it.presets,
                choice = it.activePreset,
                onChoiceChanged = { activePreset ->
                    graphicPackDataViewModel.setActivePreset(
                        it.index,
                        activePreset
                    )
                }
            )
        }
    }
}


private fun LazyListScope.graphicPackSectionItems(
    nodes: List<GraphicPackNode>,
    onClick: (GraphicPackNode) -> Unit,
) {
    items(
        items = nodes,
    ) {
        GraphicPackListItem(
            label = it.name,
            onClick = dropUnlessResumed { onClick(it) },
            modifier = Modifier.animateItem(),
        ) {
            when (it) {
                is GraphicPackSectionNode -> GraphicPackSectionListItemIcon(it.enabledGraphicPacksCount)
                is GraphicPackDataNode -> GraphicPackDataListItemIcon(it.enabled)
            }
        }
    }
}

@Composable
fun GraphicPackDataListItemIcon(isEnabled: Boolean) {
    GraphicPackListItemIcon(
        painter = painterResource(R.drawable.ic_package_2),
        showExtraInfo = isEnabled,
    ) {
        Icon(
            modifier = Modifier
                .background(MaterialTheme.colorScheme.primary, CircleShape)
                .size(16.dp),
            imageVector = Icons.Filled.Check,
            tint = contentColorFor(MaterialTheme.colorScheme.primary),
            contentDescription = stringResource(R.string.graphic_pack_is_enabled),
        )
    }
}

@Composable
fun GraphicPackSectionListItemIcon(numberOfEnabledPacks: Int) {
    GraphicPackListItemIcon(
        painter = painterResource(R.drawable.ic_lists),
        showExtraInfo = numberOfEnabledPacks > 0,
    ) {
        Text(
            textAlign = TextAlign.Center,
            text = if (numberOfEnabledPacks < 99) numberOfEnabledPacks.toString() else "99+",
            modifier = Modifier
                .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(2.dp))
                .padding(horizontal = 2.dp),
            color = contentColorFor(MaterialTheme.colorScheme.primary),
        )
    }
}

@Composable
fun GraphicPackListItemIcon(
    painter: Painter,
    showExtraInfo: Boolean,
    extraInfoContent: @Composable () -> Unit,
) {
    Box {
        Icon(
            modifier = Modifier.size(28.dp),
            painter = painter,
            contentDescription = null,
        )
        if (showExtraInfo) {
            Box(modifier = Modifier.align(Alignment.BottomEnd)) {
                extraInfoContent()
            }
        }
    }
}

@Composable
fun GraphicPackListItem(
    label: String?,
    onClick: () -> Unit,
    modifier: Modifier,
    icon: @Composable () -> Unit,
) {
    Row(
        modifier = modifier
            .clickable(onClick = onClick)
            .padding(8.dp)
            .fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon()
        Text(
            modifier = Modifier
                .weight(1.0f)
                .padding(horizontal = 8.dp),
            text = label ?: "",
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
