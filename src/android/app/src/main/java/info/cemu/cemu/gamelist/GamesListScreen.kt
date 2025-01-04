@file:OptIn(
    ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class,
)

package info.cemu.cemu.gamelist

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.pullToRefresh
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import info.cemu.cemu.R
import info.cemu.cemu.emulation.EmulationActivity
import info.cemu.cemu.guicore.FilledSearchToolbar
import info.cemu.cemu.nativeinterface.NativeGameTitles
import info.cemu.cemu.nativeinterface.NativeGameTitles.Game
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import android.graphics.drawable.Icon as ShortcutIcon

data class GamesListScreenActions(
    val goToGameDetails: () -> Unit,
    val goToGameEditProfile: () -> Unit,
    val startGame: (Game) -> Unit,
)


@Composable
fun GamesListScreen(
    selectedGameViewModel: GameViewModel,
    gameListViewModel: GameListViewModel = viewModel(),
    gameListActions: GamesListScreenActions,
    toolbarActions: @Composable RowScope.() -> Unit,
) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    val gameToRemoveShaders by gameListViewModel.gameToRemoveShaders.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    fun onRefresh() = coroutineScope.launch {
        refreshing = true
        gameListViewModel.refreshGames()
        delay(1500)
        refreshing = false
    }

    val state = rememberPullToRefreshState()

    LaunchedEffect(Unit) {
        if (gameListViewModel.checkIfGamePathsHaveChanged()) {
            gameListViewModel.refreshGames()
        }
    }

    DisposableEffect(LocalLifecycleOwner.current) {
        onDispose {
            gameListViewModel.setFilterText("")
        }
    }
    Scaffold(
        snackbarHost = { SnackbarHost(hostState = snackbarHostState) },
        topBar = {
            FilledSearchToolbar(
                actions = toolbarActions,
                hint = stringResource(R.string.search_games),
                onValueChange = gameListViewModel::setFilterText
            )
        },
    ) { scaffoldPadding ->
        Box(
            modifier = Modifier
                .padding(scaffoldPadding)
                .fillMaxSize()
                .pullToRefresh(
                    isRefreshing = refreshing,
                    state = state,
                    onRefresh = ::onRefresh,
                ),
        ) {
            GameList(
                gameListViewModel = gameListViewModel,
                selectedGameViewModel = selectedGameViewModel,
                actions = gameListActions,
                onFailedToCreateShortCut = {
                    coroutineScope.launch { snackbarHostState.showSnackbar(context.getString(R.string.shortcut_not_supported)) }
                }
            )
            PullToRefreshDefaults.Indicator(
                modifier = Modifier.align(Alignment.TopCenter),
                isRefreshing = refreshing,
                state = state,
                containerColor = MaterialTheme.colorScheme.surfaceVariant,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    if (gameToRemoveShaders != null) {
        ShaderCachesConfirmationDialog(
            gameName = gameToRemoveShaders?.name ?: "",
            onDismissRequest = gameListViewModel::clearSelectedGameForShaderRemoval,
            onConfirm = {
                gameListViewModel.removeShadersForSelectedGame()
                coroutineScope.launch { snackbarHostState.showSnackbar(context.getString(R.string.shader_caches_removed_notification)) }
            },
        )
    }
}


@Composable
fun GameList(
    gameListViewModel: GameListViewModel,
    selectedGameViewModel: GameViewModel,
    actions: GamesListScreenActions,
    onFailedToCreateShortCut: () -> Unit,
) {
    val games by gameListViewModel.games.collectAsStateWithLifecycle()
    val context = LocalContext.current
    LazyVerticalGrid(
        modifier = Modifier
            .padding(8.dp)
            .fillMaxSize(),
        columns = GridCells.Adaptive(620.dp)
    ) {
        items(items = games, key = { it.titleId }) { game ->
            GameListItem(
                modifier = Modifier.animateItem(),
                game = game,
                onStartGame = actions.startGame,
                actions = GameContextMenuActions(
                    onIsFavoriteChanged = { isFavorite ->
                        gameListViewModel.setGameTitleFavorite(game, isFavorite)
                    },
                    onEditGameProfile = {
                        selectedGameViewModel.setCurrentGame(game)
                        actions.goToGameEditProfile()
                    },
                    onRemoveShaderCaches = { gameListViewModel.setGameForShadersRemoval(game) },
                    onAboutTitle = {
                        selectedGameViewModel.setCurrentGame(game)
                        actions.goToGameDetails()
                    },
                    onCreateShortcut = {
                        createShortcutForGame(
                            context = context,
                            game = game,
                            onFailedToCreateShortCut = onFailedToCreateShortCut
                        )
                    },
                ),
            )
        }
    }
}

@Composable
fun ShaderCachesConfirmationDialog(
    gameName: String,
    onDismissRequest: () -> Unit,
    onConfirm: () -> Unit,
) {
    AlertDialog(
        title = {
            Text(stringResource(R.string.remove_shader_caches))
        },
        text = {
            Text(stringResource(R.string.remove_shader_caches_message, gameName))
        },
        dismissButton = {
            TextButton(
                onClick = onDismissRequest
            ) {
                Text(stringResource(R.string.no))
            }
        },
        onDismissRequest = onDismissRequest,
        confirmButton = {
            TextButton(
                onClick = onConfirm
            ) {
                Text(stringResource(R.string.yes))
            }
        }
    )
}

@Composable
fun GameListItem(
    actions: GameContextMenuActions,
    onStartGame: (Game) -> Unit,
    game: Game,
    modifier: Modifier = Modifier,
) {
    var contextMenuExpanded by rememberSaveable { mutableStateOf(false) }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .combinedClickable(
                onClick = { onStartGame(game) },
                onLongClick = {
                    contextMenuExpanded = true
                },
            )
            .padding(8.dp)
            .fillMaxWidth(),
    ) {
        Box {
            GameIcon(
                game = game,
                modifier = Modifier.size(60.dp),
            )
            if (game.isFavorite) {
                Icon(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(2.dp)
                        .size(24.dp)
                        .clip(androidx.compose.foundation.shape.CircleShape)
                        .background(MaterialTheme.colorScheme.surfaceVariant),
                    painter = painterResource(R.drawable.ic_favorite),
                    tint = MaterialTheme.colorScheme.primary,
                    contentDescription = stringResource(R.string.game_favorite_description),
                )
            }
        }
        Text(
            modifier = Modifier.padding(horizontal = 8.dp),
            text = game.name ?: "",
            fontSize = 24.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        GameContextMenu(
            expanded = contextMenuExpanded,
            onDismissRequest = { contextMenuExpanded = false },
            actions = actions,
            game = game,
        )
    }
}

data class GameContextMenuActions(
    val onIsFavoriteChanged: (Boolean) -> Unit,
    val onEditGameProfile: () -> Unit,
    val onRemoveShaderCaches: () -> Unit,
    val onAboutTitle: () -> Unit,
    val onCreateShortcut: () -> Unit,
)

@Composable
fun GameContextMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    actions: GameContextMenuActions,
    game: Game,
) {
    @Composable
    fun GameContextMenuItem(
        onClick: () -> Unit,
        text: String,
        enabled: Boolean = true,
        trailingIcon: @Composable (() -> Unit)? = null,
    ) {
        DropdownMenuItem(
            enabled = enabled,
            onClick = {
                onDismissRequest()
                onClick()
            },
            text = {
                Text(text = text)
            },
            trailingIcon = trailingIcon,
        )
    }
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismissRequest
    ) {
        val gameTitleHasCaches = rememberSaveable {
            NativeGameTitles.titleHasShaderCacheFiles(game.titleId)
        }
        GameContextMenuItem(
            onClick = { actions.onIsFavoriteChanged(!game.isFavorite) },
            text = stringResource(R.string.game_favorite),
            trailingIcon = {
                Checkbox(checked = game.isFavorite, onCheckedChange = null)
            }
        )
        GameContextMenuItem(
            onClick = actions.onEditGameProfile,
            text = stringResource(R.string.edit_game_profile)
        )
        GameContextMenuItem(
            enabled = gameTitleHasCaches,
            onClick = {
                actions.onRemoveShaderCaches()
            },
            text = stringResource(R.string.remove_shader_caches)
        )
        GameContextMenuItem(
            onClick = actions.onAboutTitle,
            text = stringResource(R.string.about_title),
        )
        GameContextMenuItem(
            onClick = actions.onCreateShortcut,
            text = stringResource(R.string.create_shortcut)
        )
    }
}


private fun createShortcutForGame(
    context: Context,
    game: Game,
    onFailedToCreateShortCut: () -> Unit,
) {
    val shortcutManager = context.getSystemService(
        ShortcutManager::class.java
    )
    if (!shortcutManager.isRequestPinShortcutSupported) {
        onFailedToCreateShortCut()
        return
    }
    val icon = game.icon?.asAndroidBitmap().let {
        if (it != null) ShortcutIcon.createWithBitmap(it)
        else ShortcutIcon.createWithResource(context, R.mipmap.ic_launcher)
    }
    val intent = Intent(
        context,
        EmulationActivity::class.java
    )
    intent.setAction(Intent.ACTION_VIEW)
    intent.putExtra(EmulationActivity.EXTRA_LAUNCH_PATH, game.path)
    val pinShortcutInfo = ShortcutInfo.Builder(context, game.titleId.toString())
        .setShortLabel(game.name!!)
        .setIntent(intent)
        .setIcon(icon)
        .build()
    val pinnedShortcutCallbackIntent =
        shortcutManager.createShortcutResultIntent(pinShortcutInfo)
    val successCallback = PendingIntent.getBroadcast(
        context,
        0,
        pinnedShortcutCallbackIntent,
        PendingIntent.FLAG_IMMUTABLE
    )
    shortcutManager.requestPinShortcut(pinShortcutInfo, successCallback.intentSender)
}
