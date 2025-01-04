package info.cemu.cemu.titlemanager

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import info.cemu.cemu.utils.copyInputStreamToFile
import info.cemu.cemu.utils.urlDecode
import java.nio.file.Path
import java.util.LinkedList
import kotlin.io.path.Path
import kotlin.io.path.createDirectories
import kotlin.math.max

