package com.example.piper

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onStart() {
        super.onStart()
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        multicastLock = wifi?.createMulticastLock("piper_mdns")?.also {
            it.setReferenceCounted(true)
            it.acquire()
        }
    }

    override fun onStop() {
        super.onStop()
        multicastLock?.release()
        multicastLock = null
    }
}
