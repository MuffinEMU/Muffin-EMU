package info.cemu.cemu.nativeinterface

import java.util.Objects

object NativeGraphicPacks {
    @JvmStatic
    val graphicPackBasicInfos: ArrayList<GraphicPackBasicInfo?>?
        external get

    @JvmStatic
    external fun refreshGraphicPacks()

    @JvmStatic
    external fun getGraphicPack(id: Long): GraphicPack?

    @JvmStatic
    external fun setGraphicPackActive(id: Long, active: Boolean)

    @JvmStatic
    external fun setGraphicPackActivePreset(id: Long, category: String?, preset: String?)

    @JvmStatic
    external fun getGraphicPackPresets(id: Long): ArrayList<GraphicPackPreset>

    @JvmRecord
    data class GraphicPackBasicInfo(
        @JvmField val id: Long,
        @JvmField val virtualPath: String,
        @JvmField val enabled: Boolean,
        @JvmField val titleIds: ArrayList<Long>
    )

    class GraphicPackPreset(
        private val graphicPackId: Long,
        @JvmField val category: String?,
        @JvmField val presets: ArrayList<String>,
        private var activePreset: String
    ) {
        override fun hashCode(): Int {
            return Objects.hash(graphicPackId, category, presets, activePreset)
        }

        override fun equals(other: Any?): Boolean {
            if (other == null) {
                return false
            }
            if (other === this) {
                return true
            }
            if (other is GraphicPackPreset) {
                return this.hashCode() == other.hashCode()
            }
            return false
        }

        fun getActivePreset(): String {
            return activePreset
        }

        fun setActivePreset(activePreset: String) {
            require(
                !presets.stream()
                    .noneMatch { s: String -> s == activePreset }) { "Trying to set an invalid preset: $activePreset" }
            setGraphicPackActivePreset(graphicPackId, category, activePreset)
            this.activePreset = activePreset
        }
    }

    class GraphicPack(
        @JvmField val id: Long,
        private var active: Boolean,
        @JvmField val name: String,
        @JvmField val description: String,
        private var presets: ArrayList<GraphicPackPreset>
    ) {
        fun isActive(): Boolean {
            return active
        }

        fun getPresets(): List<GraphicPackPreset> = presets
        fun reloadPresets() {
            presets = getGraphicPackPresets(id)
        }

        fun setActive(active: Boolean) {
            this.active = active
            setGraphicPackActive(id, active)
        }
    }
}
