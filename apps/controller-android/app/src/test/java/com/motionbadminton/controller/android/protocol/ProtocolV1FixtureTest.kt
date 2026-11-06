package com.motionbadminton.controller.android.protocol

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ProtocolV1FixtureTest {
    private val fixtureRoot = File("../../../protocol/golden-vectors").canonicalFile
    private val manifest: JsonObject by lazy {
        fixtureRoot.resolve("manifest.json").reader().use {
            JsonParser.parseReader(it).asJsonObject
        }
    }

    @Test
    fun everyPositiveFixtureDecodesAndReencodesByteForByte() {
        val fixtures = manifest.getAsJsonArray("positives")
        assertEquals(ProtocolV1.MessageType.entries.size, fixtures.size())
        val decodedTypes = mutableSetOf<ProtocolV1.MessageType>()

        fixtures.forEach { element ->
            val fixture = element.asJsonObject
            val relativePath = fixture.get("file").asString
            val expectedType = fixture.get("message_type").asInt
            val bytes = fixtureRoot.resolve(relativePath).readBytes()
            val message = ProtocolV1.decode(bytes)
            assertEquals(relativePath, expectedType, message.header.messageType.code)
            assertArrayEquals(relativePath, bytes, ProtocolV1.encode(message))
            decodedTypes += message.header.messageType
        }
        assertEquals(ProtocolV1.MessageType.entries.toSet(), decodedTypes)
    }

    @Test
    fun everyNegativeFixtureReturnsItsManifestRejection() {
        val fixtures = manifest.getAsJsonArray("negatives")
        assertTrue(fixtures.size() >= 5)
        fixtures.forEach { element ->
            val fixture = element.asJsonObject
            val relativePath = fixture.get("file").asString
            val expected = fixture.get("expected_rejection").asString
            val error = assertThrows(ProtocolV1.CodecException::class.java) {
                ProtocolV1.decode(fixtureRoot.resolve(relativePath).readBytes())
            }
            assertEquals(relativePath, expected, error.rejection.name)
        }
    }

    @Test
    fun workedMotionValuesDecodeWithinManifestTolerance() {
        val tolerance = manifest.get("float_tolerance").asFloat
        val message = ProtocolV1.decode(fixtureRoot.resolve("positive/motion.bin").readBytes())
        val motion = message.payload as ProtocolV1.Motion
        assertEquals(123_456_789uL, motion.sensorMonotonicNs)
        assertEquals(1f, motion.acceleration[0], tolerance)
        assertEquals(-9.80665f, motion.acceleration[2], tolerance)
        assertEquals(-0.2f, motion.angularVelocity[1], tolerance)
        assertEquals(listOf(0f, 0f, 0f, 1f), motion.orientation)
        assertEquals(3, motion.accuracy)
        assertEquals(7, motion.sensorFlags)
    }
}
