// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

package io.github.muffinemu

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.PointerId
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import kotlin.math.hypot
import kotlin.math.min

/**
 * The first on-screen GamePad: left stick, d-pad, A B X Y, L R ZL ZR, Plus and Minus, drawn as rings so the
 * game shows through. Positions are fractions of the screen so every phone and tablet gets the same layout.
 * Multi-touch: each finger owns whatever it landed on until it lifts, and the stick follows its finger.
 *
 * The control at the top centre swaps the picture between the TV and the GamePad. While the GamePad is shown,
 * a finger that lands on no control is a touch on the GamePad's screen: its position goes to the core in the
 * surface's own pixels, which the core maps onto the picture (VPADController, LatteRenderTarget_getScreenImageArea).
 */
@Composable
fun TouchPad(modifier: Modifier = Modifier, showsGamePad: Boolean = false, onSwapScreens: () -> Unit = {}) {
    val layout = remember { PadLayout() }
    // pointerInput below is set up once; these keep it reading the current values.
    val gamePadShown = rememberUpdatedState(showsGamePad)
    val swap = rememberUpdatedState(onSwapScreens)
    val pressed = remember { mutableStateOf(setOf<NativeBridge.Button>()) }
    val stickOffset = remember { mutableStateOf(Offset.Zero) } // left stick thumb, pixels from its centre
    val rightStickOffset = remember { mutableStateOf(Offset.Zero) }

    Canvas(
        modifier = modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                val owners = HashMap<PointerId, PadControl>()
                awaitEachGesture {
                    while (true) {
                        val event = awaitPointerEvent()
                        val size = Size(this.size.width.toFloat(), this.size.height.toFloat())
                        for (change in event.changes) {
                            val id = change.id
                            if (change.changedToDownIgnoreConsumed()) {
                                val control = layout.hit(change.position, size)
                                    ?: if (gamePadShown.value) PadControl.Screen else null
                                if (control != null) {
                                    owners[id] = control
                                    when (control) {
                                        is PadControl.Button -> {
                                            NativeBridge.setButton(control.button, true)
                                            pressed.value = pressed.value + control.button
                                        }
                                        is PadControl.Stick -> {
                                            val v = control.vector(change.position, size)
                                            NativeBridge.setStick(control.index, v.x, -v.y)
                                            if (control.index == NativeBridge.STICK_LEFT) stickOffset.value = control.thumb(change.position, size) else rightStickOffset.value = control.thumb(change.position, size)
                                        }
                                        is PadControl.DPad -> {
                                            val dirs = control.directions(change.position, size)
                                            dirs.forEach { NativeBridge.setButton(it, true) }
                                            pressed.value = pressed.value + dirs
                                        }
                                        is PadControl.Swap -> swap.value()
                                        PadControl.Screen -> NativeBridge.setPadTouch(change.position.x, change.position.y, true)
                                    }
                                }
                                change.consume()
                            } else if (change.changedToUpIgnoreConsumed()) {
                                when (val control = owners.remove(id)) {
                                    is PadControl.Button -> {
                                        NativeBridge.setButton(control.button, false)
                                        pressed.value = pressed.value - control.button
                                    }
                                    is PadControl.Stick -> {
                                        NativeBridge.setStick(control.index, 0f, 0f)
                                        if (control.index == NativeBridge.STICK_LEFT) stickOffset.value = Offset.Zero else rightStickOffset.value = Offset.Zero
                                    }
                                    is PadControl.DPad -> {
                                        control.all.forEach { NativeBridge.setButton(it, false) }
                                        pressed.value = pressed.value - control.all
                                    }
                                    is PadControl.Swap -> {}
                                    PadControl.Screen -> NativeBridge.setPadTouch(change.position.x, change.position.y, false)
                                    null -> {}
                                }
                                change.consume()
                            } else if (change.pressed) {
                                when (val control = owners[id]) {
                                    is PadControl.Stick -> {
                                        val v = control.vector(change.position, size)
                                        NativeBridge.setStick(control.index, v.x, -v.y)
                                        if (control.index == NativeBridge.STICK_LEFT) stickOffset.value = control.thumb(change.position, size) else rightStickOffset.value = control.thumb(change.position, size)
                                    }
                                    is PadControl.DPad -> {
                                        val dirs = control.directions(change.position, size)
                                        val gone = control.all - dirs
                                        gone.forEach { NativeBridge.setButton(it, false) }
                                        dirs.forEach { NativeBridge.setButton(it, true) }
                                        pressed.value = (pressed.value - gone) + dirs
                                    }
                                    PadControl.Screen -> NativeBridge.setPadTouch(change.position.x, change.position.y, true)
                                    else -> {}
                                }
                                change.consume()
                            }
                        }
                        if (event.changes.none { it.pressed }) break
                    }
                }
            }
    ) {
        layout.draw(this, pressed.value, stickOffset.value, rightStickOffset.value, showsGamePad)
    }
}

sealed class PadControl {
    /** The TV / GamePad swap. */
    data class Swap(val cx: Float, val cy: Float, val r: Float) : PadControl()
    /** A finger on the GamePad's screen (only while the GamePad is the picture). */
    data object Screen : PadControl()
    data class Button(val button: NativeBridge.Button, val cx: Float, val cy: Float, val r: Float) : PadControl()
    data class Stick(val index: Int, val cx: Float, val cy: Float, val r: Float) : PadControl() {
        private fun centre(size: Size) = Offset(cx * size.width, cy * size.height)
        private fun radius(size: Size) = r * min(size.width, size.height)
        fun vector(p: Offset, size: Size): Offset {
            val d = p - centre(size)
            val rad = radius(size)
            val len = hypot(d.x, d.y)
            return if (len > rad) Offset(d.x / len, d.y / len) else Offset(d.x / rad, d.y / rad)
        }
        fun thumb(p: Offset, size: Size): Offset {
            val v = vector(p, size)
            return Offset(v.x * radius(size), v.y * radius(size))
        }
    }
    data class DPad(val cx: Float, val cy: Float, val r: Float) : PadControl() {
        val all = setOf(NativeBridge.Button.UP, NativeBridge.Button.DOWN, NativeBridge.Button.LEFT, NativeBridge.Button.RIGHT)
        fun directions(p: Offset, size: Size): Set<NativeBridge.Button> {
            val d = p - Offset(cx * size.width, cy * size.height)
            val rad = r * min(size.width, size.height)
            val dead = rad * 0.25f
            val out = HashSet<NativeBridge.Button>()
            if (d.x < -dead) out += NativeBridge.Button.LEFT
            if (d.x > dead) out += NativeBridge.Button.RIGHT
            if (d.y < -dead) out += NativeBridge.Button.UP
            if (d.y > dead) out += NativeBridge.Button.DOWN
            return out
        }
    }
}

class PadLayout {
    // Fractions of width/height for centres; radii as a fraction of the shorter side.
    private val leftStick = PadControl.Stick(NativeBridge.STICK_LEFT, 0.13f, 0.62f, 0.13f)
    private val rightStick = PadControl.Stick(NativeBridge.STICK_RIGHT, 0.70f, 0.82f, 0.09f)
    private val dpad = PadControl.DPad(0.14f, 0.26f, 0.13f)
    private val buttons = listOf(
        PadControl.Button(NativeBridge.Button.A, 0.93f, 0.52f, 0.055f),
        PadControl.Button(NativeBridge.Button.B, 0.865f, 0.64f, 0.055f),
        PadControl.Button(NativeBridge.Button.X, 0.865f, 0.40f, 0.055f),
        PadControl.Button(NativeBridge.Button.Y, 0.80f, 0.52f, 0.055f),
        PadControl.Button(NativeBridge.Button.L, 0.06f, 0.07f, 0.06f),
        PadControl.Button(NativeBridge.Button.ZL, 0.17f, 0.07f, 0.06f),
        PadControl.Button(NativeBridge.Button.R, 0.94f, 0.07f, 0.06f),
        PadControl.Button(NativeBridge.Button.ZR, 0.83f, 0.07f, 0.06f),
        PadControl.Button(NativeBridge.Button.MINUS, 0.42f, 0.90f, 0.04f),
        PadControl.Button(NativeBridge.Button.PLUS, 0.58f, 0.90f, 0.04f),
    )
    private val swap = PadControl.Swap(0.5f, 0.06f, 0.05f)
    private val controls: List<PadControl> = buttons + leftStick + rightStick + dpad + swap

    fun hit(p: Offset, size: Size): PadControl? {
        val short = min(size.width, size.height)
        for (c in controls) {
            val (cx, cy, r) = when (c) {
                is PadControl.Button -> Triple(c.cx, c.cy, c.r)
                is PadControl.Stick -> Triple(c.cx, c.cy, c.r * 1.4f) // the grab zone is wider than the ring
                is PadControl.DPad -> Triple(c.cx, c.cy, c.r)
                is PadControl.Swap -> Triple(c.cx, c.cy, c.r)
                PadControl.Screen -> continue
            }
            val d = p - Offset(cx * size.width, cy * size.height)
            if (hypot(d.x, d.y) <= r * short) return c
        }
        return null
    }

    fun draw(scope: DrawScope, pressed: Set<NativeBridge.Button>, leftThumb: Offset, rightThumb: Offset, showsGamePad: Boolean) = with(scope) {
        val short = min(size.width, size.height)
        val ring = Color(0xFFF4E9DC).copy(alpha = 0.55f)
        val fill = Color(0xFFF0A35E).copy(alpha = 0.55f)
        val stroke = Stroke(width = 2.dp.toPx())
        for (b in buttons) {
            val c = Offset(b.cx * size.width, b.cy * size.height)
            val r = b.r * short
            if (b.button in pressed) drawCircle(fill, r, c) else drawCircle(ring, r, c, style = stroke)
            drawContext.canvas.nativeCanvas.drawText(
                b.button.name.replace("MINUS", "−").replace("PLUS", "+"),
                c.x, c.y + r * 0.35f,
                android.graphics.Paint().apply { color = 0xCCF4E9DC.toInt(); textSize = r * 0.9f; textAlign = android.graphics.Paint.Align.CENTER; isAntiAlias = true }
            )
        }
        run {
            // Labelled with the screen it switches TO.
            val c = Offset(swap.cx * size.width, swap.cy * size.height)
            val r = swap.r * short
            drawCircle(ring, r, c, style = stroke)
            drawContext.canvas.nativeCanvas.drawText(
                if (showsGamePad) "TV" else "PAD",
                c.x, c.y + r * 0.3f,
                android.graphics.Paint().apply { color = 0xCCF4E9DC.toInt(); textSize = r * 0.7f; textAlign = android.graphics.Paint.Align.CENTER; isAntiAlias = true }
            )
        }
        for (s in listOf(leftStick, rightStick)) {
            val c = Offset(s.cx * size.width, s.cy * size.height)
            val r = s.r * short
            drawCircle(ring, r, c, style = stroke)
            val thumb = if (s.index == NativeBridge.STICK_LEFT) leftThumb else rightThumb
            drawCircle(fill, r * 0.45f, c + thumb)
        }
        run {
            val c = Offset(dpad.cx * size.width, dpad.cy * size.height)
            val r = dpad.r * short
            val arm = r * 0.36f
            val dirs = listOf(
                NativeBridge.Button.UP to Offset(0f, -r * 0.6f),
                NativeBridge.Button.DOWN to Offset(0f, r * 0.6f),
                NativeBridge.Button.LEFT to Offset(-r * 0.6f, 0f),
                NativeBridge.Button.RIGHT to Offset(r * 0.6f, 0f),
            )
            for ((button, off) in dirs) {
                val topLeft = c + off - Offset(arm / 2f, arm / 2f)
                if (button in pressed) drawRect(fill, topLeft, Size(arm, arm)) else drawRect(ring, topLeft, Size(arm, arm), style = stroke)
            }
        }
    }
}
