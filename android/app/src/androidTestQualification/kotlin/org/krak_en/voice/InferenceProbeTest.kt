package org.krak_en.voice

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.test.platform.app.InstrumentationRegistry
import com.google.ai.edge.litertlm.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Opt-in synthetic GPU smoke test. Independent of the public supported-device list. */
@OptIn(ExperimentalApi::class)
class InferenceProbeTest {
    @Test fun gpuSummary() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val args = InstrumentationRegistry.getArguments()
        require(args.getString("runInference") == "true") { "Explicit runInference=true is required" }
        val context = instrumentation.targetContext
        val qualitySuite = args.getString("qualitySuite") == "true"
        val speculative = args.getString("speculative") == "true"
        val key = args.getString("modelCandidate") ?: "gemma4-e2b-gpu"
        val catalog = JSONObject(instrumentation.context.assets.open("inference_candidates.json").bufferedReader().use { it.readText() })
        val candidate = catalog.getJSONObject(key) // No arbitrary URLs or unpinned models.
        val output = File(requireNotNull(context.getExternalFilesDir(null)), "inference-probe").apply { mkdirs() }
        val file = File(output, "$key.json")
        val report = JSONObject().put("schema", 1).put("modelCandidate", key)
            .put("soc", Build.SOC_MODEL).put("model", Build.MODEL)
            .put("requestedBackend", "GPU").put("cpuOnlyFallback", false)
            .put("perOperatorCpuUsage", "Not measured").put("status", "running")
            .put("modelSha256", candidate.getString("sha256"))
            .put("qualitySuite", qualitySuite).put("speculativeDecoding", speculative)
        fun save(stage: String) { report.put("stage", stage); file.writeText(report.toString(2)); Log.i("INFERENCE_PROBE", "$key $stage") }
        var engine: Engine? = null
        try {
            save("hardware")
            val memory = ActivityManager.MemoryInfo()
            (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
            report.put("totalRamBytes", memory.totalMem).put("availableRamBeforeBytes", memory.availMem)
            val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            check(power.currentThermalStatus < PowerManager.THERMAL_STATUS_SEVERE) { "Device already thermally constrained" }
            // Keep weights outside the report directory pulled by Firebase.
            // Firebase shell-owned staging is imported into app-owned internal storage.
            val models = File(context.filesDir, "inference-models").apply { mkdirs() }
            val model = File(models, "$key.litertlm")
            save("staging")
            ProbeModelStaging.importIfRequested(model, candidate.getLong("bytes"))
            if (!model.exists()) {
                save("download")
                val temp = File(models, "$key.partial")
                val connection = URL(candidate.getString("url")).openConnection() as HttpURLConnection
                connection.connectTimeout = 30000; connection.readTimeout = 30000
                try {
                    check(connection.responseCode == 200) { "Model download HTTP ${connection.responseCode}; gated models must be staged by an authorized account" }
                    connection.inputStream.use { input -> temp.outputStream().use { out ->
                        val buffer = ByteArray(1024 * 1024); var bytes = 0L
                        val downloadStart = SystemClock.elapsedRealtime()
                        val minutes = (args.getString("downloadMinutes")?.toLongOrNull() ?: 8L).coerceIn(1L, 15L)
                        val deadline = downloadStart + minutes * 60 * 1000
                        var nextCheckpoint = 32L * 1024 * 1024
                        while (true) {
                            check(SystemClock.elapsedRealtime() < deadline) { "Download exceeded $minutes minutes after $bytes bytes" }
                            val n = input.read(buffer); if (n < 0) break
                            bytes += n; check(bytes <= candidate.getLong("bytes")) { "Download exceeds pinned size" }
                            out.write(buffer, 0, n)
                            if (bytes >= nextCheckpoint) {
                                report.put("downloadBytes", bytes).put("downloadElapsedMs", SystemClock.elapsedRealtime() - downloadStart)
                                save("download")
                                nextCheckpoint = bytes + 32L * 1024 * 1024
                            }
                        }
                    } }
                    check(temp.length() == candidate.getLong("bytes")) { "Incomplete model" }
                    check(temp.renameTo(model)) { "Cannot finalize model download" }
                } finally { connection.disconnect(); temp.delete() }
            }
            save("checksum")
            check(model.length() == candidate.getLong("bytes")) { "Model size mismatch" }
            val hash = MessageDigest.getInstance("SHA-256")
            model.inputStream().buffered().use { input ->
                val buffer = ByteArray(1024 * 1024)
                while (true) { val n = input.read(buffer); if (n < 0) break; hash.update(buffer, 0, n) }
            }
            check(hash.digest().joinToString("") { "%02x".format(it) } == candidate.getString("sha256")) { "Model checksum mismatch" }
            save("initialization")
            Engine.setNativeMinLogSeverity(LogSeverity.INFO)
            ExperimentalFlags.enableBenchmark = true
            ExperimentalFlags.enableSpeculativeDecoding = speculative
            val start = SystemClock.elapsedRealtime()
            engine = Engine(EngineConfig(modelPath = model.path, backend = Backend.GPU(),
                maxNumTokens = candidate.getInt("context"), cacheDir = File(context.cacheDir, key).apply { mkdirs() }.path))
            engine.initialize()
            report.put("loadMs", SystemClock.elapsedRealtime() - start)
                .put("backendEvidence", "Explicit Backend.GPU initialized; consult native logs for driver execution")
            save("generation")
            val results = JSONArray(); report.put("responses", results)
            val baseline = "Summarize these fictional meeting notes in one sentence. Maya approved a budget of 42750 dollars. The deadline is October 16. Include the name, amount and deadline. Do not invent facts."
            val notes = """
                Maya chaired the planning meeting for the community learning center. The group reviewed the equipment budget, accessibility work, room bookings, and the autumn opening schedule. Maya approved a budget of 42750 dollars. The deadline is October 16. These figures are final and should replace any earlier estimates.
                Jordan suggested buying all the furniture before measuring the rooms. The group rejected that proposal because the corridor needs to remain accessible. Priya will measure the classrooms and check doorway clearances before the next order. No date was assigned to that task. Alex will compare two suppliers and report delivery times. A supplier has not yet been selected.
                The team discussed whether evening classes should run on weekdays or weekends. No decision was made. The coordinator will ask interested residents about their availability. The room booking system needs to support recurring sessions and clearly show cancellations. The team wants a simple printed schedule near the entrance as well as an online calendar.
                Maya explained that the approved budget covers equipment and installation. Volunteers cannot commit extra spending without approval. The old estimate of 50000 dollars was explicitly rejected. Jordan will review the inventory before ordering replacement laptops. Existing equipment that still works should remain in use. No one approved a new subscription service.
                Accessibility remains a priority. Priya asked for clear signs, accessible seating and enough space for mobility aids. The group agreed to review the layout before the opening. They did not select a contractor during this meeting. Questions about the entrance ramp will be sent to the building manager. The answer is still pending.
                At the end, Maya repeated the approved total of 42750 dollars and the October 16 deadline. Alex owns the supplier comparison, Priya owns the room measurements, and Jordan owns the inventory review. The next meeting date has not been chosen. The coordinator will circulate the notes and collect questions before scheduling another meeting.
            """.trimIndent()
            val instruction = "Extract concise factual notes from this section in at most 120 words. Preserve names, exact amounts, dates, decisions, corrections, tasks and unresolved questions. Mark rejected proposals as rejected. Do not invent missing details. Keep the language of the original. Return only notes.\n\n"
            val prompts = if (qualitySuite) listOf(baseline, instruction + notes, instruction + notes) else List(3) { baseline }
            var allCorrect = true
            prompts.forEachIndexed { index, prompt ->
                val outputLimit = if (qualitySuite && index > 0) 768 else 256
                (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
                val availableBefore = memory.availMem
                val lowMemoryBefore = memory.lowMemory
                check(power.currentThermalStatus < PowerManager.THERMAL_STATUS_SEVERE) { "Thermal guard stopped test" }
                val text = StringBuilder(); val done = CountDownLatch(1)
                var failure: Throwable? = null; var firstMs: Long? = null
                val began = SystemClock.elapsedRealtime()
                val conversation = checkNotNull(engine).createConversation(ConversationConfig(
                    samplerConfig = SamplerConfig(topK = 1, topP = 1.0, temperature = 0.0),
                    thinkingConfig = ThinkingConfig(enableThinking = false), maxOutputToken = outputLimit))
                try {
                    conversation.sendMessageAsync(prompt, object : MessageCallback {
                        override fun onMessage(message: Message) {
                            val chunk = message.contents.contents.filterIsInstance<Content.Text>().joinToString("") { it.text }
                            if (chunk.isNotEmpty()) { if (firstMs == null) firstMs = SystemClock.elapsedRealtime() - began; text.append(chunk) }
                        }
                        override fun onDone() { done.countDown() }
                        override fun onError(throwable: Throwable) { failure = throwable; done.countDown() }
                    })
                    if (!done.await(90, TimeUnit.SECONDS)) {
                        report.put("timedOutResponse", JSONObject()
                            .put("index", index + 1).put("partialText", text.toString())
                            .put("firstTextMs", firstMs).put("elapsedMs", SystemClock.elapsedRealtime() - began)
                            .put("pssKb", Debug.getPss()).put("thermalStatus", power.currentThermalStatus))
                        save("generation-timeout")
                        conversation.cancelProcess()
                        if (!done.await(15, TimeUnit.SECONDS)) {
                            // Do not free native state while its callback can still be running.
                            // This failed instrumentation process is disposed by the test runner.
                            engine = null
                            error("Native callback did not finish after cancellation; process cleanup required")
                        }
                        error("Generation exceeded 90 seconds")
                    }
                    failure?.let { throw it }
                    val metrics = conversation.getBenchmarkInfo()
                    val answer = text.toString(); val normalized = answer.replace(",", "")
                    val correct = normalized.contains("42750") && answer.contains("Maya") && answer.contains("October") && answer.contains("16")
                    (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
                    val foreignCharacters = Regex("[\\u0400-\\u052f\\u0900-\\u097f\\u3040-\\u30ff\\u3400-\\u9fff\\uac00-\\ud7af]").findAll(answer).count()
                    val passed = correct && metrics.lastDecodeTokenCount < outputLimit && foreignCharacters < 8
                    allCorrect = allCorrect && passed
                    results.put(JSONObject().put("text", answer).put("correctFacts", correct)
                        .put("prompt", prompt).put("outputLimit", outputLimit).put("passed", passed)
                        .put("unexpectedScriptCharacters", foreignCharacters)
                        .put("availableRamBeforeBytes", availableBefore).put("lowMemoryBefore", lowMemoryBefore)
                        .put("availableRamAfterBytes", memory.availMem).put("lowMemoryAfter", memory.lowMemory)
                        .put("firstTextMs", firstMs).put("totalMs", SystemClock.elapsedRealtime() - began)
                        .put("prefillTokens", metrics.lastPrefillTokenCount).put("decodeTokens", metrics.lastDecodeTokenCount)
                        .put("decodeTokensPerSecond", metrics.lastDecodeTokensPerSecond)
                        .put("pssKb", Debug.getPss()).put("thermalStatus", power.currentThermalStatus))
                    save("response-${index + 1}")
                    if (!qualitySuite) check(passed) { "Synthetic facts missing or response hit output limit" }
                } finally { if (done.count == 0L) conversation.close() }
            }
            check(allCorrect) { "One or more synthetic responses failed quality checks; see raw responses" }
            report.put("status", "passed")
        } catch (e: Throwable) {
            report.put("failureStage", report.optString("stage"))
                .put("status", "failed").put("error", "${e.javaClass.simpleName}: ${e.message}")
        } finally {
            save("cleanup")
            try { engine?.close() } catch (e: Throwable) { report.put("status", "failed").put("cleanupError", e.toString()) }
            save("complete")
            Log.i("INFERENCE_PROBE", report.toString())
        }
        assertTrue(report.optString("error"), report.getString("status") == "passed")
    }
}
