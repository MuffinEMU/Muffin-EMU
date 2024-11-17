package info.cemu.cemu.gameview

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.navigation.fragment.NavHostFragment
import androidx.navigation.ui.AppBarConfiguration.Builder
import androidx.navigation.ui.NavigationUI.setupWithNavController
import info.cemu.cemu.R
import info.cemu.cemu.databinding.FragmentGameProfileEditBinding
import info.cemu.cemu.guibasecomponents.GenericRecyclerViewAdapter
import info.cemu.cemu.guibasecomponents.HeaderRecyclerViewItem
import info.cemu.cemu.guibasecomponents.SingleSelectionRecyclerViewItem
import info.cemu.cemu.guibasecomponents.ToggleRecyclerViewItem
import info.cemu.cemu.nativeinterface.NativeGameTitles
import info.cemu.cemu.nativeinterface.NativeGameTitles.getCpuModeForTitle
import info.cemu.cemu.nativeinterface.NativeGameTitles.getThreadQuantumForTitle
import info.cemu.cemu.nativeinterface.NativeGameTitles.isLoadingSharedLibrariesForTitleEnabled
import info.cemu.cemu.nativeinterface.NativeGameTitles.isShaderMultiplicationAccuracyForTitleEnabled
import info.cemu.cemu.nativeinterface.NativeGameTitles.setCpuModeForTitle
import info.cemu.cemu.nativeinterface.NativeGameTitles.setLoadingSharedLibrariesForTitleEnabled
import info.cemu.cemu.nativeinterface.NativeGameTitles.setShaderMultiplicationAccuracyForTitleEnabled
import info.cemu.cemu.nativeinterface.NativeGameTitles.setThreadQuantumForTitle
import java.util.Arrays
import java.util.stream.Collectors

class GameProfileEditFragment : Fragment() {
    private fun cpuModeToString(cpuMode: Int): String {
        val resourceId = when (cpuMode) {
            NativeGameTitles.CPU_MODE_SINGLECOREINTERPRETER -> R.string.cpu_mode_single_core_interpreter
            NativeGameTitles.CPU_MODE_SINGLECORERECOMPILER -> R.string.cpu_mode_single_core_recompiler
            NativeGameTitles.CPU_MODE_MULTICORERECOMPILER -> R.string.cpu_mode_multi_core_recompiler
            else -> R.string.cpu_mode_auto
        }
        return getString(resourceId)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val binding = FragmentGameProfileEditBinding.inflate(inflater, container, false)
        val game = ViewModelProvider(requireActivity()).get(GameViewModel::class.java).game
        val titleId = game!!.titleId

        val genericRecyclerViewAdapter = GenericRecyclerViewAdapter()

        genericRecyclerViewAdapter.addRecyclerViewItem(HeaderRecyclerViewItem(game.name))

        val loadSharedLibrariesToggle = ToggleRecyclerViewItem(
            "Load shared libraries",
            "Load libraries from the cafeLibs directory",
            isLoadingSharedLibrariesForTitleEnabled(titleId)
        ) { checked: Boolean ->
            setLoadingSharedLibrariesForTitleEnabled(
                titleId,
                checked
            )
        }
        genericRecyclerViewAdapter.addRecyclerViewItem(loadSharedLibrariesToggle)

        val shaderMultiplicationAccuracyToggle = ToggleRecyclerViewItem(
            "Shader multiplication accuracy",
            "Controls the accuracy of floating point multiplication in shaders",
            isShaderMultiplicationAccuracyForTitleEnabled(titleId)
        ) { checked: Boolean ->
            setShaderMultiplicationAccuracyForTitleEnabled(
                titleId,
                checked
            )
        }
        genericRecyclerViewAdapter.addRecyclerViewItem(shaderMultiplicationAccuracyToggle)

        val cpuModeSelection = SingleSelectionRecyclerViewItem(getString(R.string.cpu_mode),
            getCpuModeForTitle(titleId),
            listOf(
                NativeGameTitles.CPU_MODE_SINGLECOREINTERPRETER,
                NativeGameTitles.CPU_MODE_SINGLECORERECOMPILER,
                NativeGameTitles.CPU_MODE_MULTICORERECOMPILER,
                NativeGameTitles.CPU_MODE_AUTO
            ),
            { cpuMode: Int -> this.cpuModeToString(cpuMode) },
            { cpuMode: Int? ->
                setCpuModeForTitle(
                    titleId,
                    cpuMode!!
                )
            })
        genericRecyclerViewAdapter.addRecyclerViewItem(cpuModeSelection)

        val threadQuantumSelection =
            SingleSelectionRecyclerViewItem(getString(R.string.thread_quantum),
                getThreadQuantumForTitle(titleId),
                Arrays.stream(NativeGameTitles.THREAD_QUANTUM_VALUES).boxed()
                    .collect(Collectors.toList()),
                { obj: Int? -> java.lang.String.valueOf(obj) },
                { threadQuantum: Int? ->
                    setThreadQuantumForTitle(
                        titleId,
                        threadQuantum!!
                    )
                })
        genericRecyclerViewAdapter.addRecyclerViewItem(threadQuantumSelection)

        binding.recyclerView.adapter = genericRecyclerViewAdapter
        setupWithNavController(
            binding.gameEditProfileToolbar, NavHostFragment.findNavController(
                this
            ), Builder().build()
        )
        return binding.root
    }
}
