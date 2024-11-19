package info.cemu.cemu.gamelist

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import info.cemu.cemu.R
import info.cemu.cemu.guicore.ScreenContent
import info.cemu.cemu.guicore.enumtostringmapper.native.regionToStringId
import info.cemu.cemu.nativeinterface.NativeGameTitles.Game
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

@Composable
fun GameDetailsScreen(selectedGameViewModel: GameViewModel, navigateBack: () -> Unit) {
    val game by selectedGameViewModel.game.collectAsState()
    if (game == null) return
    ScreenContent(
        appBarText = stringResource(R.string.about_title),
        contentModifier = Modifier.padding(16.dp),
        contentVerticalArrangement = Arrangement.spacedBy(16.dp),
        navigateBack = navigateBack,
    ) {
        GameDetails(game!!)
    }
}

@Composable
fun GameDetails(game: Game) {
    GameIcon(
        game = game,
        modifier = Modifier.size(128.dp),
    )
    TitleDetailsEntry(entryName = stringResource(R.string.title_name), entryData = game.name)
    TitleDetailsEntry(entryName = stringResource(R.string.title_id), entryData = game.titleId)
    TitleDetailsEntry(entryName = stringResource(R.string.version), entryData = game.version)
    TitleDetailsEntry(entryName = stringResource(R.string.dlc), entryData = game.dlc)
    TitleDetailsEntry(
        entryName = stringResource(R.string.title_time_played),
        entryData = getTimePlayed(game)
    )
    TitleDetailsEntry(
        entryName = stringResource(R.string.title_last_played),
        entryData = getLastPlayedDate(game)
    )
    TitleDetailsEntry(
        entryName = stringResource(R.string.title_region),
        entryData = stringResource(regionToStringId(game.region))
    )
    TitleDetailsEntry(
        entryName = stringResource(R.string.title_path),
        entryData = game.path
    )
}


@ReadOnlyComposable
@Composable
fun getTimePlayed(game: Game): String {
    if (game.minutesPlayed == 0) {
        return stringResource(R.string.never_played)
    }
    if (game.minutesPlayed < 60) {
        return stringResource(R.string.minutes_played, game.minutesPlayed)
    }
    return stringResource(
        R.string.hours_minutes_played,
        game.minutesPlayed / 60,
        game.minutesPlayed % 60
    )
}

private val DateFormatter = DateTimeFormatter.ofLocalizedDate(
    FormatStyle.SHORT
)

@ReadOnlyComposable
@Composable
private fun getLastPlayedDate(game: Game): String {
    if (game.lastPlayedYear.toInt() == 0) {
        return stringResource(R.string.never_played)
    }
    val lastPlayedDate = LocalDate.of(
        game.lastPlayedYear.toInt(),
        game.lastPlayedMonth.toInt(),
        game.lastPlayedDay.toInt()
    )
    return DateFormatter.format(lastPlayedDate)
}

@Composable
fun <T> TitleDetailsEntry(entryName: String, entryData: T?) {
    Column {
        Text(
            text = entryName,
            fontWeight = FontWeight.Bold,
            fontSize = 24.sp,
        )
        Text(
            text = entryData?.toString() ?: "",
            fontSize = 16.sp,
        )
    }
}
