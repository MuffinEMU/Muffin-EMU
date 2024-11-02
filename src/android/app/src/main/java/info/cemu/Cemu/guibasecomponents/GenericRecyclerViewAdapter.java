package info.cemu.Cemu.guibasecomponents;

import android.view.ViewGroup;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Objects;
import java.util.stream.IntStream;

public class GenericRecyclerViewAdapter extends RecyclerView.Adapter<RecyclerView.ViewHolder> {
    private record RecyclerViewItemTuple(int viewTypeId, RecyclerViewItem item) {
    }

    private final List<RecyclerViewItemTuple> recyclerViewItems = new ArrayList<>();
    private int currentViewTypeId = 0;
    private final HashMap<Integer, Integer> recyclerViewItemsViewTypeHasMap = new HashMap<>();

    public void addRecyclerViewItem(RecyclerViewItem recyclerViewItem) {
        int viewTypeId = currentViewTypeId++;
        recyclerViewItems.add(new RecyclerViewItemTuple(viewTypeId, recyclerViewItem));
        int position = recyclerViewItems.size() - 1;
        recyclerViewItemsViewTypeHasMap.put(viewTypeId, position);
        notifyItemInserted(recyclerViewItems.size() - 1);
    }

    public void removeRecyclerViewItem(RecyclerViewItem recyclerViewItem) {
        var position = IntStream.range(0, recyclerViewItems.size()).filter(index -> recyclerViewItems.get(index).item == recyclerViewItem).findFirst();
        if (position.isEmpty()) {
            return;
        }
        var itemTuple = recyclerViewItems.get(position.getAsInt());
        recyclerViewItemsViewTypeHasMap.remove(itemTuple.viewTypeId);
        recyclerViewItems.remove(itemTuple);
        notifyItemRemoved(position.getAsInt());
    }

    public void clearRecyclerViewItems() {
        int itemsCount = recyclerViewItems.size();
        recyclerViewItems.clear();
        recyclerViewItemsViewTypeHasMap.clear();
        notifyItemRangeRemoved(0, itemsCount);
    }

    @NonNull
    @Override
    public RecyclerView.ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewTypeId) {
        Integer position = Objects.requireNonNull(recyclerViewItemsViewTypeHasMap.get(viewTypeId));
        return recyclerViewItems.get(position).item.onCreateViewHolder(parent);
    }

    @Override
    public int getItemViewType(int position) {
        return recyclerViewItems.get(position).viewTypeId;
    }

    @Override
    public void onBindViewHolder(@NonNull RecyclerView.ViewHolder holder, int position) {
        recyclerViewItems.get(position).item.onBindViewHolder(holder, this);
    }

    @Override
    public int getItemCount() {
        return recyclerViewItems.size();
    }
}
