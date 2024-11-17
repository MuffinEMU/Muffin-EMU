package info.cemu.cemu.io

import java.io.File
import java.io.IOException

object Files {
    @JvmStatic
    @Throws(IOException::class)
    fun delete(file: File) {
        val files = file.listFiles()
        if (files == null) {
            file.delete()
            return
        }
        files.forEach { delete(it) }
        file.delete()
    }
}
