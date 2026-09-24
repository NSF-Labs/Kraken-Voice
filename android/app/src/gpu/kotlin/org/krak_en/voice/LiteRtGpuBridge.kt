package org.krak_en.voice

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.ai.edge.litertlm.*
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/** S24 evaluation profile. GPU is mandatory; no CPU fallback is constructed. */
@OptIn(ExperimentalApi::class)
class LiteRtGpuBridge(private val context: Context) : InferenceBridge {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val generation = AtomicLong()
    private val conversationLock = Any()
    private var active: Conversation? = null // guarded for cancellation vs close
    private var engine: Engine? = null // worker only
    private var loadedPath: String? = null
    private var sink: EventChannel.EventSink? = null
    @Volatile private var busy = false
    @Volatile private var closed = false

    private fun supported() = ReleaseHardware.isSupported(ReleaseHardware.Profile.GPU)
    // Kotlin 0.17.1 exposes no tokenizer. UTF-8 bytes conservatively bound the
    // byte-fallback tokenizer, plus room for the single-user chat template.
    private fun inputBudget(prompt: String) = prompt.toByteArray(Charsets.UTF_8).size + 128
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { cancel(); sink = null }
    private fun cancel() {
        generation.incrementAndGet()
        synchronized(conversationLock) { active?.cancelProcess() }
    }
    override fun close() {
        closed = true
        cancel()
        worker.execute { engine?.close(); engine = null; loadedPath = null }
        worker.shutdown()
    }
    override fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "deviceSupport") {
            result.success(mapOf("supported" to supported(), "soc" to Build.SOC_MODEL,
                "backend" to "GPU", "profile" to "gemma4-litert171-adreno750",
                "modelFilename" to "gemma4-e2b-gpu.litertlm", "contextWindow" to 4096,
                "build" to "1.0.15-gpu-sm8650+15", "tokenBudget" to "utf8-upper-bound"))
            return
        }
        if (closed) { result.error("ENGINE_CLOSED", "Inference engine is closed", null); return }
        if (!supported()) { result.error("UNSUPPORTED_DEVICE", "This GPU build supports only Samsung SM-S928U with SM8650.", null); return }
        when (call.method) {
            "loadModel" -> {
                val path = call.argument<String>("modelPath")
                if (path == null) { result.error("MODEL_PATH_REQUIRED", "Model path required", null); return }
                worker.execute {
                    try {
                        if (loadedPath != path) {
                            val file = File(path)
                            check(file.isFile && file.length() == MODEL_BYTES) { "Missing or incomplete GPU model. Download the GPU model in Settings." }
                            val digest = MessageDigest.getInstance("SHA-256")
                            file.inputStream().buffered().use { input ->
                                val buffer = ByteArray(1024 * 1024)
                                while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
                            }
                            check(digest.digest().joinToString("") { "%02x".format(it) } == MODEL_SHA) { "GPU model checksum failed. Download the model again." }
                            engine?.close(); engine = null; loadedPath = null
                            Engine.setNativeMinLogSeverity(LogSeverity.INFO)
                            ExperimentalFlags.enableBenchmark = true
                            // Establish a baseline before enabling speculative decoding.
                            ExperimentalFlags.enableSpeculativeDecoding = false
                            val next = Engine(EngineConfig(modelPath = path, backend = Backend.GPU(),
                                maxNumTokens = 4096, cacheDir = File(context.cacheDir, "litert171_gpu").apply { mkdirs() }.path))
                            try { next.initialize() } catch (e: Throwable) {
                                if (next.isInitialized()) next.close()
                                throw e
                            }
                            engine = next; loadedPath = path
                            Log.i(TAG, "READY runtime=LiteRT-LM-0.17.1 backend=GPU soc=${Build.SOC_MODEL} context=4096 no_cpu_fallback")
                        }
                        main.post { result.success(null) }
                    } catch (e: Throwable) { main.post { result.error("MODEL_LOAD_FAILED", e.message, null) } }
                }
            }
            "countTokens" -> result.success(inputBudget(call.argument<String>("prompt") ?: ""))
            "cancelGeneration", "unloadModel" -> {
                cancel()
                worker.execute {
                    try {
                        if (call.method == "unloadModel") { engine?.close(); engine = null; loadedPath = null }
                        main.post { result.success(null) }
                    } catch (e: Throwable) { main.post { result.error("ENGINE_ERROR", e.message, null) } }
                }
            }
            "generate" -> {
                if (busy) { result.error("INFERENCE_BUSY", "Another response is finishing", null); return }
                val target = sink
                if (target == null) { result.error("STREAM_REQUIRED", "Attach the response stream first", null); return }
                val prompt = call.argument<String>("prompt") ?: ""
                val requested = (call.argument<Int>("maxTokens") ?: 1024).coerceIn(1, 2048)
                val autoContinue = call.argument<Boolean>("autoContinue") ?: false
                val budget = inputBudget(prompt)
                if (budget + requested > 4096) {
                    result.error("CONTEXT_LIMIT", "Source and output exceed the GPU context budget. Split or condense the source.", null); return
                }
                val limit = if (autoContinue) 4096 - budget else requested
                val id = generation.incrementAndGet()
                busy = true
                result.success(null)
                worker.execute {
                    var conversation: Conversation? = null
                    var failure: Throwable? = null
                    try {
                        if (generation.get() == id && !closed) {
                            val loaded = checkNotNull(engine) { "Load the GPU model before generating" }
                            conversation = loaded.createConversation(ConversationConfig(
                                samplerConfig = SamplerConfig(topK = 1, topP = 1.0, temperature = 0.0),
                                thinkingConfig = ThinkingConfig(enableThinking = false), maxOutputToken = limit))
                            val done = CountDownLatch(1)
                            synchronized(conversationLock) {
                                active = conversation
                                if (generation.get() == id && !closed) {
                                    conversation.sendMessageAsync(prompt, object : MessageCallback {
                                        override fun onMessage(message: Message) {
                                            val text = message.contents.contents.filterIsInstance<Content.Text>().joinToString("") { it.text }
                                            if (text.isNotEmpty()) main.post {
                                                if (generation.get() == id && !closed) target.success(mapOf("text" to text, "isDone" to false))
                                            }
                                        }
                                        override fun onDone() { done.countDown() }
                                        override fun onError(throwable: Throwable) { failure = throwable; done.countDown() }
                                    })
                                } else done.countDown()
                            }
                            done.await() // close/unload only after the native callback completes
                            failure?.let { throw it }
                            if (generation.get() == id && !closed) {
                                val metrics = conversation.getBenchmarkInfo()
                                Log.i(TAG, "DONE prefill=${metrics.lastPrefillTokenCount} decode=${metrics.lastDecodeTokenCount} decode_tps=${metrics.lastDecodeTokensPerSecond}")
                                check(metrics.lastDecodeTokenCount < limit) { "Response reached the GPU context/output limit. Any saved draft remains available." }
                            }
                        }
                    } catch (e: Throwable) { failure = e }
                    finally {
                        synchronized(conversationLock) {
                            active = null
                            try { conversation?.close() } catch (e: Throwable) { if (failure == null) failure = e }
                        }
                        busy = false
                    }
                    main.post {
                        if (generation.get() == id && !closed) {
                            if (failure != null) target.error("GENERATE_FAILED", failure?.message, null)
                            else target.success(mapOf("text" to "", "isDone" to true))
                            target.endOfStream()
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }
    companion object {
        const val TAG = "KrakenGPU"
        const val MODEL_BYTES = 2008432640L
        const val MODEL_SHA = "a53a59001894c58e6bdb5b9b227709f91a2e3e556baa7d85acf9c55402ba5cf5"
    }
}
