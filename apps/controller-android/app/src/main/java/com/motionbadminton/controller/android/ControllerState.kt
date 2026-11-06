package com.motionbadminton.controller.android

enum class ControllerState(
    val displayName: String,
    val guidance: String,
    val keepsScreenAwake: Boolean,
) {
    NOT_PAIRED(
        "Not Paired",
        "Scan the host QR code to begin.",
        false,
    ),
    PAIRING(
        "Pairing",
        "Contacting the host and requesting a player slot.",
        false,
    ),
    CALIBRATION(
        "Calibration",
        "Hold the phone securely and follow the slow-swing guide.",
        true,
    ),
    CONNECTED(
        "Connected",
        "Controller is active. Keep the phone secured with a wrist strap.",
        true,
    ),
    PAUSED(
        "Paused",
        "Motion streaming is paused until the session resumes.",
        false,
    );

    fun next(): ControllerState = entries[(ordinal + 1) % entries.size]

    /** State after the activity returns to the foreground. A paired controller
     *  paused for background resumes Connected; the host re-syncs its clock. */
    fun resumed(paired: Boolean): ControllerState =
        if (this == PAUSED && paired) CONNECTED else this
}
