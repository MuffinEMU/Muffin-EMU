package info.cemu.Cemu;

import android.app.Application;
import android.util.DisplayMetrics;

import java.io.File;
import java.util.Objects;

import info.cemu.Cemu.NativeLibrary;
import info.cemu.Cemu.utils.FileUtil;

public class CemuApplication extends Application {
    private static CemuApplication application;

    public CemuApplication() {
        application = this;
    }

    public static CemuApplication getApplication() {
        return application;
    }

    public File getInternalFolder() {
        var externalFilesDir = getExternalFilesDir(null);
        if (externalFilesDir != null)
            return externalFilesDir;
        return getFilesDir();
    }

    @Override
    public void onCreate() {
        super.onCreate();
        DisplayMetrics displayMetrics = getResources().getDisplayMetrics();
        NativeLibrary.setDPI(displayMetrics.density);
        NativeLibrary.initializeActiveSettings(getInternalFolder().toString(), getInternalFolder().toString());
        NativeLibrary.initializeEmulation();
    }
}
