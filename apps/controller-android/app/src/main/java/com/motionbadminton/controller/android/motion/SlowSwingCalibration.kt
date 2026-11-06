package com.motionbadminton.controller.android.motion

import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

enum class CalibrationHand(val code: Int) { RIGHT(1), LEFT(2) }

data class CalibrationRecord(
    val sensorMonotonicNanoseconds: Long,
    val neutralOrientation: List<Float>,
    val accelerationBias: List<Float>,
    val gyroscopeBias: List<Float>,
    val quality: Float,
    val hand: CalibrationHand,
)

enum class CalibrationFailure(val userMessage: String) {
    CONFIRM_SCREEN("Confirm that the screen faces you before capturing."),
    SENSORS_UNAVAILABLE("Motion sensors are not ready. Keep the app open and try again."),
    TOO_SHORT("Keep the phone still until neutral capture finishes."),
    SAMPLE_RATE("Sensor samples were interrupted. Keep the app in front and retry."),
    QUATERNION("Orientation tracking is invalid. Hold the phone steady and retry."),
    UNSTABLE("The phone moved during neutral capture. Hold it completely still."),
    INVALID_ORIENTATION("Hold the phone upright in portrait with its top edge pointing up."),
    EXCESSIVE_BIAS("Gyroscope drift is too high. Rest the phone briefly, then retry."),
    SWING_TOO_SMALL("Swing through a wider controlled arc, then retry."),
    SWING_TOO_FAST("That swing was too fast. Use a slow, controlled practice swing only."),
    SWING_TOO_LONG("Complete one controlled swing within three seconds."),
}

class CalibrationException(val failure: CalibrationFailure) : IllegalStateException(failure.userMessage)

enum class CalibrationPhase {
    IDLE, CAPTURING_NEUTRAL, READY_FOR_SLOW_SWING, CAPTURING_SLOW_SWING, COMPLETE, FAILED;

    /** A completed calibration is resent on (re)join; anything else recalibrates. */
    val joinAction: JoinCalibrationAction
        get() = if (this == COMPLETE) JoinCalibrationAction.RESEND_STORED_CALIBRATION else JoinCalibrationAction.CALIBRATE
}

enum class JoinCalibrationAction { CALIBRATE, RESEND_STORED_CALIBRATION }

class SlowSwingCalibration {
    var phase = CalibrationPhase.IDLE
        private set
    var failure: CalibrationFailure? = null
        private set
    var record: CalibrationRecord? = null
        private set

    /** The accepted record, only once neutral and slow swing both passed. */
    val completedRecord: CalibrationRecord?
        get() = if (phase == CalibrationPhase.COMPLETE) record else null
    private var hand = CalibrationHand.RIGHT
    private val neutral = mutableListOf<MotionSample>()
    private val swing = mutableListOf<MotionSample>()

    fun reset() {
        phase = CalibrationPhase.IDLE
        failure = null
        record = null
        neutral.clear()
        swing.clear()
    }

    fun beginNeutral(hand: CalibrationHand, screenFacingPlayerConfirmed: Boolean) {
        reset()
        if (!screenFacingPlayerConfirmed) fail(CalibrationFailure.CONFIRM_SCREEN)
        this.hand = hand
        phase = CalibrationPhase.CAPTURING_NEUTRAL
    }

    fun beginSlowSwing() {
        if (phase != CalibrationPhase.READY_FOR_SLOW_SWING) return
        swing.clear()
        phase = CalibrationPhase.CAPTURING_SLOW_SWING
    }

    fun append(sample: MotionSample) {
        when (phase) {
            CalibrationPhase.CAPTURING_NEUTRAL -> neutral += sample
            CalibrationPhase.CAPTURING_SLOW_SWING -> swing += sample
            else -> Unit
        }
    }

    fun finishNeutral(): CalibrationRecord {
        validateWindow(neutral, .5, null)
        if (!neutral.all { it.sensorFlags and 7 == 7 && it.accuracy != 0 }) fail(CalibrationFailure.SENSORS_UNAVAILABLE)
        if (!neutral.all { quaternionNorm(it.orientation) in .98f..1.02f }) fail(CalibrationFailure.QUATERNION)
        val orientation = meanQuaternion(neutral.map { it.orientation })
        val spread = neutral.maxOf { angularDistance(it.orientation, orientation) }
        if (spread > degrees(3f)) fail(CalibrationFailure.UNSTABLE)
        val shaft = rotate(orientation, listOf(0f, 1f, 0f))
        val screen = rotate(orientation, listOf(0f, 0f, 1f))
        if (shaft[2] < cos(degrees(35f)) || abs(screen[2]) > sin(degrees(25f))) fail(CalibrationFailure.INVALID_ORIENTATION)
        val accel = neutral.map { it.acceleration }
        val gyro = neutral.map { it.angularVelocity }
        val accelMean = mean(accel)
        val gyroMean = mean(gyro)
        if (standardDeviation(accel, accelMean).any { it > .35f } || rms(gyro).any { it > .15f } || gyro.maxOf(::length) > .35f) fail(CalibrationFailure.UNSTABLE)
        if (gyroMean.any { abs(it) > .20f }) fail(CalibrationFailure.EXCESSIVE_BIAS)
        val quality = min(1f, max(0f, .6f + .4f * max(0f, 1f - spread / degrees(3f))))
        return CalibrationRecord(neutral.last().monotonicNanoseconds, orientation, accelMean, gyroMean, quality, hand).also {
            record = it
            phase = CalibrationPhase.READY_FOR_SLOW_SWING
        }
    }

    fun finishSlowSwing(): CalibrationRecord {
        validateWindow(swing, .6, 3.0)
        if (!swing.all { it.sensorFlags and 7 == 7 && it.accuracy != 0 }) fail(CalibrationFailure.SENSORS_UNAVAILABLE)
        val excursion = swing.maxOf { angularDistance(swing.first().orientation, it.orientation) }
        val peak = swing.maxOf { length(it.angularVelocity) }
        if (excursion < degrees(20f) || peak < .6f) fail(CalibrationFailure.SWING_TOO_SMALL)
        if (excursion > degrees(140f) || peak > 5f) fail(CalibrationFailure.SWING_TOO_FAST)
        return (record ?: fail(CalibrationFailure.SENSORS_UNAVAILABLE)).also { phase = CalibrationPhase.COMPLETE }
    }

    private fun validateWindow(samples: List<MotionSample>, minDuration: Double, maxDuration: Double?) {
        if (samples.size < 2) fail(CalibrationFailure.TOO_SHORT)
        val duration = (samples.last().monotonicNanoseconds - samples.first().monotonicNanoseconds) / 1e9
        if (maxDuration != null && duration > maxDuration) fail(CalibrationFailure.SWING_TOO_LONG)
        if (duration < minDuration) fail(CalibrationFailure.TOO_SHORT)
        if (samples.size < 50 || (samples.size - 1) / duration < 100) fail(CalibrationFailure.SAMPLE_RATE)
    }

    private fun fail(reason: CalibrationFailure): Nothing {
        phase = CalibrationPhase.FAILED
        failure = reason
        record = null
        throw CalibrationException(reason)
    }

    private fun degrees(value: Float) = value * Math.PI.toFloat() / 180f
    private fun length(v: List<Float>) = sqrt(v.sumOf { (it * it).toDouble() }).toFloat()
    private fun quaternionNorm(q: List<Float>) = length(q)
    private fun dot(a: List<Float>, b: List<Float>) = a.indices.sumOf { (a[it] * b[it]).toDouble() }.toFloat()
    private fun mean(values: List<List<Float>>) = List(values[0].size) { axis -> values.map { it[axis] }.average().toFloat() }
    private fun standardDeviation(values: List<List<Float>>, mean: List<Float>) = List(mean.size) { axis -> sqrt(values.map { (it[axis] - mean[axis]) * (it[axis] - mean[axis]) }.average()).toFloat() }
    private fun rms(values: List<List<Float>>) = List(values[0].size) { axis -> sqrt(values.map { it[axis] * it[axis] }.average()).toFloat() }

    private fun meanQuaternion(values: List<List<Float>>): List<Float> {
        val anchor = values.first()
        val sum = MutableList(4) { 0f }
        values.forEach { value ->
            val sign = if (dot(value, anchor) < 0) -1 else 1
            repeat(4) { sum[it] += sign * value[it] }
        }
        val norm = quaternionNorm(sum)
        return sum.map { it / norm }
    }

    private fun angularDistance(a: List<Float>, b: List<Float>): Float {
        val d = abs(dot(a, b) / (quaternionNorm(a) * quaternionNorm(b))).coerceIn(-1f, 1f)
        return 2f * acos(d)
    }

    private fun rotate(qValue: List<Float>, v: List<Float>): List<Float> {
        val norm = quaternionNorm(qValue)
        val q = qValue.map { it / norm }
        val u = q.take(3)
        val uv = cross(u, v)
        val uuv = cross(u, uv)
        return List(3) { v[it] + 2f * (q[3] * uv[it] + uuv[it]) }
    }

    private fun cross(a: List<Float>, b: List<Float>) = listOf(
        a[1]*b[2] - a[2]*b[1], a[2]*b[0] - a[0]*b[2], a[0]*b[1] - a[1]*b[0],
    )
}
