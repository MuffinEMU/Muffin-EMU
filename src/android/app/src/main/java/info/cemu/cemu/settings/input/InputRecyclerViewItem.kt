package info.cemu.cemu.settings.input

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import info.cemu.cemu.R
import info.cemu.cemu.guibasecomponents.RecyclerViewItem

class InputRecyclerViewItem(
    private val inputNameResourceId: Int,
    private var boundInput: String,
    private val onInputClickListener: OnInputClickListener
) :
    RecyclerViewItem {
    interface OnInputClickListener {
        fun onInputClick(inputRecyclerViewItem: InputRecyclerViewItem?)
    }

    private class InputViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        var inputName: TextView =
            itemView.findViewById(R.id.controller_input_name)
        var boundInput: TextView =
            itemView.findViewById(R.id.controller_button_name)
    }

    private var recyclerViewAdapter: RecyclerView.Adapter<RecyclerView.ViewHolder>? = null
    private var inputViewHolder: InputViewHolder? = null

    fun clearBoundInput() {
        setBoundInput("")
    }

    fun setBoundInput(boundInput: String) {
        this.boundInput = boundInput
        recyclerViewAdapter!!.notifyItemChanged(inputViewHolder!!.adapterPosition)
    }

    override fun onCreateViewHolder(parent: ViewGroup): RecyclerView.ViewHolder {
        return InputViewHolder(
            LayoutInflater.from(parent.context)
                .inflate(R.layout.layout_controller_input, parent, false)
        )
    }

    override fun onBindViewHolder(
        viewHolder: RecyclerView.ViewHolder,
        adapter: RecyclerView.Adapter<RecyclerView.ViewHolder>
    ) {
        inputViewHolder = viewHolder as InputViewHolder
        recyclerViewAdapter = adapter
        inputViewHolder!!.itemView.setOnClickListener { view: View? ->
            onInputClickListener.onInputClick(this)
        }
        inputViewHolder!!.inputName.setText(inputNameResourceId)
        inputViewHolder!!.boundInput.text = boundInput
    }
}
