package com.example.piper

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.NetworkInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiP2pManager: WifiP2pManager? = null
    private var wifiP2pChannel: WifiP2pManager.Channel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var receiverRegistered = false
    private var receiver: BroadcastReceiver? = null

    private val wifiDirectMethodChannel = "piper/wifi_direct"
    private val wifiDirectEventChannel = "piper/wifi_direct/events"

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        multicastLock = wifi?.createMulticastLock("piper_mdns")?.also {
            it.setReferenceCounted(true)
            it.acquire()
        }
        wifiP2pManager = applicationContext.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        wifiP2pChannel = wifiP2pManager?.initialize(this, mainLooper, null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wifiDirectMethodChannel)
            .setMethodCallHandler(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, wifiDirectEventChannel)
            .setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                registerP2pReceiver()
                result.success(null)
            }
            "discover" -> {
                startDiscovery(result)
            }
            "connect" -> {
                val address = call.argument<String>("device_address")
                if (address.isNullOrEmpty()) {
                    result.error("bad_args", "device_address is required", null)
                    return
                }
                connectTo(address, result)
            }
            "disconnect" -> {
                disconnect(result)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun registerP2pReceiver() {
        if (receiverRegistered) return
        val manager = wifiP2pManager ?: return
        val channel = wifiP2pChannel ?: return
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                        requestPeers(manager, channel)
                    }
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        @Suppress("DEPRECATION")
                        val networkInfo = intent.getParcelableExtra<NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
                        if (networkInfo?.isConnected == true) {
                            manager.requestConnectionInfo(channel) { info ->
                                val ip = info?.groupOwnerAddress?.hostAddress ?: return@requestConnectionInfo
                                manager.requestGroupInfo(channel) { group ->
                                    val owner = group?.owner
                                    val deviceAddress = owner?.deviceAddress ?: "wfd-group-owner"
                                    val name = owner?.deviceName ?: "WiFiDirectPeer"
                                    // Go node now listens on a stable port; this endpoint is injected in Dart.
                                    publishEndpoint(peerId(deviceAddress), name, ip, 47822)
                                }
                            }
                        }
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        registerReceiver(receiver, filter)
        receiverRegistered = true
    }

    private fun startDiscovery(result: MethodChannel.Result) {
        val manager = wifiP2pManager ?: run {
            result.error("no_manager", "WifiP2pManager unavailable", null)
            return
        }
        val channel = wifiP2pChannel ?: run {
            result.error("no_channel", "WifiP2p channel unavailable", null)
            return
        }
        manager.discoverPeers(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = result.success(null)
            override fun onFailure(reason: Int) {
                result.error("discover_failed", "reason=$reason", null)
            }
        })
    }

    private fun connectTo(deviceAddress: String, result: MethodChannel.Result) {
        val manager = wifiP2pManager ?: run {
            result.error("no_manager", "WifiP2pManager unavailable", null)
            return
        }
        val channel = wifiP2pChannel ?: run {
            result.error("no_channel", "WifiP2p channel unavailable", null)
            return
        }
        val config = WifiP2pConfig().apply {
            this.deviceAddress = deviceAddress
        }
        manager.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = result.success(null)
            override fun onFailure(reason: Int) {
                result.error("connect_failed", "reason=$reason", null)
            }
        })
    }

    private fun disconnect(result: MethodChannel.Result) {
        val manager = wifiP2pManager ?: run {
            result.error("no_manager", "WifiP2pManager unavailable", null)
            return
        }
        val channel = wifiP2pChannel ?: run {
            result.error("no_channel", "WifiP2p channel unavailable", null)
            return
        }
        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = result.success(null)
            override fun onFailure(reason: Int) {
                result.error("disconnect_failed", "reason=$reason", null)
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun requestPeers(manager: WifiP2pManager, channel: WifiP2pManager.Channel) {
        manager.requestPeers(channel) { peers ->
            peers?.deviceList?.forEach { device ->
                publishDiscoveredDevice(device)
            }
        }
    }

    private fun publishDiscoveredDevice(device: WifiP2pDevice) {
        // IP will be published once connected via connection info callback.
        publishEndpoint(peerId(device.deviceAddress), device.deviceName ?: "WiFiDirect", "", 0)
    }

    private fun publishEndpoint(peerId: String, name: String, ip: String, port: Int) {
        val sink = eventSink ?: return
        sink.success(
            mapOf(
                "peer_id" to peerId,
                "name" to name,
                "ip" to ip,
                "port" to port
            )
        )
    }

    private fun peerId(deviceAddress: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(deviceAddress.toByteArray(Charsets.UTF_8))
        return digest.take(16).joinToString("") { "%02x".format(it) }
    }

    override fun onDestroy() {
        if (receiverRegistered && receiver != null) {
            unregisterReceiver(receiver)
            receiverRegistered = false
            receiver = null
        }
        multicastLock?.let {
            if (it.isHeld) it.release()
        }
        multicastLock = null
        super.onDestroy()
    }
}
