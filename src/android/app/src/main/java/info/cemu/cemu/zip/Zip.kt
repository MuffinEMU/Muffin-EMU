package info.cemu.cemu.zip

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.nio.file.Paths
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream

@Throws(IOException::class)
fun unzip(stream: InputStream?, targetDir: String?) {
    ZipInputStream(stream).use { zipInputStream ->
        var zipEntry: ZipEntry
        val buffer = ByteArray(8192)
        while ((zipInputStream.nextEntry.also { zipEntry = it }) != null) {
            val filePath = Paths.get(targetDir, zipEntry.name).toString()
            if (zipEntry.isDirectory) {
                createDir(filePath)
            } else {
                FileOutputStream(filePath).use { fileOutputStream ->
                    var bytesRead: Int
                    while ((zipInputStream.read(buffer).also { bytesRead = it }) > 0) {
                        fileOutputStream.write(buffer, 0, bytesRead)
                    }
                }
            }
            zipInputStream.closeEntry()
        }
    }
}

private fun createDir(dir: String) {
    val f = File(dir)
    if (!f.isDirectory) {
        f.mkdirs()
    }
}
