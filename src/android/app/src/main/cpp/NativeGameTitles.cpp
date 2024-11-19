#include <Cafe/TitleList/SaveList.h>
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
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_isLoadingSharedLibrariesForTitleEnabled([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	return NativeGameTitles::s_currentGameProfile.ShouldLoadSharedLibraries().value_or(false);
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_setLoadingSharedLibrariesForTitleEnabled([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id, jboolean enabled)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	NativeGameTitles::s_currentGameProfile.SetShouldLoadSharedLibraries(enabled);
	NativeGameTitles::s_currentGameProfile.Save(game_title_id);
}

extern "C" [[maybe_unused]] JNIEXPORT jint JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_getCpuModeForTitle([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	return static_cast<jint>(NativeGameTitles::s_currentGameProfile.GetCPUMode().value_or(CPUMode::Auto));
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_setCpuModeForTitle([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id, jint cpu_mode)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	NativeGameTitles::s_currentGameProfile.SetCPUMode(static_cast<CPUMode>(cpu_mode));
	NativeGameTitles::s_currentGameProfile.Save(game_title_id);
}

extern "C" [[maybe_unused]] JNIEXPORT jint JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_getThreadQuantumForTitle([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	return NativeGameTitles::s_currentGameProfile.GetThreadQuantum();
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_setThreadQuantumForTitle([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id, jint thread_quantum)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	NativeGameTitles::s_currentGameProfile.SetThreadQuantum(std::clamp(thread_quantum, 5000, 536870912));
	NativeGameTitles::s_currentGameProfile.Save(game_title_id);
}

extern "C" [[maybe_unused]] JNIEXPORT jboolean JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_isShaderMultiplicationAccuracyForTitleEnabled([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	return NativeGameTitles::s_currentGameProfile.GetAccurateShaderMul() == AccurateShaderMulOption::True;
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_setShaderMultiplicationAccuracyForTitleEnabled([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id, jboolean enabled)
{
	NativeGameTitles::LoadGameProfile(game_title_id);
	NativeGameTitles::s_currentGameProfile.SetAccurateShaderMul(enabled ? AccurateShaderMulOption::True : AccurateShaderMulOption::False);
	NativeGameTitles::s_currentGameProfile.Save(game_title_id);
}

extern "C" [[maybe_unused]] JNIEXPORT jboolean JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_titleHasShaderCacheFiles([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id)
{
	return !NativeGameTitles::getCachesPaths(game_title_id).empty();
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_removeShaderCacheFilesForTitle([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id)
{
	std::error_code ec;
	for (auto&& cacheFilePath : NativeGameTitles::getCachesPaths(game_title_id))
		fs::remove(cacheFilePath, ec);
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_setGameTitleFavorite([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jlong game_title_id, jboolean isFavorite)
{
	GetConfig().SetGameListFavorite(game_title_id, isFavorite);
	g_config.Save();
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_setGameTitleLoadedCallback(JNIEnv* env, [[maybe_unused]] jclass clazz, jobject game_title_loaded_callback)
{
	if (game_title_loaded_callback == nullptr)
	{
		NativeGameTitles::s_gameTitleLoader.setOnTitleLoaded(nullptr);
		return;
	}
	jclass gameTitleLoadedCallbackClass = env->GetObjectClass(game_title_loaded_callback);
	jmethodID onGameTitleLoadedMID = env->GetMethodID(gameTitleLoadedCallbackClass, "onGameTitleLoaded", "(Linfo/cemu/cemu/nativeinterface/NativeGameTitles$Game;)V");
	env->DeleteLocalRef(gameTitleLoadedCallbackClass);
	NativeGameTitles::s_gameTitleLoader.setOnTitleLoaded(std::make_shared<AndroidGameTitleLoadedCallback>(onGameTitleLoadedMID, game_title_loaded_callback));
}

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_reloadGameTitles([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz)
{
	NativeGameTitles::s_gameTitleLoader.reloadGameTitles();
}

extern "C" [[maybe_unused]] JNIEXPORT jobject JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_getInstalledGamesTitleIds(JNIEnv* env, [[maybe_unused]] jclass clazz)
{
	return JNIUtils::createJavaLongArrayList(env, CafeTitleList::GetAllTitleIds());
}

class SaveListCallback
{
  private:
	uint64 m_callbackIdSaveList;
	JNIUtils::Scopedjobject m_saveListCallbackObj;
	jmethodID m_onSaveDiscoveredMID;
	JNIUtils::Scopedjclass m_saveDataClass;
	jmethodID m_saveDataConstructorMID;

	void HandleSaveListCallback(CafeSaveListCallbackEvent* evt)
	{
		if (evt->eventType != CafeSaveListCallbackEvent::TYPE::SAVE_DISCOVERED)
			return;

		ParsedMetaXml* metaInfo = evt->saveInfo->GetMetaInfo();
		if (!metaInfo)
			return;
		auto& saveInfo = *evt->saveInfo;
		auto locationUID = std::hash<uint64>()(metaInfo->GetTitleId());
		std::string name = metaInfo->GetLongName(GetConfig().console_language.GetValue());
		const auto nl = name.find(L'\n');
		if (nl != std::string::npos)
			name.replace(nl, 1, " - ");

		JNIUtils::ScopedJNIENV env;
		jstring nameJava = env->NewStringUTF(name.c_str());
		jobject pathJava = env->NewStringUTF(saveInfo.GetPath().c_str());
		jobject saveData = env->NewObject(
			*m_saveDataClass,
			m_saveDataConstructorMID,
			nameJava,
			pathJava,
			metaInfo->GetTitleId(),
			locationUID,
			metaInfo->GetTitleVersion(),
			metaInfo->GetRegion());
		env->CallVoidMethod(*m_saveListCallbackObj, m_onSaveDiscoveredMID, saveData);
		env->DeleteLocalRef(saveData);
		env->DeleteLocalRef(nameJava);
		env->DeleteLocalRef(pathJava);
	}

  public:
	SaveListCallback(jobject saveListCallbackObject)
	{
		JNIUtils::ScopedJNIENV env;
		m_saveListCallbackObj = JNIUtils::Scopedjobject(saveListCallbackObject);
		JNIUtils::Scopedjclass saveCallbacksClass{"info/cemu/cemu/nativeinterface/NativeGameTitles$SaveListCallback"};
		m_onSaveDiscoveredMID = env->GetMethodID(*saveCallbacksClass, "onSaveDiscovered", "(Linfo/cemu/cemu/nativeinterface/NativeGameTitles$SaveData;)V");
		m_saveDataClass = JNIUtils::Scopedjclass("info/cemu/cemu/nativeinterface/NativeGameTitles$SaveData");
		m_saveDataConstructorMID = env->GetMethodID(*m_saveDataClass, "<init>", "(Ljava/lang/String;Ljava/lang/String;JJSI)V");
		m_callbackIdSaveList = CafeSaveList::RegisterCallback(
			[](CafeSaveListCallbackEvent* evt, void* ctx) {
				static_cast<SaveListCallback*>(ctx)->HandleSaveListCallback(evt);
			},
			this);
	}
	~SaveListCallback()
	{
		CafeSaveList::UnregisterCallback(m_callbackIdSaveList);
	}
};

class TitleListCallbacks
{
  private:
	JNIUtils::Scopedjobject m_titleListCallbacksObj;
	jmethodID m_onTitleDiscoveredMID;
	jmethodID m_onTitleRemovedMID;
	jmethodID m_titleDataConstructorMID;
	JNIUtils::Scopedjclass m_titleDataClass;
	uint64 m_callbackIdTitleList;

	void OnTitleDiscovered(TitleInfo& titleInfo)
	{
		if (titleInfo.IsCached())
			return; // the title list only displays non-cached entries
		if (titleInfo.IsSystemDataTitle())
			return; // don't show system data titles for now

		JNIUtils::ScopedJNIENV env;

		ParsedMetaXml* metaInfo = titleInfo.GetMetaInfo();
		std::string name = metaInfo->GetLongName(GetConfig().console_language.GetValue());
		const auto nl = name.find(L'\n');
		if (nl != std::string::npos)
			name.replace(nl, 1, " - ");

		jobject nameJava = env->NewStringUTF(name.c_str());
		jobject pathJava = env->NewStringUTF(titleInfo.GetPath().c_str());
		jobject titleData = env->NewObject(
			*m_titleDataClass,
			m_titleDataConstructorMID,
			nameJava,
			pathJava,
			titleInfo.GetAppTitleId(),
			titleInfo.GetUID(),
			titleInfo.GetAppTitleVersion(),
			metaInfo->GetRegion(),
			titleInfo.GetTitleType(),
			titleInfo.GetFormat());

		env->CallVoidMethod(*m_titleListCallbacksObj, m_onTitleDiscoveredMID, titleData);

		env->DeleteLocalRef(titleData);
		env->DeleteLocalRef(nameJava);
		env->DeleteLocalRef(pathJava);
	}

	void OnTitleRemoved(TitleInfo& titleInfo)
	{
		JNIUtils::ScopedJNIENV()->CallVoidMethod(*m_titleListCallbacksObj, m_onTitleRemovedMID, titleInfo.GetUID());
	}

	void HandleTitleListCallback(CafeTitleListCallbackEvent* evt)
	{
		if (evt->eventType != CafeTitleListCallbackEvent::TYPE::TITLE_DISCOVERED &&
			evt->eventType != CafeTitleListCallbackEvent::TYPE::TITLE_REMOVED)
			return;

		if (evt->eventType == CafeTitleListCallbackEvent::TYPE::TITLE_DISCOVERED)
		{
			OnTitleDiscovered(*evt->titleInfo);
		}
		else if (evt->eventType == CafeTitleListCallbackEvent::TYPE::TITLE_REMOVED)
		{
			OnTitleRemoved(*evt->titleInfo);
		}
	}

  public:
	TitleListCallbacks(jobject titleListCallbacks)
	{
		JNIUtils::ScopedJNIENV env;
		m_titleListCallbacksObj = JNIUtils::Scopedjobject(titleListCallbacks);
		jclass titleCallbacksClass = env->FindClass("info/cemu/cemu/nativeinterface/NativeGameTitles$TitleListCallbacks");
		m_onTitleDiscoveredMID = env->GetMethodID(titleCallbacksClass, "onTitleDiscovered", "(Linfo/cemu/cemu/nativeinterface/NativeGameTitles$TitleData;)V");
		m_onTitleRemovedMID = env->GetMethodID(titleCallbacksClass, "onTitleRemoved", "(J)V");
		env->DeleteLocalRef(titleCallbacksClass);
		m_titleDataClass = JNIUtils::Scopedjclass("info/cemu/cemu/nativeinterface/NativeGameTitles$TitleData");
		m_titleDataConstructorMID = env->GetMethodID(*m_titleDataClass, "<init>", "(Ljava/lang/String;Ljava/lang/String;JJSIII)V");
		m_callbackIdTitleList = CafeTitleList::RegisterCallback(
			[](CafeTitleListCallbackEvent* evt, void* ctx) {
				static_cast<TitleListCallbacks*>(ctx)->HandleTitleListCallback(evt);
			},
			this);
	}

	~TitleListCallbacks()
	{
		CafeTitleList::UnregisterCallback(m_callbackIdTitleList);
	}
};

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_refreshCafeTitleList([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz)
{
	CafeTitleList::Refresh();
}

std::unique_ptr<TitleListCallbacks> s_titleListCallbacks;

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_setTitleListCallbacks([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jobject title_list_callbacks)
{
	if (title_list_callbacks == nullptr)
		s_titleListCallbacks = nullptr;
	else
		s_titleListCallbacks = std::make_unique<TitleListCallbacks>(title_list_callbacks);
}

std::unique_ptr<SaveListCallback> s_saveListCallback;

extern "C" [[maybe_unused]] JNIEXPORT void JNICALL
Java_info_cemu_cemu_nativeinterface_NativeGameTitles_setSaveListCallback([[maybe_unused]] JNIEnv* env, [[maybe_unused]] jclass clazz, jobject save_list_callback)
{
	if (save_list_callback == nullptr)
		s_saveListCallback = nullptr;
	else
		s_saveListCallback = std::make_unique<SaveListCallback>(save_list_callback);
}