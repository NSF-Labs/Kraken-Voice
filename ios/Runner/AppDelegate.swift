import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler {
  
  private var eventSink: FlutterEventSink?
  private var amplitudeTimer: Timer?
  private var audioRecorder: AVAudioRecorder? // Would be initialized when recording starts

  // Audio device hot-plug
  private var deviceEventSink: FlutterEventSink?
  private var selectedPortUID: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // Configure AVAudioSession for background audio
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
      try session.setActive(true)
    } catch {
      print("Failed to configure AVAudioSession: \(error)")
    }

    // Observe route changes for hot-plug events
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRouteChange),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController

    // ── Audio Recording Channel ──────────────────────────────────────────
    let audioChannel = FlutterMethodChannel(name: "kraken.kernel/audio",
                                              binaryMessenger: controller.binaryMessenger)
    audioChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      case "pauseRecording":
        self?.audioRecorder?.pause()
        result(nil)
      case "resumeRecording":
        self?.audioRecorder?.record()
        result(nil)
      // startRecording, stopRecording, transcribe handled elsewhere or need to be implemented
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    // ── Amplitude EventChannel ───────────────────────────────────────────
    let amplitudeChannel = FlutterEventChannel(name: "kraken.kernel/audio/amplitude",
                                               binaryMessenger: controller.binaryMessenger)
    amplitudeChannel.setStreamHandler(self)

    // ── Audio Device MethodChannel ───────────────────────────────────────
    let deviceMethodChannel = FlutterMethodChannel(
      name: "kraken.kernel/audio/devices",
      binaryMessenger: controller.binaryMessenger
    )
    deviceMethodChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      case "getInputDevices":
        result(self?.getInputDevices() ?? [])
      case "selectInputDevice":
        if let args = call.arguments as? [String: Any?] {
          let deviceId = args["deviceId"] as? String
          self?.selectInputDevice(portUID: deviceId, result: result)
        } else {
          self?.selectInputDevice(portUID: nil, result: result)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    // ── Audio Device Hot-plug EventChannel ────────────────────────────────
    let deviceEventChannel = FlutterEventChannel(
      name: "kraken.kernel/audio/devices/hotplug",
      binaryMessenger: controller.binaryMessenger
    )
    deviceEventChannel.setStreamHandler(DeviceHotplugStreamHandler(appDelegate: self))

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ── Amplitude Stream Handler ─────────────────────────────────────────────

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    self.amplitudeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      guard let self = self, let recorder = self.audioRecorder, recorder.isRecording else { return }
      recorder.updateMeters()
      let power = recorder.averagePower(forChannel: 0)
      self.eventSink?(Double(power))
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    self.amplitudeTimer?.invalidate()
    self.amplitudeTimer = nil
    return nil
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // ── Audio Device Methods ─────────────────────────────────────────────────

  private func getInputDevices() -> [[String: Any]] {
    let session = AVAudioSession.sharedInstance()
    guard let inputs = session.availableInputs else { return [] }

    return inputs.map { port in
      let isActive = (selectedPortUID != nil && port.uid == selectedPortUID) ||
                     (selectedPortUID == nil && session.currentRoute.inputs.contains(where: { $0.uid == port.uid }))
      return [
        "id": port.uid,
        "name": port.portName,
        "type": mapPortType(port.portType),
        "isActive": isActive
      ]
    }
  }

  private func selectInputDevice(portUID: String?, result: @escaping FlutterResult) {
    selectedPortUID = portUID
    let session = AVAudioSession.sharedInstance()

    guard let uid = portUID else {
      // Reset to system default
      do {
        try session.setPreferredInput(nil)
        result(nil)
      } catch {
        result(FlutterError(code: "SELECT_FAILED", message: error.localizedDescription, details: nil))
      }
      return
    }

    guard let inputs = session.availableInputs,
          let target = inputs.first(where: { $0.uid == uid }) else {
      result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No input with UID \(uid)", details: nil))
      return
    }

    do {
      try session.setPreferredInput(target)
      print("[Kraken] Selected input: \(target.portName)")
      result(nil)
    } catch {
      result(FlutterError(code: "SELECT_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  private func mapPortType(_ portType: AVAudioSession.Port) -> String {
    switch portType {
    case .builtInMic:
      return "builtin"
    case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
      return "bluetooth"
    case .headsetMic, .headphones:
      return "wired"
    case .usbAudio:
      return "usb"
    default:
      return "builtin"
    }
  }

  // ── Route Change Observer ────────────────────────────────────────────────

  @objc private func handleRouteChange(notification: Notification) {
    // If the selected device was disconnected, reset to system default
    if let portUID = selectedPortUID {
      let session = AVAudioSession.sharedInstance()
      let stillExists = session.availableInputs?.contains(where: { $0.uid == portUID }) ?? false
      if !stillExists {
        selectedPortUID = nil
      }
    }
    deviceEventSink?("changed")
  }

  /// Called by DeviceHotplugStreamHandler to set/clear the device event sink
  func setDeviceEventSink(_ sink: FlutterEventSink?) {
    deviceEventSink = sink
  }
}

/// Separate StreamHandler for device hot-plug events (since AppDelegate
/// already implements FlutterStreamHandler for amplitude).
class DeviceHotplugStreamHandler: NSObject, FlutterStreamHandler {
  private weak var appDelegate: AppDelegate?

  init(appDelegate: AppDelegate) {
    self.appDelegate = appDelegate
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    appDelegate?.setDeviceEventSink(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    appDelegate?.setDeviceEventSink(nil)
    return nil
  }
}
