package com.motionbadminton.controller.android.pairing

/** One decision in the bounded rejoin loop after the host stops answering. */
sealed interface RejoinStep {
    data object Attempt : RejoinStep
    data object WaitForWifi : RejoinStep
    data class Finish(val result: PairingResult) : RejoinStep
}

/**
 * Rejoin rules after a host-liveness timeout. HELLO is only sent while a Wi-Fi
 * network exists (a phone with mobile data would otherwise route it over
 * cellular, where the LAN host is unreachable). The window covers the largest
 * host reservation (game-configurable, 5-60 s, default 30 s); the host's
 * reservation decides whether the same player is restored.
 */
object RejoinPolicy {
    const val WINDOW_NANOS = 60_000_000_000L
    const val WIFI_POLL_MILLIS = 250L
    const val UNREACHABLE_MESSAGE = "The host is unreachable. Check Wi-Fi and ask for a new code."

    fun next(now: Long, deadline: Long, wifiAvailable: Boolean, last: PairingResult?): RejoinStep = when {
        last is PairingResult.Joined -> RejoinStep.Finish(last)
        last is PairingResult.Failed && last.message != UNREACHABLE_MESSAGE -> RejoinStep.Finish(last)
        now >= deadline -> RejoinStep.Finish(last ?: PairingResult.Failed(UNREACHABLE_MESSAGE))
        !wifiAvailable -> RejoinStep.WaitForWifi
        else -> RejoinStep.Attempt
    }
}
