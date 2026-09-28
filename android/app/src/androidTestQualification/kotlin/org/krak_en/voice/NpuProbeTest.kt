package org.krak_en.voice

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Uses the app's actual Hexagon bridge, including its checksum and HTP0 requirement. */
class NpuProbeTest {
    @Test fun npuSummary() {
        require(InstrumentationRegistry.getArguments().getString("runInference") == "true")
        check(ReleaseHardware.supportsCandidate(ReleaseHardware.Profile.NPU, Build.SOC_MODEL))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val main = Handler(Looper.getMainLooper())
        ReleaseHardware.qualificationBackend = ReleaseHardware.Profile.NPU
        val bridge = HexagonBridge(context)
        val base = requireNotNull(context.getExternalFilesDir(null))
        val output = File(base, "inference-probe").apply { mkdirs() }
        val report = JSONObject().put("schema", 1).put("modelCandidate", "gemma4-e2b-npu")
            .put("model", Build.MODEL).put("soc", Build.SOC_MODEL).put("requestedBackend", "NPU")
            .put("status", "running").put("cpuOnlyFallback", false)
            .put("perOperatorCpuUsage", "CPU host work and unsupported operations remain")
        fun save(stage: String) { report.put("stage", stage); File(output, "gemma4-e2b-npu.json").writeText(report.toString(2)) }
        fun call(method: String, args: Map<String, Any?> = emptyMap(), seconds: Long = 120): Any? {
            val done = CountDownLatch(1); var value: Any? = null; var failure: String? = null
            main.post { bridge.handle(MethodCall(method, args), object : MethodChannel.Result {
                override fun success(result: Any?) { value = result; done.countDown() }
                override fun error(code: String, message: String?, details: Any?) { failure = "$code: $message"; done.countDown() }
                override fun notImplemented() { failure = "Not implemented: $method"; done.countDown() }
            }) }
            check(done.await(seconds, TimeUnit.SECONDS)) { "$method timed out" }
            check(failure == null) { failure ?: method }
            return value
        }
        try {
            save("download")
            val models = File(context.filesDir, "inference-models").apply { mkdirs() }
            val model = File(models, "gemma4-e2b-w4.gguf")
            save("staging")
            ProbeModelStaging.importIfRequested(model, HexagonBridge.MODEL_BYTES)
            if (!model.exists()) {
                save("download")
                val temp = File(models, "gemma4-e2b-w4.partial")
                val connection = URL("https://huggingface.co/h2loop-ai/gemma-4-e2b-hexagon/resolve/1bb2044c313769541558f2c27fa67561894d0f26/gemma4-e2b-w4.gguf").openConnection() as HttpURLConnection
                connection.connectTimeout = 30000; connection.readTimeout = 30000
                try {
                    check(connection.responseCode == 200) { "Download HTTP ${connection.responseCode}" }
                    val downloadStart = SystemClock.elapsedRealtime()
                    val minutes = (InstrumentationRegistry.getArguments().getString("downloadMinutes")?.toLongOrNull() ?: 8L).coerceIn(1L, 15L)
                    val deadline = downloadStart + minutes * 60 * 1000
                    connection.inputStream.use { input -> temp.outputStream().use { out ->
                        val buffer = ByteArray(1024 * 1024); var bytes = 0L
                        var nextCheckpoint = 32L * 1024 * 1024
                        while (true) {
                            check(SystemClock.elapsedRealtime() < deadline) { "Download exceeded $minutes minutes after $bytes bytes" }
                            val n = input.read(buffer); if (n < 0) break
                            bytes += n; check(bytes <= HexagonBridge.MODEL_BYTES)
                            out.write(buffer, 0, n)
                            if (bytes >= nextCheckpoint) {
                                report.put("downloadBytes", bytes).put("downloadElapsedMs", SystemClock.elapsedRealtime() - downloadStart)
                                save("download")
                                nextCheckpoint = bytes + 32L * 1024 * 1024
                            }
                        }
                    } }
                    check(temp.length() == HexagonBridge.MODEL_BYTES && temp.renameTo(model))
                } finally { connection.disconnect(); temp.delete() }
            }
            val power = context.getSystemService(android.os.PowerManager::class.java)
            check(power.currentThermalStatus < android.os.PowerManager.THERMAL_STATUS_SEVERE) { "Thermal guard" }
            save("initialization")
            val start = SystemClock.elapsedRealtime()
            call("loadModel", mapOf("modelPath" to model.path))
            report.put("loadMs", SystemClock.elapsedRealtime() - start).put("diagnostics", JSONObject(bridge.diagnostics()))
            val responses = JSONArray(); report.put("responses", responses)
            repeat(3) { index ->
                check(power.currentThermalStatus < android.os.PowerManager.THERMAL_STATUS_SEVERE) { "Thermal guard" }
                save("generation-${index + 1}")
                val done = CountDownLatch(1); val text = StringBuilder()
                var failure: String? = null; var firstMs: Long? = null
                val began = SystemClock.elapsedRealtime()
                main.post { bridge.onListen(null, object : EventChannel.EventSink {
                    override fun success(event: Any?) {
                        val data = event as? Map<*, *> ?: return
                        val chunk = data["text"] as? String ?: ""
                        if (chunk.isNotEmpty()) { if (firstMs == null) firstMs = SystemClock.elapsedRealtime() - began; text.append(chunk) }
                    }
                    override fun error(code: String, message: String?, details: Any?) { failure = "$code: $message"; done.countDown() }
                    override fun endOfStream() { done.countDown() }
                }) }
                call("generate", mapOf("prompt" to "Summarize these fictional meeting notes in one sentence. Maya approved a budget of 42750 dollars. The deadline is October 16. Include the name, amount and deadline. Do not invent facts.", "maxTokens" to 256, "autoContinue" to false))
                if (!done.await(90, TimeUnit.SECONDS)) { call("cancelGeneration", seconds = 15); error("Generation timed out") }
                check(failure == null) { failure ?: "generation" }
                val answer = text.toString()
                val correct = answer.replace(",", "").contains("42750") && answer.contains("Maya") && answer.contains("October") && answer.contains("16")
                responses.put(JSONObject().put("text", answer).put("correctFacts", correct)
                    .put("firstTextMs", firstMs).put("totalMs", SystemClock.elapsedRealtime() - began)
                    .put("pssKb", android.os.Debug.getPss()).put("thermalStatus", power.currentThermalStatus))
                save("response-${index + 1}"); check(correct) { "Required facts missing" }
            }
            report.put("status", "passed")
        } catch (e: Throwable) {
            report.put("failureStage", report.optString("stage")).put("status", "failed").put("error", e.toString())
        } finally {
            save("cleanup")
            try { call("unloadModel", seconds = 30) } catch (e: Throwable) { report.put("status", "failed").put("cleanupError", e.toString()) }
            main.post { bridge.close() }
            save("complete")
        }
        assertTrue(report.optString("error"), report.getString("status") == "passed")
    }
}
