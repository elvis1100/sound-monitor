package com.example.sound_level_monitor

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.content.ClipData
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Owns one foreground player. All file inputs are restricted to private recordings.
 * Export writes only to the URI picked by the user; sharing grants temporary read access.
 */
class RecordingBridge(private val activity: Activity) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    companion object { const val EXPORT_REQUEST = 7401 }
    private val handler = Handler(Looper.getMainLooper())
    private val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val audioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
    private val focusListener = AudioManager.OnAudioFocusChangeListener {
        if (it != AudioManager.AUDIOFOCUS_GAIN) pause()
    }
    private var focusRequest: AudioFocusRequest? = null
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) pause()
        }
    }
    init {
        ContextCompat.registerReceiver(activity, noisyReceiver,
            IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
            ContextCompat.RECEIVER_NOT_EXPORTED)
    }
    private var player: MediaPlayer? = null
    private var ready = false
    private var sink: EventChannel.EventSink? = null
    private var pendingLoad: MethodChannel.Result? = null
    private var exportResult: MethodChannel.Result? = null
    private var exportFile: File? = null
    private val tick = object : Runnable {
        override fun run() {
            emit()
            if (ready && player?.isPlaying == true) handler.postDelayed(this, 100)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    private fun ownedFile(path: String?): File {
        val root = File(activity.filesDir, "recordings").canonicalFile
        val file = File(path ?: "").canonicalFile
        require(file.path.startsWith(root.path + File.separator) &&
            file.extension.lowercase() == "wav" && file.isFile)
        return file
    }

    private fun snapshot(): Map<String, Any> = mapOf(
        "positionMs" to if (ready) (player?.currentPosition ?: 0) else 0,
        "durationMs" to if (ready) (player?.duration ?: 0) else 0,
        "playing" to (ready && player?.isPlaying == true)
    )

    private fun emit() {
        try { sink?.success(snapshot()) } catch (_: Exception) {
            sink?.success(mapOf("error" to "Could not play this recording."))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "open" -> {
                    val file = ownedFile(call.argument<String>("path"))
                    releasePlayer()
                    pendingLoad = result
                    val next = MediaPlayer()
                    player = next
                    next.setAudioAttributes(audioAttributes)
                    next.setOnPreparedListener {
                        if (player !== next) return@setOnPreparedListener
                        ready = true
                        pendingLoad?.success(snapshot())
                        pendingLoad = null
                        emit()
                    }
                    next.setOnCompletionListener {
                        emit()
                        handler.removeCallbacks(tick)
                        abandonFocus()
                    }
                    next.setOnSeekCompleteListener { emit() }
                    next.setOnErrorListener { _, _, _ ->
                        ready = false
                        pendingLoad?.error("playback_failed", "Could not play this recording.", null)
                        pendingLoad = null
                        handler.removeCallbacks(tick)
                        sink?.success(mapOf("error" to "Could not play this recording."))
                        true
                    }
                    next.setDataSource(file.path)
                    next.prepareAsync()
                }
                "play" -> {
                    check(ready)
                    check(requestFocus())
                    if (player!!.currentPosition >= player!!.duration) player!!.seekTo(0)
                    player!!.start()
                    handler.removeCallbacks(tick)
                    handler.post(tick)
                    result.success(snapshot())
                }
                "pause" -> {
                    pause()
                    result.success(snapshot())
                }
                "seek" -> {
                    check(ready)
                    val milliseconds = (call.argument<Number>("milliseconds")?.toInt() ?: 0)
                        .coerceIn(0, player!!.duration)
                    player!!.seekTo(milliseconds)
                    result.success(null)
                }
                "close" -> { releasePlayer(); result.success(null) }
                "export" -> {
                    check(exportResult == null)
                    val file = ownedFile(call.argument<String>("path"))
                    val title = safeName(call.argument<String>("title"))
                    exportResult = result
                    exportFile = file
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "audio/wav"
                        putExtra(Intent.EXTRA_TITLE, title)
                    }
                    activity.startActivityForResult(intent, EXPORT_REQUEST)
                }
                "share" -> {
                    val file = ownedFile(call.argument<String>("path"))
                    val uri = FileProvider.getUriForFile(activity,
                        activity.packageName + ".recordings", file,
                        safeName(call.argument<String>("title")))
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "audio/wav"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        putExtra(Intent.EXTRA_TITLE, call.argument<String>("title"))
                        clipData = ClipData.newRawUri("Audio recording", uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    activity.startActivity(Intent.createChooser(intent, "Share recording"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            if (pendingLoad === result) { pendingLoad = null; releasePlayer() }
            if (exportResult === result) { exportResult = null; exportFile = null }
            result.error("recording_action_failed", "Could not complete this recording action.", null)
        }
    }

    private fun safeName(title: String?): String {
        val cleaned = (title ?: "Recording")
            .map { if (it in "/\\:*?\"<>|" || it.isISOControl()) '_' else it }
            .joinToString("").trim().take(80).ifEmpty { "Recording" }
        return cleaned + ".wav"
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != EXPORT_REQUEST) return false
        val result = exportResult ?: return true
        val file = exportFile
        exportResult = null
        exportFile = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || file == null) {
            result.success(false)
            return true
        }
        Thread {
            try {
                activity.contentResolver.openOutputStream(uri, "wt").use { output ->
                    check(output != null)
                    file.inputStream().use { input -> input.copyTo(output) }
                }
                activity.runOnUiThread { result.success(true) }
            } catch (_: Exception) {
                try { activity.contentResolver.delete(uri, null, null) } catch (_: Exception) {}
                activity.runOnUiThread {
                    result.error("export_failed", "Could not save audio to that location.", null)
                }
            }
        }.start()
        return true
    }

    @Suppress("DEPRECATION")
    private fun requestFocus(): Boolean {
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = focusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(audioAttributes)
                .setOnAudioFocusChangeListener(focusListener, handler)
                .build().also { focusRequest = it }
            audioManager.requestAudioFocus(request)
        } else {
            audioManager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN)
        }
        return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    @Suppress("DEPRECATION")
    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            audioManager.abandonAudioFocus(focusListener)
        }
    }

    fun pause() {
        handler.removeCallbacks(tick)
        if (ready && player?.isPlaying == true) player?.pause()
        abandonFocus()
        emit()
    }

    private fun releasePlayer() {
        handler.removeCallbacks(tick)
        abandonFocus()
        pendingLoad?.error("playback_cancelled", "Recording closed.", null)
        pendingLoad = null
        ready = false
        player?.release()
        player = null
    }

    fun dispose() {
        try { activity.unregisterReceiver(noisyReceiver) } catch (_: Exception) {}
        releasePlayer()
        exportResult?.success(false)
        exportResult = null
        exportFile = null
        sink = null
    }
}
