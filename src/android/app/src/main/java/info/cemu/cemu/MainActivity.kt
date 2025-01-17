package info.cemu.cemu

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.DocumentsContract
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import info.cemu.cemu.about.AboutCemuActivity
import info.cemu.cemu.emulation.EmulationActivity
import info.cemu.cemu.features.DocumentsProvider
import info.cemu.cemu.gamelist.GameDetailsScreen
import info.cemu.cemu.gamelist.GameProfileEditScreen
import info.cemu.cemu.gamelist.GameViewModel
import info.cemu.cemu.gamelist.GamesListScreen
import info.cemu.cemu.gamelist.GamesListScreenActions
import info.cemu.cemu.graphicpacks.GraphicPacksActivity
import info.cemu.cemu.guicore.ActivityContent
import info.cemu.cemu.nativeinterface.NativeGameTitles.Game
import info.cemu.cemu.nativeinterface.NativeSettings
import info.cemu.cemu.settings.SettingsActivity
import info.cemu.cemu.titlemanager.TitleManagerActivity
import kotlinx.serialization.Serializable

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            ActivityContent {
                MainNav()
            }
        }
    }

    override fun onPause() {
        super.onPause()
        NativeSettings.saveSettings()
    }
}

private fun startGame(context: Context, game: Game) {
    context.startActivity(
        Intent(
            context,
            EmulationActivity::class.java
        ).apply {
            putExtra(EmulationActivity.EXTRA_LAUNCH_PATH, game.path)
        }
    )
}

sealed class MainRoutes {
    @Serializable
    object GamesRoute

    @Serializable
    object GameDetailsRoute

    @Serializable
    object GameProfileEditRoute
}


@Composable
fun MainNav() {
    val navController = rememberNavController()
    val selectedGameViewModel: GameViewModel = viewModel()
    fun navigateBack() {
        navController.popBackStack()
    }
    NavHost(navController = navController, startDestination = MainRoutes.GamesRoute) {
        composable<MainRoutes.GamesRoute> {
            val context = LocalContext.current
            GamesListScreen(
                selectedGameViewModel = selectedGameViewModel,
                gameListActions = GamesListScreenActions(
                    goToGameEditProfile = { navController.navigate(MainRoutes.GameProfileEditRoute) },
                    startGame = { startGame(context, it) },
                    goToGameDetails = { navController.navigate(MainRoutes.GameDetailsRoute) },
                ),
                toolbarActions = {
                    GameListToolBarActions()
                }
            )
        }
        composable<MainRoutes.GameDetailsRoute> {
            GameDetailsScreen(
                selectedGameViewModel = selectedGameViewModel,
                navigateBack = ::navigateBack,
            )
        }
        composable<MainRoutes.GameProfileEditRoute> {
            GameProfileEditScreen(
                selectedGameViewModel = selectedGameViewModel,
                navigateBack = ::navigateBack,
            )
        }
    }
}

@Composable
fun GameListToolBarActions() {
    var expandMenu by remember { mutableStateOf(false) }
    val context = LocalContext.current
    IconButton(
        modifier = Modifier.padding(end = 8.dp),
        onClick = { expandMenu = true },
    ) {
        IconButton(
            onClick = { expandMenu = true }
        ) {
            Icon(
                imageVector = Icons.Filled.MoreVert,
                contentDescription = "More options"
            )

        }
    }
    DropdownMenu(
        expanded = expandMenu,
        onDismissRequest = { expandMenu = false }
    ) {
        DropdownMenuItem(
            onClick = {
                context.goToActivity(SettingsActivity::class.java)
                expandMenu = false
            },
            text = { Text(stringResource(R.string.settings)) },
        )
        DropdownMenuItem(
            onClick = {
                context.goToActivity(GraphicPacksActivity::class.java)
                expandMenu = false
            },
            text = { Text(stringResource(R.string.graphic_packs)) },
        )
        DropdownMenuItem(
            onClick = {
                context.goToActivity(TitleManagerActivity::class.java)
                expandMenu = false
            },
            text = { Text(stringResource(R.string.title_manager)) },
        )
        DropdownMenuItem(
            onClick = {
                openCemuFolder(context)
                expandMenu = false
            },
            text = { Text(stringResource(R.string.open_cemu_folder)) },
        )
        DropdownMenuItem(
            onClick = {
                context.goToActivity(AboutCemuActivity::class.java)
                expandMenu = false
            },
            text = { Text(stringResource(R.string.about_cemu)) },
        )
    }
}

private fun <T : ComponentActivity> Context.goToActivity(activityClass: Class<T>) {
    startActivity(
        Intent(
            this,
            activityClass,
        )
    )
}

fun openCemuFolder(context: Context) {
    try {
        Intent(Intent.ACTION_VIEW).apply {
            addCategory(Intent.CATEGORY_DEFAULT)
            data = DocumentsContract.buildRootUri(
                DocumentsProvider.AUTHORITY,
                DocumentsProvider.ROOT_ID
            )
            addFlags(
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                        or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                        or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            context.startActivity(this@apply)
        }
    } catch (activityNotFoundException: ActivityNotFoundException) {
        Toast.makeText(context, R.string.failed_to_open_cemu_folder, Toast.LENGTH_LONG).show()
    }
}
