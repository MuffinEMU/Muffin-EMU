#include "JNIUtils.h"
#include "Cafe/GameProfile/GameProfile.h"
#include "GameTitleLoader.h"
#include "AndroidGameTitleLoadedCallback.h"

namespace NativeGameTitles
{
	GameTitleLoader s_gameTitleLoader;

	std::list<fs::path> getCachesPaths(const TitleId& titleId)
	{
		std::list<fs::path> cachePaths{
			ActiveSettings::GetCachePath("shaderCache/driver/vk/{:016x}.bin", titleId),
			ActiveSettings::GetCachePath("shaderCache/precompiled/{:016x}_spirv.bin", titleId),
			ActiveSettings::GetCachePath("shaderCache/precompiled/{:016x}_gl.bin", titleId),
			ActiveSettings::GetCachePath("shaderCache/transferable/{:016x}_shaders.bin", titleId),
			ActiveSettings::GetCachePath("shaderCache/transferable/{:016x}_vkpipeline.bin", titleId),
		};

		cachePaths.remove_if([](const fs::path& cachePath) {
			std::error_code ec;
			return !fs::exists(cachePath, ec);
		});

		return cachePaths;
	}
	TitleId s_currentTitleId = 0;
	GameProfile s_currentGameProfile{};
	void LoadGameProfile(TitleId titleId)
	{
		if (s_currentTitleId == titleId)
			return;
		s_currentTitleId = titleId;
		s_currentGameProfile.Reset();
		s_currentGameProfile.Load(titleId);
	}
} // namespace NativeGameTitles

extern "C" [[maybe_unused]] JNIEXPORT jboolean JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_isLoadingSharedLibrariesForTitleEnabled([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	return NativeGameTitles::s_currentGameProfile.ShouldLoadSharedLibraries().value_or(false);
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_setLoadingSharedLibrariesForTitleEnabled([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id, jboolean enabled)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	NativeGameTitles::s_currentGameProfile.SetShouldLoadSharedLibraries(enabled);
	NativeGameTitles::s_currentGameProfile.Save(game_title_id);
}

extern "C" [[maybe_unused]] JNIEXPORT jint JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_getCpuModeForTitle([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	return static_cast<jint>(NativeGameTitles::s_currentGameProfile.GetCPUMode().value_or(CPUMode::Auto));
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_setCpuModeForTitle([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id, jint cpu_mode)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	NativeGameTitles::s_currentGameProfile.SetCPUMode(static_cast<CPUMode>(cpu_mode));
	NativeGameTitles::s_currentGameProfile.Save(game_title_id);
}

extern "C" [[maybe_unused]] JNIEXPORT jint JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_getThreadQuantumForTitle([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	return NativeGameTitles::s_currentGameProfile.GetThreadQuantum();
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_setThreadQuantumForTitle([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id, jint thread_quantum)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	NativeGameTitles::s_currentGameProfile.SetThreadQuantum(std::clamp(thread_quantum, 5000, 536870912));
	NativeGameTitles::s_currentGameProfile.Save(game_title_id);
}

extern "C" [[maybe_unused]] JNIEXPORT jboolean JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_isShaderMultiplicationAccuracyForTitleEnabled([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	return NativeGameTitles::s_currentGameProfile.GetAccurateShaderMul() == AccurateShaderMulOption::True;
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_setShaderMultiplicationAccuracyForTitleEnabled([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id, jboolean enabled)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	NativeGameTitles::s_currentGameProfile.SetAccurateShaderMul(enabled ? AccurateShaderMulOption::True : AccurateShaderMulOption::False);
	NativeGameTitles::s_currentGameProfile.Save(game_title_id);
}

extern "C" [[maybe_unused]] JNIEXPORT jboolean JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_titleHasShaderCacheFiles([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id)
{
	return !NativeGameTitles::getCachesPaths(game_title_id).empty();
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_removeShaderCacheFilesForTitle([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id)
{
	std::error_code ec;
	for (auto&& cacheFilePath : NativeGameTitles::getCachesPaths(game_title_id))
		fs::remove(cacheFilePath, ec);
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_setGameTitleFavorite([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id, jboolean isFavorite)
{
	GetConfig().SetGameListFavorite(game_title_id, isFavorite);
	g_config.Save();
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
	jmethodID onGameTitleLoadedMID = env->GetMethodID(gameTitleLoadedCallbackClass, "onGameTitleLoaded", "(Linfo/cemu/Cemu/nativeinterface/NativeGameTitles$Game;)V");
	env->DeleteLocalRef(gameTitleLoadedCallbackClass);
	NativeGameTitles::s_gameTitleLoader.setOnTitleLoaded(std::make_shared<AndroidGameTitleLoadedCallback>(onGameTitleLoadedMID, game_title_loaded_callback));
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_reloadGameTitles([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz)
{
	NativeGameTitles::s_gameTitleLoader.reloadGameTitles();
}

extern "C" [[maybe_unused]] JNIEXPORT jobject JNICALL
Java_info_cemu_Cemu_nativeinterface_NativeGameTitles_getInstalledGamesTitleIds(JNIEnv* env, [[maybe_unused]] jclass clazz)
{
	return JNIUtils::createJavaLongArrayList(env, CafeTitleList::GetAllTitleIds());
}
