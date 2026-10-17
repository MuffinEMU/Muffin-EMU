// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

package io.github.muffinemu

import android.app.Application
import android.content.Context
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Where MuffinEMU keeps things on Android, and the one-time core start.
 *
 * Everything the player touches lives in the app's external files directory, which the Files app shows as
 * Android/data/io.github.muffinemu/files: Roms (games), mlc (the console's storage, saves, keys.txt), and
 * log.txt. No storage permission is needed for it. The read-only CemuData (shared fonts, game profiles)
 * is unpacked from the APK's assets into the private files directory.
 */
class MuffinApp : Application() {
    companion object {
        private const val DATA_STAMP = "cemudata-1"
        private val coreStarted = AtomicBoolean(false)

        fun userRoot(context: Context): File =
            (context.getExternalFilesDir(null) ?: context.filesDir)

        fun romsDir(context: Context): File = File(userRoot(context), "Roms").apply { mkdirs() }
        fun mlcDir(context: Context): File = File(userRoot(context), "mlc").apply { mkdirs() }
        fun keysFile(context: Context): File = File(mlcDir(context), "keys.txt")
        fun dataDir(context: Context): File = File(context.filesDir, "CemuData")

        /** Unpacks assets/CemuData once per app version, then starts the core. Blocking: call off the main thread. */
        fun startCore(context: Context): Boolean {
            if (coreStarted.get()) return true
            synchronized(coreStarted) {
                if (coreStarted.get()) return true
                val data = dataDir(context)
                val stamp = File(data, ".stamp")
                if (!stamp.exists() || stamp.readText() != DATA_STAMP) {
                    data.deleteRecursively()
                    copyAssetDir(context, "CemuData", data)
                    stamp.writeText(DATA_STAMP)
                }
                val ok = NativeBridge.initialize(mlcDir(context).absolutePath, data.absolutePath)
                coreStarted.set(ok)
                return ok
            }
        }

        private fun copyAssetDir(context: Context, assetPath: String, target: File) {
            val children = context.assets.list(assetPath) ?: emptyArray()
            if (children.isEmpty()) {
                target.parentFile?.mkdirs()
                context.assets.open(assetPath).use { input -> target.outputStream().use { input.copyTo(it) } }
                return
            }
            target.mkdirs()
            for (child in children) copyAssetDir(context, "$assetPath/$child", File(target, child))
        }
    }
}
