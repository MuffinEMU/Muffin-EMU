package info.cemu.cemu.settings.general

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.navigation.fragment.NavHostFragment
import info.cemu.cemu.R
import info.cemu.cemu.databinding.LayoutGenericRecyclerViewBinding
import info.cemu.cemu.guibasecomponents.ButtonRecyclerViewItem
import info.cemu.cemu.guibasecomponents.GenericRecyclerViewAdapter
import info.cemu.cemu.guibasecomponents.SingleSelectionRecyclerViewItem
import info.cemu.cemu.nativeinterface.NativeSettings
import info.cemu.cemu.nativeinterface.NativeSettings.consoleLanguage
import java.util.List

class GeneralSettingsFragment : Fragment() {
    private fun consoleLanguageToString(channels: Int): String {
        val resourceId = when (channels) {
            NativeSettings.CONSOLE_LANGUAGE_JAPANESE -> R.string.console_language_japanese
            NativeSettings.CONSOLE_LANGUAGE_ENGLISH -> R.string.console_language_english
            NativeSettings.CONSOLE_LANGUAGE_FRENCH -> R.string.console_language_french
            NativeSettings.CONSOLE_LANGUAGE_GERMAN -> R.string.console_language_german
            NativeSettings.CONSOLE_LANGUAGE_ITALIAN -> R.string.console_language_italian
            NativeSettings.CONSOLE_LANGUAGE_SPANISH -> R.string.console_language_spanish
            NativeSettings.CONSOLE_LANGUAGE_CHINESE -> R.string.console_language_chinese
            NativeSettings.CONSOLE_LANGUAGE_KOREAN -> R.string.console_language_korean
            NativeSettings.CONSOLE_LANGUAGE_DUTCH -> R.string.console_language_dutch
            NativeSettings.CONSOLE_LANGUAGE_PORTUGUESE -> R.string.console_language_portuguese
            NativeSettings.CONSOLE_LANGUAGE_RUSSIAN -> R.string.console_language_russian
            NativeSettings.CONSOLE_LANGUAGE_TAIWANESE -> R.string.console_language_taiwanese
            else -> throw IllegalArgumentException("Invalid console language: $channels")
        }
        return getString(resourceId)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false)

        val genericRecyclerViewAdapter = GenericRecyclerViewAdapter()

        genericRecyclerViewAdapter.addRecyclerViewItem(
            ButtonRecyclerViewItem(
                getString(R.string.add_game_path),
                getString(R.string.games_folder_description)
            ) {
                NavHostFragment.findNavController(
                    this@GeneralSettingsFragment
                ).navigate(R.id.action_generalSettingsFragment_to_gamePathsFragment)
            }
        )

        val consoleLanguageSelection = SingleSelectionRecyclerViewItem(
            getString(R.string.console_language),
            consoleLanguage,
            listOf(
                NativeSettings.CONSOLE_LANGUAGE_JAPANESE,
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
                NativeSettings.CONSOLE_LANGUAGE_TAIWANESE
            ),
            { channels: Int -> this.consoleLanguageToString(channels) },
            { newConsoleLanguage -> NativeSettings::consoleLanguage.set(newConsoleLanguage) }
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(consoleLanguageSelection)

        binding.recyclerView.adapter = genericRecyclerViewAdapter

        return binding.root
    }
}