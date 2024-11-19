#include "JNIUtils.h"
#include "config/ActiveSettings.h"

extern "C" [[maybe_unused]] JNIEXPORT jstring JNICALL
Java_info_cemu_cemu_nativeinterface_NativeActiveSettings_getMLCPath(JNIEnv* env, [[maybe_unused]] jclass clazz)
{
	return env->NewStringUTF(ActiveSettings::GetMlcPath().c_str());
}
