package ai.clomni.messenger.core

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build

/**
 * Whether the device has a network, from the networks the system reports as they come and go: offline once the last
 * one is lost. Listeners hear only changes.
 */
internal class OfflineState(initiallyOffline: Boolean) {
    private val networks = HashSet<Any>()
    private val listeners = LinkedHashSet<(Boolean) -> Unit>()

    @Volatile
    var isOffline: Boolean = initiallyOffline
        private set

    @Synchronized
    fun available(network: Any) {
        networks += network
        update(false)
    }

    @Synchronized
    fun lost(network: Any) {
        networks -= network
        if (networks.isEmpty()) update(true)
    }

    @Synchronized
    fun addListener(listener: (Boolean) -> Unit) {
        listeners += listener
    }

    @Synchronized
    fun removeListener(listener: (Boolean) -> Unit) {
        listeners -= listener
    }

    private fun update(offline: Boolean) {
        if (offline == isOffline) return
        isOffline = offline
        listeners.toList().forEach { it(offline) }
    }
}

/**
 * Feeds [state] from the ConnectivityManager (ACCESS_NETWORK_STATE, declared by the SDK's manifest): the "İnternet
 * yoxdur" strip of the open messenger. Callbacks arrive on a system thread.
 */
internal class NetworkMonitor(context: Context) {
    private val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager?
    val state = OfflineState(initiallyOffline = runCatching { manager != null && manager.activeNetwork == null }.getOrDefault(false))

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = state.available(network)

        override fun onLost(network: Network) = state.lost(network)
    }

    init {
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                manager?.registerDefaultNetworkCallback(callback)
            } else {
                val request = NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build()
                manager?.registerNetworkCallback(request, callback)
            }
        }
    }
}
