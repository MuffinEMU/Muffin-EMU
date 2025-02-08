package info.cemu.cemu.graphicpacks

import androidx.compose.animation.AnimatedContentScope
import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.MutableCreationExtras
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavController
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.compose.composable
import androidx.navigation.compose.navigation
import kotlinx.serialization.Serializable

@Serializable
object GraphicPacksRoute

private object GraphicPackRoutes {
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

private fun graphicPacksNavigate(navController: NavController, graphicPackNode: GraphicPackNode) {
    when (graphicPackNode) {
        is GraphicPackSectionNode -> navController.navigate(GraphicPackRoutes.GraphicPackSectionScreenRoute)
        is GraphicPackDataNode -> navController.navigate(GraphicPackRoutes.GraphicPackDataScreenRoute)
    }
}

fun NavGraphBuilder.graphicPacksNavigation(navController: NavHostController) {
    navigation<GraphicPacksRoute>(startDestination = GraphicPackRoutes.GraphicPacksRootSectionRoute) {
        composable<GraphicPackRoutes.GraphicPacksRootSectionRoute> { backStackEntry ->
            val graphicPackViewModel: GraphicPackViewModel = viewModel(backStackEntry)
            GraphicPacksRootSectionScreen(
                navigateBack = { navController.popBackStack() },
                graphicPackNodeNavigate = {
                    graphicPackViewModel.graphicPackNode = it
                    graphicPacksNavigate(navController, it)
                }
            )
        }
        composableNestedGraphicPacks<GraphicPackRoutes.GraphicPackSectionScreenRoute, GraphicPackSectionNode>(
            navController
        ) { backStackEntry, graphicPackNode ->
            val graphicPacksViewModel: GraphicPackViewModel = viewModel(backStackEntry)
            GraphicPacksSectionScreen(
                navigateBack = { navController.popBackStack() },
                graphicPackNodeNavigate = {
                    graphicPacksViewModel.graphicPackNode = it
                    graphicPacksNavigate(navController, it)
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
                navigateBack = { navController.popBackStack() },
                graphicPackDataViewModel = graphicPackDataViewModel,
            )
        }
    }
}