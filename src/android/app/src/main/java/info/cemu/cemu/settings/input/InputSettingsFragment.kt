package info.cemu.cemu.settings.input

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
import info.cemu.cemu.guibasecomponents.SimpleButtonRecyclerViewItem
import info.cemu.cemu.nativeinterface.NativeInput
import info.cemu.cemu.nativeinterface.NativeInput.getControllerType
import info.cemu.cemu.nativeinterface.NativeInput.isControllerDisabled
import info.cemu.cemu.settings.input.ControllerTypeResourceNameMapper.controllerTypeToResourceNameId


class InputSettingsFragment : Fragment() {
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false)
        val genericRecyclerViewAdapter = GenericRecyclerViewAdapter()
        genericRecyclerViewAdapter.addRecyclerViewItem(
            SimpleButtonRecyclerViewItem(
                getString(R.string.input_overlay_settings)
            ) {
                NavHostFragment.findNavController(
                    this@InputSettingsFragment
                ).navigate(R.id.action_inputSettingsFragment_to_inputOverlaySettingsFragment)
            }
        )

        for (index in 0 until NativeInput.MAX_CONTROLLERS) {
            val controllerIndex = index
            val controllerType =
                if (isControllerDisabled(controllerIndex)) NativeInput.EMULATED_CONTROLLER_TYPE_DISABLED else getControllerType(
                    controllerIndex
                )
            val controllerTypeName = getString(controllerTypeToResourceNameId(controllerType))
            val buttonRecyclerViewItem = ButtonRecyclerViewItem(
                getString(R.string.controller_numbered, controllerIndex + 1),
                getString(R.string.emulated_controller_with_type, controllerTypeName)
            ) {
                val bundle = Bundle()
                bundle.putInt(ControllerInputsFragment.CONTROLLER_INDEX, controllerIndex)
                NavHostFragment.findNavController(this@InputSettingsFragment)
                    .navigate(
                        R.id.action_inputSettingsFragment_to_controllerInputsFragment,
                        bundle
                    )
            }
            genericRecyclerViewAdapter.addRecyclerViewItem(buttonRecyclerViewItem)
        }
        binding.recyclerView.adapter = genericRecyclerViewAdapter
        return binding.root
    }
}
