package com.motionbadminton.controller.android.motion

import com.motionbadminton.controller.android.protocol.ProtocolV1
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

class MotionPipelineTest {
    private fun sample(timestamp: Long) = MotionSample(
        monotonicNanoseconds = timestamp,
        acceleration = listOf(1f, 2f, 3f),
        angularVelocity = listOf(0.1f, 0.2f, 0.3f),
        orientation = listOf(0f, 0f, 0f, 1f),
        accuracy = 3,
        sensorFlags = 0x07,
    )

    @Test
    fun `bounded buffer drops oldest and retains newest`() {
        val buffer = MotionSampleBuffer(capacity = 3)
        (1L..5L).forEach { assertTrue(buffer.offer(sample(it))) }
        assertEquals(3, buffer.snapshot().queued)
        assertEquals(5, buffer.snapshot().accepted)
        assertEquals(2, buffer.snapshot().droppedForCapacity)
        assertEquals(listOf(3L, 4L, 5L), List(3) { buffer.takeOne()!!.monotonicNanoseconds })
    }

    @Test
    fun `buffer rejects duplicate and backward timestamps`() {
        val buffer = MotionSampleBuffer(capacity = 4)
        assertTrue(buffer.offer(sample(100)))
        assertFalse(buffer.offer(sample(100)))
        assertFalse(buffer.offer(sample(99)))
        assertTrue(buffer.offer(sample(101)))
        assertEquals(2, buffer.snapshot().accepted)
        assertEquals(2, buffer.snapshot().rejectedNonMonotonic)
    }

    @Test
    fun `every sample encodes as one motion datagram`() {
        repeat(20) { rawSequence ->
            val sequence = rawSequence.toUInt()
            val source = sample(1_000_000L + rawSequence)
            val packet = MotionPacketFactory.encode(
                sample = source,
                sessionId = 0x0102030405060708uL,
                controllerId = 0x0A0B0C0Du,
                sequence = sequence,
            )
            assertEquals(ProtocolV1.HEADER_SIZE + 52, packet.size)
            val decoded = ProtocolV1.decode(packet)
            assertEquals(sequence, decoded.header.sequence)
            val motion = decoded.payload as? ProtocolV1.Motion
            assertNotNull(motion)
            assertEquals(source.monotonicNanoseconds.toULong(), motion!!.sensorMonotonicNs)
            assertEquals(source.acceleration, motion.acceleration)
            assertEquals(source.angularVelocity, motion.angularVelocity)
            assertEquals(source.orientation, motion.orientation)
        }
    }

    @Test
    fun `slow swing calibration accepts both hands and is repeatable`() {
        CalibrationHand.entries.forEach { hand ->
            val first = completedCalibration(hand, listOf(.02f, -.01f, .03f))
            val second = completedCalibration(hand, listOf(.03f, -.01f, .03f))
            assertEquals(hand, first.hand)
            assertTrue(kotlin.math.abs(first.accelerationBias[0] - second.accelerationBias[0]) < .02f)
            assertTrue(first.quality >= .6f)
        }
    }

    @Test
    fun `calibration rejects invalid phone orientation`() {
        val calibration = SlowSwingCalibration()
        calibration.beginNeutral(CalibrationHand.RIGHT, true)
        (0..120).forEach { calibration.append(calibrationSample(it, listOf(0f, 0f, 0f, 1f))) }
        try {
            calibration.finishNeutral()
            throw AssertionError("invalid orientation was accepted")
        } catch (error: CalibrationException) {
            assertEquals(CalibrationFailure.INVALID_ORIENTATION, error.failure)
        }
    }

    @Test
    fun `calibration record encodes handedness`() {
        val record = completedCalibration(CalibrationHand.LEFT, listOf(0f, 0f, 0f))
        val packet = CalibrationPacketFactory.encode(record, 1uL, 2u, 0u)
        val payload = ProtocolV1.decode(packet).payload as ProtocolV1.Calibration
        assertEquals(CalibrationHand.LEFT.code, payload.handedness)
    }

    @Test
    fun `join without completed calibration enters calibration`() {
        CalibrationPhase.entries.filter { it != CalibrationPhase.COMPLETE }.forEach { phase ->
            assertEquals(phase.name, JoinCalibrationAction.CALIBRATE, phase.joinAction)
        }
    }

    @Test
    fun `rejoin after completed calibration resends stored calibration`() {
        assertEquals(JoinCalibrationAction.RESEND_STORED_CALIBRATION, CalibrationPhase.COMPLETE.joinAction)
    }

    @Test
    fun `stored record is available only after completed calibration`() {
        val neutralOnly = SlowSwingCalibration()
        neutralOnly.beginNeutral(CalibrationHand.LEFT, true)
        assertNull(neutralOnly.completedRecord)
        val upright = listOf(sin(PI / 4).toFloat(), 0f, 0f, cos(PI / 4).toFloat())
        (0..120).forEach { neutralOnly.append(calibrationSample(it, upright)) }
        neutralOnly.finishNeutral()
        assertNull("neutral alone must not be resent", neutralOnly.completedRecord)

        val completed = completedCalibrator(CalibrationHand.LEFT, listOf(0f, 0f, 0f))
        assertEquals(CalibrationHand.LEFT, completed.completedRecord?.hand)
        completed.reset()
        assertNull(completed.completedRecord)
        assertEquals(CalibrationPhase.IDLE, completed.phase)
    }

    private fun completedCalibration(hand: CalibrationHand, acceleration: List<Float>): CalibrationRecord =
        requireNotNull(completedCalibrator(hand, acceleration).completedRecord)

    private fun completedCalibrator(hand: CalibrationHand, acceleration: List<Float>): SlowSwingCalibration {
        val calibration = SlowSwingCalibration()
        calibration.beginNeutral(hand, true)
        val upright = listOf(sin(PI / 4).toFloat(), 0f, 0f, cos(PI / 4).toFloat())
        (0..120).forEach { calibration.append(calibrationSample(it, upright, acceleration)) }
        calibration.finishNeutral()
        calibration.beginSlowSwing()
        (0..120).forEach { index ->
            val angle = PI / 2 + index.toDouble() / 120 * PI / 6
            calibration.append(calibrationSample(
                index,
                listOf(sin(angle / 2).toFloat(), 0f, 0f, cos(angle / 2).toFloat()),
                acceleration,
                listOf(1f, 0f, 0f),
            ))
        }
        calibration.finishSlowSwing()
        return calibration
    }

    private fun calibrationSample(
        index: Int,
        orientation: List<Float>,
        acceleration: List<Float> = listOf(0f, 0f, 0f),
        angularVelocity: List<Float> = listOf(0f, 0f, 0f),
    ) = MotionSample(
        monotonicNanoseconds = 1_000_000_000L + index * 5_000_000L,
        acceleration = acceleration,
        angularVelocity = angularVelocity,
        orientation = orientation,
        accuracy = 3,
        sensorFlags = 7,
    )
}
