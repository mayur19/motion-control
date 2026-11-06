package com.motionbadminton.controller.android.motion

data class MotionSample(
    val monotonicNanoseconds: Long,
    val acceleration: List<Float>,
    val angularVelocity: List<Float>,
    val orientation: List<Float>,
    val accuracy: Int,
    val sensorFlags: Int,
)

data class MotionBufferSnapshot(
    val queued: Int,
    val accepted: Long,
    val droppedForCapacity: Long,
    val rejectedNonMonotonic: Long,
    val lastTimestampNanoseconds: Long?,
)

/** Drop-oldest bounded handoff. Sensor callbacks never wait for networking. */
class MotionSampleBuffer(val capacity: Int = 256) {
    private val samples = ArrayDeque<MotionSample>(capacity)
    private var accepted = 0L
    private var droppedForCapacity = 0L
    private var rejectedNonMonotonic = 0L
    private var lastTimestamp: Long? = null

    init {
        require(capacity > 0)
    }

    @Synchronized
    fun offer(sample: MotionSample): Boolean {
        if (lastTimestamp?.let { sample.monotonicNanoseconds <= it } == true) {
            rejectedNonMonotonic++
            return false
        }
        lastTimestamp = sample.monotonicNanoseconds
        accepted++
        if (samples.size == capacity) {
            samples.removeFirst()
            droppedForCapacity++
        }
        samples.addLast(sample)
        return true
    }

    @Synchronized
    fun takeOne(): MotionSample? = samples.removeFirstOrNull()

    @Synchronized
    fun clear() = samples.clear()

    @Synchronized
    fun snapshot() = MotionBufferSnapshot(
        queued = samples.size,
        accepted = accepted,
        droppedForCapacity = droppedForCapacity,
        rejectedNonMonotonic = rejectedNonMonotonic,
        lastTimestampNanoseconds = lastTimestamp,
    )
}
