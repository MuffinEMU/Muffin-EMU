#pragma once

#include "GameTitleLoader.h"
#include "JNIUtils.h"

class AndroidGameTitleLoadedCallback : public GameTitleLoadedCallback
{
	jmethodID m_onGameTitleLoadedMID;
	JNIUtils::Scopedjobject m_gameTitleLoadedCallbackObj;

  public:
	AndroidGameTitleLoadedCallback(jmethodID onGameTitleLoadedMID, jobject gameTitleLoadedCallbackObj)
		: m_onGameTitleLoadedMID(onGameTitleLoadedMID),
		  m_gameTitleLoadedCallbackObj(gameTitleLoadedCallbackObj) {}

	void onTitleLoaded(const Game& game, const std::shared_ptr<Image>& icon) override
	{
		JNIUtils::ScopedJNIENV env;
		jstring name = env->NewStringUTF(game.name.c_str());
		jstring path = game.path.has_value() ? env->NewStringUTF(game.path->c_str()) : nullptr;
		int width = -1, height = -1;
		jintArray jIconData = nullptr;
		if (icon)
		{
			width = icon->m_width;
			height = icon->m_height;
			jIconData = env->NewIntArray(width * height);
			env->SetIntArrayRegion(jIconData, 0, width * height, reinterpret_cast<const jint*>(icon->intColors()));
		}
		env->CallVoidMethod(*m_gameTitleLoadedCallbackObj, m_onGameTitleLoadedMID, path, name, jIconData, width, height);
		if (jIconData != nullptr)
			env->DeleteLocalRef(jIconData);
		if (path != nullptr)
			env->DeleteLocalRef(path);
		env->DeleteLocalRef(name);
	}
};
