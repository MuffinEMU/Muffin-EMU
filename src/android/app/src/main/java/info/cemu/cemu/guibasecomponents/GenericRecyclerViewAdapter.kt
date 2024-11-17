package info.cemu.cemu.guibasecomponents

import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import java.util.Objects
import java.util.stream.IntStream

class GenericRecyclerViewAdapter : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
    @JvmRecord
    private data class RecyclerViewItemTuple(val viewTypeId: Int, val item: RecyclerViewItem)

    private val recyclerViewItems: MutableList<RecyclerViewItemTuple> = ArrayList()
    private var currentViewTypeId = 0
    private val recyclerViewItemsViewTypeHasMap = HashMap<Int, Int>()

    fun addRecyclerViewItem(recyclerViewItem: RecyclerViewItem) {
        val viewTypeId = currentViewTypeId++
        recyclerViewItems.add(RecyclerViewItemTuple(viewTypeId, recyclerViewItem))
        val position = recyclerViewItems.size - 1
        recyclerViewItemsViewTypeHasMap[viewTypeId] = position
        notifyItemInserted(recyclerViewItems.size - 1)
    }

    fun removeRecyclerViewItem(recyclerViewItem: RecyclerViewItem) {
        val position = IntStream.range(0, recyclerViewItems.size)
            .filter { index: Int -> recyclerViewItems[index].item === recyclerViewItem }
            .findFirst()
        if (position.isEmpty) {
            return
        }
        val itemTuple = recyclerViewItems[position.asInt]
        recyclerViewItemsViewTypeHasMap.remove(itemTuple.viewTypeId)
        recyclerViewItems.remove(itemTuple)
        notifyItemRemoved(position.asInt)
    }

    fun clearRecyclerViewItems() {
        val itemsCount = recyclerViewItems.size
        recyclerViewItems.clear()
        recyclerViewItemsViewTypeHasMap.clear()
        notifyItemRangeRemoved(0, itemsCount)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewTypeId: Int): RecyclerView.ViewHolder {
        val position = recyclerViewItemsViewTypeHasMap[viewTypeId]!!
        return recyclerViewItems[position].item.onCreateViewHolder(parent)
    }

    override fun getItemViewType(position: Int): Int {
        return recyclerViewItems[position].viewTypeId
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        recyclerViewItems[position].item.onBindViewHolder(holder, this)
    }

    override fun getItemCount(): Int {
        return recyclerViewItems.size
    }
}
