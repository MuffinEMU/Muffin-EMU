package info.cemu.cemu.graphicpacks

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.AnimatedContentScope
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.MutableCreationExtras
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavController
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import info.cemu.cemu.guicore.ActivityContent
import info.cemu.cemu.nativeinterface.NativeSettings
import kotlinx.serialization.Serializable

class GraphicPacksActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            ActivityContent {
                GraphicPacksNav(parentNavBack = ::onNavigateUp)
            }
        }
    }

    override fun onPause() {
        super.onPause()
        NativeSettings.saveSettings()
    }
}

object GraphicPackRoutes {
    @Serializable
    object GraphicPacksRootSectionRoute

    @Serializable
    object GraphicPackSectionScreenRoute

    @Serializable
    object GraphicPackDataScreenRoute
}

private inline fun <reified T : Any, reified U : GraphicPackNode> NavGraphBuilder.composableNestedGraphicPacks(
    navController: NavController,
    noinline content: @Composable (AnimatedContentScope.(NavBackStackEntry, U) -> Unit),
) {
    composable<T> { backStackEntry ->
        val previousBackStackEntry =
            navController.previousBackStackEntry ?: return@composable
        val graphicPackNode =
            viewModel<GraphicPackViewModel>(previousBackStackEntry).graphicPackNode
        if (graphicPackNode == null || graphicPackNode !is U) {
            return@composable
        }
        content(backStackEntry, graphicPackNode)
    }
}

@Composable
fun GraphicPacksNav(
    parentNavBack: () -> Unit,
) {
    val navController = rememberNavController()

    fun navigateBack() {
        if (!navController.popBackStack()) {
            parentNavBack()
        }
    }

    fun graphicPacksNavigate(graphicPackNode: GraphicPackNode) {
        when (graphicPackNode) {
            is GraphicPackSectionNode -> navController.navigate(GraphicPackRoutes.GraphicPackSectionScreenRoute)
            is GraphicPackDataNode -> navController.navigate(GraphicPackRoutes.GraphicPackDataScreenRoute)
        }
    }

    NavHost(
        navController = navController,
        startDestination = GraphicPackRoutes.GraphicPacksRootSectionRoute,
        enterTransition = {
            EnterTransition.None
        },
        exitTransition = {
            ExitTransition.None
        }
    ) {
        composable<GraphicPackRoutes.GraphicPacksRootSectionRoute> { backStackEntry ->
            val graphicPackViewModel: GraphicPackViewModel = viewModel(backStackEntry)
            GraphicPacksRootSectionScreen(
                navigateBack = ::navigateBack,
                graphicPackNodeNavigate = {
                    graphicPackViewModel.graphicPackNode = it
                    graphicPacksNavigate(it)
                }
            )
        }
        composableNestedGraphicPacks<GraphicPackRoutes.GraphicPackSectionScreenRoute, GraphicPackSectionNode>(
            navController
        ) { backStackEntry, graphicPackNode ->
            val graphicPacksViewModel: GraphicPackViewModel = viewModel(backStackEntry)
            GraphicPacksSectionScreen(
                navigateBack = ::navigateBack,
                graphicPackNodeNavigate = {
                    graphicPacksViewModel.graphicPackNode = it
                    graphicPacksNavigate(it)
                },
                graphicPackSectionNode = graphicPackNode,
            )
        }
        composableNestedGraphicPacks<GraphicPackRoutes.GraphicPackDataScreenRoute, GraphicPackDataNode>(
            navController
        ) { backStackEntry, graphicPackNode ->
            val graphicPackDataViewModel: GraphicPackDataViewModel = viewModel(
                viewModelStoreOwner = backStackEntry,
                factory = GraphicPackDataViewModel.Factory,
                extras = MutableCreationExtras().apply {
                    set(GraphicPackDataViewModel.GRAPHIC_PACK_KEY, graphicPackNode)
                }
            )
            GraphicPackDataScreen(
                navigateBack = ::navigateBack,
                graphicPackDataViewModel = graphicPackDataViewModel,
            )
        }
    }
}