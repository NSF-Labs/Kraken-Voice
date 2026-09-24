package org.krak_en.spike

import android.content.Context
import java.io.File

/**
 * QNN / Hexagon libraries bundled with the probe APK.
 * Skel libs are SoC-generation specific — wrong skel is a leading NPU hang suspect.
 */
object QnnLibManifest {
    const val HTP_V75 = "v75" // Snapdragon 8 Gen 3 — SM8650 (S24 Ultra)
    const val HTP_V81 = "v81" // Snapdragon 8 Elite Gen 5 — SM8850 (S26 Ultra)

    /** CPU-side libs packaged in jniLibs/arm64-v8a/ */
    val JNI_LIBS = listOf(
        "libQnnHtp.so",
        "libQnnHtpV75Stub.so",
        "libQnnSystem.so",
    )

    /** Skel libs packaged in assets/qnn/<generation>/ */
    val SKEL_ASSETS = mapOf(
        HTP_V75 to "qnn/v75/libQnnHtpV75Skel.so",
        // V81 skel not yet obtained — requires QAIRT SDK for SM8850 / HTP v81
    )

    fun skelForSoc(soc: String): String? = when (soc.uppercase()) {
        "SM8650", "SM8635" -> HTP_V75
        "SM8750", "SM8850" -> HTP_V81
        else -> null
    }

    fun bundledNativeLibs(nativeLibraryDir: String): List<String> {
        val dir = File(nativeLibraryDir)
        return dir.listFiles()
            ?.map { it.name }
            ?.filter { it.contains("Qnn", ignoreCase = true) || it.contains("litert", ignoreCase = true) }
            ?.sorted()
            .orEmpty()
    }

    fun extractSkelToCache(context: Context, generation: String): File? {
        val assetPath = SKEL_ASSETS[generation] ?: return null
        val outDir = File(context.cacheDir, "qnn_skel/$generation")
        outDir.mkdirs()
        val outFile = File(outDir, File(assetPath).name)
        if (outFile.exists() && outFile.length() > 0) return outFile
        return try {
            context.assets.open(assetPath).use { input ->
                outFile.outputStream().use { output -> input.copyTo(output) }
            }
            outFile
        } catch (_: Exception) {
            null
        }
    }

    fun inventory(context: Context, nativeLibraryDir: String, soc: String): Map<String, Any?> {
        val generation = skelForSoc(soc)
        val skelAsset = generation?.let { SKEL_ASSETS[it] }
        val skelExtracted = generation?.let { extractSkelToCache(context, it) }
        return mapOf(
            "qnnJniLibs" to JNI_LIBS.joinToString(";"),
            "qnnNativeLibsPresent" to bundledNativeLibs(nativeLibraryDir).joinToString(";"),
            "qnnSkelGenerationExpected" to generation,
            "qnnSkelAsset" to skelAsset,
            "qnnSkelExtracted" to skelExtracted?.absolutePath,
            "qnnSkelBundled" to (skelExtracted != null),
        )
    }
}
