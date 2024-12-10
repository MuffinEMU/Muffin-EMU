package info.cemu.cemu.input

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import info.cemu.cemu.nativeinterface.NativeInput.onMotion
import info.cemu.cemu.nativeinterface.NativeInput.setMotionEnabled

class SensorManager(context: Context) : SensorEventListener {
    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelerometer =
        sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val gyroscope =
        sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
    private val hasMotionData = accelerometer != null && gyroscope != null
    private var accelX = 0f
    private var accelY = 0f
    private var accelZ = 0f
    private var isLandscape = true
    private var isListening = false

    fun startListening() {
        if (!hasMotionData || isListening) {
            return
        }
        isListening = true
        setMotionEnabled(true)
        sensorManager.registerListener(this, gyroscope, SensorManager.SENSOR_DELAY_GAME)
        sensorManager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_GAME)
    }

    fun setIsLandscape(isLandscape: Boolean) {
        this.isLandscape = isLandscape
    }

    fun pauseListening() {
        if (!hasMotionData || !isListening) {
            return
        }
        isListening = false
        setMotionEnabled(false)
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
            accelX = event.values[0]
            accelY = event.values[1]
            accelZ = event.values[2]
            return
        }
        if (event.sensor.type != Sensor.TYPE_GYROSCOPE) {
            return
        }
        val gyroX = event.values[0]
        val gyroY = event.values[1]
        val gyroZ = event.values[2]
        if (isLandscape) {
            onMotion(event.timestamp, gyroY, gyroZ, gyroX, accelY, accelZ, accelX)
            return
        }
        onMotion(event.timestamp, gyroX, gyroY, gyroZ, accelX, accelY, accelZ)
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
    }
}
