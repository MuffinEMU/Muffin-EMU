package info.cemu.cemu.settings.gamespath

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.Menu
import android.view.MenuInflater
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.activity.result.ActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.view.MenuProvider
import androidx.documentfile.provider.DocumentFile
import androidx.fragment.app.Fragment
import androidx.lifecycle.Lifecycle
import info.cemu.cemu.R
import info.cemu.cemu.databinding.LayoutGenericRecyclerViewBinding
import info.cemu.cemu.nativeinterface.NativeSettings
import info.cemu.cemu.nativeinterface.NativeSettings.addGamesPath
import info.cemu.cemu.nativeinterface.NativeSettings.removeGamesPath
import info.cemu.cemu.settings.gamespath.GamePathAdapter.OnRemoveGamePath
import java.util.Objects
import java.util.stream.Collectors
import java.util.stream.Stream

class GamePathsFragment : Fragment() {
    private var folderSelectionLauncher: ActivityResultLauncher<Intent>? = null
    private var gamePathAdapter: GamePathAdapter? = null
    private var gamesPaths: List<String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        folderSelectionLauncher = registerForActivityResult<Intent, ActivityResult>(
            ActivityResultContracts.StartActivityForResult()
        ) { result: ActivityResult ->
            if (result.resultCode != Activity.RESULT_OK) {
                return@registerForActivityResult
            }
            val data = result.data ?: return@registerForActivityResult
            val uri = data.data!!
            requireActivity().contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            val documentFile = DocumentFile.fromTreeUri(requireContext(), uri)
                ?: return@registerForActivityResult
            val gamesPath = documentFile.uri.toString()
            if (gamesPaths!!.stream().anyMatch { p: String -> p == gamesPath }) {
                Toast.makeText(
                    requireContext(),
                    R.string.game_path_already_added,
                    Toast.LENGTH_LONG
                ).show()
                return@registerForActivityResult
            }
            addGamesPath(gamesPath)
            gamesPaths = Stream.concat(
                Stream.of(gamesPath), gamesPaths!!.stream()
            )
                .collect(Collectors.toList())
            gamePathAdapter!!.submitList(gamesPaths)
        }
        gamePathAdapter = GamePathAdapter { path: String ->
            removeGamesPath(path)
            gamesPaths = gamesPaths!!.filter { p: String -> p != path }
            gamePathAdapter!!.submitList(gamesPaths)
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false)
        binding.recyclerView.adapter = gamePathAdapter
        gamesPaths = NativeSettings.gamesPaths
        gamePathAdapter!!.submitList(gamesPaths)
        requireActivity().addMenuProvider(object : MenuProvider {
            override fun onCreateMenu(menu: Menu, menuInflater: MenuInflater) {
                menuInflater.inflate(R.menu.game_paths, menu)
            }

            override fun onMenuItemSelected(menuItem: MenuItem): Boolean {
                if (menuItem.itemId == R.id.action_add_game_path) {
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    folderSelectionLauncher!!.launch(intent)
                    return true
                }
                return false
            }
        }, viewLifecycleOwner, Lifecycle.State.RESUMED)
        return binding.root
    }
}