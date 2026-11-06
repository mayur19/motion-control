package com.motionbadminton.controller.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ControllerStateTest {
    @Test
    fun stateNamesAndOrderMatchIosFlow() {
        assertEquals(
            listOf("Not Paired", "Pairing", "Calibration", "Connected", "Paused"),
            ControllerState.entries.map { it.displayName },
        )
    }

    @Test
    fun debugAdvanceCyclesThroughEveryState() {
        var state = ControllerState.NOT_PAIRED
        ControllerState.entries.drop(1).forEach { expected ->
            state = state.next()
            assertEquals(expected, state)
        }
        assertEquals(ControllerState.NOT_PAIRED, state.next())
    }

    @Test
    fun keepAwakeIsLimitedToActiveSessionStates() {
        assertFalse(ControllerState.NOT_PAIRED.keepsScreenAwake)
        assertFalse(ControllerState.PAIRING.keepsScreenAwake)
        assertTrue(ControllerState.CALIBRATION.keepsScreenAwake)
        assertTrue(ControllerState.CONNECTED.keepsScreenAwake)
        assertFalse(ControllerState.PAUSED.keepsScreenAwake)
    }

    @Test
    fun resumeRestoresConnectedOnlyForAPairedPausedController() {
        assertEquals(ControllerState.CONNECTED, ControllerState.PAUSED.resumed(paired = true))
        assertEquals(ControllerState.PAUSED, ControllerState.PAUSED.resumed(paired = false))
        assertEquals(ControllerState.PAIRING, ControllerState.PAIRING.resumed(paired = true))
        assertEquals(ControllerState.NOT_PAIRED, ControllerState.NOT_PAIRED.resumed(paired = false))
    }
}
