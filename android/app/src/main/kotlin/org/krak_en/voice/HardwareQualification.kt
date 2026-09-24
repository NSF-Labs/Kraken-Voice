package org.krak_en.voice

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import java.io.File

/** Read-only metrics. No serial, accounts, recordings or user documents. */
object HardwareQualification {
    fun snapshot(context: Context): Map<String, Any?> {
        val mem = ActivityManager.MemoryInfo()
        (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(mem)
        val process = Debug.MemoryInfo().also { Debug.getMemoryInfo(it) }
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val temperature = battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return mapOf(
            "qualificationBuild" to true,
            "appBuild" to ReleaseHardware.BUILD,
            "manufacturer" to Build.MANUFACTURER, "model" to Build.MODEL,
            "soc" to Build.SOC_MODEL, "android" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT, "firmware" to Build.FINGERPRINT,
            "abis" to Build.SUPPORTED_ABIS.toList(), "emulator" to ReleaseHardware.isEmulator(),
            "gpu" to runCatching { File("/sys/class/kgsl/kgsl-3d0/gpu_model").readText().trim() }.getOrNull(),
            "loadedDriverLibraries" to runCatching { File("/proc/self/maps").readLines()
                .filter { it.contains("libOpenCL") || it.contains("libcdsprpc") }
                .map { it.substringAfterLast(' ') }.distinct() }.getOrNull(),
            "totalRamBytes" to mem.totalMem, "availableRamBytes" to mem.availMem,
            "processPssKb" to process.totalPss,
            "thermalStatus" to power.currentThermalStatus,
            "batteryTemperatureC" to if (temperature != null && temperature != Int.MIN_VALUE) temperature / 10.0 else null,
            "pluggedIn" to (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0),
            "productionEligible" to ReleaseHardware.Profile.entries.any {
                ReleaseHardware.supportsDevice(it, Build.MANUFACTURER, Build.MODEL,
                    Build.SOC_MODEL, Build.VERSION.SDK_INT, Build.SUPPORTED_ABIS.toList())
            },
            "candidateBackends" to if (ReleaseHardware.isEmulator()) emptyList<String>() else
                ReleaseHardware.Profile.entries.filter { ReleaseHardware.supportsCandidate(it, Build.SOC_MODEL) }.map { it.name })
    }
}
