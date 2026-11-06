package com.motionbadminton.controller.android.pairing

import com.motionbadminton.controller.android.protocol.ProtocolV1
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HostLivenessTest {
    private val second = 1_000_000_000L
    private val assignment = PairingAssignment(0x0102030405060708uL, 0x0A0B0C0Du, 1)

    @Test
    fun `host is lost only after the welcome timeout without host packets`() {
        val liveness = HostLiveness.fromWelcome(timeoutMilliseconds = 2000, now = 10 * second)
        assertFalse(liveness.isExpired(12 * second))
        assertTrue(liveness.isExpired(12 * second + 1))

        val heard = liveness.recording(11 * second)
        assertFalse(heard.isExpired(13 * second))
        assertTrue(heard.isExpired(13 * second + 1))
        assertFalse("recording must not mutate the original", liveness.isExpired(12 * second))
    }

    @Test
    fun `zero timeout falls back to protocol default`() {
        assertEquals(
            HostLiveness.DEFAULT_TIMEOUT_NANOS,
            HostLiveness.fromWelcome(timeoutMilliseconds = 0, now = 0).timeoutNanos,
        )
    }

    @Test
    fun `clock going backwards is not expiry`() {
        assertFalse(HostLiveness.fromWelcome(2000, 10 * second).isExpired(5 * second))
    }

    @Test
    fun `classifies host control packets for this controller`() {
        val ping = ProtocolV1.Ping(7u, 99uL)
        assertEquals(HostControlEvent.Ping(ping), HostControlEvent.classify(message(ProtocolV1.MessageType.PING, ping), assignment))
        assertEquals(HostControlEvent.Alive, HostControlEvent.classify(message(ProtocolV1.MessageType.STATUS, hostStatus()), assignment))
        assertEquals(
            HostControlEvent.Goodbye(3),
            HostControlEvent.classify(message(ProtocolV1.MessageType.GOODBYE, ProtocolV1.Goodbye(3, 4u, 5uL)), assignment),
        )
    }

    @Test
    fun `ignores packets for another session or controller`() {
        assertEquals(
            HostControlEvent.Unrelated,
            HostControlEvent.classify(message(ProtocolV1.MessageType.STATUS, hostStatus(), sessionId = 1uL), assignment),
        )
        assertEquals(
            HostControlEvent.Unrelated,
            HostControlEvent.classify(message(ProtocolV1.MessageType.STATUS, hostStatus(), controllerId = 1u), assignment),
        )
    }

    private fun hostStatus() = ProtocolV1.Status(
        senderMonotonicNs = 1uL, batteryPercent = 255, sensorState = 0, appState = 0,
        pauseReason = 0, actualSampleHz = 0, lastMotionSequence = 0u,
    )

    private fun message(
        type: ProtocolV1.MessageType,
        payload: ProtocolV1.Payload,
        sessionId: ULong = assignment.sessionId,
        controllerId: UInt = assignment.controllerId,
    ) = ProtocolV1.Message(
        ProtocolV1.Header(ProtocolV1.VERSION, type, 0, sessionId, controllerId, 1u),
        payload,
    )
}
