package info.cemu.cemu.guibasecomponents

import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView

interface RecyclerViewItem {
    fun onCreateViewHolder(parent: ViewGroup): RecyclerView.ViewHolder

    fun onBindViewHolder(
        viewHolder: RecyclerView.ViewHolder,
        adapter: RecyclerView.Adapter<RecyclerView.ViewHolder>
    )
}
