package info.cemu.cemu.settings

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.navigation
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import info.cemu.cemu.guicore.ActivityContent
import info.cemu.cemu.settings.audio.AudioSettingsScreen
import info.cemu.cemu.settings.customdrivers.CustomDriversScreen
import info.cemu.cemu.settings.gamespath.GamePathsScreen
import info.cemu.cemu.settings.general.GeneralSettingsScreen
import info.cemu.cemu.settings.graphics.GraphicsSettingsScreen
import info.cemu.cemu.settings.input.ControllerInputSettingsScreen
import info.cemu.cemu.settings.input.InputSettingsScreen
import info.cemu.cemu.settings.input.InputSettingsScreenActions
import info.cemu.cemu.settings.inputoverlay.InputOverlaySettingsScreen
import info.cemu.cemu.settings.overlay.OverlaySettingsScreen
import kotlinx.serialization.Serializable

class SettingsActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            ActivityContent {
                SettingsNav(parentNavBack = ::onNavigateUp)
            }
        }
    }
}

private sealed class SettingsRoutes {
    @Serializable
    object GeneralSettings

    @Serializable
    object GeneralSettingsScreenRoute

    @Serializable
    object InputSettingsRoute

    @Serializable
    object SettingsHomeScreenRoute

    @Serializable
    object AudioSettingsScreenRoute

    @Serializable
    object GraphicsSettingsScreenRoute

    @Serializable
    object CustomDriversScreenRoute

    @Serializable
    object GamePathsScreenRoute

    @Serializable
    object OverlaySettingsScreenRoute

    @Serializable
    object InputSettingsScreenRoute

    @Serializable
    data class ControllerInputSettingsScreenRoute(val index: Int)

    @Serializable
    object InputOverlaySettingsScreenRoute
}


@Composable
fun SettingsNav(
    parentNavBack: () -> Unit,
) {
    val navController = rememberNavController()

    fun navigateBack() {
        if (!navController.popBackStack()) {
            parentNavBack()
        }
    }

    NavHost(
        navController = navController,
        startDestination = SettingsRoutes.SettingsHomeScreenRoute,
        enterTransition = {
            EnterTransition.None
        },
        exitTransition = {
            ExitTransition.None
        }
    ) {
        composable<SettingsRoutes.SettingsHomeScreenRoute> {
            SettingsHomeScreen(
                navigateBack = ::navigateBack,
                actions = SettingsHomeScreenActions(
                    goToGeneralSettings = { navController.navigate(SettingsRoutes.GeneralSettings) },
                    goToInputSettings = { navController.navigate(SettingsRoutes.InputSettingsRoute) },
                    goToGraphicsSettings = { navController.navigate(SettingsRoutes.GraphicsSettingsScreenRoute) },
                    goToAudioSettings = { navController.navigate(SettingsRoutes.AudioSettingsScreenRoute) },
                    goToOverlaySettings = { navController.navigate(SettingsRoutes.OverlaySettingsScreenRoute) },
                )
            )
        }
        composable<SettingsRoutes.AudioSettingsScreenRoute> {
            AudioSettingsScreen(
                navigateBack = ::navigateBack,
            )
        }
        composable<SettingsRoutes.GraphicsSettingsScreenRoute> {
            GraphicsSettingsScreen(
                navigateBack = ::navigateBack,
                goToCustomDriversSettings = {
                    navController.navigate(SettingsRoutes.CustomDriversScreenRoute)
                }
            )
        }
        composable<SettingsRoutes.CustomDriversScreenRoute> {
            CustomDriversScreen(
                navigateBack = ::navigateBack,
            )
        }
        composable<SettingsRoutes.OverlaySettingsScreenRoute> {
            OverlaySettingsScreen(
                navigateBack = ::navigateBack,
            )
        }
        navigation<SettingsRoutes.InputSettingsRoute>(startDestination = SettingsRoutes.InputSettingsScreenRoute) {
            composable<SettingsRoutes.ControllerInputSettingsScreenRoute> { navBackStackEntry ->
                val controllerIndex =
                    navBackStackEntry.toRoute<SettingsRoutes.ControllerInputSettingsScreenRoute>().index
                ControllerInputSettingsScreen(
                    navigateBack = ::navigateBack,
                    controllerIndex = controllerIndex,
                )
            }
            composable<SettingsRoutes.InputOverlaySettingsScreenRoute> {
                InputOverlaySettingsScreen(
                    navigateBack = ::navigateBack
                )
            }
            composable<SettingsRoutes.InputSettingsScreenRoute> {
                InputSettingsScreen(
                    navigateBack = ::navigateBack,
                    actions = InputSettingsScreenActions(
                        goToInputOverlaySettings = {
                            navController.navigate(SettingsRoutes.InputOverlaySettingsScreenRoute)
                        },
                        goToControllerSettings = { controllerIndex ->
                            navController.navigate(
                                SettingsRoutes.ControllerInputSettingsScreenRoute(
                                    controllerIndex
                                )
                            )
                        },
                    )
                )
            }
        }
        navigation<SettingsRoutes.GeneralSettings>(startDestination = SettingsRoutes.GeneralSettingsScreenRoute) {
            composable<SettingsRoutes.GeneralSettingsScreenRoute> {
                GeneralSettingsScreen(
                    navigateBack = ::navigateBack,
                    goToGamePathsSettings = { navController.navigate(SettingsRoutes.GamePathsScreenRoute) }
                )
            }
            composable<SettingsRoutes.GamePathsScreenRoute> {
                GamePathsScreen(
                    navigateBack = ::navigateBack,
                )
            }
        }
    }
}