package com.kraken.hub.kraken_hub

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Message
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.core.app.ActivityCompat
import android.media.MediaRecorder
import java.io.File
import android.content.Intent

class MainActivity: FlutterFragmentActivity() {
    private val INFERENCE_CHANNEL = "kraken.kernel/inference"
    private val INFERENCE_STREAM_CHANNEL = "kraken.kernel/inference/stream"
    private val AUDIO_CHANNEL = "kraken.kernel/audio"

    private var eventSink: EventChannel.EventSink? = null
    private var isGenerating = false
    private var engine: Engine? = null
    private var conversation: Conversation? = null

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
            audioFilePath = "${cacheDir.absolutePath}/temp_audio_${System.currentTimeMillis()}.m4a"
            
            val intent = Intent(this, KrakenRecordingService::class.java).apply {
                action = KrakenRecordingService.ACTION_START
                putExtra(KrakenRecordingService.EXTRA_FILE_PATH, audioFilePath)
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
        if (!isRecording) {
            result?.success(audioFilePath)
            return
        }
        isRecording = false
        try {
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

        // Setup Inference Stream EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, INFERENCE_STREAM_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    isGenerating = false
                }
            }
        )

        // Setup Inference MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INFERENCE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "loadModel" -> {
                    val defaultPath = "${applicationContext.filesDir.parentFile?.path}/app_flutter/gemma4.litertlm"
                    val modelPath = call.argument<String>("modelPath") ?: defaultPath
                    
                    // Initialization can be heavy, run on background thread
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val engineConfig = EngineConfig(
                                modelPath = modelPath,
                                backend = Backend.CPU() // Default to CPU for broad compatibility
                            )
                            engine = Engine(engineConfig)
                            engine?.initialize()
                            conversation = engine?.createConversation()
                            
                            withContext(Dispatchers.Main) {
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("MODEL_LOAD_FAILED", "Failed to load LiteRT model from $modelPath: ${e.message}", null)
                            }
                        }
                    }
                }
                "unloadModel" -> {
                    conversation?.close()
                    conversation = null
                    engine?.close()
                    engine = null
                    result.success(null)
                }
                "generate" -> {
                    val prompt = call.argument<String>("prompt") ?: ""
                    isGenerating = true
                    result.success(null)

                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val conv = conversation
                            if (conv != null) {
                                val responseFlow = conv.sendMessageAsync(Message.user(prompt))
                                responseFlow.collect { message ->
                                    if (!isGenerating || eventSink == null) return@collect
                                    
                                    // Extract text from the Message object robustly
                                    var chunkText = ""
                                    try {
                                        // Try direct property access via reflection
                                        val textGetter = message.javaClass.methods.firstOrNull { 
                                            it.name == "getText" && it.parameterCount == 0 
                                        }
                                        if (textGetter != null) {
                                            chunkText = (textGetter.invoke(message) as? String) ?: ""
                                        }
                                    } catch (_: Exception) {}
                                    
                                    // Fallback: parse toString() and clean it up
                                    if (chunkText.isEmpty()) {
                                        val raw = message.toString()
                                        // Strip Kotlin wrapper like "Message(text=..., role=...)" 
                                        val textMatch = Regex("""text=([^,)]+)""").find(raw)
                                        chunkText = textMatch?.groupValues?.getOrNull(1)?.trim() ?: raw
                                        // Clean any remaining wrapper artifacts
                                        chunkText = chunkText.removePrefix("Message(").removeSuffix(")")
                                    }
                                    
                                    if (chunkText.isNotEmpty()) {
                                        withContext(Dispatchers.Main) {
                                            val eventMap = mapOf(
                                                "text" to chunkText,
                                                "isDone" to false
                                            )
                                            eventSink?.success(eventMap)
                                        }
                                    }
                                }
                                
                                // Send done event after flow completes
                                withContext(Dispatchers.Main) {
                                    if (isGenerating && eventSink != null) {
                                        val doneMap = mapOf(
                                            "text" to "",
                                            "isDone" to true
                                        )
                                        eventSink?.success(doneMap)
                                        eventSink?.endOfStream()
                                        isGenerating = false
                                    }
                                }
                            } else {
                                // Fallback to a mock JSON stream if the real Gemma model isn't loaded
                                val mockJson = """
                                {
                                  "summary": "This is a simulated executive summary. It appears the actual Gemma LiteRT model could not be loaded on this device (likely because it hasn't been sideloaded yet). The team discussed the completion of Handoff 2B, focusing on the audio import pipeline and the new streaming AI interface.",
                                  "action_items": [
                                    "Download the actual Gemma model to the device.",
                                    "Verify the model path in LocalInferenceService.",
                                    "Test the pipeline with a real inference session."
                                  ]
                                }
                                """.trimIndent()

                                // Stream it character by character to simulate LLM thinking
                                for (char in mockJson) {
                                    if (!isGenerating || eventSink == null) return@launch
                                    withContext(Dispatchers.Main) {
                                        val eventMap = mapOf(
                                            "text" to char.toString(),
                                            "isDone" to false
                                        )
                                        eventSink?.success(eventMap)
                                    }
                                    kotlinx.coroutines.delay(15) // Adjust delay for realism
                                }

                                withContext(Dispatchers.Main) {
                                    if (isGenerating && eventSink != null) {
                                        val doneMap = mapOf("text" to "", "isDone" to true)
                                        eventSink?.success(doneMap)
                                        eventSink?.endOfStream()
                                        isGenerating = false
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            isGenerating = false
                            withContext(Dispatchers.Main) {
                                eventSink?.error("GENERATE_FAILED", e.message, null)
                            }
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

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
                    Handler(Looper.getMainLooper()).postDelayed({
                        result.success("Stubbed Whisper transcription for the recorded audio.")
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
    }
}
