package info.cemu.cemu.guibasecomponents

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.materialswitch.MaterialSwitch
import info.cemu.cemu.R

class ToggleRecyclerViewItem(
    private val label: String,
    private val description: String,
    private var checked: Boolean,
    private val onCheckedChangeListener: OnCheckedChangeListener?
) :
    RecyclerViewItem {
    fun interface OnCheckedChangeListener {
        fun onCheckChanged(checked: Boolean)
    }

    private class ToggleViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        var label: TextView =
            itemView.findViewById(R.id.toggle_label)
        var description: TextView =
            itemView.findViewById(R.id.toggle_description)
        var toggle: MaterialSwitch = itemView.findViewById(R.id.toggle)
    }

    override fun onCreateViewHolder(parent: ViewGroup): RecyclerView.ViewHolder {
        return ToggleViewHolder(
            LayoutInflater.from(parent.context).inflate(R.layout.layout_toggle, parent, false)
        )
    }

    override fun onBindViewHolder(
        viewHolder: RecyclerView.ViewHolder,
        adapter: RecyclerView.Adapter<RecyclerView.ViewHolder>
    ) {
        val toggleViewHolder = viewHolder as ToggleViewHolder
        toggleViewHolder.label.text = label
        toggleViewHolder.description.text = description
        toggleViewHolder.toggle.isChecked = checked
        toggleViewHolder.itemView.setOnClickListener { view: View? ->
            checked = !toggleViewHolder.toggle.isChecked
            toggleViewHolder.toggle.isChecked = checked
            onCheckedChangeListener?.onCheckChanged(checked)
        }
    }
}
