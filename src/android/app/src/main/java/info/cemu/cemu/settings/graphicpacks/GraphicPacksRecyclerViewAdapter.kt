package info.cemu.cemu.settings.graphicpacks

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.card.MaterialCardView
import com.google.android.material.textview.MaterialTextView
import info.cemu.cemu.R
import info.cemu.cemu.guibasecomponents.RecyclerViewItem
import java.util.Arrays
import java.util.regex.Pattern
import java.util.stream.Collectors

class GraphicPacksRecyclerViewAdapter(private val onItemClickCallback: OnItemClickCallback) :
    RecyclerView.Adapter<RecyclerView.ViewHolder>() {
    private class GraphicPackSearchItemRecyclerViewItem(
        val dataNode: GraphicPackDataNode,
        private val onClickCallback: OnClickCallback
    ) :
        RecyclerViewItem {
        private class ViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
            var name: MaterialTextView =
                itemView.findViewById(R.id.graphic_pack_search_name)
            var path: MaterialTextView =
                itemView.findViewById(R.id.graphic_pack_search_path)
            var enabledIcon: MaterialCardView =
                itemView.findViewById(R.id.graphic_pack_enabled_icon)
        }

        fun interface OnClickCallback {
            fun onClick()
        }

        val titleIdInstalled: Boolean = dataNode.titleIdInstalled

        override fun onCreateViewHolder(parent: ViewGroup): RecyclerView.ViewHolder {
            return ViewHolder(
                LayoutInflater.from(parent.context)
                    .inflate(R.layout.layout_graphic_pack_search_item, parent, false)
            )
        }

        override fun onBindViewHolder(
            viewHolder: RecyclerView.ViewHolder,
            adapter: RecyclerView.Adapter<RecyclerView.ViewHolder>
        ) {
            val graphicPackViewHolder = viewHolder as ViewHolder
            graphicPackViewHolder.itemView.setOnClickListener { v: View? -> onClickCallback.onClick() }
            graphicPackViewHolder.name.text = dataNode.name
            graphicPackViewHolder.path.text = dataNode.path
            if (dataNode.enabled) {
                graphicPackViewHolder.enabledIcon.visibility = View.VISIBLE
            }
        }
    }

    fun interface OnItemClickCallback {
        fun onClick(graphicPackDataNode: GraphicPackDataNode)
    }

    private var showInstalledGamesOnly = false
    private var filterText = ""

    private var recyclerViewItems: MutableList<GraphicPackSearchItemRecyclerViewItem> = ArrayList()
    private var filteredViewItems: MutableList<GraphicPackSearchItemRecyclerViewItem> = ArrayList()

    fun setShowInstalledOnly(showInstalledGamesOnly: Boolean) {
        this.showInstalledGamesOnly = showInstalledGamesOnly
        filter()
    }

    fun setItems(graphicPackDataNodes: List<GraphicPackDataNode>) {
        clearItems()
        recyclerViewItems = graphicPackDataNodes.stream()
            .sorted(Comparator.comparing(GraphicPackDataNode::path))
            .map { graphicPackDataNode: GraphicPackDataNode ->
                GraphicPackSearchItemRecyclerViewItem(
                    graphicPackDataNode,
                    GraphicPackSearchItemRecyclerViewItem.OnClickCallback {
                        onItemClickCallback.onClick(
                            graphicPackDataNode
                        )
                    }
                )
            }.collect(Collectors.toList())
        filteredViewItems = recyclerViewItems
        if (showInstalledGamesOnly) {
            filteredViewItems = filteredViewItems.stream()
                .filter { g: GraphicPackSearchItemRecyclerViewItem -> g.titleIdInstalled }
                .collect(
                    Collectors.toList()
                )
        }
        notifyItemRangeInserted(0, filteredViewItems.size)
    }

    private fun resetFilteredItems() {
        filteredViewItems = recyclerViewItems
        if (showInstalledGamesOnly) {
            filteredViewItems = filteredViewItems.stream()
                .filter { g: GraphicPackSearchItemRecyclerViewItem -> g.titleIdInstalled }
                .collect(
                    Collectors.toList()
                )
        }
        notifyDataSetChanged()
    }

    fun setFilterText(filterText: String) {
        this.filterText = filterText
        filter()
    }

    fun filter() {
        if (filterText.isBlank()) {
            resetFilteredItems()
            return
        }
        val stringBuilder = StringBuilder()
        val pattern = Arrays.stream(filterText.split(" ".toRegex()).dropLastWhile { it.isEmpty() }
            .toTypedArray())
            .map { s: String? -> "(?=.*" + Pattern.quote(s) + ")" }
            .collect(
                { stringBuilder },
                { obj: StringBuilder, str: String? -> obj.append(str) },
                { obj: StringBuilder, s: StringBuilder? -> obj.append(s) })
            .append(".*")
            .toString()
        val regex = Pattern.compile(pattern, Pattern.CASE_INSENSITIVE)
        var filteredData = recyclerViewItems.stream()
        if (showInstalledGamesOnly) {
            filteredData =
                filteredData.filter { g: GraphicPackSearchItemRecyclerViewItem -> g.titleIdInstalled }
        }
        filteredData = filteredData.filter { g: GraphicPackSearchItemRecyclerViewItem ->
            regex.matcher(g.dataNode.path).matches()
        }
        filteredViewItems = filteredData.collect(Collectors.toList())
        notifyDataSetChanged()
    }

    fun clearItems() {
        if (filteredViewItems.isEmpty()) {
            return
        }
        val itemsCount = filteredViewItems.size
        filteredViewItems.clear()
        recyclerViewItems.clear()
        notifyItemRangeRemoved(0, itemsCount)
    }

    override fun onCreateViewHolder(parent: ViewGroup, position: Int): RecyclerView.ViewHolder {
        return filteredViewItems[position].onCreateViewHolder(parent)
    }

    override fun getItemViewType(position: Int): Int {
        return position
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        filteredViewItems[position].onBindViewHolder(holder, this)
    }

    override fun getItemCount(): Int {
        return filteredViewItems.size
    }
}
