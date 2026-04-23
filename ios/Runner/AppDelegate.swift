import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler {
  
  private var eventSink: FlutterEventSink?
  private var amplitudeTimer: Timer?
  private var audioRecorder: AVAudioRecorder? // Would be initialized when recording starts

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // Configure AVAudioSession for background audio
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
      try session.setActive(true)
    } catch {
      print("Failed to configure AVAudioSession: \(error)")
    }

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
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

    let amplitudeChannel = FlutterEventChannel(name: "kraken.kernel/audio/amplitude",
                                               binaryMessenger: controller.binaryMessenger)
    amplitudeChannel.setStreamHandler(self)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

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
}
