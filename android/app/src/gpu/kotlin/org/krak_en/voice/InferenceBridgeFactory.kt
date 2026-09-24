package org.krak_en.voice
import android.content.Context
object InferenceBridgeFactory {
    fun create(context: Context): InferenceBridge = LiteRtGpuBridge(context)
}
