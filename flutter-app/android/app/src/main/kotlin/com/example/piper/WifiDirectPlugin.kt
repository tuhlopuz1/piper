package com.example.piper

import android.content.Context
import android.net.wifi.p2p.WifiP2pManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class WifiDirectPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private val manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager?
    private var eventSink: EventChannel.EventSink? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startDiscovery" -> startDiscovery(result)
            "stopDiscovery"  -> stopDiscovery(result)
            else             -> result.notImplemented()
        }
    }

    override fun onListen(args: Any?, sink: EventChannel.EventSink?) { eventSink = sink }
    override fun onCancel(args: Any?) { eventSink = null }

    private fun startDiscovery(result: MethodChannel.Result) {
        // WifiP2pManager.discoverPeers — full implementation in Phase 6
        result.success(null)
    }

    private fun stopDiscovery(result: MethodChannel.Result) {
        result.success(null)
    }
}
