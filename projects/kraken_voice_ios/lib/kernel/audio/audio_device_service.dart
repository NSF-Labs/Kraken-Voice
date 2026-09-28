import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Represents an audio input device available on the system.
class AudioInputDevice {
  /// Platform-specific device ID (Android: int → String, iOS: portUID).
  final String id;

  /// Human-readable name (e.g. "Built-in Microphone", "Galaxy Buds2 Pro").
  final String name;

  /// Device type classification for icon rendering.
  final AudioDeviceType type;

  /// Whether this device is currently the active/selected input.
  final bool isActive;

  const AudioInputDevice({
    required this.id,
    required this.name,
    required this.type,
    this.isActive = false,
  });

  factory AudioInputDevice.fromMap(Map<String, dynamic> map) {
    return AudioInputDevice(
      id: map['id']?.toString() ?? '',
      name: map['name'] as String? ?? 'Unknown',
      type: _parseType(map['type'] as String? ?? 'builtin'),
      isActive: map['isActive'] as bool? ?? false,
    );
  }

  static AudioDeviceType _parseType(String raw) {
    switch (raw) {
      case 'bluetooth':
        return AudioDeviceType.bluetooth;
      case 'usb':
        return AudioDeviceType.usb;
      case 'wired':
        return AudioDeviceType.wired;
      case 'builtin':
      default:
        return AudioDeviceType.builtin;
    }
  }

  @override
  String toString() => 'AudioInputDevice($name, type=$type, active=$isActive)';
}

enum AudioDeviceType { builtin, bluetooth, usb, wired }

/// Reactive service for enumerating and selecting audio input devices.
///
/// Uses platform channels:
///   - MethodChannel: `kraken.kernel/audio/devices` (enumerate, select)
///   - EventChannel: `kraken.kernel/audio/devices/hotplug` (connect/disconnect)
class AudioDeviceService {
  static final AudioDeviceService _instance = AudioDeviceService._();
  factory AudioDeviceService() => _instance;
  AudioDeviceService._();

  final MethodChannel _channel =
      const MethodChannel('kraken.kernel/audio/devices');
  final EventChannel _hotplugChannel =
      const EventChannel('kraken.kernel/audio/devices/hotplug');

  /// Current list of available input devices, refreshed on hot-plug events.
  final ValueNotifier<List<AudioInputDevice>> devices =
      ValueNotifier(const []);

  /// The currently selected device ID. Null means system default.
  final ValueNotifier<String?> selectedDeviceId = ValueNotifier(null);

  StreamSubscription? _hotplugSub;
  bool _initialized = false;

  /// Initialize the service: fetch initial device list and start listening
  /// for hot-plug events.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await refreshDevices();

    _hotplugSub = _hotplugChannel.receiveBroadcastStream().listen(
      (event) {
        debugPrint('[AudioDeviceService] Hot-plug event received');
        refreshDevices();
      },
      onError: (e) {
        debugPrint('[AudioDeviceService] Hot-plug stream error: $e');
      },
    );
  }

  /// Fetch the current list of audio input devices from the platform.
  Future<List<AudioInputDevice>> refreshDevices() async {
    try {
      final result = await _channel.invokeListMethod<Map>('getInputDevices');
      final list = result
              ?.map((m) =>
                  AudioInputDevice.fromMap(Map<String, dynamic>.from(m)))
              .toList() ??
          [];
      devices.value = list;

      // Update selectedDeviceId if the active device changed
      final active = list.where((d) => d.isActive).firstOrNull;
      if (active != null && selectedDeviceId.value != active.id) {
        selectedDeviceId.value = active.id;
      }

      debugPrint(
          '[AudioDeviceService] Found ${list.length} device(s): ${list.map((d) => d.name).join(', ')}');
      return list;
    } on PlatformException catch (e) {
      debugPrint('[AudioDeviceService] getInputDevices failed: ${e.message}');
      return [];
    } on MissingPluginException {
      debugPrint(
          '[AudioDeviceService] Platform channel not available (desktop?)');
      return [];
    }
  }

  /// Select a specific audio input device by its platform ID.
  /// Pass `null` to reset to the system default.
  Future<bool> selectDevice(String? deviceId) async {
    try {
      await _channel.invokeMethod('selectInputDevice', {
        'deviceId': deviceId,
      });
      selectedDeviceId.value = deviceId;
      // Refresh to update isActive flags
      await refreshDevices();
      return true;
    } on PlatformException catch (e) {
      debugPrint('[AudioDeviceService] selectInputDevice failed: ${e.message}');
      return false;
    }
  }

  /// Get the label for the currently selected device, or a default.
  String get selectedDeviceLabel {
    final id = selectedDeviceId.value;
    if (id == null) return 'System Default';
    final device = devices.value.where((d) => d.id == id).firstOrNull;
    return device?.name ?? 'System Default';
  }

  void dispose() {
    _hotplugSub?.cancel();
    _hotplugSub = null;
    _initialized = false;
  }
}
