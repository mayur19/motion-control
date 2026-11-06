package com.motionbadminton.controller.android.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import java.net.DatagramSocket

/**
 * Pins controller UDP sockets to the Wi-Fi network. The host is on the LAN, so a
 * socket that the OS routes over mobile data (for example while Wi-Fi is
 * reassociating) can never reach it and stays on that network after Wi-Fi
 * returns.
 */
class WifiNetwork(context: Context) {
    private val connectivity = context.applicationContext
        .getSystemService(ConnectivityManager::class.java)

    @Suppress("DEPRECATION") // allNetworks is the synchronous lookup available from API 29.
    fun current(): Network? = connectivity?.allNetworks?.firstOrNull { network ->
        connectivity.getNetworkCapabilities(network)
            ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
    }

    /** Binds the socket to Wi-Fi when available; returns false if it is not. */
    fun bind(socket: DatagramSocket): Boolean {
        val network = current() ?: return false
        return try {
            network.bindSocket(socket)
            true
        } catch (_: Exception) {
            false
        }
    }
}
