package org.krak_en.voice

import android.os.Build
import java.util.Locale

/** Explicit device/profile allowlist. New models require on-device validation. */
object ReleaseHardware {
    const val BUILD = "1.0.16+16"
    enum class Profile { NPU, GPU }
    var qualificationBackend: Profile? = null

    fun isEmulator(): Boolean = Build.FINGERPRINT.startsWith("generic") ||
        Build.HARDWARE.contains("ranchu") || Build.HARDWARE.contains("goldfish") ||
        Build.MODEL.contains("Emulator") || Build.PRODUCT.contains("sdk")

    fun supportsCandidate(profile: Profile, soc: String): Boolean =
        Regex(if (profile == Profile.GPU) "^SM(?:8650|8750|8850)(?:-[A-Z0-9]+)*$"
            else "^SM(?:8750|8850)(?:-[A-Z0-9]+)*$")
            .matches(soc.trim().uppercase(Locale.ROOT))

    fun supportsSoc(soc: String): Boolean =
        Regex("^SM8850(?:-[A-Z0-9]+)*$").matches(soc.trim().uppercase(Locale.ROOT))

    fun supportsDevice(profile: Profile, manufacturer: String, model: String,
                       soc: String, sdk: Int, abis: List<String>): Boolean {
        if (sdk < 31 || "arm64-v8a" !in abis ||
            manufacturer.trim().lowercase(Locale.ROOT) != "samsung") return false
        val phone = model.trim().uppercase(Locale.ROOT)
        val expectedSoc = when (profile) {
            Profile.GPU -> if (phone == "SM-S928U") "SM8650" else return false
            Profile.NPU -> when (phone) {
                "SM-S948U" -> "SM8850"
                // Upstream v79 support; physical S25 acceptance testing still required.
                "SM-S931U", "SM-S936U", "SM-S938U" -> "SM8750"
                else -> return false
            }
        }
        return Regex("^$expectedSoc(?:-[A-Z0-9]+)*$")
                .matches(soc.trim().uppercase(Locale.ROOT))
    }

    fun isSupported(profile: Profile = Profile.NPU): Boolean {
        if (BuildConfig.FLAVOR == "qualification") {
            val selected = qualificationBackend ?: if (Build.SOC_MODEL.startsWith("SM8650")) Profile.GPU else Profile.NPU
            return selected == profile && !isEmulator() && Build.VERSION.SDK_INT >= 31 &&
                "arm64-v8a" in Build.SUPPORTED_ABIS && supportsCandidate(profile, Build.SOC_MODEL)
        }
        return supportsDevice(profile, Build.MANUFACTURER, Build.MODEL, Build.SOC_MODEL,
            Build.VERSION.SDK_INT, Build.SUPPORTED_ABIS.toList())
    }

    fun npuProfile(): String = if (Build.SOC_MODEL.trim().uppercase(Locale.ROOT)
        .startsWith("SM8750")) "gemma4-hexagon-v79" else "gemma4-hexagon-v81"
}
