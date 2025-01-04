package info.cemu.cemu.utils

import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.nio.file.Paths
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream

@Throws(IOException::class)
fun unzip(stream: InputStream?, targetDir: String) {
    ZipInputStream(stream).use { zipInputStream ->
        var zipEntry: ZipEntry
        val buffer = ByteArray(8192)
        while ((zipInputStream.nextEntry.also { zipEntry = it }) != null) {
            extractZipEntry(zipInputStream, zipEntry, buffer, targetDir)
            zipInputStream.closeEntry()
        }
    }
}

private fun extractZipEntry(
    zipInputStream: ZipInputStream,
    zipEntry: ZipEntry,
    buffer: ByteArray,
    targetDir: String,
) {
    val file = Paths.get(targetDir, zipEntry.name).toFile()
    if (zipEntry.isDirectory) {
        file.apply { if (!isDirectory) mkdirs() }
        return
    }
    FileOutputStream(file).use { fileOutputStream ->
        var bytesRead: Int
        while ((zipInputStream.read(buffer).also { bytesRead = it }) > 0) {
            fileOutputStream.write(buffer, 0, bytesRead)
        }
    }
}
