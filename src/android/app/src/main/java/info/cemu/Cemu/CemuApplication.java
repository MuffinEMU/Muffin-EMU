package info.cemu.Cemu;

import android.app.Application;
import android.util.DisplayMetrics;

import java.io.File;
import java.io.PrintWriter;
import java.io.StringWriter;

import info.cemu.Cemu.nativeinterface.NativeEmulation;
import info.cemu.Cemu.nativeinterface.NativeGraphicPacks;
import info.cemu.Cemu.nativeinterface.NativeLogging;
import info.cemu.Cemu.nativeinterface.NativeSwkbd;

public class CemuApplication extends Application {
    static {
        System.loadLibrary("CemuAndroid");
    }

    private static Thread.UncaughtExceptionHandler defaultUncaughtExceptionHandler;
    private static CemuApplication application;

    public CemuApplication() {
        application = this;
    }

    public static CemuApplication getApplication() {
        return application;
    }

    public File getInternalFolder() {
        var externalFilesDir = getExternalFilesDir(null);
        if (externalFilesDir != null) {
            return externalFilesDir;
        }
        return getFilesDir();
    }

    @Override
    public void onCreate() {
        super.onCreate();
        if (defaultUncaughtExceptionHandler == null) {
            defaultUncaughtExceptionHandler = Thread.getDefaultUncaughtExceptionHandler();
        }
        Thread.setDefaultUncaughtExceptionHandler((thread, exception) -> {
            StringWriter stringWriter = new StringWriter();
            PrintWriter printWriter = new PrintWriter(stringWriter);
            exception.printStackTrace(printWriter);
            String stacktrace = stringWriter.toString();
            NativeLogging.crashLog(stacktrace);
            defaultUncaughtExceptionHandler.uncaughtException(thread, exception);
        });
        DisplayMetrics displayMetrics = getResources().getDisplayMetrics();
        NativeEmulation.setDPI(displayMetrics.density);
        NativeEmulation.initializeActiveSettings(getInternalFolder().toString(), getInternalFolder().toString());
        NativeEmulation.initializeEmulation();
        NativeSwkbd.initializeSwkbd();
        NativeGraphicPacks.refreshGraphicPacks();
    }
}
