package info.cemu.cemu.settings.inputoverlay

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import info.cemu.cemu.CemuApplication
import info.cemu.cemu.inputoverlay.InputOverlaySettingsProvider

class InputOverlaySettingsViewModel(
    private val inputOverlaySettingsProvider: InputOverlaySettingsProvider
) : ViewModel() {
    val overlaySettings = inputOverlaySettingsProvider.overlaySettings

    override fun onCleared() {
        super.onCleared()
        inputOverlaySettingsProvider.overlaySettings = overlaySettings
    }

    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                InputOverlaySettingsViewModel(
                    InputOverlaySettingsProvider(CemuApplication.Application)
                )
            }
        }
    }
}