package com.motionbadminton.controller.android.motion

import com.motionbadminton.controller.android.protocol.ProtocolV1
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

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
}
