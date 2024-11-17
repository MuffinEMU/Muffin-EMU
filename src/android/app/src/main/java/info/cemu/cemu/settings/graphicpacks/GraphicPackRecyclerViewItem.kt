package info.cemu.cemu.settings.graphicpacks

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.CompoundButton
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.materialswitch.MaterialSwitch
import info.cemu.cemu.R
import info.cemu.cemu.guibasecomponents.RecyclerViewItem
import info.cemu.cemu.nativeinterface.NativeGraphicPacks.GraphicPack

class GraphicPackRecyclerViewItem(
    private val graphicPack: GraphicPack,
    private val onCheckedChangeListener: OnCheckedChangeListener?
) :
    RecyclerViewItem {
    private class GraphicPackViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        var name: TextView =
            itemView.findViewById(R.id.graphic_pack_name)
        var enableToggle: MaterialSwitch =
            itemView.findViewById(R.id.graphic_pack_enable_toggle)
        var description: TextView =
            itemView.findViewById(R.id.graphic_pack_description)
    }

    fun interface OnCheckedChangeListener {
        fun onCheckedChange(checked: Boolean)
    }

    override fun onCreateViewHolder(parent: ViewGroup): RecyclerView.ViewHolder {
        return GraphicPackViewHolder(
            LayoutInflater.from(parent.context).inflate(R.layout.layout_graphic_pack, parent, false)
        )
    }

    override fun onBindViewHolder(
        viewHolder: RecyclerView.ViewHolder,
        recyclerViewAdapter: RecyclerView.Adapter<RecyclerView.ViewHolder>
    ) {
        val graphicPackViewHolder = viewHolder as GraphicPackViewHolder
        graphicPackViewHolder.name.text = graphicPack.name
        if (graphicPack.description != null) {
            graphicPackViewHolder.description.text = graphicPack.description
        } else {
            graphicPackViewHolder.description.setText(R.string.graphic_pack_no_description)
        }
        graphicPackViewHolder.enableToggle.isChecked = graphicPack.isActive()
        graphicPackViewHolder.enableToggle.setOnCheckedChangeListener { materialCheckBox: CompoundButton?, isChecked: Boolean ->
            graphicPack.setActive(isChecked)
            onCheckedChangeListener?.onCheckedChange(isChecked)
        }
    }
}
