package org.krak_en.spike

import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

/**
 * Artifact fingerprint for probe validity. Results without this are discarded.
 */
data class ModelFingerprint(
    val filename: String,
    val sizeBytes: Long,
    val sha256: String,
    val path: String,
) {
    val valid: Boolean get() = sizeBytes > 0 && sha256.isNotBlank() && sha256 != "error"

    fun toLogMap(): Map<String, Any?> = mapOf(
        "modelFilename" to filename,
        "modelSizeBytes" to sizeBytes,
        "modelSha256" to sha256,
        "modelPath" to path,
    )

    companion object {
        /** Official litert-community release artifact (CPU/GPU graph). */
        const val OFFICIAL_FILENAME = "gemma-4-E2B-it.litertlm"
        const val OFFICIAL_SOURCE =
            "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm"

        fun fromPath(modelPath: String): ModelFingerprint {
            val file = File(modelPath)
            return ModelFingerprint(
                filename = file.name,
                sizeBytes = if (file.isFile) file.length() else -1L,
                sha256 = if (file.isFile) sha256File(file) else "error",
                path = modelPath,
            )
        }

        private fun sha256File(file: File): String {
            val digest = MessageDigest.getInstance("SHA-256")
            FileInputStream(file).use { input ->
                val buffer = ByteArray(1024 * 1024)
                var read: Int
                while (input.read(buffer).also { read = it } != -1) {
                    digest.update(buffer, 0, read)
                }
            }
            return digest.digest().joinToString("") { "%02x".format(it) }
        }
    }
}
