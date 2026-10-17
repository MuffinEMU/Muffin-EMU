// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// The vendored ih264d decoder includes AOSP's <log/log.h> when built for Android; the NDK only has
// <android/log.h>. This stands in for the one macro it uses.
#pragma once
#include <android/log.h>
#include <stdint.h>

#ifndef ALOGE
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, "ih264d", __VA_ARGS__)
#endif
#ifndef ALOGW
#define ALOGW(...) __android_log_print(ANDROID_LOG_WARN, "ih264d", __VA_ARGS__)
#endif
#ifndef ALOGI
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, "ih264d", __VA_ARGS__)
#endif
#ifndef ALOGD
#define ALOGD(...) __android_log_print(ANDROID_LOG_DEBUG, "ih264d", __VA_ARGS__)
#endif
#ifndef ALOGV
#define ALOGV(...) ((void)0)
#endif

// AOSP's security-bulletin hook (liblog), used by the decoder on a handful of malformed-stream paths.
// The NDK has no liblog equivalent; the event goes to logcat instead of the system event log.
#ifdef __cplusplus
extern "C" {
#endif
static inline int android_errorWriteLog(int tag, const char* subTag)
{
	__android_log_print(ANDROID_LOG_WARN, "ih264d", "errorWriteLog tag=0x%x %s", tag, subTag ? subTag : "");
	return 0;
}
static inline int android_errorWriteWithInfoLog(int tag, const char* subTag, int32_t uid, const char* data, uint32_t dataLen)
{
	(void)uid; (void)data; (void)dataLen;
	return android_errorWriteLog(tag, subTag);
}
#ifdef __cplusplus
}
#endif
