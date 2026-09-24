package org.krak_en.spike

/**
 * Minimal Hexagon / QNN availability check — logs to KRAKEN_ACCEL_PROBE.
 * Uses bundled jniLibs, not vendor paths (namespace-blocked).
 */
object QnnHexagonProbe {

    fun run(nativeLibraryDir: String, soc: String) {
        val bundled = QnnLibManifest.bundledNativeLibs(nativeLibraryDir)
        val generation = QnnLibManifest.skelForSoc(soc)
        val skelBundled = generation != null && QnnLibManifest.SKEL_ASSETS.containsKey(generation)

        val loadErrors = mutableListOf<String>()
        val loaded = mutableListOf<String>()

        for (lib in QnnLibManifest.JNI_LIBS) {
            try {
                System.loadLibrary(lib.removePrefix("lib").removeSuffix(".so"))
                loaded += lib
            } catch (t: Throwable) {
                loadErrors += "$lib: ${verbatimError(t)}"
            }
        }

        val initOk = loaded.isNotEmpty()
        ProbeLog.log(
            mapOf(
                "event" to "qnn_hexagon_probe",
                "initOk" to initOk,
                "soc" to soc,
                "qnnSkelGenerationExpected" to generation,
                "qnnSkelBundled" to skelBundled,
                "qnnJniLibsLoaded" to loaded.joinToString(";"),
                "qnnNativeLibsPresent" to bundled.joinToString(";"),
                "error" to if (loadErrors.isEmpty()) null else loadErrors.joinToString(" | "),
            ),
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
}
