package info.cemu.cemu.guibasecomponents

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import info.cemu.cemu.R

class SimpleButtonRecyclerViewItem(
    private val text: String,
    private val onButtonClickListener: OnButtonClickListener?
) :
    RecyclerViewItem {
    fun interface OnButtonClickListener {
        fun onButtonClick()
    }

    private class SimpleButtonViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        var text: TextView =
            itemView.findViewById(R.id.simple_button_text)
    }

    override fun onCreateViewHolder(parent: ViewGroup): RecyclerView.ViewHolder {
        return SimpleButtonViewHolder(
            LayoutInflater.from(parent.context)
                .inflate(R.layout.layout_simple_button, parent, false)
        )
    }

    override fun onBindViewHolder(
        viewHolder: RecyclerView.ViewHolder,
        adapter: RecyclerView.Adapter<RecyclerView.ViewHolder>
    ) {
        val buttonViewHolder = viewHolder as SimpleButtonViewHolder?
        buttonViewHolder!!.text.text = text
        buttonViewHolder.itemView.setOnClickListener { view: View? ->
            onButtonClickListener?.onButtonClick()
        }
    }
}
