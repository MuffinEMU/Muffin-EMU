package info.cemu.cemu.settings.graphicpacks

import android.content.DialogInterface
import android.os.Bundle
import android.view.LayoutInflater
import android.view.Menu
import android.view.MenuInflater
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.widget.SearchView
import androidx.core.view.MenuProvider
import androidx.fragment.app.Fragment
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.navigation.fragment.NavHostFragment
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.snackbar.Snackbar
import info.cemu.cemu.R
import info.cemu.cemu.databinding.LayoutGenericRecyclerViewBinding
import info.cemu.cemu.guibasecomponents.FilterableRecyclerViewAdapter
import info.cemu.cemu.io.Files.delete
import info.cemu.cemu.nativeinterface.NativeGameTitles.installedGamesTitleIds
import info.cemu.cemu.nativeinterface.NativeGraphicPacks.GraphicPackBasicInfo
import info.cemu.cemu.nativeinterface.NativeGraphicPacks.graphicPackBasicInfos
import info.cemu.cemu.nativeinterface.NativeGraphicPacks.refreshGraphicPacks
import info.cemu.cemu.zip.unzip
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Request.Builder
import okhttp3.Response
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Paths
import java.util.Objects
import java.util.Optional
import java.util.function.Consumer
import kotlin.jvm.optionals.getOrNull

class GraphicPacksRootFragment : Fragment(), MenuProvider {
    private var installedOnly = true
    private val installedTitleIds = installedGamesTitleIds
    private val graphicPackSectionRootNode = GraphicPackSectionNode()
    private val genericRecyclerViewAdapter =
        FilterableRecyclerViewAdapter<GraphicPackListItemRecyclerViewItem>()
    private var graphicPackViewModel: GraphicPackViewModel? = null
    private var recyclerView: RecyclerView? = null
    private val graphicPacksRecyclerViewAdapter =
        GraphicPacksRecyclerViewAdapter { graphicPackDataNode: GraphicPackDataNode ->
            graphicPackViewModel!!.graphicPackNode = graphicPackDataNode
            val bundle = Bundle()
            bundle.putString("title", graphicPackDataNode.name)
            NavHostFragment.findNavController(this@GraphicPacksRootFragment)
                .navigate(R.id.action_graphicPacksRootFragment_to_graphicPacksFragment, bundle)
        }
    private val client = OkHttpClient()
    private var updateInProgress = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        genericRecyclerViewAdapter.setPredicate { g: GraphicPackListItemRecyclerViewItem -> g.titleIdInstalled }
        graphicPacksRecyclerViewAdapter.setShowInstalledOnly(this.installedOnly)
        fillGraphicPacks()
        val navController = NavHostFragment.findNavController(this@GraphicPacksRootFragment)
        graphicPackViewModel =
            ViewModelProvider(navController.currentBackStackEntry!!)
                .get(GraphicPackViewModel::class.java)
    }

    override fun onCreateMenu(menu: Menu, menuInflater: MenuInflater) {
        menuInflater.inflate(R.menu.graphic_packs, menu)
        val searchMenuItem = menu.findItem(R.id.action_graphic_packs_search)
        menu.findItem(R.id.show_installed_games_only).setChecked(installedOnly)
        val searchView = Objects.requireNonNull(searchMenuItem.actionView) as SearchView
        searchView.setOnQueryTextListener(object : SearchView.OnQueryTextListener {
            override fun onQueryTextSubmit(query: String): Boolean {
                graphicPacksRecyclerViewAdapter.setFilterText(query)
                return true
            }

            override fun onQueryTextChange(newText: String): Boolean {
                graphicPacksRecyclerViewAdapter.setFilterText(newText)
                return true
            }
        })
        searchMenuItem.setOnActionExpandListener(object : MenuItem.OnActionExpandListener {
            override fun onMenuItemActionExpand(item: MenuItem): Boolean {
                if (recyclerView == null) {
                    return true
                }
                recyclerView!!.adapter = graphicPacksRecyclerViewAdapter
                return true
            }

            override fun onMenuItemActionCollapse(item: MenuItem): Boolean {
                if (recyclerView == null) {
                    return true
                }
                recyclerView!!.adapter = genericRecyclerViewAdapter
                return true
            }
        })
    }

    private fun showInstalledOnly(installedOnly: Boolean) {
        this.installedOnly = installedOnly
        if (installedOnly) {
            genericRecyclerViewAdapter.setPredicate { g: GraphicPackListItemRecyclerViewItem -> g.titleIdInstalled }
            return
        }
        genericRecyclerViewAdapter.clearPredicate()
    }

    override fun onMenuItemSelected(menuItem: MenuItem): Boolean {
        if (menuItem.itemId == R.id.action_graphic_packs_download && !updateInProgress) {
            checkForUpdates()
            return true
        }
        if (menuItem.itemId == R.id.action_graphic_packs_search) {
            return true
        }
        if (menuItem.itemId == R.id.show_installed_games_only) {
            val installedOnly = !menuItem.isChecked
            graphicPacksRecyclerViewAdapter.setShowInstalledOnly(installedOnly)
            menuItem.setChecked(installedOnly)
            showInstalledOnly(installedOnly)
            return true
        }
        return false
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        val binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false)
        recyclerView = binding.recyclerView
        recyclerView!!.adapter = genericRecyclerViewAdapter
        requireActivity().addMenuProvider(this, viewLifecycleOwner, Lifecycle.State.RESUMED)
        return binding.root
    }

    private fun setDataNodes(
        graphicPackDataNodes: MutableList<GraphicPackDataNode>,
        graphicPackSectionNode: GraphicPackSectionNode
    ) {
        for (node in graphicPackSectionNode.children) {
            if (node is GraphicPackSectionNode) {
                setDataNodes(graphicPackDataNodes, node)
            } else if (node is GraphicPackDataNode) {
                graphicPackDataNodes.add(node)
            }
        }
    }

    private fun fillGraphicPacks() {
        val nativeGraphicPacks = graphicPackBasicInfos
        graphicPackSectionRootNode.clear()
        val graphicPackDataNodes: MutableList<GraphicPackDataNode> = ArrayList()
        nativeGraphicPacks!!.forEach(Consumer { graphicPack: GraphicPackBasicInfo? ->
            val hasTitleIdInstalled = graphicPack!!.titleIds.stream()
                .anyMatch { o: Long? -> installedTitleIds!!.contains(o) }
            graphicPackSectionRootNode.addGraphicPackDataByTokens(graphicPack, hasTitleIdInstalled)
        })

        setDataNodes(graphicPackDataNodes, graphicPackSectionRootNode)
        graphicPacksRecyclerViewAdapter.setItems(graphicPackDataNodes)

        genericRecyclerViewAdapter.clearRecyclerViewItems()
        graphicPackSectionRootNode.sort()
        graphicPackSectionRootNode.children.forEach(Consumer { node: GraphicPackNode ->
            val graphicPackItemRecyclerViewItem = GraphicPackListItemRecyclerViewItem(
                node
            ) {
                graphicPackViewModel!!.graphicPackNode = node
                val bundle = Bundle()
                bundle.putString("title", node.name)
                NavHostFragment.findNavController(this@GraphicPacksRootFragment)
                    .navigate(R.id.action_graphicPacksRootFragment_to_graphicPacksFragment, bundle)
            }
            genericRecyclerViewAdapter.addRecyclerViewItem(graphicPackItemRecyclerViewItem)
        })
    }

    private fun checkForUpdates() {
        val dialog = createGraphicPacksDownloadDialog()
        requireActivity().runOnUiThread {
            (dialog.findViewById<View>(R.id.textViewGraphicPacksDownload) as TextView)
                .setText(R.string.checking_version_download_text)
        }
        val request: Request = Builder()
            .url(RELEASES_API_URL)
            .build()
        requireActivity().runOnUiThread {
            (dialog.findViewById<View>(R.id.textViewGraphicPacksDownload) as TextView)
                .setText(R.string.graphic_packs_download_text)
        }
        client.newCall(request).enqueue(object : Callback {
            @Throws(IOException::class)
            override fun onResponse(call: Call, response: Response) {
                try {
                    response.body?.use { responseBody ->
                        val json = JSONObject(Objects.requireNonNull(responseBody).string())
                        val version = json.getString("name")
                        if (currentVersion.getOrNull() == version) {
                            onGraphicPacksLatestVersion(dialog)
                            return
                        }
                        val downloadUrl = json.getJSONArray("assets")
                            .getJSONObject(0)
                            .getString("browser_download_url")
                        downloadNewUpdate(downloadUrl, version, dialog)
                    }
                } catch (e: JSONException) {
                    requireActivity().runOnUiThread { dialog.dismiss() }
                }
            }

            override fun onFailure(call: Call, e: IOException) {
                if (!call.isCanceled()) {
                    onDownloadError(dialog)
                }
            }
        })
    }

    private val currentVersion: Optional<String>
        get() {
            val graphicPacksVersionFile = Paths.get(
                requireActivity().getExternalFilesDir(
                    null
                )!!.absolutePath,
                "graphicPacks",
                "downloadedGraphicPacks",
                "version.txt"
            )
            return try {
                Optional.of(
                    String(
                        Files.readAllBytes(
                            graphicPacksVersionFile
                        )
                    )
                )
            } catch (ignored: IOException) {
                Optional.empty()
            }
        }

    private fun downloadNewUpdate(
        graphicPacksZipDownloadUrl: String,
        version: String,
        dialog: AlertDialog
    ) {
        val request: Request = Builder()
            .url(graphicPacksZipDownloadUrl)
            .build()

        val graphicPacksDirPath = Paths.get(
            requireActivity().getExternalFilesDir(null)!!.absolutePath,
            "graphicPacks"
        )
        client.newCall(request).enqueue(object : Callback {
            @Throws(IOException::class)
            override fun onResponse(call: Call, response: Response) {
                response.body?.use { responseBody ->
                    val graphicPacksTempDirPath =
                        graphicPacksDirPath.resolve("downloadedGraphicPacksTemp")
                    delete(graphicPacksTempDirPath.toFile())
                    unzip(
                        responseBody.byteStream(),
                        graphicPacksTempDirPath.toString()
                    )
                    Files.write(
                        graphicPacksTempDirPath.resolve("version.txt"), version.toByteArray(
                            StandardCharsets.UTF_8
                        )
                    )
                    val downloadedGraphicPacksDirPath =
                        graphicPacksDirPath.resolve("downloadedGraphicPacks")
                    delete(downloadedGraphicPacksDirPath.toFile())
                    Files.move(graphicPacksTempDirPath, downloadedGraphicPacksDirPath)
                    refreshGraphicPacks()
                    requireActivity().runOnUiThread { fillGraphicPacks() }
                    onDownloadFinish(dialog)
                }
            }

            override fun onFailure(call: Call, e: IOException) {
                if (!call.isCanceled()) {
                    onDownloadError(dialog)
                }
            }
        })
    }

    private fun onDownloadError(dialog: AlertDialog) {
        requireActivity().runOnUiThread {
            dialog.dismiss()
            Snackbar.make(
                requireView(),
                R.string.download_graphic_packs_error_text,
                Snackbar.LENGTH_SHORT
            ).show()
        }
    }

    private fun onDownloadFinish(dialog: AlertDialog) {
        requireActivity().runOnUiThread {
            dialog.dismiss()
            Snackbar.make(
                requireView(),
                R.string.download_graphic_packs_finish_text,
                Snackbar.LENGTH_SHORT
            ).show()
        }
    }

    private fun onGraphicPacksLatestVersion(dialog: AlertDialog) {
        requireActivity().runOnUiThread {
            dialog.dismiss()
            Snackbar.make(
                requireView(),
                R.string.graphic_packs_no_updates_text,
                Snackbar.LENGTH_SHORT
            ).show()
        }
    }

    private fun createGraphicPacksDownloadDialog(): AlertDialog {
        updateInProgress = true
        return MaterialAlertDialogBuilder(requireContext()).setView(R.layout.layout_graphic_packs_download)
            .setTitle(R.string.graphic_packs_download_dialog_title)
            .setCancelable(false)
            .setOnDismissListener { d: DialogInterface? -> updateInProgress = false }
            .setNegativeButton(
                R.string.cancel
            ) { dialogInterface: DialogInterface?, i: Int -> client.dispatcher.cancelAll() }
            .show()
    }

    override fun onDestroy() {
        client.dispatcher.cancelAll()
        super.onDestroy()
    }

    companion object {
        private const val RELEASES_API_URL =
            "https://api.github.com/repos/cemu-project/cemu_graphic_packs/releases/latest"
    }
}