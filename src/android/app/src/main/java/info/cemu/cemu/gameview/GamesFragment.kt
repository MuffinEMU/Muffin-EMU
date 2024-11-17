package info.cemu.cemu.gameview

import android.app.PendingIntent
import android.content.DialogInterface
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.Color
import android.graphics.drawable.Icon
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.ContextMenu
import android.view.ContextMenu.ContextMenuInfo
import android.view.LayoutInflater
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.appcompat.widget.SearchView
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.navigation.fragment.NavHostFragment
import com.google.android.material.color.MaterialColors
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import info.cemu.cemu.R
import info.cemu.cemu.databinding.FragmentGamesBinding
import info.cemu.cemu.emulation.EmulationActivity
import info.cemu.cemu.gameview.GameAdapter.GameTitleClickAction
import info.cemu.cemu.nativeinterface.NativeGameTitles.Game
import info.cemu.cemu.nativeinterface.NativeGameTitles.reloadGameTitles
import info.cemu.cemu.nativeinterface.NativeGameTitles.removeShaderCacheFilesForTitle
import info.cemu.cemu.nativeinterface.NativeGameTitles.titleHasShaderCacheFiles
import info.cemu.cemu.nativeinterface.NativeSettings.gamesPaths
import info.cemu.cemu.settings.SettingsActivity
import java.util.Objects

class GamesFragment : Fragment() {
    private var gameAdapter: GameAdapter? = null
    private var gameListViewModel: GameListViewModel? = null
    private var gameViewModel: GameViewModel? = null
    private var refreshing = false
    private val handler = Handler(Looper.getMainLooper())
    private var currentGamePaths = HashSet<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        currentGamePaths = HashSet(gamesPaths)
        gameAdapter = GameAdapter { game: Game ->
            val intent = Intent(
                requireContext(),
                EmulationActivity::class.java
            )
            intent.putExtra(EmulationActivity.EXTRA_LAUNCH_PATH, game.path)
            startActivity(intent)
        }
        gameListViewModel = ViewModelProvider(this).get(
            GameListViewModel::class.java
        )
        gameViewModel = ViewModelProvider(requireActivity()).get(GameViewModel::class.java)
        gameListViewModel!!.getGames()
            .observe(this) { gameList: List<Game>? -> gameAdapter!!.submitList(gameList) }
        reloadGameTitles()
    }

    override fun onResume() {
        super.onResume()
        val gamePaths = HashSet(gamesPaths)
        if (currentGamePaths != gamePaths) {
            currentGamePaths = gamePaths
            reloadGameTitles()
        }
        gameAdapter!!.setFilterText(null)
    }

    override fun onCreateContextMenu(menu: ContextMenu, v: View, menuInfo: ContextMenuInfo?) {
        super.onCreateContextMenu(menu, v, menuInfo)
        val inflater = requireActivity().menuInflater
        inflater.inflate(R.menu.game, menu)
        val selectedGame = gameAdapter!!.selectedGame ?: return
        menu.findItem(R.id.favorite).setChecked(selectedGame.isFavorite)
        menu.findItem(R.id.remove_shader_caches)
            .setEnabled(titleHasShaderCacheFiles(selectedGame.titleId))
    }

    override fun onContextItemSelected(item: MenuItem): Boolean {
        val game = gameAdapter!!.selectedGame ?: return super.onContextItemSelected(item)
        val itemId = item.itemId
        if (itemId == R.id.favorite) {
            gameListViewModel!!.setGameTitleFavorite(game, !game.isFavorite)
            return true
        }
        if (itemId == R.id.game_profile) {
            gameViewModel!!.game = game
            NavHostFragment.findNavController(this)
                .navigate(R.id.action_games_fragment_to_game_edit_profile)
            return true
        }
        if (itemId == R.id.remove_shader_caches) {
            removeShaderCachesForGame(game)
            return true
        }
        if (itemId == R.id.about_title) {
            gameViewModel!!.game = game
            NavHostFragment.findNavController(this)
                .navigate(R.id.action_games_fragment_to_game_details_fragment)
            return true
        }
        if (itemId == R.id.create_shortcut) {
            createShortcutForGame(game)
            return true
        }
        return super.onContextItemSelected(item)
    }

    private fun createShortcutForGame(game: Game) {
        val context = requireContext()
        val shortcutManager = context.getSystemService(
            ShortcutManager::class.java
        )
        if (!shortcutManager.isRequestPinShortcutSupported) {
            Toast.makeText(context, R.string.shortcut_not_supported, Toast.LENGTH_SHORT).show()
            return
        }
        if (game.icon == null) {
            return
        }
        val intent = Intent(
            requireContext(),
            EmulationActivity::class.java
        )
        intent.setAction(Intent.ACTION_VIEW)
        intent.putExtra(EmulationActivity.EXTRA_LAUNCH_PATH, game.path)
        val pinShortcutInfo = ShortcutInfo.Builder(context, game.titleId.toString())
            .setShortLabel(game.name!!)
            .setIntent(intent)
            .setIcon(Icon.createWithBitmap(game.icon))
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

    private fun removeShaderCachesForGame(game: Game) {
        val builder = MaterialAlertDialogBuilder(requireContext())
        builder.setTitle(R.string.remove_shader_caches)
            .setMessage(getString(R.string.remove_shader_caches_message, game.name))
            .setPositiveButton(R.string.yes) { dialog: DialogInterface?, which: Int ->
                removeShaderCacheFilesForTitle(game.titleId)
                Toast.makeText(
                    requireContext(),
                    R.string.shader_caches_removed_notification,
                    Toast.LENGTH_SHORT
                ).show()
            }
            .setNegativeButton(
                R.string.no
            ) { dialog: DialogInterface, which: Int -> dialog.dismiss() }
            .show()
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val binding = FragmentGamesBinding.inflate(inflater, container, false)
        val recyclerView = binding.gamesRecyclerView
        registerForContextMenu(recyclerView)
        binding.settingsButton.setOnClickListener { v: View? ->
            val intent = Intent(
                requireActivity(),
                SettingsActivity::class.java
            )
            startActivity(intent)
        }
        binding.searchBar.inflateMenu(R.menu.game_list)
        val searchMenuItem = binding.searchBar.menu.findItem(R.id.action_search)
        binding.searchBar.setOnClickListener { v: View? -> searchMenuItem.expandActionView() }
        val searchView = Objects.requireNonNull(searchMenuItem.actionView) as SearchView
        val searchPlate = searchView.findViewById<View>(androidx.appcompat.R.id.search_plate)
        searchPlate?.setBackgroundColor(Color.TRANSPARENT)
        searchView.queryHint = getString(R.string.search_games)
        searchView.setOnQueryTextListener(object : SearchView.OnQueryTextListener {
            override fun onQueryTextSubmit(query: String): Boolean {
                gameAdapter!!.setFilterText(query)
                return true
            }

            override fun onQueryTextChange(newText: String): Boolean {
                gameAdapter!!.setFilterText(newText)
                return true
            }
        })

        binding.gamesSwipeRefresh.setOnRefreshListener {
            if (refreshing) {
                return@setOnRefreshListener
            }
            refreshing = true
            handler.postDelayed({
                binding.gamesSwipeRefresh.isRefreshing = false
                refreshing = false
            }, 1000)
            gameListViewModel!!.refreshGames()
        }
        binding.gamesSwipeRefresh.setColorSchemeColors(
            MaterialColors.getColor(
                requireContext(),
                com.google.android.material.R.attr.colorOnSurfaceVariant,
                Color.BLACK
            )
        )
        binding.gamesSwipeRefresh.setProgressBackgroundColorSchemeColor(
            MaterialColors.getColor(
                requireContext(),
                com.google.android.material.R.attr.colorSurfaceVariant,
                Color.WHITE
            )
        )
        recyclerView.adapter = gameAdapter

        return binding.root
    }
}