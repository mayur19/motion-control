package com.motionbadminton.controller.android.protocol

import android.os.SystemClock

/**
 * The single clock for every timestamp the controller puts on the wire.
 *
 * `SensorEvent.timestamp` uses the `elapsedRealtimeNanos` time base (it keeps
 * counting through device sleep). Clock-sync PONG and STATUS times must use the
 * same base, or the host's offset estimate is wrong by the device's total sleep
 * time, which made every sample appear hours in the future. `System.nanoTime()`
 * pauses during sleep and is reserved for local interval measurement only.
 */
object ProtocolClock {
    fun nowNanos(): Long = SystemClock.elapsedRealtimeNanos()
}
