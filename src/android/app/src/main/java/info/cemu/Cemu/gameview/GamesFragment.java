package info.cemu.Cemu.gameview;

import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.ContextMenu;
import android.view.LayoutInflater;
import android.view.MenuInflater;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import androidx.lifecycle.ViewModelProvider;
import androidx.navigation.fragment.NavHostFragment;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.material.dialog.MaterialAlertDialogBuilder;

import java.util.HashSet;

import info.cemu.Cemu.R;
import info.cemu.Cemu.databinding.FragmentGamesBinding;
import info.cemu.Cemu.emulation.EmulationActivity;
import info.cemu.Cemu.nativeinterface.NativeGameTitles;
import info.cemu.Cemu.nativeinterface.NativeGameTitles.Game;
import info.cemu.Cemu.nativeinterface.NativeSettings;
import info.cemu.Cemu.settings.SettingsActivity;

public class GamesFragment extends Fragment {
    private GameAdapter gameAdapter;
    private GameListViewModel gameListViewModel;
    private GameViewModel gameViewModel;
    private boolean refreshing = false;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private HashSet<String> currentGamePaths = new HashSet<>();

    @Override
    public void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        currentGamePaths = new HashSet<>(NativeSettings.getGamesPaths());
        gameAdapter = new GameAdapter(game -> {
            Intent intent = new Intent(getContext(), EmulationActivity.class);
            intent.putExtra(EmulationActivity.LAUNCH_PATH, game.path());
            startActivity(intent);
        });
        gameListViewModel = new ViewModelProvider(this).get(GameListViewModel.class);
        gameViewModel = new ViewModelProvider(requireActivity()).get(GameViewModel.class);
        gameListViewModel.getGames().observe(this, gameList -> gameAdapter.submitList(gameList));
        NativeGameTitles.reloadGameTitles();
    }

    @Override
    public void onResume() {
        super.onResume();
        var gamePaths = new HashSet<>(NativeSettings.getGamesPaths());
        if (!currentGamePaths.equals(gamePaths)) {
            currentGamePaths = gamePaths;
            NativeGameTitles.reloadGameTitles();
        }
    }

    @Override
    public void onCreateContextMenu(@NonNull ContextMenu menu, @NonNull View v, @Nullable ContextMenu.ContextMenuInfo menuInfo) {
        super.onCreateContextMenu(menu, v, menuInfo);
        MenuInflater inflater = requireActivity().getMenuInflater();
        inflater.inflate(R.menu.menu_game, menu);
        Game selectedGame = gameAdapter.getSelectedGame();
        menu.findItem(R.id.favorite).setChecked(selectedGame.isFavorite());
        menu.findItem(R.id.remove_shader_caches).setEnabled(NativeGameTitles.titleHasShaderCacheFiles(selectedGame.titleId()));
    }

    @Override
    public boolean onContextItemSelected(@NonNull MenuItem item) {
        Game game = gameAdapter.getSelectedGame();
        if (game == null) {
            return super.onContextItemSelected(item);
        }
        int itemId = item.getItemId();
        if (itemId == R.id.favorite) {
            gameListViewModel.setGameTitleFavorite(game, !game.isFavorite());
            return true;
        }
        if (itemId == R.id.game_profile) {
            gameViewModel.setGame(game);
            NavHostFragment.findNavController(this).navigate(R.id.action_games_fragment_to_game_edit_profile);
            return true;
        }
        if (itemId == R.id.remove_shader_caches) {
            removeShaderCachesForGame(game);
            return true;
        }
        if (itemId == R.id.about_title) {
            gameViewModel.setGame(game);
            NavHostFragment.findNavController(this).navigate(R.id.action_games_fragment_to_game_details_fragment);
            return true;
        }
        return super.onContextItemSelected(item);
    }

    private void removeShaderCachesForGame(Game game) {
        MaterialAlertDialogBuilder builder = new MaterialAlertDialogBuilder(requireContext());
        builder.setTitle(R.string.remove_shader_caches)
                .setMessage(getString(R.string.remove_shader_caches_message, game.name()))
                .setPositiveButton(R.string.yes, (dialog, which) -> {
                    NativeGameTitles.removeShaderCacheFilesForTitle(game.titleId());
                    Toast.makeText(requireContext(), R.string.shader_caches_removed_notification, Toast.LENGTH_SHORT).show();
                })
                .setNegativeButton(R.string.no, (dialog, which) -> dialog.dismiss())
                .show();
    }

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        FragmentGamesBinding binding = FragmentGamesBinding.inflate(inflater, container, false);
        RecyclerView recyclerView = binding.gamesRecyclerView;
        registerForContextMenu(recyclerView);
        binding.settingsButton.setOnClickListener(v -> {
            Intent intent = new Intent(requireActivity(), SettingsActivity.class);
            startActivity(intent);
        });
        View rootView = binding.getRoot();

        binding.gamesSwipeRefresh.setOnRefreshListener(() -> {
            if (refreshing) return;
            refreshing = true;
            handler.postDelayed(() -> {
                binding.gamesSwipeRefresh.setRefreshing(false);
                refreshing = false;
            }, 1000);
            gameListViewModel.refreshGames();
        });
        recyclerView.setAdapter(gameAdapter);
        binding.searchText.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence charSequence, int i, int i1, int i2) {
            }

            @Override
            public void onTextChanged(CharSequence charSequence, int i, int i1, int i2) {
                gameAdapter.setFilterText(charSequence.toString());
            }

            @Override
            public void afterTextChanged(Editable editable) {
            }
        });

        return rootView;
    }

}