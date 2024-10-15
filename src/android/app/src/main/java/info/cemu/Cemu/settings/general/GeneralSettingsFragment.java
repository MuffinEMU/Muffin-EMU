package info.cemu.Cemu.settings.general;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.NonNull;
import androidx.fragment.app.Fragment;
import androidx.navigation.fragment.NavHostFragment;

import java.util.List;

import info.cemu.Cemu.R;
import info.cemu.Cemu.databinding.LayoutGenericRecyclerViewBinding;
import info.cemu.Cemu.guibasecomponents.ButtonRecyclerViewItem;
import info.cemu.Cemu.guibasecomponents.GenericRecyclerViewAdapter;
import info.cemu.Cemu.guibasecomponents.SingleSelectionRecyclerViewItem;
import info.cemu.Cemu.nativeinterface.NativeSettings;

public class GeneralSettingsFragment extends Fragment {
    private String consoleLanguageToString(int channels) {
        int resourceId = switch (channels) {
            case NativeSettings.CONSOLE_LANGUAGE_JAPANESE -> R.string.console_language_japanese;
            case NativeSettings.CONSOLE_LANGUAGE_ENGLISH -> R.string.console_language_english;
            case NativeSettings.CONSOLE_LANGUAGE_FRENCH -> R.string.console_language_french;
            case NativeSettings.CONSOLE_LANGUAGE_GERMAN -> R.string.console_language_german;
            case NativeSettings.CONSOLE_LANGUAGE_ITALIAN -> R.string.console_language_italian;
            case NativeSettings.CONSOLE_LANGUAGE_SPANISH -> R.string.console_language_spanish;
            case NativeSettings.CONSOLE_LANGUAGE_CHINESE -> R.string.console_language_chinese;
            case NativeSettings.CONSOLE_LANGUAGE_KOREAN -> R.string.console_language_korean;
            case NativeSettings.CONSOLE_LANGUAGE_DUTCH -> R.string.console_language_dutch;
            case NativeSettings.CONSOLE_LANGUAGE_PORTUGUESE -> R.string.console_language_portuguese;
            case NativeSettings.CONSOLE_LANGUAGE_RUSSIAN -> R.string.console_language_russian;
            case NativeSettings.CONSOLE_LANGUAGE_TAIWANESE -> R.string.console_language_taiwanese;
            default -> throw new IllegalArgumentException("Invalid console language: " + channels);
        };
        return getString(resourceId);
    }

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        var binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false);

        GenericRecyclerViewAdapter genericRecyclerViewAdapter = new GenericRecyclerViewAdapter();

        genericRecyclerViewAdapter.addRecyclerViewItem(new ButtonRecyclerViewItem(getString(R.string.add_game_path), getString(R.string.games_folder_description), () -> NavHostFragment.findNavController(GeneralSettingsFragment.this).navigate(R.id.action_generalSettingsFragment_to_gamePathsFragment)));

        SingleSelectionRecyclerViewItem<Integer> consoleLanguageSelection = new SingleSelectionRecyclerViewItem<>(getString(R.string.console_language),
                NativeSettings.getConsoleLanguage(),
                List.of(NativeSettings.CONSOLE_LANGUAGE_JAPANESE,
                        NativeSettings.CONSOLE_LANGUAGE_ENGLISH,
                        NativeSettings.CONSOLE_LANGUAGE_FRENCH,
                        NativeSettings.CONSOLE_LANGUAGE_GERMAN,
                        NativeSettings.CONSOLE_LANGUAGE_ITALIAN,
                        NativeSettings.CONSOLE_LANGUAGE_SPANISH,
                        NativeSettings.CONSOLE_LANGUAGE_CHINESE,
                        NativeSettings.CONSOLE_LANGUAGE_KOREAN,
                        NativeSettings.CONSOLE_LANGUAGE_DUTCH,
                        NativeSettings.CONSOLE_LANGUAGE_PORTUGUESE,
                        NativeSettings.CONSOLE_LANGUAGE_RUSSIAN,
                        NativeSettings.CONSOLE_LANGUAGE_TAIWANESE),
                this::consoleLanguageToString,
                NativeSettings::setConsoleLanguage);
        genericRecyclerViewAdapter.addRecyclerViewItem(consoleLanguageSelection);

        binding.recyclerView.setAdapter(genericRecyclerViewAdapter);

        return binding.getRoot();
    }
}