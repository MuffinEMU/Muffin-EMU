package info.cemu.cemu.guibasecomponents

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import info.cemu.cemu.R

class ButtonRecyclerViewItem(
    private val text: String,
    private val description: String,
    private val onButtonClickListener: OnButtonClickListener?
) :
    RecyclerViewItem {
    fun interface OnButtonClickListener {
        fun onButtonClick()
    }

    private class ButtonViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        var text: TextView =
            itemView.findViewById(R.id.button_text)
        var description: TextView =
            itemView.findViewById(R.id.button_description)
    }

    override fun onCreateViewHolder(parent: ViewGroup): RecyclerView.ViewHolder {
        return ButtonViewHolder(
            LayoutInflater.from(parent.context).inflate(R.layout.layout_button, parent, false)
        )
    }

    override fun onBindViewHolder(
        viewHolder: RecyclerView.ViewHolder,
        adapter: RecyclerView.Adapter<RecyclerView.ViewHolder>
    ) {
        val buttonViewHolder = viewHolder as ButtonViewHolder
        buttonViewHolder.text.text = text
        buttonViewHolder.description.text = description
        buttonViewHolder.itemView.setOnClickListener { view: View? ->
            onButtonClickListener?.onButtonClick()
        }
    }
}
