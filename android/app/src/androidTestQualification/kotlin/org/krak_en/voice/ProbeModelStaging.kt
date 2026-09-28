package org.krak_en.voice

import android.os.ParcelFileDescriptor
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File

/** Test-only import from Firebase's shell-owned staging area into app-owned storage. */
object ProbeModelStaging {
    fun importIfRequested(model: File, expectedBytes: Long) {
        if (InstrumentationRegistry.getArguments().getString("useStagedModel") != "true") return
        require(model.name in setOf("gemma4-e2b-gpu.litertlm", "gemma4-e2b-portable-gpu.litertlm", "gemma4-e2b-w4.gguf"))
        val temp = File(model.parentFile, model.name + ".staging")
        try {
            val descriptor = InstrumentationRegistry.getInstrumentation().uiAutomation
                .executeShellCommand("cat /data/local/tmp/${model.name}")
            ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { input ->
                temp.outputStream().use { output ->
                    val buffer = ByteArray(1024 * 1024)
                    var bytes = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        bytes += count
                        check(bytes <= expectedBytes) { "Staged model exceeds pinned size" }
                        output.write(buffer, 0, count)
                    }
                    check(bytes == expectedBytes) { "Staged model missing or incomplete: $bytes bytes" }
                }
            }
            check(temp.renameTo(model)) { "Cannot finalize staged model" }
            // Each caller verifies the pinned SHA-256 before initializing inference.
        } finally {
            temp.delete()
        }
    }
}
