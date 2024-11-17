@file:Suppress("unused")

package info.cemu.cemu.nativeinterface

import android.net.Uri
import android.provider.DocumentsContract
import android.util.Log
import info.cemu.cemu.CemuApplication
import info.cemu.cemu.io.Files
import java.io.IOException
import java.nio.file.Path

private const val PATH_SEPARATOR_ENCODED = "%2F"
private const val PATH_SEPARATOR_DECODED = "/"
private const val COLON_ENCODED = "%3A"
private const val MODE = "r"

private fun Uri.toCppPath(): String {
    val uriPath = toString()
    val delimiterPos = uriPath.lastIndexOf(COLON_ENCODED)
    if (delimiterPos == -1) {
        return uriPath
    }
    return uriPath.substring(0, delimiterPos) + uriPath.substring(delimiterPos).replace(
        PATH_SEPARATOR_ENCODED, PATH_SEPARATOR_DECODED
    )
}

private fun String.fromCppPath(): Uri {
    val delimiterPos = lastIndexOf(COLON_ENCODED)
    if (delimiterPos == -1) {
        return Uri.parse(this)
    }
    return Uri.parse(
        substring(0, delimiterPos) + substring(delimiterPos).replace(
            PATH_SEPARATOR_DECODED, PATH_SEPARATOR_ENCODED
        )
    )
}

fun openContentUri(uri: String): Int {
    try {
        if (!exists(uri)) {
            return -1
        }
        val parcelFileDescriptor =
            CemuApplication.application.applicationContext.contentResolver.openFileDescriptor(
                uri.fromCppPath(), MODE
            )
        if (parcelFileDescriptor != null) {
            val fd = parcelFileDescriptor.detachFd()
            parcelFileDescriptor.close()
            return fd
        }
    } catch (e: Exception) {
        Log.e("FileCallbacks", "Cannot open content uri, error: " + e.message)
    }
    return -1
}

fun listFiles(uri: String): Array<String?> {
    val files = ArrayList<String>()
    val directoryUri = uri.fromCppPath()
    val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
        directoryUri,
        DocumentsContract.getDocumentId(directoryUri)
    )
    try {
        CemuApplication.application.applicationContext.contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
            null,
            null,
            null
        ).use { cursor ->
            while (cursor != null && cursor.moveToNext()) {
                val documentId = cursor.getString(0)
                val documentUri =
                    DocumentsContract.buildDocumentUriUsingTree(directoryUri, documentId)
                files.add(documentUri.toCppPath())
            }
        }
    } catch (e: Exception) {
        Log.e("FileCallbacks", "Cannot list files: " + e.message)
    }
    var filesArray = arrayOfNulls<String>(files.size)
    filesArray = files.toArray(filesArray)
    return filesArray
}

fun isDirectory(uri: String): Boolean {
    val mimeType = CemuApplication.application.applicationContext.contentResolver.getType(
        uri.fromCppPath()
    )
    return DocumentsContract.Document.MIME_TYPE_DIR == mimeType
}

fun isFile(uri: String): Boolean {
    return !isDirectory(uri)
}

fun exists(uri: String): Boolean {
    try {
        CemuApplication.application.applicationContext.contentResolver.query(
            uri.fromCppPath(), null, null, null, null
        ).use { cursor ->
            return cursor != null && cursor.moveToFirst()
        }
    } catch (e: Exception) {
        Log.e("FileCallbacks", "Failed checking if file exists: " + e.message)
        return false
    }
}

fun delete(fileToDelete: Path) {
    try {
        Files.delete(fileToDelete.toFile())
    } catch (ignored: IOException) {
    }
}
