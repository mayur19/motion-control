package com.motionbadminton.controller.android.pairing

/**
 * The launcher activity is exported, so any installed app can start it with
 * extras. A `join_uri` extra would make the controller join a host chosen by
 * that app and stream motion to it without the user scanning a code. It exists
 * only for debug automation, so release builds ignore it.
 */
object LaunchJoin {
    const val EXTRA_JOIN_URI = "join_uri"

    fun acceptedUri(extra: String?, debugBuild: Boolean): String? =
        extra?.takeIf { debugBuild && it.isNotBlank() }
}
