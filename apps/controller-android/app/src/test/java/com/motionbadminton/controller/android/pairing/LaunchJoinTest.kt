package com.motionbadminton.controller.android.pairing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LaunchJoinTest {
    private val uri = "motion-badminton://join?v=1&host=192.0.2.1&port=7000"

    @Test
    fun `release builds ignore a join uri supplied by another app`() {
        assertNull(LaunchJoin.acceptedUri(uri, debugBuild = false))
    }

    @Test
    fun `debug builds accept the automation join uri`() {
        assertEquals(uri, LaunchJoin.acceptedUri(uri, debugBuild = true))
        assertNull(LaunchJoin.acceptedUri(null, debugBuild = true))
        assertNull(LaunchJoin.acceptedUri("  ", debugBuild = true))
    }
}
