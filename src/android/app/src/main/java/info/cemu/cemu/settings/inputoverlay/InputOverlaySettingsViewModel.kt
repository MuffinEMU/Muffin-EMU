package info.cemu.cemu.settings.inputoverlay

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import info.cemu.cemu.CemuApplication
import info.cemu.cemu.inputoverlay.InputOverlaySettingsManager

class InputOverlaySettingsViewModel(
    private val inputOverlaySettingsManager: InputOverlaySettingsManager
) : ViewModel() {
    val overlaySettings = inputOverlaySettingsManager.overlaySettings

    override fun onCleared() {
        super.onCleared()
        inputOverlaySettingsManager.overlaySettings = overlaySettings
    }

    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                InputOverlaySettingsViewModel(
                    InputOverlaySettingsManager(CemuApplication.Application)
                )
            }
        }
    }
}