package info.cemu.cemu.settings.graphics

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import info.cemu.cemu.R
import info.cemu.cemu.databinding.LayoutGenericRecyclerViewBinding
import info.cemu.cemu.guibasecomponents.GenericRecyclerViewAdapter
import info.cemu.cemu.guibasecomponents.SingleSelectionRecyclerViewItem
import info.cemu.cemu.guibasecomponents.ToggleRecyclerViewItem
import info.cemu.cemu.nativeinterface.NativeSettings
import info.cemu.cemu.nativeinterface.NativeSettings.accurateBarriers
import info.cemu.cemu.nativeinterface.NativeSettings.asyncShaderCompile
import info.cemu.cemu.nativeinterface.NativeSettings.downscalingFilter
import info.cemu.cemu.nativeinterface.NativeSettings.fullscreenScaling
import info.cemu.cemu.nativeinterface.NativeSettings.upscalingFilter
import info.cemu.cemu.nativeinterface.NativeSettings.vSyncMode
import java.util.List

class GraphicsSettingsFragment : Fragment() {
    private fun vsyncModeToString(vsyncMode: Int): String {
        val resourceId = when (vsyncMode) {
            NativeSettings.VSYNC_MODE_OFF -> R.string.off
            NativeSettings.VSYNC_MODE_DOUBLE_BUFFERING -> R.string.double_buffering
            NativeSettings.VSYNC_MODE_TRIPLE_BUFFERING -> R.string.triple_buffering
            else -> throw IllegalArgumentException("Invalid vsync mode: $vsyncMode")
        }
        return getString(resourceId)
    }

    private fun fullscreenScalingModeToString(fullscreenScaling: Int): String {
        val resourceId = when (fullscreenScaling) {
            NativeSettings.FULLSCREEN_SCALING_KEEP_ASPECT_RATIO -> R.string.keep_aspect_ratio
            NativeSettings.FULLSCREEN_SCALING_STRETCH -> R.string.stretch
            else -> throw IllegalArgumentException("Invalid fullscreen scaling mode:  $fullscreenScaling")
        }
        return getString(resourceId)
    }

    private fun scalingFilterToString(scalingFilter: Int): String {
        val resourceId = when (scalingFilter) {
            NativeSettings.SCALING_FILTER_BILINEAR_FILTER -> R.string.bilinear
            NativeSettings.SCALING_FILTER_BICUBIC_FILTER -> R.string.bicubic
            NativeSettings.SCALING_FILTER_BICUBIC_HERMITE_FILTER -> R.string.hermite
            NativeSettings.SCALING_FILTER_NEAREST_NEIGHBOR_FILTER -> R.string.nearest_neighbor
            else -> throw IllegalArgumentException("Invalid scaling filter:  $scalingFilter")
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

        val asyncShaderToggle = ToggleRecyclerViewItem(
            getString(R.string.async_shader_compile),
            getString(R.string.async_shader_compile_description),
            asyncShaderCompile,
            NativeSettings::asyncShaderCompile::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(asyncShaderToggle)

        val vsyncModeSelection = SingleSelectionRecyclerViewItem(
            getString(R.string.vsync),
            vSyncMode,
            listOf(
                NativeSettings.VSYNC_MODE_OFF,
                NativeSettings.VSYNC_MODE_DOUBLE_BUFFERING,
                NativeSettings.VSYNC_MODE_TRIPLE_BUFFERING
            ),
            { vsyncMode: Int -> this.vsyncModeToString(vsyncMode) },
            NativeSettings::vSyncMode::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(vsyncModeSelection)

        val accurateBarriersToggle = ToggleRecyclerViewItem(
            getString(R.string.accurate_barriers),
            getString(R.string.accurate_barriers_description),
            accurateBarriers,
            NativeSettings::accurateBarriers::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(accurateBarriersToggle)

        val fullscreenScalingSelection = SingleSelectionRecyclerViewItem(
            getString(R.string.fullscreen_scaling),
            fullscreenScaling,
            listOf(
                NativeSettings.FULLSCREEN_SCALING_KEEP_ASPECT_RATIO,
                NativeSettings.FULLSCREEN_SCALING_STRETCH
            ),
            { fullscreenScaling: Int -> this.fullscreenScalingModeToString(fullscreenScaling) },
            NativeSettings::fullscreenScaling::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(fullscreenScalingSelection)

        val scalingFilterChoices = List.of(
            NativeSettings.SCALING_FILTER_BILINEAR_FILTER,
            NativeSettings.SCALING_FILTER_BICUBIC_FILTER,
            NativeSettings.SCALING_FILTER_BICUBIC_HERMITE_FILTER,
            NativeSettings.SCALING_FILTER_NEAREST_NEIGHBOR_FILTER
        )

        val upscaleFilterSelection = SingleSelectionRecyclerViewItem(
            getString(R.string.upscale_filter),
            upscalingFilter,
            scalingFilterChoices,
            { scalingFilter: Int -> this.scalingFilterToString(scalingFilter) },
            NativeSettings::upscalingFilter::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(upscaleFilterSelection)

        val downscaleFilterSelection = SingleSelectionRecyclerViewItem(
            getString(R.string.downscale_filter),
            downscalingFilter,
            scalingFilterChoices,
            { scalingFilter: Int -> this.scalingFilterToString(scalingFilter) },
            NativeSettings::downscalingFilter::set
        )
        genericRecyclerViewAdapter.addRecyclerViewItem(downscaleFilterSelection)

        binding.recyclerView.adapter = genericRecyclerViewAdapter
        return binding.root
    }
}