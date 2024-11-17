package info.cemu.cemu.guibasecomponents

import android.content.DialogInterface
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import info.cemu.cemu.R
import info.cemu.cemu.guibasecomponents.SelectionAdapter.ChoiceItem
import java.util.function.Function
import java.util.stream.Collectors

class SingleSelectionRecyclerViewItem<T>(
    private val label: String?,
    private var description: String?,
    private val selectionAdapter: BaseSelectionAdapter<T>,
    private var onItemSelectedListener: OnItemSelectedListener<T>?
) :
    RecyclerViewItem {
    private class SingleSelectionViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        var label: TextView =
            itemView.findViewById(R.id.selection_label)
        var description: TextView =
            itemView.findViewById(R.id.selection_description)
    }

    fun interface OnItemSelectedListener<T> {
        fun onItemSelected(
            selectedValue: T,
            selectionRecyclerViewItem: SingleSelectionRecyclerViewItem<T>
        )
    }

    fun interface OnChoiceSelectedListener<T> {
        fun onChoiceSelected(selectedValue: T)
    }

    private var singleSelectionViewHolder: SingleSelectionViewHolder? = null
    private var recyclerViewAdapter: RecyclerView.Adapter<RecyclerView.ViewHolder>? = null
    private var selectAlertDialog: AlertDialog? = null

    constructor(
        label: String?,
        currentChoice: T,
        choicesList: List<T>,
        choiceValueToNameFunction: (T) -> String,
        onChoiceSelectedListener: OnChoiceSelectedListener<T>
    ) : this(
        label,
        choiceValueToNameFunction(currentChoice),
        SelectionAdapter<T>(
            choicesList.map { choice: T ->
                ChoiceItem<T>({ t: TextView ->
                    t.text = choiceValueToNameFunction(choice)
                }, choice)
            }.toList(),
            currentChoice
        ),
        { selectedValue: T, selectionRecyclerViewItem: SingleSelectionRecyclerViewItem<T> ->
            onChoiceSelectedListener.onChoiceSelected(selectedValue)
            selectionRecyclerViewItem.setDescription(choiceValueToNameFunction(selectedValue))
        })

    fun setDescription(description: String?) {
        this.description = description
        recyclerViewAdapter!!.notifyItemChanged(singleSelectionViewHolder!!.adapterPosition)
    }

    override fun onCreateViewHolder(parent: ViewGroup): RecyclerView.ViewHolder {
        return SingleSelectionViewHolder(
            LayoutInflater.from(parent.context)
                .inflate(R.layout.layout_single_selection, parent, false)
        )
    }

    override fun onBindViewHolder(
        viewHolder: RecyclerView.ViewHolder,
        adapter: RecyclerView.Adapter<RecyclerView.ViewHolder>
    ) {
        this.recyclerViewAdapter = adapter
        singleSelectionViewHolder = viewHolder as SingleSelectionViewHolder?
        singleSelectionViewHolder!!.label.text = label
        singleSelectionViewHolder!!.description.text = description
        singleSelectionViewHolder!!.itemView.setOnClickListener { view: View? ->
            if (selectAlertDialog == null) {
                val builder = MaterialAlertDialogBuilder(viewHolder.itemView.context)
                selectAlertDialog = builder.setTitle(label)
                    .setAdapter(selectionAdapter) { dialogInterface: DialogInterface?, position: Int ->
                        if (!selectionAdapter.isEnabled(position)) {
                            return@setAdapter
                        }
                        val selectedValue = selectionAdapter.getItem(position)
                        selectionAdapter.setSelectedValue(selectedValue)
                        onItemSelectedListener?.onItemSelected(
                            selectedValue,
                            this@SingleSelectionRecyclerViewItem
                        )
                    }.setNegativeButton(
                        R.string.cancel
                    ) { dialogInterface: DialogInterface, i: Int -> dialogInterface.dismiss() }
                    .show()
                return@setOnClickListener
            }
            selectAlertDialog!!.show()
        }
    }
}
