package org.krak_en.voice
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
interface InferenceBridge : EventChannel.StreamHandler {
    fun diagnostics(): Map<String, Any?> = emptyMap()
    fun handle(call: MethodCall, result: MethodChannel.Result)
    fun close()
}
