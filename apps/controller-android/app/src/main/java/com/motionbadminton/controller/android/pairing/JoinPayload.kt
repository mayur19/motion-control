package com.motionbadminton.controller.android.pairing

import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

data class JoinPayload(
    val host: String,
    val port: Int,
    val sessionId: ULong,
    val pairingSecret: ByteArray,
    val expiresUnixSeconds: Long,
) {
    override fun equals(other: Any?): Boolean = other is JoinPayload &&
        host == other.host && port == other.port && sessionId == other.sessionId &&
        pairingSecret.contentEquals(other.pairingSecret) &&
        expiresUnixSeconds == other.expiresUnixSeconds

    override fun hashCode(): Int = pairingSecret.contentHashCode()

    enum class Error(val userMessage: String) {
        INVALID_CODE("This is not a Motion Badminton pairing code."),
        UNSUPPORTED_VERSION("The host uses an unsupported pairing-code version."),
        INVALID_ADDRESS("The pairing code contains an invalid host address."),
        INVALID_PORT("The pairing code contains an invalid network port."),
        INVALID_CREDENTIAL("The pairing code is damaged or altered."),
        EXPIRED("This pairing code has expired. Ask the host for a new code."),
    }

    class ValidationException(val reason: Error) : IllegalArgumentException(reason.userMessage)

    companion object {
        const val VERSION = 1

        fun parse(rawValue: String, nowUnixSeconds: Long = System.currentTimeMillis() / 1000): JoinPayload {
            val uri = try { URI(rawValue) } catch (_: Exception) { reject(Error.INVALID_CODE) }
            if (uri.scheme != "motion-badminton" || uri.host != "join") reject(Error.INVALID_CODE)
            val values = uri.rawQuery?.split("&")?.associate { pair ->
                val parts = pair.split("=", limit = 2)
                if (parts.size != 2) reject(Error.INVALID_CODE)
                parts[0] to URLDecoder.decode(parts[1], StandardCharsets.UTF_8)
            } ?: reject(Error.INVALID_CODE)
            if (values["v"]?.toIntOrNull() != VERSION) reject(Error.UNSUPPORTED_VERSION)
            val host = values["host"] ?: reject(Error.INVALID_ADDRESS)
            if (!isIPv4(host)) reject(Error.INVALID_ADDRESS)
            val port = values["port"]?.toIntOrNull() ?: reject(Error.INVALID_PORT)
            if (port !in 1..65535) reject(Error.INVALID_PORT)
            val session = values["session"]?.takeIf { it.length == 16 && it.isHex() }
                ?.toULongOrNull(16)?.takeIf { it != 0uL } ?: reject(Error.INVALID_CREDENTIAL)
            val secretHex = values["secret"]?.takeIf { it.length == 32 && it.isHex() }
                ?: reject(Error.INVALID_CREDENTIAL)
            val expiry = values["expires"]?.toLongOrNull()?.takeIf { it > 0 }
                ?: reject(Error.INVALID_CREDENTIAL)
            if (expiry <= nowUnixSeconds) reject(Error.EXPIRED)
            return JoinPayload(host, port, session, secretHex.hexBytes(), expiry)
        }

        private fun isIPv4(value: String): Boolean {
            val parts = value.split('.')
            return parts.size == 4 && parts.all { part ->
                part.isNotEmpty() && part.all(Char::isDigit) &&
                    part.toIntOrNull()?.let { it in 0..255 } == true
            }
        }

        private fun String.isHex() = all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }
        private fun String.hexBytes() = chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        private fun reject(reason: Error): Nothing = throw ValidationException(reason)
    }
}
