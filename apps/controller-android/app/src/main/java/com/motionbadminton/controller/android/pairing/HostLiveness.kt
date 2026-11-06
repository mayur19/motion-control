package com.motionbadminton.controller.android.pairing

import com.motionbadminton.controller.android.protocol.ProtocolV1

/**
 * Controller-side view of whether the host is still alive.
 *
 * The host sends STATUS every heartbeat interval (protocol section 4.7). If no
 * valid host packet for this controller arrives within WELCOME
 * `disconnect_timeout_ms`, the host is treated as lost. Times are
 * [com.motionbadminton.controller.android.protocol.ProtocolClock] values.
 */
data class HostLiveness(val timeoutNanos: Long, val lastHeardNanos: Long) {
    fun recording(now: Long): HostLiveness = copy(lastHeardNanos = maxOf(lastHeardNanos, now))

    fun isExpired(now: Long): Boolean = now > lastHeardNanos && now - lastHeardNanos > timeoutNanos

    companion object {
        const val DEFAULT_TIMEOUT_NANOS = 2_000_000_000L
        private const val NANOS_PER_MILLI = 1_000_000L

        fun fromWelcome(timeoutMilliseconds: Int, now: Long): HostLiveness {
            val configured = timeoutMilliseconds.toLong() * NANOS_PER_MILLI
            return HostLiveness(if (configured > 0) configured else DEFAULT_TIMEOUT_NANOS, now)
        }
    }
}

/** What a decoded control-path packet means to a joined controller. */
sealed interface HostControlEvent {
    data class Ping(val ping: ProtocolV1.Ping) : HostControlEvent
    data object Alive : HostControlEvent
    data class Goodbye(val reason: Int) : HostControlEvent
    data object Unrelated : HostControlEvent

    companion object {
        fun classify(message: ProtocolV1.Message, assignment: PairingAssignment): HostControlEvent {
            if (message.header.sessionId != assignment.sessionId ||
                message.header.controllerId != assignment.controllerId
            ) return Unrelated
            return when (val payload = message.payload) {
                is ProtocolV1.Ping -> Ping(payload)
                is ProtocolV1.Goodbye -> Goodbye(payload.reason)
                else -> Alive
            }
        }
    }
}

/** Why a joined controller stopped treating the host as connected. */
enum class HostLoss {
    /** No host packet within the disconnect timeout; the client retries HELLO. */
    TIMED_OUT,

    /** The host sent GOODBYE; the session is over and a new code is needed. */
    ENDED,
}
