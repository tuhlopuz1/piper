package com.example.piper

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.NetworkInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class WifiDirectPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        const val P2P_PORT = 7788
    }

    private val manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager?
    private val p2pChannel: WifiP2pManager.Channel? =
        manager?.initialize(context, context.mainLooper, null)

    private var eventSink: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null

    // ── Flutter channels ──────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startDiscovery" -> startDiscovery(result)
            "stopDiscovery"  -> stopDiscovery(result)
            else             -> result.notImplemented()
        }
    }

    override fun onListen(args: Any?, sink: EventChannel.EventSink?) { eventSink = sink }
    override fun onCancel(args: Any?) { eventSink = null }

    // ── BroadcastReceiver lifecycle (called from MainActivity) ────────────────

    fun registerReceiver() {
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                when (intent.action) {
                    WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> onPeersChanged()
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        @Suppress("DEPRECATION")
                        val netInfo = intent.getParcelableExtra<NetworkInfo>(
                            WifiP2pManager.EXTRA_NETWORK_INFO
                        )
                        if (netInfo?.isConnected == true) {
                            onConnected()
                        }
                    }
                }
            }
        }
        context.registerReceiver(receiver, filter)
    }

    fun unregisterReceiver() {
        receiver?.let {
            try { context.unregisterReceiver(it) } catch (_: Exception) {}
        }
        receiver = null
    }

    // ── Discovery ─────────────────────────────────────────────────────────────

    private fun startDiscovery(result: MethodChannel.Result) {
        val mgr = manager ?: return result.success(null)
        val ch  = p2pChannel ?: return result.success(null)
        mgr.discoverPeers(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = result.success(null)
            // Non-fatal — WiFi Direct may be unsupported or disabled.
            override fun onFailure(reason: Int) = result.success(null)
        })
    }

    private fun stopDiscovery(result: MethodChannel.Result) {
        val mgr = manager ?: return result.success(null)
        val ch  = p2pChannel ?: return result.success(null)
        mgr.stopPeerDiscovery(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {}
            override fun onFailure(reason: Int) {}
        })
        mgr.removeGroup(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {}
            override fun onFailure(reason: Int) {}
        })
        result.success(null)
    }

    // ── P2P event handlers ────────────────────────────────────────────────────

    private fun onPeersChanged() {
        val mgr = manager ?: return
        val ch  = p2pChannel ?: return
        mgr.requestPeers(ch) { peerList ->
            peerList.deviceList.forEach { device ->
                // Attempt connection. groupOwnerIntent=0 → prefer to be client,
                // letting the other device be Group Owner so we can learn the IP.
                val config = WifiP2pConfig().apply {
                    deviceAddress = device.deviceAddress
                    groupOwnerIntent = 0
                }
                mgr.connect(ch, config, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {}
                    override fun onFailure(reason: Int) {}
                })
            }
        }
    }

    private fun onConnected() {
        val mgr = manager ?: return
        val ch  = p2pChannel ?: return
        mgr.requestConnectionInfo(ch) { info ->
            val ip = info?.groupOwnerAddress?.hostAddress ?: return@requestConnectionInfo
            val event = mapOf(
                "id"   to ip,
                "name" to "wifidirect",
                "ip"   to ip,
                "port" to P2P_PORT
            )
            eventSink?.success(event)
        }
    }
}
