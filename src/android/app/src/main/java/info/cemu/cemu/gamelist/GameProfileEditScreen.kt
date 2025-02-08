package info.cemu.cemu.gamelist

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import info.cemu.cemu.R
import info.cemu.cemu.guicore.components.Header
import info.cemu.cemu.guicore.components.ScreenContent
import info.cemu.cemu.guicore.components.SingleSelection
import info.cemu.cemu.guicore.components.Toggle
import info.cemu.cemu.guicore.nativeenummapper.cpuModeToStringId
import info.cemu.cemu.nativeinterface.NativeGameTitles

@Composable
fun GameProfileEditScreen(game: NativeGameTitles.Game?, navigateBack: () -> Unit) {
    if (game == null)
        return

    val titleId = game.titleId
    ScreenContent(
        appBarText = stringResource(R.string.edit_game_profile),
        navigateBack = navigateBack,
        contentModifier = Modifier.padding(16.dp),
        contentVerticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Header(text = game.name)
        Toggle(
            label = stringResource(R.string.load_shared_libraries),
            description = stringResource(R.string.load_shared_libraries_description),
            initialCheckedState = {
                NativeGameTitles.isLoadingSharedLibrariesForTitleEnabled(
                    titleId
                )
            },
            onCheckedChanged = { enabled ->
                NativeGameTitles.setLoadingSharedLibrariesForTitleEnabled(
                    titleId,
                    enabled
                )
            },
        )
        Toggle(
            label = stringResource(R.string.shader_multiplication_accuracy),
            description = stringResource(R.string.shader_multiplication_accuracy_description),
            initialCheckedState = {
                NativeGameTitles.isShaderMultiplicationAccuracyForTitleEnabled(
                    titleId
                )
            },
            onCheckedChanged = { enabled ->
                NativeGameTitles.setShaderMultiplicationAccuracyForTitleEnabled(
                    titleId,
                    enabled
                )
            },
        )
        SingleSelection(
            label = stringResource(R.string.cpu_mode),
            initialChoice = { NativeGameTitles.getCpuModeForTitle(titleId) },
            choices = listOf(
                NativeGameTitles.CPU_MODE_SINGLECOREINTERPRETER,
                NativeGameTitles.CPU_MODE_SINGLECORERECOMPILER,
                NativeGameTitles.CPU_MODE_MULTICORERECOMPILER,
                NativeGameTitles.CPU_MODE_AUTO
            ),
            choiceToString = { cpuMode -> stringResource(cpuModeToStringId(cpuMode)) },
            onChoiceChanged = { cpuMode -> NativeGameTitles.setCpuModeForTitle(titleId, cpuMode) }
        )
        SingleSelection(
            label = stringResource(R.string.thread_quantum),
            initialChoice = { NativeGameTitles.getThreadQuantumForTitle(titleId) },
            choices = NativeGameTitles.THREAD_QUANTUM_VALUES.toList(),
            choiceToString = { it.toString() },
            onChoiceChanged = { threadQuantum ->
                NativeGameTitles.setThreadQuantumForTitle(titleId, threadQuantum)
            }
        )
    }
}
