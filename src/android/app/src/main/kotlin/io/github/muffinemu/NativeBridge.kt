// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

package io.github.muffinemu

import android.view.Surface

/** The core's JNI face: src/android/Bridge/AndroidBridge.cpp implements every native method here. */
object NativeBridge {
    init {
        System.loadLibrary("Cemu")
    }

    /** Button order is the contract with AndroidPadButton in AndroidBridge.h. */
    enum class Button { A, B, X, Y, L, R, ZL, ZR, MINUS, PLUS, STICK_L, STICK_R, UP, DOWN, LEFT, RIGHT }

    const val STICK_LEFT = 0
    const val STICK_RIGHT = 1

    @JvmStatic external fun initialize(userDataDir: String, dataDir: String): Boolean
    @JvmStatic external fun setSurface(surface: Surface?, width: Int, height: Int, scale: Float)
    @JvmStatic external fun resizeSurface(width: Int, height: Int, scale: Float)
    @JvmStatic external fun setShowsGamePad(gamePad: Boolean)
    @JvmStatic external fun bootTitle(path: String): Int
    @JvmStatic external fun stopTitle()
    @JvmStatic external fun setPaused(paused: Boolean): Boolean
    @JvmStatic external fun isTitleRunning(): Boolean
    @JvmStatic external fun statusText(): String
    @JvmStatic external fun pollMessage(): String?
    @JvmStatic external fun framesPerSecond(): Double
    @JvmStatic external fun reloadAndCountKeys(): Int
    @JvmStatic external fun setButton(button: Int, pressed: Boolean)
    @JvmStatic external fun setStick(stick: Int, x: Float, y: Float)
    @JvmStatic external fun setPadTouch(x: Float, y: Float, down: Boolean)
    @JvmStatic external fun setPhysicalState(buttons: Int, lx: Float, ly: Float, rx: Float, ry: Float, lt: Float, rt: Float)
    @JvmStatic external fun releaseAllButtons()

    fun setButton(button: Button, pressed: Boolean) = setButton(button.ordinal, pressed)
}
