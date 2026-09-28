import Flutter
import UIKit
import AVFoundation
import CryptoKit
import os

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler, AVAudioRecorderDelegate {
  private var recorder: AVAudioRecorder?
  private var amplitudeSink: FlutterEventSink?
  private var audioChannel: FlutterMethodChannel?
  private var meterTimer: Timer?
  private var limitSeconds: Double = 1200
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var starting = false
  private var gemma: KrakenGemmaBridge?

  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    NotificationCenter.default.addObserver(self, selector: #selector(interrupted),
      name: AVAudioSession.interruptionNotification, object: nil)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KrakenIOS") else { return }
    let messenger = registrar.messenger()
    gemma = KrakenGemmaBridge(messenger: messenger)
    FlutterMethodChannel(name: "kraken.kernel/models", binaryMessenger: messenger).setMethodCallHandler { call, result in
      guard call.method == "installBundledWhisper",
            let args = call.arguments as? [String: Any],
            let destination = args["path"] as? String else {
        result(FlutterMethodNotImplemented); return
      }
      let key = registrar.lookupKey(forAsset: "assets/models/ggml-base.bin")
      let source = Bundle.main.bundleURL.appendingPathComponent(key)
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let data = try Data(contentsOf: source, options: .mappedIfSafe)
          let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
          guard hash == "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe" else {
            throw NSError(domain: "KrakenModels", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bundled Whisper verification failed"])
          }
          let target = URL(fileURLWithPath: destination)
          try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
          try data.write(to: target, options: .atomic)
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          var installed = target
          try installed.setResourceValues(values)
          DispatchQueue.main.async { result(nil) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "MODEL_SETUP_FAILED", message: error.localizedDescription, details: nil)) }
        }
      }
    }

    let channel = FlutterMethodChannel(name: "kraken.kernel/audio", binaryMessenger: messenger)
    audioChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterError(code: "UNAVAILABLE", message: "Audio engine unavailable", details: nil)); return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "startRecording": self.start(args, result)
      case "stopRecording": result(self.stop())
      case "pauseRecording": self.recorder?.pause(); result(nil)
      case "resumeRecording":
        do {
          try AVAudioSession.sharedInstance().setActive(true)
          guard self.recorder?.record() == true else { throw NSError(domain: "KrakenAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not resume recording"]) }
          result(nil)
        } catch { result(FlutterError(code: "RESUME_FAILED", message: error.localizedDescription, details: nil)) }
      case "setRecordingLimit": self.limitSeconds = (args["seconds"] as? NSNumber)?.doubleValue ?? 1200; result(nil)
      case "getDuration":
        guard let path = args["path"] as? String else { result(0); return }
        do { let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)); result(Int(player.duration * 1000)) }
        catch { result(FlutterError(code: "DURATION_FAILED", message: error.localizedDescription, details: nil)) }
      default: result(FlutterMethodNotImplemented)
      }
    }
    FlutterEventChannel(name: "kraken.kernel/audio/amplitude", binaryMessenger: messenger).setStreamHandler(self)
    FlutterMethodChannel(name: "kraken.kernel/audio/devices", binaryMessenger: messenger).setMethodCallHandler { call, result in
      let session = AVAudioSession.sharedInstance()
      switch call.method {
      case "getInputDevices":
        result((session.availableInputs ?? []).map { port in [
          "id": port.uid, "name": port.portName,
          "type": port.portType == .bluetoothHFP ? "bluetooth" : port.portType == .usbAudio ? "usb" : port.portType == .headsetMic ? "wired" : "builtin",
          "isActive": session.currentRoute.inputs.contains { $0.uid == port.uid }
        ] as [String: Any] })
      case "selectInputDevice":
        let uid = (call.arguments as? [String: Any])?["deviceId"] as? String
        let port = session.availableInputs?.first { $0.uid == uid }
        if uid != nil && port == nil { result(FlutterError(code: "DEVICE_NOT_FOUND", message: "Audio input disconnected", details: nil)); return }
        do { try session.setPreferredInput(port); result(nil) }
        catch { result(FlutterError(code: "SELECT_FAILED", message: error.localizedDescription, details: nil)) }
      default: result(FlutterMethodNotImplemented)
      }
    }
    FlutterEventChannel(name: "kraken.kernel/audio/devices/hotplug", binaryMessenger: messenger).setStreamHandler(RouteEvents())
    FlutterMethodChannel(name: "kraken.kernel/processing", binaryMessenger: messenger).setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterMethodNotImplemented); return }
      switch call.method {
      case "start":
        if self.backgroundTask == .invalid {
          self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Kraken processing") { [weak self] in self?.endBackgroundTask() }
        }
        result(nil)
      case "stop": self.endBackgroundTask(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func start(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard recorder == nil && !starting else { result(FlutterError(code: "ALREADY_RECORDING", message: "A recording is already active", details: nil)); return }
    starting = true
    AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
      DispatchQueue.main.async {
        guard let self else { result(FlutterError(code: "UNAVAILABLE", message: "Audio engine unavailable", details: nil)); return }
        self.starting = false
        guard granted else { result(FlutterError(code: "MICROPHONE_DENIED", message: "Allow microphone access in Settings to record.", details: nil)); return }
        do {
          let session = AVAudioSession.sharedInstance()
          try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
          try session.setActive(true)
          let folder = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("recordings", isDirectory: true)
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          let url = folder.appendingPathComponent("recording_\(UUID().uuidString).m4a")
          let recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
          ])
          recorder.delegate = self
          recorder.isMeteringEnabled = true
          guard recorder.prepareToRecord(), recorder.record() else { throw NSError(domain: "KrakenAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not start microphone recording"]) }
          self.recorder = recorder
          self.limitSeconds = (args["limitSeconds"] as? NSNumber)?.doubleValue ?? 1200
          self.meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder, recorder.isRecording else { return }
            recorder.updateMeters()
            self.amplitudeSink?(Double(recorder.averagePower(forChannel: 0)))
            if self.limitSeconds > 0 && recorder.currentTime >= self.limitSeconds { self.finishFromSystem() }
          }
          result(url.path)
        } catch {
          try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
          result(FlutterError(code: "RECORD_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func stop() -> String? {
    let path = recorder?.url.path
    recorder?.stop()
    recorder = nil
    meterTimer?.invalidate()
    meterTimer = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    return path
  }

  private func finishFromSystem() {
    guard let recorder else { return }
    let duration = Int(recorder.currentTime * 1000)
    _ = stop()
    audioChannel?.invokeMethod("onNotificationStop", arguments: ["durationMs": duration])
  }

  @objc private func interrupted(_ notification: Notification) {
    guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          type == AVAudioSession.InterruptionType.began.rawValue, recorder != nil else { return }
    // Preserve the file on calls/Siri/audio interruptions instead of silently recording nothing.
    finishFromSystem()
  }

  func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) { finishFromSystem() }
  private func endBackgroundTask() {
    if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { amplitudeSink = events; return nil }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { amplitudeSink = nil; return nil }
}

private class RouteEvents: NSObject, FlutterStreamHandler {
  private var observer: NSObjectProtocol?
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    observer = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { _ in events("changed") }
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    return nil
  }
}

import Gemma4Swift
import MLX
import MLXLMCommon

/// Kraken's iOS Gemma bridge uses the same pinned runtime as FWPlanner.
/// A completion marker prevents interrupted downloads being treated as ready.
private final class KrakenGemmaBridge: NSObject, FlutterStreamHandler {
  private var pipeline: Gemma4Pipeline?
  private var tokenizer: (any MLXLMCommon.Tokenizer)?
  private var sink: FlutterEventSink?
  private var generation: Task<Void, Never>?
  private var download: Task<Void, Never>?
  private var loading = false
  private var downloadProgress = 0.0
  private var downloadError: String?
  private let channel: FlutterMethodChannel
  private let modelURL: URL
  private var marker: URL { modelURL.appendingPathComponent("kraken-complete") }
  private var supported: Bool {
    #if targetEnvironment(simulator)
    return false
    #else
    return ProcessInfo.processInfo.physicalMemory >= 6 * 1024 * 1024 * 1024
    #endif
  }
  private var ready: Bool { FileManager.default.fileExists(atPath: marker.path) && Gemma4ModelCache.isDownloaded(.e2b4bit) }
  private var unsupportedReason: String {
    #if targetEnvironment(simulator)
    return "Gemma needs a physical device with Metal; simulator inference is unavailable."
    #else
    return "This Gemma model needs at least 6 GB of device memory. Whisper transcription remains available."
    #endif
  }

  init(messenger: FlutterBinaryMessenger) {
    let models = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("models")
    Gemma4ModelCache.customModelsDirectory = models
    modelURL = models.appendingPathComponent("mlx-community/gemma-4-e2b-it-4bit")
    channel = FlutterMethodChannel(name: "kraken.kernel/inference", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in self?.handle(call, result) }
    }
    FlutterEventChannel(name: "kraken.kernel/inference/stream", binaryMessenger: messenger).setStreamHandler(self)
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { sink = events; return nil }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }
  private func failure(_ error: Error) -> FlutterError { FlutterError(code: "GEMMA_FAILED", message: error.localizedDescription, details: nil) }

  private func memoryStatus() -> [String: Any] {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return ["physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
            "availableMemoryBytes": os_proc_available_memory(),
            "processFootprintBytes": status == KERN_SUCCESS ? info.phys_footprint : 0,
            "mlxActiveBytes": MLX.Memory.activeMemory,
            "mlxPeakBytes": MLX.Memory.peakMemory,
            "mlxCacheBytes": MLX.Memory.cacheMemory]
  }

  @MainActor private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "memoryStatus": result(memoryStatus())
    case "modelStatus":
      result(["supported": supported, "ready": ready, "downloading": download != nil,
              "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
              "availableMemoryBytes": os_proc_available_memory(),
              "progress": downloadProgress, "error": downloadError as Any? ?? NSNull(),
              "reason": supported ? "" : unsupportedReason, "path": modelURL.path])
    case "downloadModel":
      guard supported else { result(FlutterError(code: "UNSUPPORTED_DEVICE", message: unsupportedReason, details: nil)); return }
      guard download == nil, !ready else { result(nil); return }
      downloadError = nil
      downloadProgress = 0
      download = Task { @MainActor in
        let previousIdleSetting = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
          self.download = nil
          UIApplication.shared.isIdleTimerDisabled = previousIdleSetting
        }
        do {
          let url = try await Gemma4ModelDownloader.download(.e2b4bit, force: true) { progress in
            Task { @MainActor in self.downloadProgress = progress.fraction }
          }
          try Task.checkCancellation()
          // Validate tokenizer too; config + one shard alone isn't sufficient.
          _ = try await Gemma4TokenizerLoader().load(from: url)
          try Data("gemma-4-e2b-it-4bit".utf8).write(to: self.marker, options: .atomic)
          var cached = url
          var values = URLResourceValues(); values.isExcludedFromBackup = true
          try cached.setResourceValues(values)
          self.downloadProgress = 1
        } catch { self.downloadError = error.localizedDescription }
      }
      result(nil)
    case "cancelDownload": download?.cancel(); result(nil)
    case "loadModel":
      guard supported else { result(FlutterError(code: "UNSUPPORTED_DEVICE", message: unsupportedReason, details: nil)); return }
      guard ready else { result(FlutterError(code: "MODEL_MISSING", message: "Install Gemma in AI Models first.", details: nil)); return }
      if pipeline?.isReady == true { result(nil); return }
      guard !loading else { result(FlutterError(code: "MODEL_BUSY", message: "Gemma is loading. Try again shortly.", details: nil)); return }
      loading = true
      Task { @MainActor in
        defer { self.loading = false }
        do {
          // MLX's default allocator cache can retain large prefill temporaries.
          MLX.Memory.cacheLimit = 64 * 1024 * 1024
          MLX.Memory.clearCache()
          let p = Gemma4Pipeline()
          try await withError { try await p.load(from: self.modelURL, multimodal: false) }
          self.tokenizer = try await Gemma4TokenizerLoader().load(from: self.modelURL)
          self.pipeline = p
          result(nil)
        } catch { self.pipeline = nil; result(self.failure(error)) }
      }
    case "countTokens":
      guard let tokenizer else { result(FlutterError(code: "NO_MODEL", message: "Load Gemma before counting tokens.", details: nil)); return }
      // Include conservative chat-template overhead in the 4096-token budget.
      result(tokenizer.encode(text: args["prompt"] as? String ?? "", addSpecialTokens: true).count + 64)
    case "generate":
      guard let pipeline, pipeline.isReady, let tokenizer else { result(FlutterError(code: "NO_MODEL", message: "Gemma is not loaded.", details: nil)); return }
      guard generation == nil else { result(FlutterError(code: "MODEL_BUSY", message: "Gemma is generating.", details: nil)); return }
      let prompt = args["prompt"] as? String ?? ""
      let maxTokens = min(2048, max(1, args["maxTokens"] as? Int ?? 1024))
      guard tokenizer.encode(text: prompt, addSpecialTokens: true).count + maxTokens + 64 <= 4096 else {
        result(FlutterError(code: "CONTEXT_EXCEEDED", message: "The prompt exceeds the iOS context budget.", details: nil)); return
      }
      generation = Task { @MainActor in
        defer { self.generation = nil }
        do {
          let text = try await withError {
            try await pipeline.chat(prompt: prompt, systemPrompt: "You are a helpful assistant. Follow the user's requested format and language.", maxTokens: maxTokens)
          }
          try Task.checkCancellation()
          self.sink?(["text": text, "isDone": false])
          self.sink?(["text": "", "isDone": true])
        } catch { self.sink?(self.failure(error)) }
      }
      result(nil)
    case "cancelGeneration": generation?.cancel(); result(nil)
    case "unloadModel":
      let task = generation
      task?.cancel()
      Task { @MainActor in
        await task?.value
        self.pipeline?.unload(); self.pipeline = nil; self.tokenizer = nil
        result(nil)
      }
    case "isModelLoaded": result(pipeline?.isReady == true)
    default: result(FlutterMethodNotImplemented)
    }
  }
}
