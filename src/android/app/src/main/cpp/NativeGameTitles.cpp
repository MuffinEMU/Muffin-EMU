#include "JNIUtils.h"
#include "GameTitleLoader.h"
#include "AndroidGameTitleLoadedCallback.h"

namespace NativeGameTitles
{
	GameTitleLoader s_gameTitleLoader;
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_setGameTitleLoadedCallback(JNIEnv* env, [[maybe_unused]] jclass clazz, jobject game_title_loaded_callback)
{
	if (game_title_loaded_callback == nullptr)
	{
		NativeGameTitles::s_gameTitleLoader.setOnTitleLoaded(nullptr);
		return;
	}
	jclass gameTitleLoadedCallbackClass = env->GetObjectClass(game_title_loaded_callback);
	jmethodID onGameTitleLoadedMID = env->GetMethodID(gameTitleLoadedCallbackClass, "onGameTitleLoaded", "(Ljava/lang/String;Ljava/lang/String;[III)V");
	env->DeleteLocalRef(gameTitleLoadedCallbackClass);
	NativeGameTitles::s_gameTitleLoader.setOnTitleLoaded(std::make_shared<AndroidGameTitleLoadedCallback>(onGameTitleLoadedMID, game_title_loaded_callback));
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_reloadGameTitles([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz)
{
	NativeGameTitles::s_gameTitleLoader.reloadGameTitles();
}

extern "C" JNIEXPORT jobject JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_getInstalledGamesTitleIds(JNIEnv* env, [[maybe_unused]] jclass clazz)
{
	return JNIUtils::createJavaLongArrayList(env, CafeTitleList::GetAllTitleIds());
}
