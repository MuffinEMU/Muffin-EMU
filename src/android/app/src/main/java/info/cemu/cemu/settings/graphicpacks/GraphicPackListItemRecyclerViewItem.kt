package info.cemu.cemu.settings.graphicpacks

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.card.MaterialCardView
import com.google.android.material.textview.MaterialTextView
import info.cemu.cemu.R
import info.cemu.cemu.guibasecomponents.RecyclerViewItem

class GraphicPackListItemRecyclerViewItem(
    node: GraphicPackNode,
    private val onClickCallback: OnClickCallback
) :
    RecyclerViewItem {
    private class ViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        var title: MaterialTextView =
            itemView.findViewById(R.id.graphic_pack_text)
        var icon: ImageView =
            itemView.findViewById(R.id.graphic_pack_icon)
        var enabledGraphicPacksCount: MaterialTextView =
            itemView.findViewById(R.id.graphic_pack_enabled_count)
        var enabledIcon: ImageView =
            itemView.findViewById(R.id.graphic_pack_enabled_icon)
        var graphicPackExtraInfo: MaterialCardView =
            itemView.findViewById(R.id.graphic_pack_extra_info)
    }

    fun interface OnClickCallback {
        fun onClick()
    }


    private val text: String?

    @JvmField
    val titleIdInstalled: Boolean
    private val graphicPackNode: GraphicPackNode

    init {
        this.text = node.name
        this.titleIdInstalled = node.titleIdInstalled
        graphicPackNode = node
    }

    override fun onCreateViewHolder(parent: ViewGroup): RecyclerView.ViewHolder {
        return ViewHolder(
            LayoutInflater.from(parent.context)
                .inflate(R.layout.layout_graphic_pack_item, parent, false)
        )
    }

    override fun onBindViewHolder(
        viewHolder: RecyclerView.ViewHolder,
        adapter: RecyclerView.Adapter<RecyclerView.ViewHolder>
    ) {
        val graphicPackViewHolder = viewHolder as ViewHolder
        graphicPackViewHolder.itemView.setOnClickListener { v: View? -> onClickCallback.onClick() }
        graphicPackViewHolder.title.text = text
        if (graphicPackNode is GraphicPackSectionNode) {
            configureGraphicPackSection(graphicPackViewHolder, graphicPackNode)
        } else if (graphicPackNode is GraphicPackDataNode) {
            configureGraphicPack(graphicPackViewHolder, graphicPackNode)
        }
    }

    private fun configureGraphicPackSection(
        viewHolder: ViewHolder,
        sectionNode: GraphicPackSectionNode
    ) {
        viewHolder.icon.setImageResource(R.drawable.ic_lists)
        val enabledGraphicPacksCount = sectionNode.enabledGraphicPacksCount
        if (enabledGraphicPacksCount == 0) {
            return
        }
        val graphicPacksCountText =
            if (enabledGraphicPacksCount >= 100) "99+" else enabledGraphicPacksCount.toString()
        viewHolder.enabledGraphicPacksCount.text = graphicPacksCountText
        viewHolder.enabledGraphicPacksCount.visibility = View.VISIBLE
    }

    private fun configureGraphicPack(viewHolder: ViewHolder, dataNode: GraphicPackDataNode) {
        viewHolder.icon.setImageResource(R.drawable.ic_package_2)
        if (dataNode.enabled) {
            viewHolder.enabledIcon.visibility = View.VISIBLE
        }
    }
}
