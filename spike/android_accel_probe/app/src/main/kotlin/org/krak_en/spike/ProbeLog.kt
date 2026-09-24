package org.krak_en.spike

import android.util.Log

object ProbeLog {
    private const val TAG = "KRAKEN_ACCEL_PROBE"

    fun log(fields: Map<String, Any?>) {
        val body = fields.entries.joinToString(", ") { (k, v) ->
            val value = when (v) {
                null -> "null"
                is String -> "\"${v.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")}\""
                is Boolean, is Number -> v.toString()
                else -> "\"${v.toString().replace("\"", "\\\"")}\""
            }
            "\"$k\":$value"
        }
        Log.i(TAG, "{$body}")
    }
}
