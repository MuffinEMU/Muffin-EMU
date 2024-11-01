#include "Common/ExceptionHandler/ExceptionHandler.h"
#include "JNIUtils.h"

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeLogging_log(JNIEnv* env, [[maybe_unused]] jclass clazz, jstring message)
{
	cemuLog_log(LogType::Force, JNIUtils::JStringToString(env, message));
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeLogging_crashLog(JNIEnv* env, [[maybe_unused]] jclass clazz, jstring stacktrace)
{
	if (!CrashLog_Create())
		return; // give up if crashlog was already created
	CrashLog_WriteLine("Unhandled exception from java code");
	CrashLog_WriteLine(JNIUtils::JStringToString(env, stacktrace));
}
