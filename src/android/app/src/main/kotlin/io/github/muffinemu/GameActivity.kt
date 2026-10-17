// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

package io.github.muffinemu

import android.app.AlertDialog
import android.os.Bundle
import android.text.InputFilter
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowManager
import android.widget.EditText
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
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
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
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
    private var showsGamePad by mutableStateOf(false)
    /** The on-screen pad steps aside while a physical controller is being used, as on iOS. */
    private var padVisible by mutableStateOf(true)
    /** Frames the core finished in the last second, or -1 before the first count. */
    private var fps by mutableStateOf(-1)
    private var keyboardOpen = false
    private var booted = false
    // The game runs only while the activity is in front AND has a surface to present into. Back from Home,
    // onResume comes before surfaceCreated, so resuming on onResume alone ran the renderer with no surface.
    private var resumed = false
    private var hasSurface = false
    /** Set when the surface is destroyed, so the next one is given to the core as new rather than as a resize. */
    private var surfaceLost = false
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
        watchKeyboard()
        countFrames()
        // Back (often an edge swipe, easy to make by accident with thumbs at the edges) asks first while a game
        // runs; nothing on the screen is lost by asking. With no game up (it failed to start), back just leaves.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (!booted || !NativeBridge.isTitleRunning()) { finish(); return }
                NativeBridge.releaseAllButtons()
                AlertDialog.Builder(this@GameActivity)
                    .setTitle("Quit the game?")
                    .setMessage("Anything not saved in the game is lost.")
                    .setPositiveButton("Quit") { _, _ -> finish() }
                    .setNegativeButton("Keep playing", null)
                    .show()
            }
        })

        setContent {
            Box(Modifier.fillMaxSize()) {
                AndroidView(factory = { context ->
                    SurfaceView(context).apply {
                        holder.addCallback(object : SurfaceHolder.Callback {
                            override fun surfaceCreated(holder: SurfaceHolder) {}

                            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                                val density = resources.displayMetrics.density
                                val points = (width / density).toInt() to (height / density).toInt()
                                hasSurface = true
                                if (!booted) {
                                    NativeBridge.setSurface(holder.surface, points.first, points.second, density)
                                    booted = true
                                    thread(name = "Muffin boot") {
                                        val code = NativeBridge.bootTitle(path)
                                        runOnUiThread { status = if (code == 0) "" else NativeBridge.statusText() }
                                    }
                                } else if (surfaceLost) {
                                    // A new surface after the old one was destroyed (back from Home): the core
                                    // builds a swapchain on it.
                                    surfaceLost = false
                                    NativeBridge.setSurface(holder.surface, points.first, points.second, density)
                                    updatePaused()
                                } else {
                                    // The same surface at a new size (rotation, multi-window). Rebuilding the layer
                                    // here would race the GPU thread presenting into it; the core resizes instead.
                                    NativeBridge.resizeSurface(points.first, points.second, density)
                                }
                            }

                            override fun surfaceDestroyed(holder: SurfaceHolder) {
                                // The window is going away (home button, lock): hold the game until a surface is back.
                                hasSurface = false
                                surfaceLost = true
                                updatePaused()
                                NativeBridge.setSurface(null, 0, 0, 1f)
                            }
                        })
                    }
                }, modifier = Modifier.fillMaxSize())

                TouchPad(
                    modifier = Modifier.fillMaxSize(),
                    showsGamePad = showsGamePad,
                    onSwapScreens = {
                        showsGamePad = !showsGamePad
                        NativeBridge.setShowsGamePad(showsGamePad)
                    },
                    visible = padVisible,
                    onTouchedWhileHidden = { padVisible = true }
                )

                if (fps >= 0 && status.isEmpty()) {
                    Text(
                        "$fps FPS",
                        color = Color(0xFFF4E9DC).copy(alpha = 0.8f),
                        fontSize = 12.sp,
                        modifier = Modifier.align(Alignment.TopStart).padding(start = 12.dp, top = 8.dp)
                    )
                }

                if (status.isNotEmpty()) {
                    Text(
                        status + "\n\nGo back to your games. Share log there sends the details if you ask for help.",
                        color = Color(0xFFF4E9DC),
                        fontSize = 15.sp,
                        modifier = Modifier.align(Alignment.Center).padding(32.dp)
                    )
                }
            }
        }
    }

    /**
     * A game asks for text (a name, a message) through the Wii U's software keyboard; the core posts the request
     * and waits for an answer (src/gui/android/WindowSystem.cpp). Checked a few times a second while the screen is
     * up. Done sends what was typed; backing out sends the text the game started with, so it is never left waiting.
     */
    private fun watchKeyboard() = lifecycleScope.launch {
        while (isActive) {
            delay(200)
            if (keyboardOpen) continue
            val request = NativeBridge.pendingKeyboard() ?: continue
            val generation = request[0].toIntOrNull() ?: continue
            val maxLength = request[1].toIntOrNull() ?: 0
            val original = request[2]
            val field = EditText(this@GameActivity).apply {
                setText(original)
                setSelection(original.length)
                if (maxLength > 0) filters = arrayOf(InputFilter.LengthFilter(maxLength))
            }
            keyboardOpen = true
            NativeBridge.releaseAllButtons()
            AlertDialog.Builder(this@GameActivity)
                .setView(field)
                .setPositiveButton("Done") { _, _ -> NativeBridge.submitKeyboard(generation, field.text.toString()) }
                .setOnCancelListener { NativeBridge.submitKeyboard(generation, original) }
                .setOnDismissListener { keyboardOpen = false }
                .show()
        }
    }

    /** The bridge reports a running frame count; the readout is its change over each second while a game runs. */
    private fun countFrames() = lifecycleScope.launch {
        var last = -1.0
        while (isActive) {
            delay(1000)
            if (!booted || !NativeBridge.isTitleRunning()) { last = -1.0; fps = -1; continue }
            val now = NativeBridge.framesPerSecond()
            if (last >= 0) fps = (now - last).toInt().coerceAtLeast(0)
            last = now
        }
    }

    private fun updatePaused() {
        if (booted) NativeBridge.setPaused(!(resumed && hasSurface))
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        updatePaused()
    }

    override fun onPause() {
        super.onPause()
        resumed = false
        NativeBridge.releaseAllButtons()
        updatePaused()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (booted && !isChangingConfigurations) NativeBridge.stopTitle()
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

    /**
     * A radial deadzone, rescaled so the stick still reaches full tilt: controller sticks rarely rest at exactly
     * zero, and a worn one drifts enough to walk a character. The same 0.25 the iOS bridge applies to
     * physical sticks (ios_physical_stick_deadzone in CemuBridge.mm), so a controller feels the same on both.
     */
    private fun deadzone(x: Float, y: Float): Pair<Float, Float> {
        val dz = 0.25f
        val mag = kotlin.math.sqrt(x * x + y * y)
        if (mag <= dz) return 0f to 0f
        val scale = minOf(1f, (mag - dz) / (1f - dz)) / mag
        return x * scale to y * scale
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        val button = keyToButton(keyCode) ?: return super.onKeyDown(keyCode, event)
        padVisible = false
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
        // A stick resting slightly off centre keeps sending events; only a real push hides the pad.
        if (kotlin.math.abs(event.getAxisValue(MotionEvent.AXIS_X)) > 0.5f || kotlin.math.abs(event.getAxisValue(MotionEvent.AXIS_Y)) > 0.5f) padVisible = false
        // the core wants +y up
        deadzone(event.getAxisValue(MotionEvent.AXIS_X), -event.getAxisValue(MotionEvent.AXIS_Y)).let { lx = it.first; ly = it.second }
        deadzone(event.getAxisValue(MotionEvent.AXIS_Z), -event.getAxisValue(MotionEvent.AXIS_RZ)).let { rx = it.first; ry = it.second }
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
