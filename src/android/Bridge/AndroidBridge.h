// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// The JNI face of the core for the Kotlin app (src/android/app, class io.github.muffinemu.NativeBridge).
// Every function here is a static native method of that class; the Kotlin declarations are the contract.
#pragma once

#include <jni.h>

// Buttons the app sends, in the order NativeBridge.Button declares them. The bridge maps them to the
// bits the core's GameController provider reads (InputManager.cpp, kGCBit*).
enum AndroidPadButton : int
{
	ANDROID_PAD_A = 0,
	ANDROID_PAD_B,
	ANDROID_PAD_X,
	ANDROID_PAD_Y,
	ANDROID_PAD_L,
	ANDROID_PAD_R,
	ANDROID_PAD_ZL,
	ANDROID_PAD_ZR,
	ANDROID_PAD_MINUS,
	ANDROID_PAD_PLUS,
	ANDROID_PAD_STICK_L,
	ANDROID_PAD_STICK_R,
	ANDROID_PAD_UP,
	ANDROID_PAD_DOWN,
	ANDROID_PAD_LEFT,
	ANDROID_PAD_RIGHT,
	ANDROID_PAD_COUNT
};
