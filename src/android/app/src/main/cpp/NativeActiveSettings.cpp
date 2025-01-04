#include "JNIUtils.h"
#include "config/ActiveSettings.h"

extern "C" [[maybe_unused]] JNIEXPORT jstring JNICALL
Java_info_cemu_cemu_nativeinterface_NativeActiveSettings_getMLCPath(JNIEnv* env, [[maybe_unused]] jclass clazz)
{
	return JNIUtils::toJString(env, ActiveSettings::GetMlcPath());
}

extern "C" [[maybe_unused]] JNIEXPORT jstring JNICALL
Java_info_cemu_cemu_nativeinterface_NativeActiveSettings_getUserDataPath(JNIEnv* env, [[maybe_unused]] jclass clazz)
{
	return JNIUtils::toJString(env, ActiveSettings::GetUserDataPath());
}
