package com.motionbadminton.controller.android.motion

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager

data class MotionSamplerSnapshot(
    val requestedHz: Int,
    val actualHz: Int,
    val accuracy: Int,
    val status: String,
    val buffer: MotionBufferSnapshot,
)

class MotionSampler(
    private val sensorManager: SensorManager,
    val buffer: MotionSampleBuffer = MotionSampleBuffer(),
) : SensorEventListener {
    companion object {
        const val REQUESTED_HZ = 200
        const val REQUESTED_PERIOD_MICROSECONDS = 1_000_000 / REQUESTED_HZ
    }

    private val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val gyroscope = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE_UNCALIBRATED)
        ?: sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
    private val rotation = sensorManager.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
        ?: sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)

    private val lock = Any()
    private var acceleration: List<Float>? = null
    private var angularVelocity: List<Float>? = null
    private var orientation: List<Float>? = null
    private var accuracy = SensorManager.SENSOR_STATUS_UNRELIABLE
    private var status = "Stopped"
    private val recentTimestamps = ArrayDeque<Long>()

    fun start(): Boolean {
        if (status == "Sampling") return true
        if (accelerometer == null || gyroscope == null || rotation == null) {
            synchronized(lock) { status = "Unavailable" }
            return false
        }
        val accelerationRegistered = sensorManager.registerListener(
            this, accelerometer, REQUESTED_PERIOD_MICROSECONDS, 0,
        )
        val gyroscopeRegistered = sensorManager.registerListener(
            this, gyroscope, REQUESTED_PERIOD_MICROSECONDS, 0,
        )
        val rotationRegistered = sensorManager.registerListener(
            this, rotation, REQUESTED_PERIOD_MICROSECONDS, 0,
        )
        val started = accelerationRegistered && gyroscopeRegistered && rotationRegistered
        synchronized(lock) { status = if (started) "Sampling" else "Registration failed" }
        if (!started) sensorManager.unregisterListener(this)
        return started
    }

    fun stop(reason: String = "Stopped") {
        sensorManager.unregisterListener(this)
        buffer.clear()
        synchronized(lock) {
            status = reason
            recentTimestamps.clear()
        }
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_GYROSCOPE, Sensor.TYPE_GYROSCOPE_UNCALIBRATED -> {
                synchronized(lock) {
                    angularVelocity = event.values.take(3)
                }
            }
            Sensor.TYPE_GAME_ROTATION_VECTOR, Sensor.TYPE_ROTATION_VECTOR -> {
                val quaternion = FloatArray(4)
                SensorManager.getQuaternionFromVector(quaternion, event.values)
                synchronized(lock) {
                    orientation = listOf(quaternion[1], quaternion[2], quaternion[3], quaternion[0])
                }
            }
            Sensor.TYPE_ACCELEROMETER -> {
                val sample: MotionSample?
                synchronized(lock) {
                    acceleration = event.values.take(3)
                    val gyro = angularVelocity
                    val attitude = orientation
                    sample = if (gyro != null && attitude != null) {
                        MotionSample(
                            monotonicNanoseconds = event.timestamp,
                            acceleration = acceleration!!,
                            angularVelocity = gyro,
                            orientation = attitude,
                            accuracy = protocolAccuracy(accuracy),
                            sensorFlags = 0x07,
                        )
                    } else null
                }
                if (sample != null && buffer.offer(sample)) {
                    synchronized(lock) {
                        recentTimestamps.addLast(event.timestamp)
                        val cutoff = event.timestamp - 1_000_000_000L
                        while (recentTimestamps.firstOrNull()?.let { it < cutoff } == true) {
                            recentTimestamps.removeFirst()
                        }
                    }
                }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, value: Int) {
        synchronized(lock) { accuracy = value }
    }

    fun snapshot(): MotionSamplerSnapshot = synchronized(lock) {
        MotionSamplerSnapshot(
            requestedHz = REQUESTED_HZ,
            actualHz = recentTimestamps.size,
            accuracy = protocolAccuracy(accuracy),
            status = status,
            buffer = buffer.snapshot(),
        )
    }

    private fun protocolAccuracy(value: Int): Int = when (value) {
        SensorManager.SENSOR_STATUS_UNRELIABLE -> 0
        SensorManager.SENSOR_STATUS_ACCURACY_LOW -> 1
        SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM -> 2
        SensorManager.SENSOR_STATUS_ACCURACY_HIGH -> 3
        else -> 255
    }
}
