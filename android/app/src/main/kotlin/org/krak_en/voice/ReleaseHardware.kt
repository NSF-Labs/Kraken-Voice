package org.krak_en.voice

import android.os.Build
import java.util.Locale

/** Explicit device/profile allowlist. New models require on-device validation. */
object ReleaseHardware {
    enum class Profile { NPU, GPU }

    fun supportsSoc(soc: String): Boolean =
        Regex("^SM8850(?:-[A-Z0-9]+)*$").matches(soc.trim().uppercase(Locale.ROOT))

    fun supportsDevice(profile: Profile, manufacturer: String, model: String,
                       soc: String, sdk: Int, abis: List<String>): Boolean {
        if (sdk < 31 || "arm64-v8a" !in abis ||
            manufacturer.trim().lowercase(Locale.ROOT) != "samsung") return false
        val expectedModel = if (profile == Profile.NPU) "SM-S948U" else "SM-S928U"
        val expectedSoc = if (profile == Profile.NPU) "SM8850" else "SM8650"
        return model.trim().uppercase(Locale.ROOT) == expectedModel &&
            Regex("^$expectedSoc(?:-[A-Z0-9]+)*$")
                .matches(soc.trim().uppercase(Locale.ROOT))
    }

    fun isSupported(profile: Profile = Profile.NPU): Boolean = supportsDevice(
        profile, Build.MANUFACTURER, Build.MODEL, Build.SOC_MODEL,
        Build.VERSION.SDK_INT, Build.SUPPORTED_ABIS.toList())
}
