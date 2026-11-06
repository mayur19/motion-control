package com.motionbadminton.controller.android.pairing

import org.junit.Assert.assertEquals
import org.junit.Test

class RejoinPolicyTest {
    private val start = 1_000_000_000L
    private val deadline = start + RejoinPolicy.WINDOW_NANOS
    private val unreachable = PairingResult.Failed(RejoinPolicy.UNREACHABLE_MESSAGE)

    @Test
    fun `window covers the largest host reservation`() {
        assertEquals(60_000_000_000L, RejoinPolicy.WINDOW_NANOS)
    }

    @Test
    fun `waits for wifi instead of sending hello over another network`() {
        assertEquals(RejoinStep.WaitForWifi, RejoinPolicy.next(start, deadline, wifiAvailable = false, last = null))
        assertEquals(RejoinStep.WaitForWifi, RejoinPolicy.next(start, deadline, wifiAvailable = false, last = unreachable))
    }

    @Test
    fun `attempts while wifi is up and only unreachable results so far`() {
        assertEquals(RejoinStep.Attempt, RejoinPolicy.next(start, deadline, wifiAvailable = true, last = null))
        assertEquals(RejoinStep.Attempt, RejoinPolicy.next(start, deadline, wifiAvailable = true, last = unreachable))
    }

    @Test
    fun `finishes on join or on a real rejection`() {
        val joined = PairingResult.Joined(PairingAssignment(1uL, 2u, 1))
        val rejected = PairingResult.Failed("This pairing code has expired. Ask the host for a new code.")
        assertEquals(RejoinStep.Finish(joined), RejoinPolicy.next(start, deadline, true, joined))
        assertEquals(RejoinStep.Finish(rejected), RejoinPolicy.next(start, deadline, true, rejected))
    }

    @Test
    fun `gives up as unreachable when the window closes`() {
        assertEquals(RejoinStep.Finish(unreachable), RejoinPolicy.next(deadline, deadline, false, null))
        assertEquals(RejoinStep.Finish(unreachable), RejoinPolicy.next(deadline + 1, deadline, true, unreachable))
    }
}
