package info.cemu.cemu.guibasecomponents

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.checkbox.MaterialCheckBox
import info.cemu.cemu.R

class CheckboxRecyclerViewItem(
    private val label: String,
    private val description: String,
    private var checked: Boolean,
    private val onCheckedChangeListener: OnCheckedChangeListener?
) :
    RecyclerViewItem {
    interface OnCheckedChangeListener {
        fun onCheckChanged(checked: Boolean)
    }

    private class CheckBoxViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        var label: TextView =
            itemView.findViewById(R.id.checkbox_label)
        var description: TextView =
            itemView.findViewById(R.id.checkbox_description)
        var checkBox: MaterialCheckBox = itemView.findViewById(R.id.checkbox)
    }

    override fun onCreateViewHolder(parent: ViewGroup): RecyclerView.ViewHolder {
        return CheckBoxViewHolder(
            LayoutInflater.from(parent.context).inflate(R.layout.layout_checkbox, parent, false)
        )
    }

    override fun onBindViewHolder(
        viewHolder: RecyclerView.ViewHolder,
        adapter: RecyclerView.Adapter<RecyclerView.ViewHolder>
    ) {
        val checkBoxViewHolder = viewHolder as CheckBoxViewHolder
        checkBoxViewHolder.label.text = label
        checkBoxViewHolder.description.text = description
        checkBoxViewHolder.checkBox.isChecked = checked
        checkBoxViewHolder.itemView.setOnClickListener { view: View? ->
            checked = !checkBoxViewHolder.checkBox.isChecked
            checkBoxViewHolder.checkBox.isChecked = checked
            onCheckedChangeListener?.onCheckChanged(checked)
        }
    }
}
