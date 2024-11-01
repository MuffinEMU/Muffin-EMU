package info.cemu.Cemu.nativeinterface;

public class NativeLogging {
    public static native void log(String message);

    public static native void crashLog(String stacktrace);
}
