package info.cemu.cemu.inputoverlay

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import info.cemu.cemu.R
import info.cemu.cemu.databinding.LayoutGenericRecyclerViewBinding
import info.cemu.cemu.guibasecomponents.GenericRecyclerViewAdapter
import info.cemu.cemu.guibasecomponents.SingleSelectionRecyclerViewItem
import info.cemu.cemu.guibasecomponents.SliderRecyclerViewItem
import info.cemu.cemu.guibasecomponents.ToggleRecyclerViewItem
import info.cemu.cemu.inputoverlay.InputOverlaySettingsProvider.OverlaySettings
import info.cemu.cemu.nativeinterface.NativeInput
import java.util.stream.Collectors
import java.util.stream.IntStream


class InputOverlaySettingsFragment : Fragment() {
    private var overlaySettings: OverlaySettings? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (overlaySettings == null) {
            val inputOverlaySettingsProvider = InputOverlaySettingsProvider(requireContext())
            overlaySettings = inputOverlaySettingsProvider.overlaySettings
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false)
        val genericRecyclerViewAdapter = GenericRecyclerViewAdapter()

        val inputOverlayToggle = ToggleRecyclerViewItem(
            getString(R.string.input_overlay),
            getString(R.string.enable_input_overlay),
            overlaySettings!!.isOverlayEnabled
        ) { checked: Boolean ->
            overlaySettings!!.isOverlayEnabled = checked
            overlaySettings!!.saveSettings()
        }
        genericRecyclerViewAdapter.addRecyclerViewItem(inputOverlayToggle)

        val vibrateOnTouchToggle = ToggleRecyclerViewItem(
            getString(R.string.vibrate),
            getString(R.string.enable_vibrate_on_touch),
            overlaySettings!!.isVibrateOnTouchEnabled
        ) { checked: Boolean ->
            overlaySettings!!.isVibrateOnTouchEnabled = checked
            overlaySettings!!.saveSettings()
        }
        genericRecyclerViewAdapter.addRecyclerViewItem(vibrateOnTouchToggle)

        val alphaSlider = SliderRecyclerViewItem(
            getString(R.string.alpha_slider),
            0f,
            255f,
            overlaySettings!!.alpha.toFloat()
        ) { value: Float ->
            overlaySettings!!.alpha = value.toInt()
            overlaySettings!!.saveSettings()
        }
        genericRecyclerViewAdapter.addRecyclerViewItem(alphaSlider)

        val controllerSelection = SingleSelectionRecyclerViewItem(
            getString(R.string.overlay_controller),
            overlaySettings!!.controllerIndex,
            IntStream.range(0, NativeInput.MAX_CONTROLLERS).boxed().collect(Collectors.toList()),
            { controllerIndex: Int ->
                getString(
                    R.string.controller_numbered,
                    controllerIndex + 1
                )
            },
            { controllerIndex: Int? ->
                overlaySettings!!.controllerIndex =
                    controllerIndex!!
            })
        genericRecyclerViewAdapter.addRecyclerViewItem(controllerSelection)

        binding.recyclerView.adapter = genericRecyclerViewAdapter

        return binding.root
    }
}