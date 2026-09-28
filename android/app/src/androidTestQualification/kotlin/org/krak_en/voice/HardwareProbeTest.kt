package org.krak_en.voice

import android.app.ActivityManager
import android.content.Context
import android.opengl.EGL14
import android.opengl.GLES20
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.UUID

/** Discovery only: never starts an Activity, constructs an inference engine or opens a model. */
class HardwareProbeTest {
    private external fun nativeDiscovery(): String

    @Test fun recordHardware() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val memory = ActivityManager.MemoryInfo()
        (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
        val report = JSONObject().apply {
            put("schemaVersion", 1)
            put("runId", UUID.randomUUID().toString())
            put("timestampMs", System.currentTimeMillis())
            put("inferencePerformed", false)
            put("build", JSONObject().apply {
                put("manufacturer", Build.MANUFACTURER); put("model", Build.MODEL)
                put("device", Build.DEVICE); put("hardware", Build.HARDWARE)
                put("board", Build.BOARD); put("socManufacturer", Build.SOC_MANUFACTURER)
                put("socModel", Build.SOC_MODEL); put("apiLevel", Build.VERSION.SDK_INT)
                put("androidRelease", Build.VERSION.RELEASE)
                put("abis", JSONArray(Build.SUPPORTED_ABIS.toList()))
            })
            put("ram", JSONObject().put("totalBytes", memory.totalMem).put("availableBytes", memory.availMem))
            put("gles", capture { gles() })
            put("declaredVulkanFeatures", JSONArray(context.packageManager.systemAvailableFeatures
                .filter { it.name?.startsWith("android.hardware.vulkan") == true }
                .map { JSONObject().put("name", it.name).put("version", it.version) }))
            put("native", capture { System.loadLibrary("hardware_probe"); JSONObject(nativeDiscovery()) })
            put("litertLm", JSONObject().apply {
                put("version", "0.17.1")
                put("configuredAppBackend", "GPU")
                put("availableAccelerators", JSONObject.NULL)
                put("status", "Not enumerated: bundled LiteRT-LM Engine API has no model-free accelerator availability API")
                put("note", "Backend options are not proof of device support; no Engine was initialized")
            })
            put("hexagon", JSONObject().apply {
                put("runtime", "llama.cpp / ggml-hexagon (not LiteRT-LM NPU)")
                put("packagedLibraries", JSONArray(File(context.applicationInfo.nativeLibraryDir).listFiles()
                    .orEmpty().filter { it.name.contains("hexagon") || it.name.contains("htp") }
                    .map { it.name }.sorted()))
                put("executionVerified", false)
                put("note", "Packaged v79/v81 libraries and vendor loader visibility do not prove NPU compatibility. No DSP session opened.")
            })
        }
        val dir = File(requireNotNull(context.getExternalFilesDir(null)), "hardware-probe").apply { mkdirs() }
        val file = File(dir, "hardware.json")
        file.writeText(report.toString(2))
        // ASCII escaping keeps each numbered Logcat chunk below the byte limit, including unusual device strings.
        val compact = report.toString().map { if (it.code >= 127) "\\u%04x".format(it.code) else it.toString() }.joinToString("")
        val chunks = compact.chunked(2800)
        chunks.forEachIndexed { index, chunk -> Log.i("HARDWARE_PROBE", "${report.getString("runId")} ${index + 1}/${chunks.size} $chunk") }
        instrumentation.sendStatus(0, Bundle().apply { putString("stream", "\nHARDWARE_PROBE report: ${file.absolutePath}\n") })
        assertTrue("Discovery report must be saved", file.length() > 0)
        // Missing accelerators are discovery outcomes, not test failures or certification.
    }

    private fun capture(block: () -> JSONObject): JSONObject = try { block() } catch (e: Exception) {
        JSONObject().put("error", "${e.javaClass.simpleName}: ${e.message}")
    } catch (e: LinkageError) {
        JSONObject().put("error", "${e.javaClass.simpleName}: ${e.message}")
    }

    private fun gles(): JSONObject {
        val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(display != EGL14.EGL_NO_DISPLAY) { "No EGL display" }
        var context = EGL14.EGL_NO_CONTEXT
        var surface = EGL14.EGL_NO_SURFACE
        try {
            val major = IntArray(1)
            val minor = IntArray(1)
            check(EGL14.eglInitialize(display, major, 0, minor, 0)) { "EGL initialize failed" }
            val configs = arrayOfNulls<android.opengl.EGLConfig>(1)
            val count = IntArray(1)
            val attributes = intArrayOf(EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT, EGL14.EGL_NONE)
            check(EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, count, 0) && count[0] > 0)
            context = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT,
                intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0)
            check(context != EGL14.EGL_NO_CONTEXT)
            surface = EGL14.eglCreatePbufferSurface(display, configs[0],
                intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE), 0)
            check(surface != EGL14.EGL_NO_SURFACE)
            check(EGL14.eglMakeCurrent(display, surface, surface, context))
            return JSONObject().put("vendor", GLES20.glGetString(GLES20.GL_VENDOR))
                .put("renderer", GLES20.glGetString(GLES20.GL_RENDERER))
                .put("version", GLES20.glGetString(GLES20.GL_VERSION))
                .put("extensions", GLES20.glGetString(GLES20.GL_EXTENSIONS))
                .put("eglVersion", "${major[0]}.${minor[0]}")
        } finally {
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            if (surface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, surface)
            if (context != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, context)
            EGL14.eglTerminate(display)
            EGL14.eglReleaseThread()
        }
    }
}
