package com.motionbadminton.controller.android.pairing

import com.motionbadminton.controller.android.protocol.ProtocolV1
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class PairingTest {
    private val valid = "motion-badminton://join?v=1&host=192.168.50.12&port=7000&session=0102030405060708&secret=00112233445566778899aabbccddeeff&expires=1800000120"

    @Test
    fun `valid join payload parses exactly`() {
        val result = JoinPayload.parse(valid, nowUnixSeconds = 1_800_000_000)
        assertEquals("192.168.50.12", result.host)
        assertEquals(7000, result.port)
        assertEquals(0x0102030405060708uL, result.sessionId)
        assertArrayEquals(
            byteArrayOf(
                0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
                0x88.toByte(), 0x99.toByte(), 0xaa.toByte(), 0xbb.toByte(),
                0xcc.toByte(), 0xdd.toByte(), 0xee.toByte(), 0xff.toByte(),
            ),
            result.pairingSecret,
        )
    }

    @Test
    fun `expired altered and wrong version codes have specific errors`() {
        fun reason(value: String, now: Long = 1_800_000_000) =
            assertThrows(JoinPayload.ValidationException::class.java) {
                JoinPayload.parse(value, now)
            }.reason
        assertEquals(JoinPayload.Error.EXPIRED, reason(valid, 1_800_000_120))
        assertEquals(
            JoinPayload.Error.INVALID_CREDENTIAL,
            reason(valid.replace("secret=00", "secret=zz")),
        )
        assertEquals(JoinPayload.Error.UNSUPPORTED_VERSION, reason(valid.replace("v=1", "v=2")))
    }

    @Test
    fun `welcome rejection states decode`() {
        for (state in 2..5) {
            val data = ProtocolV1.encode(
                ProtocolV1.Message(
                    ProtocolV1.Header(1, ProtocolV1.MessageType.WELCOME, 0, 1uL, 2u, state.toUInt()),
                    ProtocolV1.Welcome(0, state, 500, 2000, 8, 1uL, 2uL),
                ),
            )
            val welcome = ProtocolV1.decode(data).payload as ProtocolV1.Welcome
            assertEquals(state, welcome.sessionState)
            assertEquals(0, welcome.player)
        }
    }
}
