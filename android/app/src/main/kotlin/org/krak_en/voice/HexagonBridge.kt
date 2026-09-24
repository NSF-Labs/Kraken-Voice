package org.krak_en.voice

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/** Owns the model on one worker; cancellation never frees memory in use. */
class HexagonBridge(private val context: Context) : InferenceBridge {
    private val main = Handler(Looper.getMainLooper())
    private val generation = AtomicLong()
    private var sink: EventChannel.EventSink? = null
    private var loadedPath: String? = null // worker thread only
    @Volatile private var busy = false
    @Volatile private var closed = false
    private var activeGeneration = 0L
    private var activeSink: EventChannel.EventSink? = null

    private external fun nativeLoad(path: ByteArray, libraries: ByteArray)
    private external fun nativeUnload()
    private external fun nativeGenerate(prompt: ByteArray, limit: Int, autoContinue: Boolean)
    private external fun nativeCount(prompt: ByteArray): Int
    private external fun nativeCancel()
    private external fun nativeResetCancel()

    fun onBytes(bytes: ByteArray) {
        val text = bytes.toString(Charsets.UTF_8)
        val id = activeGeneration
        val target = activeSink
        main.post { if (generation.get() == id && !closed) target?.success(mapOf("text" to text, "isDone" to false)) }
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { cancel(); sink = null }
    private fun cancel() {
        generation.incrementAndGet()
        if (nativeLoaded) nativeCancel()
    }
    override fun close() {
        closed = true
        cancel()
        worker.execute { if (nativeLoaded) nativeUnload(); loadedPath = null }
    }
    private fun ensureNative() {
        if (!nativeLoaded) { System.loadLibrary("kraken_npu"); nativeLoaded = true }
    }
    override fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "deviceSupport") {
            result.success(mapOf(
                "supported" to ReleaseHardware.isSupported(),
                "soc" to if (android.os.Build.VERSION.SDK_INT >= 31) android.os.Build.SOC_MODEL else "unknown",
                "backend" to "NPU", "profile" to "gemma4-hexagon-v81",
                "modelFilename" to "gemma4-e2b-w4.gguf",
                "contextWindow" to 4096, "build" to "1.0.14-npu-sm8850+14"
            )); return
        }
        if (!ReleaseHardware.isSupported()) {
            result.error("UNSUPPORTED_DEVICE", "This NPU build supports only Samsung SM-S948U with SM8850.", null); return
        }
        if (closed) { result.error("ENGINE_CLOSED", "Inference engine is closed", null); return }
        when (call.method) {
            "loadModel" -> {
                val path = call.argument<String>("modelPath")
                if (path == null) { result.error("MODEL_PATH_REQUIRED", "Model path required", null); return }
                worker.execute {
                    try {
                        if (loadedPath != path) {
                            val file = File(path)
                            check(file.isFile && file.canRead()) { "The NPU model is missing or unreadable: ${file.name}. Download the AI model in Settings." }
                            check(file.length() == MODEL_BYTES) { "Wrong or incomplete NPU model: ${file.name} (${file.length()} bytes; expected $MODEL_BYTES). Download the AI model in Settings." }
                            val digest = MessageDigest.getInstance("SHA-256")
                            file.inputStream().buffered().use { input ->
                                val buffer = ByteArray(1024 * 1024)
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    digest.update(buffer, 0, count)
                                }
                            }
                            check(digest.digest().joinToString("") { "%02x".format(it) } == MODEL_SHA) {
                                "Model checksum failed. Delete and download the model again."
                            }
                            ensureNative()
                            loadedPath = null
                            nativeLoad(path.toByteArray(), context.applicationInfo.nativeLibraryDir.toByteArray())
                            loadedPath = path
                        }
                        main.post { result.success(null) }
                    } catch (e: Throwable) {
                        main.post { result.error("MODEL_LOAD_FAILED", e.message, null) }
                    }
                }
            }
            "cancelGeneration" -> {
                cancel()
                worker.execute { main.post { result.success(null) } }
            }
            "unloadModel" -> {
                cancel()
                worker.execute {
                    if (nativeLoaded) nativeUnload()
                    loadedPath = null
                    main.post { result.success(null) }
                }
            }
            "countTokens" -> {
                val prompt = call.argument<String>("prompt") ?: ""
                worker.execute {
                    try {
                        check(loadedPath != null) { "Load the model before counting tokens" }
                        val count = nativeCount(prompt.toByteArray())
                        main.post { result.success(count) }
                    } catch (e: Throwable) { main.post { result.error("TOKEN_COUNT_FAILED", e.message, null) } }
                }
            }
            "generate" -> {
                if (busy) { result.error("INFERENCE_BUSY", "Another response is finishing", null); return }
                val target = sink
                if (target == null) { result.error("STREAM_REQUIRED", "Attach the response stream first", null); return }
                val prompt = call.argument<String>("prompt") ?: ""
                val limit = (call.argument<Int>("maxTokens") ?: 1024).coerceIn(1, 2048)
                val autoContinue = call.argument<Boolean>("autoContinue") ?: false
                busy = true
                val id = generation.incrementAndGet()
                result.success(null)
                worker.execute {
                    try {
                        check(loadedPath != null) { "Load the NPU model before generating" }
                        if (generation.get() == id && !closed) {
                            activeGeneration = id; activeSink = target
                            nativeResetCancel()
                            // Cancellation may have arrived between the generation check and reset.
                            if (generation.get() != id) nativeCancel()
                            nativeGenerate(prompt.trim().toByteArray(), limit, autoContinue)
                            main.post { if (generation.get() == id && !closed) {
                                target.success(mapOf("text" to "", "isDone" to true)); target.endOfStream()
                            } }
                        }
                    } catch (e: Throwable) {
                        main.post { if (generation.get() == id && !closed) {
                            target.error("GENERATE_FAILED", e.message, null); target.endOfStream()
                        } }
                    } finally { busy = false; activeSink = null }
                }
            }
            else -> result.notImplemented()
        }
    }
    companion object {
        private val worker = Executors.newSingleThreadExecutor()
        @Volatile private var nativeLoaded = false
        const val MODEL_BYTES = 2620370976L
        const val MODEL_SHA = "e531007218dfab990486a5de7676a6932d6ea8dea233d1f698d7c21cf8a16889"
    }
}
