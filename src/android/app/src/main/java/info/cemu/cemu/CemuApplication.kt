package info.cemu.cemu

import android.app.Application
import info.cemu.cemu.nativeinterface.NativeEmulation.initializeActiveSettings
import info.cemu.cemu.nativeinterface.NativeEmulation.initializeEmulation
import info.cemu.cemu.nativeinterface.NativeEmulation.setDPI
import info.cemu.cemu.nativeinterface.NativeGraphicPacks.refreshGraphicPacks
import info.cemu.cemu.nativeinterface.NativeLogging.crashLog
import info.cemu.cemu.nativeinterface.NativeSwkbd.initializeSwkbd
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

class CemuApplication : Application() {
    init {
        Application = this
    }

    val internalFolder: File
        get() {
            val externalFilesDir = getExternalFilesDir(null)
            if (externalFilesDir != null) {
                return externalFilesDir
            }
            return filesDir
        }

    override fun onCreate() {
        super.onCreate()
        if (DefaultUncaughtExceptionHandler == null) {
            DefaultUncaughtExceptionHandler = Thread.getDefaultUncaughtExceptionHandler()
        }
        Thread.setDefaultUncaughtExceptionHandler { thread: Thread, exception: Throwable ->
            val stringWriter = StringWriter()
            val printWriter = PrintWriter(stringWriter)
            exception.printStackTrace(printWriter)
            val stacktrace = stringWriter.toString()
            crashLog(stacktrace)
            DefaultUncaughtExceptionHandler!!.uncaughtException(
                thread,
                exception
            )
        }
        val displayMetrics = resources.displayMetrics
        setDPI(displayMetrics.density)
        initializeActiveSettings(internalFolder.toString(), internalFolder.toString())
        initializeEmulation()
        initializeSwkbd()
        refreshGraphicPacks()
    }

    companion object {
        init {
            System.loadLibrary("CemuAndroid")
        }

        private var DefaultUncaughtExceptionHandler: Thread.UncaughtExceptionHandler? = null

        @JvmStatic
        lateinit var Application: CemuApplication
            private set
    }
}
