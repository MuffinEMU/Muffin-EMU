package info.cemu.cemu.settings.graphicpacks

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.navigation.fragment.NavHostFragment
import info.cemu.cemu.R
import info.cemu.cemu.databinding.LayoutGenericRecyclerViewBinding
import info.cemu.cemu.guibasecomponents.GenericRecyclerViewAdapter
import info.cemu.cemu.guibasecomponents.SingleSelectionRecyclerViewItem
import info.cemu.cemu.guibasecomponents.StringSelectionAdapter
import info.cemu.cemu.nativeinterface.NativeGraphicPacks.GraphicPack
import info.cemu.cemu.nativeinterface.NativeGraphicPacks.getGraphicPack
import java.util.Objects
import java.util.function.Consumer
import java.util.stream.IntStream

class GraphicPacksFragment : Fragment() {
    private val genericRecyclerViewAdapter = GenericRecyclerViewAdapter()
    private var graphicPackPreviousViewModel: GraphicPackViewModel? = null
    private var graphicPackCurrentViewModel: GraphicPackViewModel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val navController = NavHostFragment.findNavController(this)
        graphicPackPreviousViewModel =
            ViewModelProvider(navController.previousBackStackEntry!!)
                .get(GraphicPackViewModel::class.java)
        graphicPackCurrentViewModel =
            ViewModelProvider(navController.currentBackStackEntry!!)
                .get(GraphicPackViewModel::class.java)
        fillData()
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false)
        binding.recyclerView.adapter = genericRecyclerViewAdapter

        return binding.root
    }

    private fun fillData() {
        val graphicNode = graphicPackPreviousViewModel!!.graphicPackNode
        if (graphicNode is GraphicPackSectionNode) {
            fillData(graphicNode)
        } else if (graphicNode is GraphicPackDataNode) {
            fillData(graphicNode)
        }
    }

    private fun fillData(graphicPackSectionNode: GraphicPackSectionNode) {
        graphicPackSectionNode.children.forEach(Consumer { node: GraphicPackNode ->
            val graphicPackItemRecyclerViewItem = GraphicPackListItemRecyclerViewItem(node,
                GraphicPackListItemRecyclerViewItem.OnClickCallback {
                    graphicPackCurrentViewModel!!.graphicPackNode = node
                    val bundle = Bundle()
                    bundle.putString("title", node.name)
                    NavHostFragment.findNavController(this@GraphicPacksFragment)
                        .navigate(R.id.action_graphicPacksFragment_self, bundle)
                })
            genericRecyclerViewAdapter.addRecyclerViewItem(graphicPackItemRecyclerViewItem)
        })
    }

    private fun fillData(graphicPackDataNode: GraphicPackDataNode) {
        genericRecyclerViewAdapter.clearRecyclerViewItems()
        val graphicPack = getGraphicPack(graphicPackDataNode.id)
        genericRecyclerViewAdapter.addRecyclerViewItem(
            GraphicPackRecyclerViewItem(
                graphicPack!!
            ) { enabled: Boolean ->
                graphicPackDataNode.enabled = enabled
            }
        )
        fillPresets(graphicPack)
    }

    private fun fillPresets(graphicPack: GraphicPack) {
        val recyclerViewItems = ArrayList<SingleSelectionRecyclerViewItem<String>>()
        IntStream.range(0, graphicPack.getPresets().size).forEach { index: Int ->
            val graphicPackPreset = graphicPack.getPresets()[index]
            var category = graphicPackPreset.category
            if (category == null) {
                category = getString(R.string.active_preset_category)
            }
            val recyclerViewItem = SingleSelectionRecyclerViewItem<String>(
                category,
                graphicPackPreset.getActivePreset(),
                StringSelectionAdapter(
                    graphicPackPreset.presets,
                    graphicPackPreset.getActivePreset()
                )
            ) { selectedValue: String?, selectionRecyclerViewItem: SingleSelectionRecyclerViewItem<String> ->
                val oldPresets = graphicPack.getPresets()
                graphicPack.getPresets()[index].setActivePreset(selectedValue!!)
                selectionRecyclerViewItem.setDescription(selectedValue)
                graphicPack.reloadPresets()
                if (oldPresets != graphicPack.getPresets()) {
                    recyclerViewItems.forEach(Consumer { recyclerViewItem: SingleSelectionRecyclerViewItem<String>? ->
                        genericRecyclerViewAdapter.removeRecyclerViewItem(
                            recyclerViewItem!!
                        )
                    })
                    fillPresets(graphicPack)
                }
            }
            recyclerViewItems.add(recyclerViewItem)
            genericRecyclerViewAdapter.addRecyclerViewItem(recyclerViewItem)
        }
    }
}