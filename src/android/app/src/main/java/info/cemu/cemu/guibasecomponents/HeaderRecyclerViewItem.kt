package info.cemu.cemu.guibasecomponents

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import info.cemu.cemu.R
import java.util.Optional

class HeaderRecyclerViewItem : RecyclerViewItem {
    private class HeaderViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        var header: TextView =
            itemView.findViewById(R.id.textview_header)
    }

    private val headerResourceIdText: Optional<Int>
    private val headerText: String?

    constructor(headerResourceIdText: Int) {
        this.headerResourceIdText = Optional.of(headerResourceIdText)
        this.headerText = null
    }

    constructor(headerText: String?) {
        this.headerResourceIdText = Optional.empty()
        this.headerText = headerText
    }

    override fun onCreateViewHolder(parent: ViewGroup): RecyclerView.ViewHolder {
        return HeaderViewHolder(
            LayoutInflater.from(parent.context).inflate(R.layout.layout_header, parent, false)
        )
    }

    override fun onBindViewHolder(
        viewHolder: RecyclerView.ViewHolder,
        adapter: RecyclerView.Adapter<RecyclerView.ViewHolder>
    ) {
        val headerViewHolder = viewHolder as HeaderViewHolder
        if (headerResourceIdText.isEmpty) {
            headerViewHolder.header.text = headerText
            return
        }
        headerViewHolder.header.setText(headerResourceIdText.get())
    }
}
