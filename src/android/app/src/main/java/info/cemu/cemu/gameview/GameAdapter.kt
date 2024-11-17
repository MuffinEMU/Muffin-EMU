package info.cemu.cemu.gameview

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.card.MaterialCardView
import info.cemu.cemu.R
import info.cemu.cemu.nativeinterface.NativeGameTitles.Game

class GameAdapter(private val gameTitleClickAction: GameTitleClickAction) :
    ListAdapter<Game, GameAdapter.ViewHolder>(DIFF_CALLBACK) {
    private var originalGameList: List<Game>? = null
    private var filterText: String = ""
    var selectedGame: Game? = null
        private set

    fun interface GameTitleClickAction {
        fun action(game: Game)
    }

    override fun submitList(list: List<Game>?) {
        originalGameList = list ?: emptyList()
        updateGameList()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.layout_game, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val game = getItem(position) ?: return
        holder.icon.setImageBitmap(game.icon)
        holder.favoriteIcon.visibility = if (game.isFavorite) View.VISIBLE else View.GONE
        holder.text.text = game.name
        holder.itemView.setOnClickListener { _: View? ->
            gameTitleClickAction.action(
                game
            )
        }
        holder.itemView.setOnLongClickListener { _: View? ->
            selectedGame = game
            false
        }
    }

    fun setFilterText(filterText: String?) {
        this.filterText = filterText?.lowercase() ?: ""
        updateGameList()
    }

    private fun updateGameList() {
        if (filterText.isBlank() || originalGameList == null) {
            super.submitList(originalGameList)
            return
        }
        super.submitList(originalGameList!!.filter {
            it.name?.lowercase()?.contains(filterText) ?: false
        })
    }

    class ViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        var icon: ImageView =
            itemView.findViewById(R.id.game_icon)
        var text: TextView =
            itemView.findViewById(R.id.game_title)
        var favoriteIcon: MaterialCardView =
            itemView.findViewById(R.id.game_favorite_icon)
    }

    companion object {
        @JvmField
        val DIFF_CALLBACK: DiffUtil.ItemCallback<Game> = object : DiffUtil.ItemCallback<Game>() {
            override fun areItemsTheSame(oldItem: Game, newItem: Game): Boolean {
                return oldItem.titleId == newItem.titleId
            }

            override fun areContentsTheSame(oldItem: Game, newItem: Game): Boolean {
                return oldItem.path == newItem.path && oldItem.titleId == newItem.titleId && oldItem.isFavorite == newItem.isFavorite
            }
        }
    }
}
