package info.cemu.cemu.settings

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.provider.DocumentsContract
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.navigation.fragment.NavHostFragment
import info.cemu.cemu.R
import info.cemu.cemu.databinding.LayoutGenericRecyclerViewBinding
import info.cemu.cemu.features.DocumentsProvider
import info.cemu.cemu.guibasecomponents.GenericRecyclerViewAdapter
import info.cemu.cemu.guibasecomponents.SimpleButtonRecyclerViewItem

class SettingsFragment : Fragment() {
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val binding = LayoutGenericRecyclerViewBinding.inflate(inflater, container, false)
        val genericRecyclerViewAdapter = GenericRecyclerViewAdapter()

        genericRecyclerViewAdapter.addRecyclerViewItem(SimpleButtonRecyclerViewItem(
            getString(R.string.open_cemu_folder)
        ) { this.openCemuFolder() })
        val navController = NavHostFragment.findNavController(this)
        genericRecyclerViewAdapter.addRecyclerViewItem(SimpleButtonRecyclerViewItem(
            getString(R.string.general_settings)
        ) { navController.navigate(R.id.action_settingsFragment_to_generalSettingsFragment) })
        genericRecyclerViewAdapter.addRecyclerViewItem(SimpleButtonRecyclerViewItem(
            getString(R.string.input_settings)
        ) { navController.navigate(R.id.action_settingsFragment_to_inputSettingsFragment) })
        genericRecyclerViewAdapter.addRecyclerViewItem(SimpleButtonRecyclerViewItem(
            getString(R.string.graphics_settings)
        ) { navController.navigate(R.id.action_settingsFragment_to_graphicSettingsFragment) })
        genericRecyclerViewAdapter.addRecyclerViewItem(SimpleButtonRecyclerViewItem(
            getString(R.string.audio_settings)
        ) { navController.navigate(R.id.action_settingsFragment_to_audioSettingsFragment) })
        genericRecyclerViewAdapter.addRecyclerViewItem(SimpleButtonRecyclerViewItem(
            getString(R.string.graphic_packs)
        ) { navController.navigate(R.id.action_settingsFragment_to_graphicPacksRootFragment) })
        genericRecyclerViewAdapter.addRecyclerViewItem(SimpleButtonRecyclerViewItem(
            getString(R.string.overlay)
        ) { navController.navigate(R.id.action_settingsFragment_to_overlaySettingsFragment) })
        binding.recyclerView.adapter = genericRecyclerViewAdapter

        return binding.root
    }

    private fun openCemuFolder() {
        try {
            val intent = Intent(Intent.ACTION_VIEW)
            intent.addCategory(Intent.CATEGORY_DEFAULT)
            intent.setData(
                DocumentsContract.buildRootUri(
                    DocumentsProvider.AUTHORITY,
                    DocumentsProvider.ROOT_ID
                )
            )
            intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            requireContext().startActivity(intent)
        } catch (activityNotFoundException: ActivityNotFoundException) {
            Toast.makeText(requireContext(), R.string.failed_to_open_cemu_folder, Toast.LENGTH_LONG)
                .show()
        }
    }
}