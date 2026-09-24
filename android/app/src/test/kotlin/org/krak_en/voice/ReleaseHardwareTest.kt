package org.krak_en.voice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReleaseHardwareTest {
    private fun permits(profile: ReleaseHardware.Profile, model: String, soc: String,
                        manufacturer: String = "samsung", sdk: Int = 31,
                        abis: List<String> = listOf("arm64-v8a")) =
        ReleaseHardware.supportsDevice(profile, manufacturer, model, soc, sdk, abis)

    @Test fun permitsOnlyValidatedModelAndBackendPairs() {
        val npu = ReleaseHardware.Profile.NPU
        val gpu = ReleaseHardware.Profile.GPU
        assertTrue(permits(npu, "SM-S948U", "SM8850"))
        assertTrue(permits(gpu, "SM-S928U", "SM8650-AC"))
        assertFalse(permits(npu, "SM-S928U", "SM8650"))
        assertFalse(permits(gpu, "SM-S948U", "SM8850"))
        for (profile in ReleaseHardware.Profile.entries) {
            assertFalse(permits(profile, "SM-A236V", "SM6375"))
            assertFalse(permits(profile, "unknown", "SM8850"))
        }
        assertFalse(permits(npu, "SM-S948U1", "SM8850"))
        assertFalse(permits(gpu, "SM-S928B", "SM8650"))
        assertFalse(permits(npu, "SM-S948U", "SM8950"))
        assertFalse(permits(npu, "SM-S948U", "SM8850", manufacturer = "other"))
        assertFalse(permits(npu, "SM-S948U", "SM8850", sdk = 30))
        assertFalse(permits(npu, "SM-S948U", "SM8850", abis = listOf("armeabi-v7a")))
    }

    @Test fun permitsKnownFlagshipsAndSuffixVariants() {
        listOf("SM8850", "sm8850-ac", " SM8850-AB ").forEach {
            assertTrue(it, ReleaseHardware.supportsSoc(it))
        }
    }

    @Test fun excludesOlderUnrelatedAndUnknownChips() {
        listOf("SM8750", "sm8750-ac", "SM8950", "SM8650", "SM8550", "SM8735", "SM9999", "SM88500", "Exynos 2600", "", "unknown").forEach {
            assertFalse(it, ReleaseHardware.supportsSoc(it))
        }
    }
}
