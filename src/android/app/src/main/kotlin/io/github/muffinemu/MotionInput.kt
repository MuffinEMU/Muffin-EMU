// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

package io.github.muffinemu

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.view.Surface

/**
 * The phone's gyroscope and accelerometer as the GamePad's motion (gyro aiming, tilt). Android's sensor axes are
 * CoreMotion's (x right, y toward the top in portrait, z out of the screen; rates counter-clockwise in rad/s), so
 * this does step 1 of IOSMotion.mm: turn each reading into the screen's frame for the current rotation. The
 * accelerometer reports the force away from the ground in m/s²; the core wants the ground vector in g. The bridge
 * does the rest (submitMotion).
 */
class MotionInput(context: Context, private val rotation: () -> Int) : SensorEventListener {
    private val sensors = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val gyroscope = sensors.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
    private val accelerometer = sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val ground = FloatArray(3)
    private var haveGround = false

    /** False on a device with no gyroscope; the GamePad then reports no motion, as before. */
    val available: Boolean get() = gyroscope != null && accelerometer != null

    fun start() {
        if (!available) return
        sensors.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_GAME)
        sensors.registerListener(this, gyroscope, SensorManager.SENSOR_DELAY_GAME)
    }

    fun stop() {
        sensors.unregisterListener(this)
        haveGround = false
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                for (i in 0..2) ground[i] = -event.values[i] / SensorManager.GRAVITY_EARTH
                haveGround = true
            }
            Sensor.TYPE_GYROSCOPE -> {
                if (!haveGround) return
                val r = toScreen(ground[0], ground[1], ground[2])
                val w = toScreen(event.values[0], event.values[1], event.values[2])
                NativeBridge.submitMotion(r[0], r[1], r[2], w[0], w[1], w[2], event.timestamp / 1e9)
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}

    /**
     * Device frame to screen frame (right, up, out). ROTATION_90 means the device was turned counter-clockwise
     * (its top now points left), which is iOS's LandscapeRight row in IOSMotion.mm; ROTATION_270 is LandscapeLeft.
     */
    private fun toScreen(x: Float, y: Float, z: Float): FloatArray = when (rotation()) {
        Surface.ROTATION_90 -> floatArrayOf(-y, x, z)
        Surface.ROTATION_180 -> floatArrayOf(-x, -y, z)
        Surface.ROTATION_270 -> floatArrayOf(y, -x, z)
        else -> floatArrayOf(x, y, z)
    }
}
