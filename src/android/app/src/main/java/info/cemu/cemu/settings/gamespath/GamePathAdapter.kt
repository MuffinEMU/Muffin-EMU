package info.cemu.cemu.settings.gamespath

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import info.cemu.cemu.R

class GamePathAdapter(private val onRemoveGamePath: OnRemoveGamePath) :
    ListAdapter<String, GamePathAdapter.ViewHolder>(DIFF_CALLBACK) {
    fun interface OnRemoveGamePath {
        fun onRemoveGamePath(path: String)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view =
            LayoutInflater.from(parent.context).inflate(R.layout.layout_game_path, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val gamePath = getItem(position)
        holder.gamePath.text = gamePath
        holder.gamePath.isSelected = true
        holder.deleteButton.setOnClickListener { v: View? ->
            onRemoveGamePath.onRemoveGamePath(
                gamePath
            )
        }
    }

    class ViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        var gamePath: TextView =
            itemView.findViewById(R.id.game_path_text)
        var deleteButton: Button =
            itemView.findViewById(R.id.remove_game_path_button)
    }

    companion object {
        private val DIFF_CALLBACK: DiffUtil.ItemCallback<String> =
            object : DiffUtil.ItemCallback<String>() {
                override fun areItemsTheSame(oldItem: String, newItem: String): Boolean {
                    return oldItem == newItem
                }

                override fun areContentsTheSame(oldItem: String, newItem: String): Boolean {
                    return oldItem == newItem
                }
            }
    }
}
