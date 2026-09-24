package org.krak_en.voice

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.os.Handler
import android.os.Looper
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.core.app.ActivityCompat
import android.media.MediaRecorder
import java.io.File
import android.content.Intent
import android.os.Build
import android.os.PowerManager

class MainActivity: FlutterFragmentActivity() {

    override fun onDestroy() {
        // Force-stop the recording service when the activity is destroyed
        // (e.g. user swiped the app from recents). This prevents the
        // foreground notification from running forever as an orphan.
        if (KrakenRecordingService.isRecordingActive) {
            val intent = Intent(this, KrakenRecordingService::class.java).apply {
                action = KrakenRecordingService.ACTION_STOP
            }
            try { startService(intent) } catch (_: Exception) {}
        }
        if (::inferenceBridge.isInitialized) inferenceBridge.close()
        super.onDestroy()
    }
    private val INFERENCE_CHANNEL = "kraken.kernel/inference"
    private val INFERENCE_STREAM_CHANNEL = "kraken.kernel/inference/stream"
    private val AUDIO_CHANNEL = "kraken.kernel/audio"
    private val AUDIO_DEVICES_CHANNEL = "kraken.kernel/audio/devices"
    private val AUDIO_DEVICES_HOTPLUG_CHANNEL = "kraken.kernel/audio/devices/hotplug"

    private lateinit var inferenceBridge: InferenceBridge

    private var mediaRecorder: MediaRecorder? = null
    private var audioFilePath: String? = null
    private var pendingStartRecordingResult: MethodChannel.Result? = null
    private var pendingSilenceDetectionResult: MethodChannel.Result? = null
    private val RECORD_AUDIO_REQUEST_CODE = 1001

    private var isRecording = false
    private val SILENCE_THRESHOLD = 2000
    private val SILENCE_DURATION_MS = 1500L
    private var detectSilenceFlag = false
    private var silenceStartTime: Long = 0L

    // Audio device handler for mic enumeration and selection
    private lateinit var audioDeviceHandler: AudioDeviceHandler

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == RECORD_AUDIO_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                startAudioRecording(pendingStartRecordingResult)
            } else {
                pendingStartRecordingResult?.error("PERMISSION_DENIED", "Microphone permission denied", null)
            }
            pendingStartRecordingResult = null
        }
    }

    private fun startAudioRecording(result: MethodChannel.Result?) {
        try {
            // Matches path_provider's application documents directory on Android.
            val recordingsDir = File(getDir("flutter", MODE_PRIVATE), "recordings")
            check(recordingsDir.isDirectory || recordingsDir.mkdirs()) {
                "Could not create the recordings directory"
            }
            audioFilePath = File(recordingsDir, "audio_${System.currentTimeMillis()}.m4a").absolutePath
            
            val intent = Intent(this, KrakenRecordingService::class.java).apply {
                action = KrakenRecordingService.ACTION_START
                putExtra(KrakenRecordingService.EXTRA_FILE_PATH, audioFilePath)
                // Pass the selected device ID so the service can use setPreferredDevice
                audioDeviceHandler.getSelectedDeviceId()?.let {
                    putExtra(KrakenRecordingService.EXTRA_DEVICE_ID, it)
                }
            }
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            
            isRecording = true
            
            if (detectSilenceFlag && result != null) {
                pendingSilenceDetectionResult = result
                // silenceStartTime will be reset in amplitudeListener once we get above threshold
            } else {
                result?.success(audioFilePath)
            }
        } catch (e: Exception) {
            result?.error("RECORDING_FAILED", e.message, null)
        }
    }

    private fun stopAudioRecording(result: MethodChannel.Result?) {
        val wasRecording = isRecording
        isRecording = false
        try {
            // Always send stop to the service — handles orphaned services
            // from previous sessions where isRecording might be false here.
            val intent = Intent(this, KrakenRecordingService::class.java).apply {
                action = KrakenRecordingService.ACTION_STOP
            }
            startService(intent)
            
            // Fulfill the silence detection pending result
            pendingSilenceDetectionResult?.success(audioFilePath)
            pendingSilenceDetectionResult = null
            
            // Fulfill explicit stop request
            result?.success(audioFilePath)
        } catch (e: Exception) {
            pendingSilenceDetectionResult?.error("STOP_FAILED", e.message, null)
            pendingSilenceDetectionResult = null
            result?.error("STOP_FAILED", e.message, null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Cleanup any orphaned recording service from a previous session
        // (e.g. hot-reload or crash left the service running).
        if (KrakenRecordingService.isRecordingActive) {
            android.util.Log.w("KrakenMain", "Orphaned recording service detected — stopping.")
            val cleanupIntent = Intent(this, KrakenRecordingService::class.java).apply {
                action = KrakenRecordingService.ACTION_STOP
            }
            try { startService(cleanupIntent) } catch (_: Exception) {}
        }

        // Setup Audio Device Handler (mic enumeration & selection)
        audioDeviceHandler = AudioDeviceHandler(this)
        audioDeviceHandler.setupChannels(
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_DEVICES_CHANNEL),
            EventChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_DEVICES_HOTPLUG_CHANNEL)
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kraken.kernel/documents")
            .setMethodCallHandler(DocumentTextHandler()::handle)

        inferenceBridge = InferenceBridgeFactory.create(applicationContext)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, INFERENCE_STREAM_CHANNEL)
            .setStreamHandler(inferenceBridge)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INFERENCE_CHANNEL)
            .setMethodCallHandler(inferenceBridge::handle)

        // Setup Audio Amplitude EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "kraken.kernel/audio/amplitude").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    KrakenRecordingService.amplitudeListener = { amplitude ->
                        events?.success(amplitude)
                        
                        // Handle silence detection if enabled
                        if (detectSilenceFlag && isRecording) {
                            if (amplitude > SILENCE_THRESHOLD) {
                                // silenceStartTime is tracked via a field now, let's just make it a var in the class
                                silenceStartTime = 0L
                            } else {
                                if (silenceStartTime == 0L) {
                                    silenceStartTime = System.currentTimeMillis()
                                } else if (System.currentTimeMillis() - silenceStartTime > SILENCE_DURATION_MS) {
                                    // Silence detected! We must run this on the main thread
                                    Handler(Looper.getMainLooper()).post {
                                        stopAudioRecording(null)
                                    }
                                }
                            }
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    KrakenRecordingService.amplitudeListener = null
                }
            }
        )

        // Setup Audio MethodChannel
        val audioChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
        
        // Wire notification callbacks from the service back to Flutter
        KrakenRecordingService.onNotificationStop = {
            Handler(Looper.getMainLooper()).post {
                audioChannel.invokeMethod("onNotificationStop", null)
            }
        }
        KrakenRecordingService.onNotificationPause = {
            Handler(Looper.getMainLooper()).post {
                audioChannel.invokeMethod("onNotificationPause", null)
            }
        }

        audioChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> {
                    detectSilenceFlag = call.argument<Boolean>("detectSilence") ?: false
                    silenceStartTime = 0L
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        pendingStartRecordingResult = result
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), RECORD_AUDIO_REQUEST_CODE)
                    } else {
                        startAudioRecording(result)
                    }
                }
                "pauseRecording" -> {
                    val intent = Intent(this, KrakenRecordingService::class.java).apply {
                        action = KrakenRecordingService.ACTION_PAUSE
                    }
                    startService(intent)
                    result.success(null)
                }
                "resumeRecording" -> {
                    val intent = Intent(this, KrakenRecordingService::class.java).apply {
                        action = KrakenRecordingService.ACTION_RESUME
                    }
                    startService(intent)
                    result.success(null)
                }
                "stopRecording" -> {
                    stopAudioRecording(result)
                }
                "transcribe" -> {
                    val path = call.argument<String>("path")
                    // TODO: Replace with actual Whisper ONNX inference once the model is integrated.
                    // For now, simulate a transcription delay and return a placeholder result.
                    Handler(Looper.getMainLooper()).postDelayed({
                        result.success("[Whisper engine pending integration] Audio recorded successfully at: ${path ?: "unknown path"}. Real transcription will replace this placeholder once the Whisper ONNX model is wired into the native layer.")
                    }, 1500)
                }
                "getDuration" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        try {
                            val retriever = android.media.MediaMetadataRetriever()
                            retriever.setDataSource(path)
                            val time = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                            retriever.release()
                            val durationMs = time?.toLong() ?: 0L
                            result.success(durationMs)
                        } catch (e: Exception) {
                            result.success(0L)
                        }
                    } else {
                        result.success(0L)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Setup Wake Lock / Download MethodChannel.
        // The Gemma download now runs NATIVELY inside KrakenDownloadService,
        // completely independent of the Flutter Dart engine lifecycle.
        val downloadChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kraken.kernel/wakelock")

        // Wire native download callbacks back to Flutter
        KrakenDownloadService.onProgress = { progress, sizeStr ->
            Handler(Looper.getMainLooper()).post {
                downloadChannel.invokeMethod("onDownloadProgress", mapOf(
                    "progress" to progress,
                    "sizeStr" to sizeStr
                ))
            }
        }
        KrakenDownloadService.onComplete = {
            Handler(Looper.getMainLooper()).post {
                downloadChannel.invokeMethod("onDownloadComplete", null)
            }
        }
        KrakenDownloadService.onError = { errorMsg ->
            Handler(Looper.getMainLooper()).post {
                downloadChannel.invokeMethod("onDownloadError", mapOf(
                    "error" to errorMsg
                ))
            }
        }

        downloadChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    try {
                        val intent = Intent(this, KrakenDownloadService::class.java).apply {
                            action = KrakenDownloadService.ACTION_START
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("WAKELOCK_ERROR", e.message, null)
                    }
                }
                "startNativeDownload" -> {
                    try {
                        val url = call.argument<String>("url") ?: ""
                        val outputPath = call.argument<String>("outputPath") ?: ""
                        val intent = Intent(this, KrakenDownloadService::class.java).apply {
                            action = KrakenDownloadService.ACTION_START_NATIVE_DOWNLOAD
                            putExtra(KrakenDownloadService.EXTRA_DOWNLOAD_URL, url)
                            putExtra(KrakenDownloadService.EXTRA_OUTPUT_PATH, outputPath)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("DOWNLOAD_ERROR", e.message, null)
                    }
                }
                "release" -> {
                    try {
                        val intent = Intent(this, KrakenDownloadService::class.java).apply {
                            action = KrakenDownloadService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("WAKELOCK_ERROR", e.message, null)
                    }
                }
                "updateProgress" -> {
                    try {
                        val text = call.argument<String>("text") ?: "Downloading…"
                        val intent = Intent(this, KrakenDownloadService::class.java).apply {
                            action = KrakenDownloadService.ACTION_UPDATE_PROGRESS
                            putExtra(KrakenDownloadService.EXTRA_PROGRESS_TEXT, text)
                        }
                        startService(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("WAKELOCK_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
