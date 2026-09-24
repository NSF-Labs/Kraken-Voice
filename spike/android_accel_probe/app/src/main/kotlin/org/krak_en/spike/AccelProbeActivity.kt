package org.krak_en.spike

import android.app.Activity
import android.content.Intent
import android.os.BatteryManager
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Throwaway spike harness — not shipped in production.
 * Logs JSON-ish lines to logcat tag KRAKEN_ACCEL_PROBE.
 *
 * Intent extras:
 *   backend: cpu | gpu | npu | qnn (required)
 *   modelPath: optional
 *   shortPrompt: "true" for ~500-token prefill smoke
 */
class AccelProbeActivity : Activity() {

    companion object {
        private const val DEFAULT_MODEL =
            "/storage/emulated/0/Documents/KrakenModels/gemma4.litertlm"
        private const val LITERT_LM_VERSION = "0.15.0"
        private const val DECODE_PROMPT = "List three action items as bullet points."
        private const val HEARTBEAT_MS = 20_000L
        private const val INIT_TIMEOUT_MS = 30 * 60 * 1000L // NPU JIT: 30 min

        private val PREFILL_BLOCK =
            "Attendee discussed quarterly goals, budget allocation, hiring plans, " +
                "and product roadmap priorities for the next release cycle. "

        private val STANDARD_PREFILL_PROMPT = buildString {
            append("Summarize the following meeting notes in one sentence. ")
            repeat(40) { append(PREFILL_BLOCK.replace("Attendee", "Attendee $it")) }
        }

        private val SHORT_PREFILL_PROMPT = buildString {
            append("Summarize the following meeting notes in one sentence. ")
            while (length < 2000) append(PREFILL_BLOCK)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val modelPath = intent?.getStringExtra("modelPath") ?: DEFAULT_MODEL
        val backendRequested = intent?.getStringExtra("backend")?.lowercase()
        val shortPrompt = intent.getBooleanExtra("shortPrompt", false) ||
            intent?.getStringExtra("shortPrompt")?.equals("true", ignoreCase = true) == true
        val deviceModel = android.os.Build.MODEL
        val soc = readSocModel()
        val battery = readBatterySnapshot()
        val fingerprint = ModelFingerprint.fromPath(modelPath)
        val qnnInventory = QnnLibManifest.inventory(this, applicationInfo.nativeLibraryDir, soc)

        val fingerprintFields = buildMap<String, Any?> {
            put("event", "probe_start")
            put("tsMs", SystemClock.elapsedRealtime())
            put("device", deviceModel)
            put("soc", soc)
            put("litertLmVersion", LITERT_LM_VERSION)
            put("backendRequested", backendRequested ?: "unset")
            put("backendConfigured", backendRequested?.uppercase())
            put("backendActuallySelected", "pending")
            put("shortPrompt", shortPrompt)
            put("batteryTempC", battery.tempC)
            put("batteryPct", battery.pct)
            put("fingerprintValid", fingerprint.valid)
            putAll(fingerprint.toLogMap())
            putAll(qnnInventory)
        }
        ProbeLog.log(fingerprintFields)

        if (!fingerprint.valid) {
            logInitFailure(backendRequested ?: "unset", "Invalid model fingerprint — result discarded")
            finish()
            return
        }

        if (backendRequested.isNullOrBlank()) {
            logInitFailure("unset", "Missing required intent extra: backend")
            finish()
            return
        }

        when (backendRequested) {
            "qnn" -> {
                QnnHexagonProbe.run(applicationInfo.nativeLibraryDir, soc)
                ProbeLog.log(mapOf("event" to "probe_complete", "backend" to "qnn"))
                finish()
                return
            }
            "npu", "cpu", "gpu" -> {
                runGemmaBackendProbe(
                    backendRequested.uppercase(),
                    modelPath,
                    deviceModel,
                    soc,
                    shortPrompt,
                    battery,
                    fingerprint,
                )
            }
            else -> {
                logInitFailure(backendRequested, "Unknown backend: $backendRequested")
                finish()
                return
            }
        }

        ProbeLog.log(mapOf("event" to "probe_complete", "backend" to backendRequested))
        finish()
    }

    private fun runGemmaBackendProbe(
        backendName: String,
        modelPath: String,
        deviceModel: String,
        soc: String,
        shortPrompt: Boolean,
        battery: BatterySnapshot,
        fingerprint: ModelFingerprint,
    ) {
        var engine: Engine? = null
        var conversation: Conversation? = null
        val backendConfigured = backendName

        try {
            val backend = resolveBackend(backendName, soc)
            val cacheDir = cacheDir.absolutePath

            val constructStart = SystemClock.elapsedRealtime()
            val config = EngineConfig(
                modelPath = modelPath,
                backend = backend,
                maxNumTokens = 32768,
                cacheDir = cacheDir,
            )
            engine = Engine(config)
            val constructMs = SystemClock.elapsedRealtime() - constructStart

            ProbeLog.log(
                mapOf(
                    "event" to "model_load_complete",
                    "tsMs" to SystemClock.elapsedRealtime(),
                    "backendConfigured" to backendConfigured,
                    "backendActuallySelected" to backendConfigured,
                    "engineConstructMs" to constructMs,
                    "modelSha256" to fingerprint.sha256,
                ),
            )

            val compileMs = runInitializeWithTimeout(engine, backendName)
            if (compileMs < 0) {
                logInitFailure(
                    backendName,
                    "engine.initialize() timed out after ${INIT_TIMEOUT_MS / 1000}s",
                )
                return
            }

            ProbeLog.log(
                mapOf(
                    "event" to "engine_initialize_complete",
                    "tsMs" to SystemClock.elapsedRealtime(),
                    "backendConfigured" to backendConfigured,
                    "backendActuallySelected" to backendConfigured,
                    "compileMs" to compileMs,
                    "initOk" to true,
                ),
            )

            conversation = engine.createConversation()
            val prefillPrompt = if (shortPrompt) SHORT_PREFILL_PROMPT else STANDARD_PREFILL_PROMPT
            val prefillInputTokens = estimateTokens(prefillPrompt)

            val prefill = runGeneration(
                conversation,
                prefillPrompt,
                stage = "prefill",
                inputTokens = prefillInputTokens,
            )

            val decode = runGeneration(
                conversation,
                DECODE_PROMPT,
                stage = "decode",
                inputTokens = estimateTokens(DECODE_PROMPT),
            )

            val batteryEnd = readBatterySnapshot()

            ProbeLog.log(
                mapOf(
                    "event" to "probe_result",
                    "device" to deviceModel,
                    "soc" to soc,
                    "backendConfigured" to backendConfigured,
                    "backendActuallySelected" to backendConfigured,
                    "shortPrompt" to shortPrompt,
                    "initOk" to true,
                    "fingerprintValid" to true,
                    "modelFilename" to fingerprint.filename,
                    "modelSizeBytes" to fingerprint.sizeBytes,
                    "modelSha256" to fingerprint.sha256,
                    "litertLmVersion" to LITERT_LM_VERSION,
                    "engineConstructMs" to constructMs,
                    "compileMs" to compileMs,
                    "initCompileMs" to (constructMs + compileMs),
                    "prefillInputTokensEst" to prefillInputTokens,
                    "prefillOutputTokensEst" to prefill.outputTokensEst,
                    "prefillMs" to prefill.totalMs,
                    "prefillTokPerSec" to prefill.tokPerSec,
                    "decodeInputTokensEst" to estimateTokens(DECODE_PROMPT),
                    "decodeOutputTokensEst" to decode.outputTokensEst,
                    "decodeMs" to decode.totalMs,
                    "decodeTokPerSec" to decode.tokPerSec,
                    "batteryTempCStart" to battery.tempC,
                    "batteryPctStart" to battery.pct,
                    "batteryTempCEnd" to batteryEnd.tempC,
                    "batteryPctEnd" to batteryEnd.pct,
                ),
            )
        } catch (t: Throwable) {
            logInitFailure(backendName, verbatimError(t), Log.getStackTraceString(t))
        } finally {
            try {
                conversation?.close()
            } catch (_: Exception) {
            }
            try {
                engine?.close()
            } catch (_: Exception) {
            }
        }
    }

    /** Returns compileMs, or -1 on timeout. */
    private fun runInitializeWithTimeout(engine: Engine, backendName: String): Long =
        runBlocking {
            val done = AtomicBoolean(false)
            val compileMs = AtomicLong(-1L)
            val stageRef = AtomicReference("init_$backendName")
            val initStart = SystemClock.elapsedRealtime()

            val heartbeatJob = startHeartbeat(stageRef, AtomicInteger(0), initStart, done)

            val initJob = launch(Dispatchers.Default) {
                val compileStart = SystemClock.elapsedRealtime()
                engine.initialize()
                compileMs.set(SystemClock.elapsedRealtime() - compileStart)
            }

            val completed = withTimeoutOrNull(INIT_TIMEOUT_MS) {
                initJob.join()
                true
            } ?: false

            done.set(true)
            heartbeatJob.cancel()

            if (!completed) {
                initJob.cancel()
                -1L
            } else {
                compileMs.get()
            }
        }

    private fun resolveBackend(backendName: String, soc: String): Backend = when (backendName) {
        "GPU" -> Backend.GPU()
        "NPU" -> {
            val generation = QnnLibManifest.skelForSoc(soc)
            QnnLibManifest.extractSkelToCache(this, generation ?: QnnLibManifest.HTP_V75)
            Backend.NPU(nativeLibraryDir = applicationInfo.nativeLibraryDir)
        }
        else -> Backend.CPU()
    }

    private fun logInitFailure(backend: String, error: String, stack: String? = null) {
        ProbeLog.log(
            buildMap {
                put("event", "init_failure")
                put("tsMs", SystemClock.elapsedRealtime())
                put("backend", backend)
                put("initOk", false)
                put("error", error)
                if (stack != null) put("stack", stack)
            },
        )
    }

    private fun verbatimError(t: Throwable): String {
        val msg = t.message
        return if (!msg.isNullOrBlank()) {
            "${t.javaClass.name}: $msg"
        } else {
            t.javaClass.name
        }
    }

    private data class BatterySnapshot(val pct: Int, val tempC: Double)

    private data class GenStats(
        val outputTokensEst: Int,
        val totalMs: Long,
        val tokPerSec: Double,
        val timeToFirstTokenMs: Long,
    )

    private fun runGeneration(
        conversation: Conversation,
        prompt: String,
        stage: String,
        inputTokens: Int,
    ): GenStats = runBlocking {
        val stageStart = SystemClock.elapsedRealtime()
        val tokensProcessed = AtomicInteger(0)
        val firstTokenMs = AtomicLong(-1L)
        val stageRef = AtomicReference(stage)
        val done = AtomicBoolean(false)

        ProbeLog.log(
            mapOf(
                "event" to "${stage}_start",
                "tsMs" to stageStart,
                "inputTokensEst" to inputTokens,
            ),
        )

        val heartbeatJob = startHeartbeat(stageRef, tokensProcessed, stageStart, done)

        val sb = StringBuilder()
        try {
            conversation.sendMessageAsync(Message.user(prompt)).collect { message ->
                val text = extractText(message)
                if (text.isNotEmpty()) {
                    if (firstTokenMs.get() < 0) {
                        firstTokenMs.set(SystemClock.elapsedRealtime() - stageStart)
                    }
                    sb.append(text)
                    tokensProcessed.set(estimateTokens(sb.length))
                }
            }
        } finally {
            done.set(true)
            heartbeatJob.cancel()
        }

        val elapsed = SystemClock.elapsedRealtime() - stageStart
        val outputTokens = estimateTokens(sb.length)
        val ttft = firstTokenMs.get().coerceAtLeast(0L)

        if (stage == "prefill") {
            val prefillElapsed = if (ttft > 0) ttft else elapsed
            val prefillTps = if (prefillElapsed > 0) {
                inputTokens * 1000.0 / prefillElapsed
            } else {
                0.0
            }
            ProbeLog.log(
                mapOf(
                    "event" to "prefill_complete",
                    "tsMs" to SystemClock.elapsedRealtime(),
                    "inputTokensEst" to inputTokens,
                    "outputTokensEst" to outputTokens,
                    "elapsedMs" to prefillElapsed,
                    "tokPerSec" to prefillTps,
                ),
            )
            GenStats(outputTokens, elapsed, prefillTps, ttft)
        } else {
            val decodeElapsed = (elapsed - ttft).coerceAtLeast(1L)
            val decodeTps = if (decodeElapsed > 0) {
                outputTokens * 1000.0 / decodeElapsed
            } else {
                0.0
            }
            ProbeLog.log(
                mapOf(
                    "event" to "decode_complete",
                    "tsMs" to SystemClock.elapsedRealtime(),
                    "outputTokensEst" to outputTokens,
                    "elapsedMs" to decodeElapsed,
                    "tokPerSec" to decodeTps,
                ),
            )
            GenStats(outputTokens, elapsed, decodeTps, ttft)
        }
    }

    private fun startHeartbeat(
        stageRef: AtomicReference<String>,
        tokensProcessed: AtomicInteger,
        stageStart: Long,
        done: AtomicBoolean,
    ): Job {
        return CoroutineScope(Dispatchers.Default).launch {
            while (!done.get()) {
                delay(HEARTBEAT_MS)
                if (done.get()) break
                val elapsed = SystemClock.elapsedRealtime() - stageStart
                val tokens = tokensProcessed.get()
                val tps = if (elapsed > 0) tokens * 1000.0 / elapsed else 0.0
                ProbeLog.log(
                    mapOf(
                        "event" to "heartbeat",
                        "tsMs" to SystemClock.elapsedRealtime(),
                        "stage" to stageRef.get(),
                        "tokensProcessedEst" to tokens,
                        "tokPerSec" to tps,
                    ),
                )
            }
        }
    }

    private fun estimateTokens(charCount: Int): Int = (charCount / 4.0).toInt().coerceAtLeast(0)

    private fun estimateTokens(text: String): Int = estimateTokens(text.length)

    private fun extractText(message: Message): String {
        try {
            val getter = message.javaClass.methods.firstOrNull {
                it.name == "getText" && it.parameterCount == 0
            }
            if (getter != null) {
                return (getter.invoke(message) as? String).orEmpty()
            }
        } catch (_: Exception) {
        }
        return message.toString()
    }

    private fun readBatterySnapshot(): BatterySnapshot {
        val bm = getSystemService(BATTERY_SERVICE) as BatteryManager
        val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val tempTenths = try {
            val intent = registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
        } catch (_: Exception) {
            -1
        }
        val tempC = if (tempTenths > 0) tempTenths / 10.0 else -1.0
        return BatterySnapshot(pct, tempC)
    }

    private fun readSocModel(): String {
        return try {
            val c = Class.forName("android.os.SystemProperties")
            val get = c.getMethod("get", String::class.java, String::class.java)
            (get.invoke(null, "ro.soc.model", "unknown") as String)
        } catch (_: Exception) {
            "unknown"
        }
    }
}
