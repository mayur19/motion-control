package com.motionbadminton.controller.android

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.graphics.drawable.GradientDrawable
import com.motionbadminton.controller.android.motion.MotionSampleBuffer
import com.motionbadminton.controller.android.motion.MotionSampler
import com.motionbadminton.controller.android.motion.MotionStreamer
import com.motionbadminton.controller.android.pairing.HostLoss
import com.motionbadminton.controller.android.pairing.JoinPayload
import com.motionbadminton.controller.android.pairing.LaunchJoin
import com.motionbadminton.controller.android.pairing.PairingClient
import com.motionbadminton.controller.android.pairing.PairingResult
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning

class MainActivity : Activity() {
    private var controllerState = ControllerState.NOT_PAIRED
    private var paired = false
    private lateinit var stateTitle: TextView
    private lateinit var stateGuidance: TextView
    private lateinit var debugState: TextView
    private lateinit var debugKeepAwake: TextView
    private lateinit var debugHost: EditText
    private lateinit var debugPort: EditText
    private lateinit var debugSensor: TextView
    private lateinit var debugRate: TextView
    private lateinit var debugAccuracy: TextView
    private lateinit var debugQueue: TextView
    private lateinit var debugDropped: TextView
    private lateinit var debugNonMonotonic: TextView
    private lateinit var debugNetwork: TextView
    private lateinit var debugSent: TextView
    private lateinit var debugErrors: TextView
    private lateinit var debugLastSend: TextView
    private lateinit var debugWifi: TextView
    private lateinit var debugPairing: TextView
    private lateinit var debugAssignment: TextView
    private lateinit var manualJoinUri: EditText
    private lateinit var motionSampler: MotionSampler
    private lateinit var motionStreamer: MotionStreamer
    private lateinit var pairingClient: PairingClient
    private val refreshHandler = Handler(Looper.getMainLooper())
    private var isForeground = false
    private var sampling = false
    private var streaming = false
    private val refreshMotionDiagnostics = object : Runnable {
        override fun run() {
            renderMotionDiagnostics()
            if (isForeground) refreshHandler.postDelayed(this, 250)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val buffer = MotionSampleBuffer(capacity = 256)
        motionSampler = MotionSampler(getSystemService(SensorManager::class.java), buffer)
        motionStreamer = MotionStreamer(this, buffer)
        pairingClient = PairingClient(this)
        setContentView(buildInterface())
        renderState()
        LaunchJoin.acceptedUri(
            intent.getStringExtra(LaunchJoin.EXTRA_JOIN_URI),
            debugBuild = BuildConfig.DEBUG,
        )?.let(::beginJoin)
    }

    override fun onResume() {
        super.onResume()
        isForeground = true
        if (::pairingClient.isInitialized) pairingClient.updateStatus(true, true, 0)
        val resumedState = controllerState.resumed(paired)
        if (resumedState != controllerState) {
            controllerState = resumedState
            renderState()
        }
        applyKeepAwakePolicy()
        updateMotionRuntime()
        refreshHandler.removeCallbacks(refreshMotionDiagnostics)
        refreshHandler.post(refreshMotionDiagnostics)
    }

    override fun onPause() {
        isForeground = false
        if (::pairingClient.isInitialized) {
            val sensor = motionSampler.snapshot()
            pairingClient.updateStatus(false, sensor.status == "Sampling", sensor.actualHz)
        }
        refreshHandler.removeCallbacks(refreshMotionDiagnostics)
        stopMotion("Background")
        if (controllerState.keepsScreenAwake) {
            controllerState = ControllerState.PAUSED
            renderState()
        }
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        applyKeepAwakePolicy()
    }

    private fun buildInterface(): View {
        val scroll = ScrollView(this).apply {
            setBackgroundColor(color(R.color.background))
            isFillViewport = true
        }
        val content = verticalLayout(20).apply {
            setPadding(dp(20), dp(24), dp(20), dp(28))
        }
        scroll.addView(content, matchWrap())

        content.addView(horizontalLayout(8).apply {
            addView(verticalLayout(2).apply {
                addView(label("MOTION BADMINTON", 20, R.color.text_primary, true))
                addView(label("Android controller", 14, R.color.text_secondary))
            }, weighted())
            addView(label("v${BuildConfig.VERSION_NAME}", 13, R.color.text_secondary).apply {
                typeface = Typeface.MONOSPACE
                gravity = Gravity.END
            })
        })

        content.addView(panel(verticalLayout(16).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            addView(label("◎", 52, R.color.accent, true).apply { gravity = Gravity.CENTER })
            stateTitle = label("", 28, R.color.text_primary, true).apply { gravity = Gravity.CENTER }
            addView(stateTitle, matchWrap())
            stateGuidance = label("", 16, R.color.text_secondary).apply {
                gravity = Gravity.CENTER
                textAlignment = View.TEXT_ALIGNMENT_CENTER
            }
            addView(stateGuidance, matchWrap())
            addView(Button(this@MainActivity).apply {
                text = "Advance debug state  →"
                textSize = 16f
                setTextColor(Color.BLACK)
                background = roundedBackground(color(R.color.accent), 14)
                setPadding(dp(16), dp(12), dp(16), dp(12))
                contentDescription = "Advance debug state"
                setOnClickListener {
                    controllerState = controllerState.next()
                    renderState()
                }
            }, matchWrap(top = 8))
            addView(Button(this@MainActivity).apply {
                text = "Scan host QR"
                contentDescription = "Scan host QR"
                setOnClickListener { scanHostQr() }
            }, matchWrap(top = 4))
        }))

        content.addView(panel(verticalLayout(12).apply {
            addView(label("⚒  DEBUG PANEL", 13, R.color.text_secondary, true))
            debugState = addDebugRow("State", "")
            addDebugRow("Device", "${Build.MANUFACTURER} ${Build.MODEL}")
            addDebugRow("System", "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            addDebugRow("Build", "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
            debugKeepAwake = addDebugRow("Keep awake", "")
            debugPairing = addDebugRow("Pairing", "Not paired")
            debugAssignment = addDebugRow("Assignment", "—")
            manualJoinUri = EditText(this@MainActivity).apply {
                hint = "Paste join URI"
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
                setSingleLine(true)
            }
            addView(manualJoinUri, matchWrap())
            addView(Button(this@MainActivity).apply {
                text = "Join pasted code"
                setOnClickListener { beginJoin(manualJoinUri.text.toString()) }
            }, matchWrap())
            addView(label("TEMPORARY UDP DESTINATION", 11, R.color.text_secondary, true))
            addView(horizontalLayout(8).apply {
                debugHost = EditText(this@MainActivity).apply {
                    setText("127.0.0.1")
                    hint = "Host"
                    inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
                    setSingleLine(true)
                }
                addView(debugHost, weighted())
                debugPort = EditText(this@MainActivity).apply {
                    setText("7000")
                    hint = "Port"
                    inputType = InputType.TYPE_CLASS_NUMBER
                    setSingleLine(true)
                }
                addView(debugPort, LinearLayout.LayoutParams(dp(92), ViewGroup.LayoutParams.WRAP_CONTENT))
            })
            debugSensor = addDebugRow("Sensor", "")
            debugRate = addDebugRow("Requested / actual", "")
            debugAccuracy = addDebugRow("Accuracy", "")
            debugQueue = addDebugRow("Queued", "")
            debugDropped = addDebugRow("Dropped local", "")
            debugNonMonotonic = addDebugRow("Non-monotonic", "")
            debugNetwork = addDebugRow("Network", "")
            debugSent = addDebugRow("Sent / rate", "")
            debugErrors = addDebugRow("Network errors", "")
            debugLastSend = addDebugRow("Last send", "")
            debugWifi = addDebugRow("Low-latency Wi-Fi", "")
        }))

        content.addView(verticalLayout(9).apply {
            addView(label("Permissions are requested only when needed", 15, R.color.text_primary, true))
            addView(label("▣  Camera — scan the host session QR code", 13, R.color.text_secondary))
            addView(label("≋  Motion — read swings during active play", 13, R.color.text_secondary))
            addView(label("⌁  Network — connect directly to the host", 13, R.color.text_secondary))
        })
        return scroll
    }

    private fun renderState() {
        stateTitle.text = controllerState.displayName.uppercase()
        stateGuidance.text = controllerState.guidance
        debugState.text = controllerState.displayName
        debugKeepAwake.text = if (controllerState.keepsScreenAwake) "Enabled" else "Disabled"
        applyKeepAwakePolicy()
        updateMotionRuntime()
        renderMotionDiagnostics()
    }

    private fun updateMotionRuntime() {
        if (!::motionSampler.isInitialized || !::debugHost.isInitialized) return
        val shouldSample = isForeground && controllerState.keepsScreenAwake
        val shouldStream = isForeground && controllerState == ControllerState.CONNECTED
        if (shouldSample && !sampling) {
            sampling = motionSampler.start()
        } else if (!shouldSample && sampling) {
            if (streaming) {
                motionStreamer.stop()
                streaming = false
            }
            motionSampler.stop(if (isForeground) "Inactive session" else "Background")
            sampling = false
        }
        if (shouldStream && !streaming) {
            streaming = motionStreamer.start(
                debugHost.text.toString(),
                debugPort.text.toString().toIntOrNull() ?: 7000,
            )
        } else if (!shouldStream && streaming) {
            motionStreamer.stop()
            streaming = false
        }
    }

    private fun scanHostQr() {
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .enableAutoZoom()
            .build()
        GmsBarcodeScanning.getClient(this, options).startScan()
            .addOnSuccessListener { barcode ->
                barcode.rawValue?.let(::beginJoin)
                    ?: showPairingError("The scanned QR code did not contain join data.")
            }
            .addOnFailureListener {
                showPairingError("QR scanning failed. Use manual code entry.")
            }
    }

    private fun beginJoin(rawValue: String) {
        val payload = try {
            JoinPayload.parse(rawValue)
        } catch (error: JoinPayload.ValidationException) {
            showPairingError(error.reason.userMessage)
            return
        }
        debugHost.setText(payload.host)
        debugPort.setText(payload.port.toString())
        controllerState = ControllerState.PAIRING
        debugPairing.text = "Contacting host"
        renderState()
        pairingClient.join(rawValue, onHostLost = { loss ->
            // Leaving Connected stops motion streaming to a silent host.
            if (loss == HostLoss.TIMED_OUT) {
                controllerState = ControllerState.PAIRING
                debugPairing.text = "Host not responding. Reconnecting"
                renderState()
            }
        }) { result ->
            when (result) {
                is PairingResult.Joined -> {
                    motionStreamer.configure(
                        result.assignment.sessionId,
                        result.assignment.controllerId,
                    )
                    debugPairing.text = "Player ${result.assignment.player} connected"
                    debugAssignment.text =
                        "P${result.assignment.player} / ${result.assignment.controllerId.toString(16)}"
                    paired = true
                    controllerState = ControllerState.CONNECTED
                    renderState()
                }
                is PairingResult.Failed -> showPairingError(result.message)
            }
        }
    }

    private fun showPairingError(message: String) {
        paired = false
        debugPairing.text = message
        controllerState = ControllerState.NOT_PAIRED
        renderState()
    }

    private fun stopMotion(reason: String) {
        if (streaming) motionStreamer.stop()
        if (sampling) motionSampler.stop(reason)
        streaming = false
        sampling = false
    }

    private fun renderMotionDiagnostics() {
        if (!::debugSensor.isInitialized) return
        val sensor = motionSampler.snapshot()
        val network = motionStreamer.snapshot()
        pairingClient.updateStatus(
            appActive = isForeground,
            sensorValid = sensor.status != "Unavailable" && sensor.status != "Registration failed",
            actualSampleHz = sensor.actualHz,
        )
        debugSensor.text = sensor.status
        debugRate.text = "${sensor.requestedHz} / ${sensor.actualHz} Hz"
        debugAccuracy.text = sensor.accuracy.toString()
        debugQueue.text = "${sensor.buffer.queued} / 256"
        debugDropped.text = sensor.buffer.droppedForCapacity.toString()
        debugNonMonotonic.text = sensor.buffer.rejectedNonMonotonic.toString()
        debugNetwork.text = network.status
        debugSent.text = "${network.sent} / ${network.sentHz} Hz"
        debugErrors.text = network.networkErrors.toString()
        debugLastSend.text = network.lastSuccessfulSendNanoseconds?.let {
            "${((System.nanoTime() - it).coerceAtLeast(0L)) / 1_000_000} ms ago"
        } ?: "Never"
        debugWifi.text = if (network.lowLatencyWifiHeld) "Held" else "Released"
    }

    private fun applyKeepAwakePolicy() {
        if (controllerState.keepsScreenAwake && hasWindowFocus()) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    private fun LinearLayout.addDebugRow(title: String, value: String): TextView {
        val result = label(value, 14, R.color.text_primary).apply {
            typeface = Typeface.MONOSPACE
            gravity = Gravity.END
        }
        addView(horizontalLayout(6).apply {
            addView(label(title, 14, R.color.text_secondary), weighted())
            // Long values (e.g. pairing errors) wrap within the row instead of
            // being measured wider than the screen and clipped.
            addView(result, weighted(DEBUG_VALUE_WEIGHT))
        })
        return result
    }

    private fun panel(child: View): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        background = roundedBackground(color(R.color.panel), 18)
        setPadding(dp(20), dp(20), dp(20), dp(20))
        addView(child, matchWrap())
        layoutParams = matchWrap(top = 20)
    }

    private fun label(text: String, size: Int, colorResource: Int, bold: Boolean = false) =
        TextView(this).apply {
            this.text = text
            textSize = size.toFloat()
            setTextColor(color(colorResource))
            if (bold) setTypeface(typeface, Typeface.BOLD)
        }

    private fun verticalLayout(spacingDp: Int) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        showDividers = LinearLayout.SHOW_DIVIDER_MIDDLE
        dividerDrawable = SpacingDrawable(dp(spacingDp), vertical = true)
    }

    private fun horizontalLayout(spacingDp: Int) = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        showDividers = LinearLayout.SHOW_DIVIDER_MIDDLE
        dividerDrawable = SpacingDrawable(dp(spacingDp), vertical = false)
    }

    private fun roundedBackground(backgroundColor: Int, radiusDp: Int) = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        color = android.content.res.ColorStateList.valueOf(backgroundColor)
        cornerRadius = dp(radiusDp).toFloat()
    }

    private fun color(resource: Int): Int = getColor(resource)
    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun matchWrap(top: Int = 0) = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT,
    ).apply { topMargin = dp(top) }

    private fun weighted(weight: Float = 1f) =
        LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, weight)
}

/** Debug value column gets twice the title column so messages wrap readably. */
private const val DEBUG_VALUE_WEIGHT = 2f

private class SpacingDrawable(
    private val spacing: Int,
    private val vertical: Boolean,
) : android.graphics.drawable.ColorDrawable(Color.TRANSPARENT) {
    override fun getIntrinsicHeight(): Int = if (vertical) spacing else 1
    override fun getIntrinsicWidth(): Int = if (vertical) 1 else spacing
}
