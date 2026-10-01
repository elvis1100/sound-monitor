package com.example.sound_level_monitor

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var recordings: RecordingBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = RecordingBridge(this)
        recordings = bridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "sound_monitor/recordings").setMethodCallHandler(bridge)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger,
            "sound_monitor/playback").setStreamHandler(bridge)
    }

    override fun onStop() {
        recordings?.pause()
        super.onStop()
    }

    override fun onDestroy() {
        recordings?.dispose()
        super.onDestroy()
    }

    @Deprecated("Activity result callback used for the document picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (recordings?.onActivityResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
