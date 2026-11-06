package com.motionbadminton.controller.android.pairing

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.motionbadminton.controller.android.BuildConfig
import com.motionbadminton.controller.android.motion.MotionSampler
import com.motionbadminton.controller.android.network.WifiNetwork
import com.motionbadminton.controller.android.protocol.ProtocolClock
import com.motionbadminton.controller.android.protocol.ProtocolV1
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import java.util.UUID

data class PairingAssignment(val sessionId: ULong, val controllerId: UInt, val player: Int)

sealed interface PairingResult {
    data class Joined(val assignment: PairingAssignment) : PairingResult
    data class Failed(val message: String) : PairingResult
}

class PairingClient(context: Context) {
    private val applicationContext = context.applicationContext
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "MotionBadminton-Pairing")
    }
    private val main = Handler(Looper.getMainLooper())
    private val generation = AtomicInteger()
    private val wifi = WifiNetwork(applicationContext)
    private val installationId = applicationContext
        .getSharedPreferences("motion_badminton", Context.MODE_PRIVATE)
        .let { preferences ->
            preferences.getString("installation_id", null) ?: UUID.randomUUID().toString()
                .replace("-", "").take(8)
                .also { preferences.edit().putString("installation_id", it).apply() }
        }
    @Volatile private var controlSocket: DatagramSocket? = null
    @Volatile private var appActive = true
    @Volatile private var sensorValid = true
    @Volatile private var actualSampleHz = 0
    @Volatile private var activeJoin: ActiveJoin? = null

    private data class ActiveJoin(
        val payload: JoinPayload,
        val callback: (PairingResult) -> Unit,
        val onHostLost: (HostLoss) -> Unit,
    )

    fun join(
        rawValue: String,
        onHostLost: (HostLoss) -> Unit = {},
        callback: (PairingResult) -> Unit,
    ) {
        val payload = try {
            JoinPayload.parse(rawValue)
        } catch (error: JoinPayload.ValidationException) {
            callback(PairingResult.Failed(error.reason.userMessage))
            return
        }
        val token = generation.incrementAndGet()
        activeJoin = ActiveJoin(payload, callback, onHostLost)
        worker.execute {
            val result = exchange(payload, token)
            if (generation.get() == token) main.post { callback(result) }
        }
    }

    fun cancel() {
        generation.incrementAndGet()
        activeJoin = null
        controlSocket?.close()
        controlSocket = null
    }

    fun updateStatus(appActive: Boolean, sensorValid: Boolean, actualSampleHz: Int) {
        this.appActive = appActive
        this.sensorValid = sensorValid
        this.actualSampleHz = actualSampleHz.coerceIn(0, 1000)
    }

    private fun exchange(payload: JoinPayload, token: Int): PairingResult {
        val socket = try {
            DatagramSocket().apply {
                val boundToWifi = wifi.bind(this)
                Log.d(TAG, "join socket created boundToWifi=$boundToWifi")
                connect(InetAddress.getByName(payload.host), payload.port)
                soTimeout = 350
            }
        } catch (_: Exception) {
            return PairingResult.Failed(RejoinPolicy.UNREACHABLE_MESSAGE)
        }
        var sequence = 0u
        val delays = listOf(0L, 250L, 500L, 1_000L, 1_500L)
        for (delay in delays) {
            if (generation.get() != token) {
                socket.close()
                return PairingResult.Failed("Pairing canceled.")
            }
            if (delay > 0) Thread.sleep(delay)
            val hello = helloPacket(payload, sequence++)
            try {
                socket.send(DatagramPacket(hello, hello.size))
                val response = ByteArray(256)
                val packet = DatagramPacket(response, response.size)
                socket.receive(packet)
                val decoded = ProtocolV1.decode(response.copyOf(packet.length))
                Log.d(
                    TAG,
                    "join attempt=$sequence received type=${decoded.header.messageType} " +
                        "sessionMatch=${decoded.header.sessionId == payload.sessionId}",
                )
                if (decoded.header.messageType != ProtocolV1.MessageType.WELCOME ||
                    decoded.header.sessionId != payload.sessionId
                ) continue
                val welcome = decoded.payload as ProtocolV1.Welcome
                if (welcome.sessionState == 1) {
                    val assignment = PairingAssignment(
                        payload.sessionId, decoded.header.controllerId, welcome.player,
                    )
                    controlSocket?.close()
                    controlSocket = socket
                    Thread(
                        {
                            controlLoop(socket, assignment, token, sequence, welcome.disconnectTimeoutMs)
                        },
                        "MotionBadminton-Clock",
                    ).apply { isDaemon = true }.start()
                    return PairingResult.Joined(assignment)
                }
                socket.close()
                return PairingResult.Failed(rejectionMessage(welcome.sessionState))
            } catch (_: SocketTimeoutException) {
                Log.d(TAG, "join attempt=$sequence timed out")
            } catch (error: Exception) {
                // A malformed/unrelated datagram is ignored; retry remains bounded.
                Log.d(TAG, "join attempt=$sequence ignored ${error.javaClass.simpleName}")
            }
        }
        socket.close()
        return PairingResult.Failed(RejoinPolicy.UNREACHABLE_MESSAGE)
    }

    private fun controlLoop(
        socket: DatagramSocket,
        assignment: PairingAssignment,
        token: Int,
        initialSequence: UInt,
        disconnectTimeoutMs: Int,
    ) {
        var sequence = initialSequence
        var nextHeartbeat = 0L
        var liveness = HostLiveness.fromWelcome(disconnectTimeoutMs, ProtocolClock.nowNanos())
        socket.soTimeout = 100
        while (!socket.isClosed && generation.get() == token) {
            try {
                val now = ProtocolClock.nowNanos()
                if (appActive && liveness.isExpired(now)) {
                    handleHostLoss(HostLoss.TIMED_OUT, socket, token)
                    return
                }
                if (now >= nextHeartbeat) {
                    sequence = sendStatus(socket, assignment, sequence)
                    nextHeartbeat = now + 500_000_000L
                }
                val response = ByteArray(256)
                val packet = DatagramPacket(response, response.size)
                socket.receive(packet)
                val receiveNanos = ProtocolClock.nowNanos()
                val receiveTime = receiveNanos.toULong()
                val decoded = ProtocolV1.decode(response.copyOf(packet.length))
                val ping = when (val event = HostControlEvent.classify(decoded, assignment)) {
                    HostControlEvent.Unrelated -> continue
                    HostControlEvent.Alive -> {
                        liveness = liveness.recording(receiveNanos)
                        continue
                    }
                    is HostControlEvent.Goodbye -> {
                        handleHostLoss(HostLoss.ENDED, socket, token)
                        return
                    }
                    is HostControlEvent.Ping -> {
                        liveness = liveness.recording(receiveNanos)
                        event.ping
                    }
                }
                val sendTime = ProtocolClock.nowNanos().toULong()
                val pong = ProtocolV1.encode(
                    ProtocolV1.Message(
                        ProtocolV1.Header(
                            ProtocolV1.VERSION, ProtocolV1.MessageType.PONG, 0,
                            assignment.sessionId, assignment.controllerId, sequence++,
                        ),
                        ProtocolV1.Pong(
                            ping.pingId,
                            ping.senderMonotonicNs,
                            receiveTime,
                            sendTime,
                        ),
                    ),
                )
                socket.send(DatagramPacket(pong, pong.size))
            } catch (_: SocketTimeoutException) {
                // Periodically re-check cancellation.
            } catch (_: Exception) {
                if (!socket.isClosed) continue
            }
        }
    }

    /**
     * Leaves Connected when the host stops answering or says GOODBYE. A timeout
     * re-sends HELLO with the same installation identity for a bounded window
     * so a brief host-side outage can reclaim the reservation; GOODBYE ends the
     * pairing. Results are delivered through the original join callback.
     */
    private fun handleHostLoss(loss: HostLoss, socket: DatagramSocket, token: Int) {
        socket.close()
        if (controlSocket === socket) controlSocket = null
        val join = activeJoin ?: return
        if (generation.get() != token) return
        main.post { join.onHostLost(loss) }
        when (loss) {
            HostLoss.ENDED -> main.post { join.callback(PairingResult.Failed(HOST_ENDED_MESSAGE)) }
            HostLoss.TIMED_OUT -> worker.execute { rejoin(join, token) }
        }
    }

    private fun rejoin(join: ActiveJoin, token: Int) {
        val deadline = System.nanoTime() + RejoinPolicy.WINDOW_NANOS
        var last: PairingResult? = null
        while (generation.get() == token) {
            val step = RejoinPolicy.next(System.nanoTime(), deadline, wifi.current() != null, last)
            when (step) {
                RejoinStep.Attempt -> last = exchange(join.payload, token)
                RejoinStep.WaitForWifi -> Thread.sleep(RejoinPolicy.WIFI_POLL_MILLIS)
                is RejoinStep.Finish -> {
                    if (generation.get() == token) main.post { join.callback(step.result) }
                    return
                }
            }
        }
    }

    private fun sendStatus(
        socket: DatagramSocket,
        assignment: PairingAssignment,
        sequence: UInt,
    ): UInt {
        val message = ProtocolV1.Message(
            ProtocolV1.Header(
                ProtocolV1.VERSION, ProtocolV1.MessageType.STATUS, 0,
                assignment.sessionId, assignment.controllerId, sequence,
            ),
            ProtocolV1.Status(
                senderMonotonicNs = ProtocolClock.nowNanos().toULong(),
                batteryPercent = 255,
                sensorState = if (sensorValid) 2 else 3,
                appState = if (appActive) 0 else 1,
                pauseReason = if (appActive) 0 else 1,
                actualSampleHz = actualSampleHz,
                lastMotionSequence = 0u,
            ),
        )
        val data = ProtocolV1.encode(message)
        socket.send(DatagramPacket(data, data.size))
        return sequence + 1u
    }

    private fun helloPacket(payload: JoinPayload, sequence: UInt): ByteArray = ProtocolV1.encode(
        ProtocolV1.Message(
            ProtocolV1.Header(
                ProtocolV1.VERSION, ProtocolV1.MessageType.HELLO, 0,
                payload.sessionId, 0u, sequence,
            ),
            ProtocolV1.Hello(
                pairingSecret = payload.pairingSecret,
                platform = 2,
                capabilities = 0x000F,
                maxSampleHz = MotionSampler.REQUESTED_HZ,
                deviceModel = "$installationId#${Build.MANUFACTURER} ${Build.MODEL}".take(63),
                appVersion = BuildConfig.VERSION_NAME.take(31),
                osVersion = "Android ${Build.VERSION.RELEASE}".take(31),
            ),
        ),
    )

    private fun rejectionMessage(state: Int): String = when (state) {
        2 -> "This pairing code has expired. Ask the host for a new code."
        3 -> "The pairing code was rejected. Scan the current host code again."
        4 -> "The host already has two controllers connected."
        5 -> "The host does not support this controller version."
        else -> "The host rejected the join request."
    }

    private companion object {
        /** Debug log tag; messages carry no secrets, identities or addresses. */
        const val TAG = "MotionBadminton"
        const val HOST_ENDED_MESSAGE = "The host ended the session. Scan the new host code to join again."
    }
}
