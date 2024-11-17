package info.cemu.cemu.gameview

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.annotation.StringRes
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.navigation.fragment.NavHostFragment
import androidx.navigation.ui.AppBarConfiguration.Builder
import androidx.navigation.ui.NavigationUI.setupWithNavController
import info.cemu.cemu.R
import info.cemu.cemu.databinding.FragmentGameDetailsBinding
import info.cemu.cemu.nativeinterface.NativeGameTitles
import info.cemu.cemu.nativeinterface.NativeGameTitles.Game
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

class GameDetailsFragment : Fragment() {
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val binding = FragmentGameDetailsBinding.inflate(inflater, container, false)
        val game = ViewModelProvider(requireActivity()).get(GameViewModel::class.java).game
        binding.gameTitleName.text = game!!.name
        binding.titleVersion.text = game.version.toString()
        if (game.icon != null) {
            binding.titleIcon.setImageBitmap(game.icon)
        }
        if (game.dlc.toInt() != 0) {
            binding.titleDlc.text = game.dlc.toString()
        }
        binding.titleTimePlayed.text = getTimePlayed(game)
        binding.titleLastPlayed.text = getLastPlayedDate(game)
        binding.titleId.text = String.format("%016x", game.titleId)
        binding.titleRegion.setText(getRegionName(game))
        setupWithNavController(
            binding.gameDetailsToolbar,
            NavHostFragment.findNavController(this),
            Builder().build()
        )
        return binding.root
    }

    private fun getLastPlayedDate(game: Game): String {
        if (game.lastPlayedYear.toInt() == 0) {
            return getString(R.string.never_played)
        }
        val lastPlayedDate = LocalDate.of(
            game.lastPlayedYear.toInt(),
            game.lastPlayedMonth.toInt(),
            game.lastPlayedDay.toInt()
        )
        return DATE_FORMATTER.format(lastPlayedDate)
    }

    private fun getTimePlayed(game: Game): String {
        if (game.minutesPlayed == 0) {
            return getString(R.string.never_played)
        }
        if (game.minutesPlayed < 60) {
            return getString(R.string.minutes_played, game.minutesPlayed)
        }
        return getString(
            R.string.hours_minutes_played,
            game.minutesPlayed / 60,
            game.minutesPlayed % 60
        )
    }

    @StringRes
    private fun getRegionName(game: Game): Int {
        return when (game.region) {
            NativeGameTitles.CONSOLE_REGION_JPN -> R.string.console_region_japan
            NativeGameTitles.CONSOLE_REGION_USA -> R.string.console_region_usa
            NativeGameTitles.CONSOLE_REGION_EUR -> R.string.console_region_europe
            NativeGameTitles.CONSOLE_REGION_AUS_DEPR -> R.string.console_region_australia
            NativeGameTitles.CONSOLE_REGION_CHN -> R.string.console_region_china
            NativeGameTitles.CONSOLE_REGION_KOR -> R.string.console_region_korea
            NativeGameTitles.CONSOLE_REGION_TWN -> R.string.console_region_taiwan
            NativeGameTitles.CONSOLE_REGION_AUTO -> R.string.console_region_auto
            else -> R.string.console_region_many
        }
    }

    companion object {
        private val DATE_FORMATTER: DateTimeFormatter = DateTimeFormatter.ofLocalizedDate(
            FormatStyle.SHORT
        )
    }
}
