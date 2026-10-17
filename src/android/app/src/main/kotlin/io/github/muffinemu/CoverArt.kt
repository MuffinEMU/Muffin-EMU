// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

package io.github.muffinemu

import android.content.Context
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Box art from GameTDB, the source the iOS app uses (CoverArtFetcher.swift): the standard front cover, tried
 * across GameTDB's regions and both image formats until one exists. Covers are kept in the app's private files
 * by GameTDB id. A game GameTDB has nothing for gets a marker so it isn't asked again on every launch; a
 * network failure writes no marker, so a later launch tries again.
 */
object CoverArt {
    private val regions = listOf("US", "EN", "JA", "DE", "FR")
    private val extensions = listOf("jpg", "png")
    private val validId = Regex("^[A-Za-z0-9]{4,6}$")

    private fun dir(context: Context) = File(context.filesDir, "covers").apply { mkdirs() }

    private fun cached(context: Context, id: String): File? =
        extensions.map { File(dir(context), "$id.$it") }.firstOrNull { it.isFile }

    /** The cover file for this GameTDB id, downloading it if needed. Blocking: call off the main thread. */
    fun file(context: Context, id: String): File? {
        if (!validId.matches(id)) return null
        cached(context, id)?.let { return it }
        val none = File(dir(context), "$id.none")
        if (none.exists()) return null
        for (region in regions) {
            for (ext in extensions) {
                val connection = URL("https://art.gametdb.com/wiiu/cover/$region/$id.$ext").openConnection() as HttpURLConnection
                connection.connectTimeout = 8000
                connection.readTimeout = 15000
                try {
                    when (connection.responseCode) {
                        404 -> continue
                        200 -> {
                            val bytes = connection.inputStream.use { it.readBytes() }
                            if (!isImage(bytes)) continue
                            return File(dir(context), "$id.$ext").apply { writeBytes(bytes) }
                        }
                        else -> return null // rate limited or a server error: not "no art", so no marker
                    }
                } catch (e: IOException) {
                    return null
                } finally {
                    connection.disconnect()
                }
            }
        }
        none.createNewFile()
        return null
    }

    /** A small decode for a library row, about [maxPixels] on the long side. */
    fun thumbnail(file: File, maxPixels: Int = 192): ImageBitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxPixels) sample *= 2
        val bitmap = BitmapFactory.decodeFile(file.absolutePath, BitmapFactory.Options().apply { inSampleSize = sample })
        return bitmap?.asImageBitmap()
    }

    private fun isImage(bytes: ByteArray): Boolean =
        bytes.size > 4 && ((bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte() && bytes[2] == 0xFF.toByte()) ||
            (bytes[0] == 0x89.toByte() && bytes[1] == 0x50.toByte() && bytes[2] == 0x4E.toByte() && bytes[3] == 0x47.toByte()))
}
