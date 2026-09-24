package org.krak_en.voice

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Handles audio input device enumeration, selection, and hot-plug detection.
 *
 * Channels:
 *   MethodChannel: "kraken.kernel/audio/devices"
 *     - getInputDevices → List<Map>
 *     - selectInputDevice(deviceId: String?) → null
 *
 *   EventChannel: "kraken.kernel/audio/devices/hotplug"
 *     - Sends "changed" on device connect/disconnect
 */
class AudioDeviceHandler(private val context: Context) {

    private val audioManager: AudioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var eventSink: EventChannel.EventSink? = null
    private var selectedDeviceId: Int? = null

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
            eventSink?.success("changed")
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            // If our selected device was removed, reset to default
            if (selectedDeviceId != null) {
                val stillExists = getInputDevices().any { it.id == selectedDeviceId }
                if (!stillExists) {
                    selectedDeviceId = null
                }
            }
            eventSink?.success("changed")
        }
    }

    /** Set up the MethodChannel and EventChannel on the Flutter engine. */
    fun setupChannels(
        methodChannel: MethodChannel,
        eventChannel: EventChannel
    ) {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInputDevices" -> {
                    val devices = getInputDevices().map { device ->
                        mapOf(
                            "id" to device.id.toString(),
                            "name" to getDeviceName(device),
                            "type" to getDeviceTypeString(device),
                            "isActive" to (device.id == selectedDeviceId)
                        )
                    }
                    result.success(devices)
                }
                "selectInputDevice" -> {
                    val deviceIdStr = call.argument<String>("deviceId")
                    selectedDeviceId = deviceIdStr?.toIntOrNull()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                audioManager.registerAudioDeviceCallback(
                    deviceCallback,
                    Handler(Looper.getMainLooper())
                )
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
                audioManager.unregisterAudioDeviceCallback(deviceCallback)
            }
        })
    }

    /** Get the currently selected device ID, or null for system default. */
    fun getSelectedDeviceId(): Int? = selectedDeviceId

    /** Find the AudioDeviceInfo for the selected device, if any. */
    fun getSelectedDevice(): AudioDeviceInfo? {
        val id = selectedDeviceId ?: return null
        return getInputDevices().firstOrNull { it.id == id }
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private fun getInputDevices(): List<AudioDeviceInfo> {
        return audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
            .filter { isRelevantInputDevice(it) }
            .toList()
    }

    private fun isRelevantInputDevice(device: AudioDeviceInfo): Boolean {
        return when (device.type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> true
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> true
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> true
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> true
            AudioDeviceInfo.TYPE_USB_DEVICE -> true
            AudioDeviceInfo.TYPE_USB_HEADSET -> true
            AudioDeviceInfo.TYPE_USB_ACCESSORY -> true
            else -> {
                // Android 12+ BLE audio
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    device.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                    device.type == AudioDeviceInfo.TYPE_BLE_SPEAKER
                } else {
                    false
                }
            }
        }
    }

    private fun getDeviceName(device: AudioDeviceInfo): String {
        // ProductName is available API 28+ and is usually more descriptive
        val productName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            device.productName?.toString()?.takeIf { it.isNotBlank() && it != "0" }
        } else null

        return productName ?: getTypeLabel(device)
    }

    private fun getTypeLabel(device: AudioDeviceInfo): String {
        return when (device.type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Built-in Microphone"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth (SCO)"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth (A2DP)"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired Headset"
            AudioDeviceInfo.TYPE_USB_DEVICE -> "USB Audio Device"
            AudioDeviceInfo.TYPE_USB_HEADSET -> "USB Headset"
            AudioDeviceInfo.TYPE_USB_ACCESSORY -> "USB Accessory"
            else -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    when (device.type) {
                        AudioDeviceInfo.TYPE_BLE_HEADSET -> "BLE Headset"
                        AudioDeviceInfo.TYPE_BLE_SPEAKER -> "BLE Speaker"
                        else -> "Audio Device (${device.type})"
                    }
                } else {
                    "Audio Device (${device.type})"
                }
            }
        }
    }

    private fun getDeviceTypeString(device: AudioDeviceInfo): String {
        return when (device.type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> "builtin"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired"
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_ACCESSORY -> "usb"
            else -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    when (device.type) {
                        AudioDeviceInfo.TYPE_BLE_HEADSET,
                        AudioDeviceInfo.TYPE_BLE_SPEAKER -> "bluetooth"
                        else -> "builtin"
                    }
                } else {
                    "builtin"
                }
            }
        }
    }
}
