package com.motionbadminton.controller.android.motion

import android.content.Context
import android.net.wifi.WifiManager
import com.motionbadminton.controller.android.protocol.ProtocolV1
import java.net.DatagramPacket
import java.net.DatagramSocket
import com.motionbadminton.controller.android.network.WifiNetwork
import java.net.InetAddress
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

data class MotionStreamerSnapshot(
    val sent: Long,
    val sentHz: Int,
    val networkErrors: Long,
    val lastSuccessfulSendNanoseconds: Long?,
    val status: String,
    val lowLatencyWifiHeld: Boolean,
)

object MotionPacketFactory {
    fun encode(sample: MotionSample, sessionId: ULong, controllerId: UInt, sequence: UInt) =
        ProtocolV1.encode(
            ProtocolV1.Message(
                ProtocolV1.Header(
                    protocolVersion = ProtocolV1.VERSION,
                    messageType = ProtocolV1.MessageType.MOTION,
                    flags = 0,
                    sessionId = sessionId,
                    controllerId = controllerId,
                    sequence = sequence,
                ),
                ProtocolV1.Motion(
                    sensorMonotonicNs = sample.monotonicNanoseconds.toULong(),
                    acceleration = sample.acceleration,
                    angularVelocity = sample.angularVelocity,
                    orientation = sample.orientation,
                    accuracy = sample.accuracy,
                    sensorFlags = sample.sensorFlags,
                ),
            ),
        )
}

class MotionStreamer(
    context: Context,
    private val buffer: MotionSampleBuffer,
    sessionId: ULong = nonzeroULong(),
    controllerId: UInt = nonzeroUInt(),
) {
    var sessionId: ULong = sessionId
        private set
    var controllerId: UInt = controllerId
        private set
    private val wifiManager = context.applicationContext.getSystemService(WifiManager::class.java)
    private val wifiNetwork = WifiNetwork(context)
    private val lock = Any()
    private var wifiLock: WifiManager.WifiLock? = null
    private var executor: ScheduledExecutorService? = null
    private var socket: DatagramSocket? = null
    private var destination: InetAddress? = null
    private var port = 0
    private var sequence = 0u
    private var sent = 0L
    private var networkErrors = 0L
    private var lastSuccessfulSend: Long? = null
    private val recentSends = ArrayDeque<Long>()
    private var status = "Stopped"

    fun configure(sessionId: ULong, controllerId: UInt) {
        synchronized(lock) {
            this.sessionId = sessionId
            this.controllerId = controllerId
            sequence = 0u
        }
    }

    fun start(host: String, port: Int): Boolean {
        stop()
        if (host.isBlank() || port !in 1..65535) {
            synchronized(lock) { status = "Invalid destination" }
            return false
        }
        return try {
            destination = InetAddress.getByName(host)
            this.port = port
            socket = DatagramSocket().also { wifiNetwork.bind(it) }
            wifiLock = wifiManager.createWifiLock(
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY,
                "MotionBadminton:streaming",
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
            executor = Executors.newSingleThreadScheduledExecutor { runnable ->
                Thread(runnable, "MotionBadminton-UDP").apply { priority = Thread.MAX_PRIORITY }
            }.also {
                it.scheduleAtFixedRate(::sendOneIfAvailable, 0, 1, TimeUnit.MILLISECONDS)
            }
            synchronized(lock) { status = "Streaming" }
            true
        } catch (_: Exception) {
            synchronized(lock) {
                networkErrors++
                status = "Start failed"
            }
            stopResources()
            false
        }
    }

    fun stop() {
        stopResources()
        synchronized(lock) {
            status = "Stopped"
            recentSends.clear()
        }
    }

    private fun stopResources() {
        executor?.shutdownNow()
        executor = null
        socket?.close()
        socket = null
        if (wifiLock?.isHeld == true) wifiLock?.release()
        wifiLock = null
    }

    private fun sendOneIfAvailable() {
        val sample = buffer.takeOne() ?: return
        try {
            val payload = MotionPacketFactory.encode(sample, sessionId, controllerId, sequence)
            sequence++
            socket?.send(DatagramPacket(payload, payload.size, destination, port))
                ?: throw IllegalStateException("Socket stopped")
            val now = System.nanoTime()
            synchronized(lock) {
                sent++
                lastSuccessfulSend = now
                recentSends.addLast(now)
                val cutoff = now - 1_000_000_000L
                while (recentSends.firstOrNull()?.let { it < cutoff } == true) {
                    recentSends.removeFirst()
                }
            }
        } catch (_: Exception) {
            synchronized(lock) { networkErrors++ }
        }
    }

    fun snapshot(): MotionStreamerSnapshot = synchronized(lock) {
        MotionStreamerSnapshot(
            sent = sent,
            sentHz = recentSends.size,
            networkErrors = networkErrors,
            lastSuccessfulSendNanoseconds = lastSuccessfulSend,
            status = status,
            lowLatencyWifiHeld = wifiLock?.isHeld == true,
        )
    }

    companion object {
        private val random = SecureRandom()
        private fun nonzeroULong(): ULong = generateSequence { random.nextLong().toULong() }
            .first { it != 0uL }
        private fun nonzeroUInt(): UInt = generateSequence { random.nextInt().toUInt() }
            .first { it != 0u }
    }
}
