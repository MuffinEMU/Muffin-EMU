package info.cemu.cemu.guibasecomponents

import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import java.util.function.Predicate
import java.util.stream.Collectors

class FilterableRecyclerViewAdapter<T : RecyclerViewItem?> :
    RecyclerView.Adapter<RecyclerView.ViewHolder>() {
    private var predicate: Predicate<T>? = null
    private val recyclerViewItems: MutableList<T> = ArrayList()
    private var filteredRecyclerViewItems: MutableList<T> = ArrayList()

    fun addRecyclerViewItem(recyclerViewItem: T) {
        recyclerViewItems.add(recyclerViewItem)
        if (predicate == null || predicate!!.test(recyclerViewItem)) {
            filteredRecyclerViewItems.add(recyclerViewItem)
            notifyItemInserted(filteredRecyclerViewItems.size - 1)
        }
    }

    fun setPredicate(predicate: Predicate<T>) {
        this.predicate = predicate
        val oldSize = filteredRecyclerViewItems.size
        filteredRecyclerViewItems =
            recyclerViewItems.stream().filter(predicate).collect(Collectors.toList())
        if (oldSize != filteredRecyclerViewItems.size) {
            notifyDataSetChanged()
        }
    }

    fun clearPredicate() {
        val oldSize = filteredRecyclerViewItems.size
        filteredRecyclerViewItems = ArrayList(recyclerViewItems)
        if (oldSize != filteredRecyclerViewItems.size) {
            notifyDataSetChanged()
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, position: Int): RecyclerView.ViewHolder {
        return filteredRecyclerViewItems[position]!!.onCreateViewHolder(parent)
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        filteredRecyclerViewItems[position]!!.onBindViewHolder(holder, this)
    }

    override fun getItemCount(): Int {
        return filteredRecyclerViewItems.size
    }

    fun clearRecyclerViewItems() {
        val size = filteredRecyclerViewItems.size
        filteredRecyclerViewItems.clear()
        recyclerViewItems.clear()
        notifyItemRangeRemoved(0, size)
    }
}
