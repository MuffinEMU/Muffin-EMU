@file:OptIn(ExperimentalPathApi::class, ExperimentalUuidApi::class)

package info.cemu.cemu.settings.customdrivers

import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import info.cemu.cemu.nativeinterface.NativeActiveSettings
import info.cemu.cemu.nativeinterface.NativeSettings
import info.cemu.cemu.utils.decodeJsonFromFile
import info.cemu.cemu.utils.unzip
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.serialization.Serializable
import java.io.File
import java.io.InputStream
import kotlin.io.path.ExperimentalPathApi
import kotlin.io.path.Path
import kotlin.io.path.createDirectories
import kotlin.io.path.deleteRecursively
import kotlin.io.path.exists
import kotlin.io.path.isDirectory
import kotlin.io.path.moveTo
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

@Serializable
data class DriverMetadata(
    val schemaVersion: Int,
    val name: String,
    val description: String,
    val author: String,
    val packageVersion: String,
    val vendor: String,
    val driverVersion: String,
    val minApi: Int,
    val libraryName: String,
)

data class Driver(
    val path: String,
    val metadata: DriverMetadata,
    val selected: Boolean = false,
)

enum class DriverInstallStatus {
    Installed,
    AlreadyInstalled,
    ErrorInstalling,
}

class CustomDriversViewModel : ViewModel() {
    private val selectedDriverPath = MutableStateFlow(NativeSettings.getCustomDriverPath())
    val isSystemDriverSelected = selectedDriverPath.map { it == null }.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5000),
        false
    )

    private val _installedDrivers = MutableStateFlow<List<Driver>>(emptyList())
    val installedDrivers = _installedDrivers.asStateFlow()

    init {
        _installedDrivers.value = parseInstalledDrivers()
    }

    private fun parseInstalledDrivers(): List<Driver> {
        val customDriversDir = getCustomDriversDir()

        if (!customDriversDir.isDirectory())
            return emptyList()

        val driverDirs: Array<File> = customDriversDir.toFile().listFiles() ?: return emptyList()

        val drivers = mutableListOf<Driver>()
        val selectedDriver = selectedDriverPath.value

        for (driverDir in driverDirs) {
            if (!driverDir.isDirectory)
                continue
            val metadata =
                decodeJsonFromFile<DriverMetadata>(driverDir.resolve(META_FILE_NAME)) ?: continue
            val driver = Driver(
                path = driverDir.path,
                metadata = metadata,
                selected = selectedDriver == driverDir.path,
            )
            drivers.add(driver)
        }

        drivers.sortBy { it.metadata.name }

        return drivers
    }

    fun installDriver(driverZipFileInputStream: InputStream): DriverInstallStatus {
        val tempDir =
            Path(NativeActiveSettings.getUserDataPath()).resolve(Uuid.random().toString())

        try {
            tempDir.createDirectories()
            unzip(driverZipFileInputStream, tempDir)

            val metadata =
                decodeJsonFromFile<DriverMetadata>(tempDir.resolve(META_FILE_NAME).toFile())
            if (metadata == null
                || metadata.minApi > Build.VERSION.SDK_INT
                || metadata.schemaVersion != SUPPORTED_SCHEMA_VERSION
                || !tempDir.resolve(metadata.libraryName).exists()
            ) {
                tempDir.deleteRecursively()
                return DriverInstallStatus.ErrorInstalling
            }

            if (_installedDrivers.value.any { it.metadata == metadata }) {
                tempDir.deleteRecursively()
                return DriverInstallStatus.AlreadyInstalled
            }

            val customDriversDir = getCustomDriversDir()
            customDriversDir.createDirectories()
            val driverPath = tempDir.moveTo(customDriversDir.resolve(tempDir.fileName))

            _installedDrivers.value = _installedDrivers.value.toMutableList().apply {
                val driver = Driver(
                    metadata = metadata,
                    path = driverPath.toString(),
                )
                add(driver)
                sortBy { it.metadata.name }
            }

            return DriverInstallStatus.Installed
        } catch (exception: Exception) {
            tempDir.deleteRecursively()
            return DriverInstallStatus.ErrorInstalling
        }
    }

    fun deleteDriver(driver: Driver) {
        if (!_installedDrivers.value.any { it == driver })
            return

        _installedDrivers.value -= driver
        if (selectedDriverPath.value == driver.path) {
            selectedDriverPath.value = null
            NativeSettings.setCustomDriverPath(null)
        }

        Path(driver.path).toFile().deleteRecursively()
    }

    fun setSystemDriverSelected() {
        if (selectedDriverPath.value == null)
            return

        val installedDrivers = _installedDrivers.value.toMutableList()
        val oldSelectedDriverIndex = installedDrivers.indexOfFirst { it.selected }
        if (oldSelectedDriverIndex != -1) {
            installedDrivers[oldSelectedDriverIndex] =
                installedDrivers[oldSelectedDriverIndex].copy(selected = false)
            _installedDrivers.value = installedDrivers
        }

        selectedDriverPath.value = null
        NativeSettings.setCustomDriverPath(null)
    }

    fun setDriverSelected(driver: Driver) {
        if (selectedDriverPath.value == driver.path)
            return

        val installedDrivers = _installedDrivers.value.toMutableList()

        val oldSelectedDriverIndex = installedDrivers.indexOfFirst { it.selected }
        if (oldSelectedDriverIndex != -1)
            installedDrivers[oldSelectedDriverIndex] =
                installedDrivers[oldSelectedDriverIndex].copy(selected = false)

        val newSelectedDriverIndex = installedDrivers.indexOf(driver)
        if (newSelectedDriverIndex == -1)
            return
        installedDrivers[newSelectedDriverIndex] = driver.copy(selected = true)

        _installedDrivers.value = installedDrivers

        NativeSettings.setCustomDriverPath(driver.path)
        selectedDriverPath.value = driver.path
    }

    companion object {
        private const val SUPPORTED_SCHEMA_VERSION = 1
        private const val META_FILE_NAME = "meta.json"
        private const val CUSTOM_DRIVERS_DIR_NAME = "customDrivers"
        private fun getCustomDriversDir() =
            Path(NativeActiveSettings.getUserDataPath()).resolve(CUSTOM_DRIVERS_DIR_NAME)
    }
}