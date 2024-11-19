package info.cemu.cemu.gamelist

import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import info.cemu.cemu.R
import info.cemu.cemu.nativeinterface.NativeGameTitles


@Composable
fun GameIcon(
    game: NativeGameTitles.Game,
    modifier: Modifier
) {
    if (game.icon != null) {
        Image(
            modifier = modifier
                .border(
                    width = Dp.Hairline,
                    color = MaterialTheme.colorScheme.onSurface,
                    shape = RoundedCornerShape(8.dp)
                )
                .clip(RoundedCornerShape(8.dp)),
            bitmap = game.icon!!,
            contentDescription = stringResource(R.string.game_icon),
        )
    } else {
        Icon(
            modifier = modifier,
            painter = painterResource(R.drawable.ic_question_mark),
            contentDescription = stringResource(R.string.game_icon_empty),
        )
    }
}