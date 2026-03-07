package com.example.piper

import android.Manifest
import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiDirectPlugin: WifiDirectPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = WifiDirectPlugin(this)
        wifiDirectPlugin = plugin
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "piper/wifidirect"
        ).setMethodCallHandler(plugin)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "piper/wifidirect/events"
        ).setStreamHandler(plugin)
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        // Acquire multicast lock so Go's mDNS can join multicast groups.
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        multicastLock = wifi?.createMulticastLock("piper_mdns")?.also {
            it.setReferenceCounted(true)
            it.acquire()
        }

        // Request the permission required for WiFi Direct peer scan.
        val perms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        ActivityCompat.requestPermissions(this, perms, REQUEST_WIFI_DIRECT)
    }

    override fun onResume() {
        super.onResume()
        wifiDirectPlugin?.registerReceiver()
    }

    override fun onPause() {
        super.onPause()
        wifiDirectPlugin?.unregisterReceiver()
    }

    override fun onDestroy() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
        super.onDestroy()
    }

    companion object {
        private const val REQUEST_WIFI_DIRECT = 1
    }
}
