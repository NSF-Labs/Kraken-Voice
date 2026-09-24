package org.krak_en.voice

import android.content.Context
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Only the selected runtime is constructed; an initialization failure never selects CPU. */
object InferenceBridgeFactory {
    fun create(context: Context): InferenceBridge = when {
        ReleaseHardware.isSupported(ReleaseHardware.Profile.GPU) -> LiteRtGpuBridge(context)
        ReleaseHardware.isSupported(ReleaseHardware.Profile.NPU) -> HexagonBridge(context)
        else -> UnsupportedInferenceBridge()
    }
}

private class UnsupportedInferenceBridge : InferenceBridge {
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {}
    override fun onCancel(arguments: Any?) {}
    override fun close() {}
    override fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "deviceSupport") result.success(mapOf("supported" to false))
        else result.error("UNSUPPORTED_DEVICE", "No enabled accelerated AI profile for this phone.", null)
    }
}
