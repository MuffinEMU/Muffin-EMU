// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

package io.github.muffinemu

import android.os.Bundle
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import kotlin.concurrent.thread

/**
 * The emulator screen: one SurfaceView the core's Vulkan renderer presents into, the on-screen pad on top,
 * and a physical controller read from the activity's input events.
 */
class GameActivity : ComponentActivity() {
    companion object {
        const val EXTRA_PATH = "path"
    }

    private var status by mutableStateOf("")
    private var booted = false
    private var physicalButtons = 0
    private var lx = 0f; private var ly = 0f; private var rx = 0f; private var ry = 0f; private var lt = 0f; private var rt = 0f

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val path = intent.getStringExtra(EXTRA_PATH) ?: run { finish(); return }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        setContent {
            Box(Modifier.fillMaxSize()) {
                AndroidView(factory = { context ->
                    SurfaceView(context).apply {
                        holder.addCallback(object : SurfaceHolder.Callback {
                            override fun surfaceCreated(holder: SurfaceHolder) {}

                            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                                val density = resources.displayMetrics.density
                                val points = (width / density).toInt() to (height / density).toInt()
                                if (!booted) {
                                    NativeBridge.setSurface(holder.surface, points.first, points.second, density)
                                    booted = true
                                    thread(name = "Muffin boot") {
                                        val code = NativeBridge.bootTitle(path)
                                        runOnUiThread { status = if (code == 0) "" else NativeBridge.statusText() }
                                    }
                                } else {
                                    NativeBridge.setSurface(holder.surface, points.first, points.second, density)
                                }
                            }

                            override fun surfaceDestroyed(holder: SurfaceHolder) {
                                // The window is going away (home button, lock): hold the game until a surface is back.
                                NativeBridge.setPaused(true)
                                NativeBridge.setSurface(null, 0, 0, 1f)
                            }
                        })
                    }
                }, modifier = Modifier.fillMaxSize())

                TouchPad(modifier = Modifier.fillMaxSize())

                if (status.isNotEmpty()) {
                    Text(
                        status,
                        color = Color(0xFFF4E9DC),
                        fontSize = 15.sp,
                        modifier = Modifier.align(Alignment.Center).padding(32.dp)
                    )
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (booted) NativeBridge.setPaused(false)
    }

    override fun onPause() {
        super.onPause()
        NativeBridge.releaseAllButtons()
        if (booted) NativeBridge.setPaused(true)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (booted) NativeBridge.stopTitle()
    }

    // ---- physical controllers (Bluetooth or USB): keys and axes straight from the input system

    private fun keyToButton(keyCode: Int): NativeBridge.Button? = when (keyCode) {
        KeyEvent.KEYCODE_BUTTON_A -> NativeBridge.Button.B   // Nintendo layout: the right-hand button is A on a Wii U
        KeyEvent.KEYCODE_BUTTON_B -> NativeBridge.Button.A
        KeyEvent.KEYCODE_BUTTON_X -> NativeBridge.Button.Y
        KeyEvent.KEYCODE_BUTTON_Y -> NativeBridge.Button.X
        KeyEvent.KEYCODE_BUTTON_L1 -> NativeBridge.Button.L
        KeyEvent.KEYCODE_BUTTON_R1 -> NativeBridge.Button.R
        KeyEvent.KEYCODE_BUTTON_L2 -> NativeBridge.Button.ZL
        KeyEvent.KEYCODE_BUTTON_R2 -> NativeBridge.Button.ZR
        KeyEvent.KEYCODE_BUTTON_SELECT -> NativeBridge.Button.MINUS
        KeyEvent.KEYCODE_BUTTON_START -> NativeBridge.Button.PLUS
        KeyEvent.KEYCODE_BUTTON_THUMBL -> NativeBridge.Button.STICK_L
        KeyEvent.KEYCODE_BUTTON_THUMBR -> NativeBridge.Button.STICK_R
        KeyEvent.KEYCODE_DPAD_UP -> NativeBridge.Button.UP
        KeyEvent.KEYCODE_DPAD_DOWN -> NativeBridge.Button.DOWN
        KeyEvent.KEYCODE_DPAD_LEFT -> NativeBridge.Button.LEFT
        KeyEvent.KEYCODE_DPAD_RIGHT -> NativeBridge.Button.RIGHT
        else -> null
    }

    private fun pushPhysical() = NativeBridge.setPhysicalState(physicalButtons, lx, ly, rx, ry, lt, rt)

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        val button = keyToButton(keyCode) ?: return super.onKeyDown(keyCode, event)
        if (event.repeatCount == 0) {
            physicalButtons = physicalButtons or (1 shl button.ordinal)
            pushPhysical()
        }
        return true
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        val button = keyToButton(keyCode) ?: return super.onKeyUp(keyCode, event)
        physicalButtons = physicalButtons and (1 shl button.ordinal).inv()
        pushPhysical()
        return true
    }

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.source and InputDevice.SOURCE_JOYSTICK != InputDevice.SOURCE_JOYSTICK) return super.onGenericMotionEvent(event)
        lx = event.getAxisValue(MotionEvent.AXIS_X)
        ly = -event.getAxisValue(MotionEvent.AXIS_Y) // the core wants +y up
        rx = event.getAxisValue(MotionEvent.AXIS_Z)
        ry = -event.getAxisValue(MotionEvent.AXIS_RZ)
        lt = maxOf(event.getAxisValue(MotionEvent.AXIS_LTRIGGER), event.getAxisValue(MotionEvent.AXIS_BRAKE))
        rt = maxOf(event.getAxisValue(MotionEvent.AXIS_RTRIGGER), event.getAxisValue(MotionEvent.AXIS_GAS))
        // A hat switch reports the d-pad as axes
        val hatX = event.getAxisValue(MotionEvent.AXIS_HAT_X)
        val hatY = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
        fun hat(button: NativeBridge.Button, on: Boolean) {
            physicalButtons = if (on) physicalButtons or (1 shl button.ordinal) else physicalButtons and (1 shl button.ordinal).inv()
        }
        hat(NativeBridge.Button.LEFT, hatX < -0.5f)
        hat(NativeBridge.Button.RIGHT, hatX > 0.5f)
        hat(NativeBridge.Button.UP, hatY < -0.5f)
        hat(NativeBridge.Button.DOWN, hatY > 0.5f)
        pushPhysical()
        return true
    }
}
