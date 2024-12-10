package info.cemu.cemu.graphicpacks

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.CreationExtras
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import info.cemu.cemu.nativeinterface.NativeGraphicPacks
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class Preset(
    val index: Int,
    val category: String?,
    val activePreset: String,
    val presets: List<String>,
)

class GraphicPackDataViewModel(private val graphicPackNode: GraphicPackDataNode) : ViewModel() {
    private val nativeGraphicPack = NativeGraphicPacks.getGraphicPack(graphicPackNode.id)
    val description = nativeGraphicPack?.description ?: ""
    private var nativePresets: List<NativeGraphicPacks.GraphicPackPreset> = emptyList()
    private val _presets = MutableStateFlow<List<Preset>>(emptyList())
    val presets = _presets.asStateFlow()

    val name = graphicPackNode.name

    private var _enabled = MutableStateFlow(graphicPackNode.enabled)
    val enabled = _enabled.asStateFlow()
    fun setEnabled(enabled: Boolean) {
        nativeGraphicPack?.setActive(enabled)
        _enabled.value = enabled
        graphicPackNode.enabled = enabled
    }

    init {
        refreshPresets()
    }

    private fun refreshPresets() {
        nativeGraphicPack?.reloadPresets()
        if (nativePresets == nativeGraphicPack?.presets) {
            return
        }
        nativePresets = nativeGraphicPack?.presets ?: emptyList()
        nativePresets.mapIndexed { index, preset ->
            Preset(
                index = index,
                category = preset.category,
                activePreset = preset.activePreset,
                presets = preset.presets,
            )
        }.let {
            _presets.value = it
        }
    }

    fun setActivePreset(index: Int, activePreset: String) {
        _presets.value = _presets.value.toMutableList().apply {
            set(index, get(index).copy(activePreset = activePreset))
        }
        nativePresets[index].activePreset = activePreset
        refreshPresets()
    }

    companion object {
        val GRAPHIC_PACK_KEY = object : CreationExtras.Key<GraphicPackDataNode> {}
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                GraphicPackDataViewModel(
                    this[GRAPHIC_PACK_KEY] as GraphicPackDataNode
                )
            }
        }
    }
}