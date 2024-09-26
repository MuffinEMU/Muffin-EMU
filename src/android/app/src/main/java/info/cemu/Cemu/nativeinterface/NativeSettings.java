package info.cemu.Cemu.nativeinterface;

import java.util.ArrayList;

public class NativeSettings {
    public static native void addGamesPath(String uri);

    public static native void removeGamesPath(String uri);

    public static native ArrayList<String> getGamesPaths();

    public static native boolean getAsyncShaderCompile();

    public static native void setAsyncShaderCompile(boolean enabled);

    public static final int VSYNC_MODE_OFF = 0;
    public static final int VSYNC_MODE_DOUBLE_BUFFERING = 1;
    public static final int VSYNC_MODE_TRIPLE_BUFFERING = 2;

    public static native int getVSyncMode();

    public static native void setVSyncMode(int vsyncMode);

    public static native boolean getAccurateBarriers();

    public static native void setAccurateBarriers(boolean enabled);

    public static native boolean getAudioDeviceEnabled(boolean tv);

    public static native void setAudioDeviceEnabled(boolean enabled, boolean tv);

    public static final int AUDIO_CHANNELS_MONO = 0;
    public static final int AUDIO_CHANNELS_STEREO = 1;
    public static final int AUDIO_CHANNELS_SURROUND = 2;

    public static native void setAudioDeviceChannels(int channels, boolean tv);

    public static native int getAudioDeviceChannels(boolean tv);

    public static final int AUDIO_MIN_VOLUME = 0;
    public static final int AUDIO_MAX_VOLUME = 100;

    public static native void setAudioDeviceVolume(int volume, boolean tv);

    public static native int getAudioDeviceVolume(boolean tv);

    public static final int OVERLAY_SCREEN_POSITION_DISABLED = 0;
    public static final int OVERLAY_SCREEN_POSITION_TOP_LEFT = 1;
    public static final int OVERLAY_SCREEN_POSITION_TOP_CENTER = 2;
    public static final int OVERLAY_SCREEN_POSITION_TOP_RIGHT = 3;
    public static final int OVERLAY_SCREEN_POSITION_BOTTOM_LEFT = 4;
    public static final int OVERLAY_SCREEN_POSITION_BOTTOM_CENTER = 5;
    public static final int OVERLAY_SCREEN_POSITION_BOTTOM_RIGHT = 6;

    public static native int getOverlayPosition();

    public static native void setOverlayPosition(int position);

    public static native boolean isOverlayFPSEnabled();

    public static native void setOverlayFPSEnabled(boolean enabled);

    public static native boolean isOverlayDrawCallsPerFrameEnabled();

    public static native void setOverlayDrawCallsPerFrameEnabled(boolean enabled);

    public static native boolean isOverlayCPUUsageEnabled();

    public static native void setOverlayCPUUsageEnabled(boolean enabled);

    public static native boolean isOverlayCPUPerCoreUsageEnabled();

    public static native void setOverlayCPUPerCoreUsageEnabled(boolean enabled);

    public static native boolean isOverlayRAMUsageEnabled();

    public static native void setOverlayRAMUsageEnabled(boolean enabled);

    public static native boolean isOverlayDebugEnabled();

    public static native void setOverlayDebugEnabled(boolean enabled);

    public static native int getNotificationsPosition();

    public static native void setNotificationsPosition(int position);

    public static native boolean isNotificationControllerProfilesEnabled();

    public static native void setNotificationControllerProfilesEnabled(boolean enabled);

    public static native boolean isNotificationShaderCompilerEnabled();

    public static native void setNotificationShaderCompilerEnabled(boolean enabled);

    public static native boolean isNotificationFriendListEnabled();

    public static native void setNotificationFriendListEnabled(boolean enabled);
}
