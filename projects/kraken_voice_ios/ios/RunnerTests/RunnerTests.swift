import Flutter
import UIKit
import XCTest
import AVFoundation
import file_picker

@MainActor
class RunnerTests: XCTestCase {
  private func openAudioPicker(_ result: @escaping FlutterResult) async throws -> (FilePickerPlugin, UIDocumentPickerViewController) {
    let plugin = FilePickerPlugin()
    // Give the Flutter host's root window time to appear on physical hardware.
    for _ in 0..<100 {
      if UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
        .flatMap(\.windows).contains(where: { $0.isKeyWindow && $0.rootViewController != nil }) { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    plugin.handle(FlutterMethodCall(methodName: "audio", arguments: [
      "allowMultipleSelection": false, "withData": false, "allowCompression": false,
    ]), result: result)
    let picker = try XCTUnwrap(plugin.value(forKey: "documentPickerController") as? UIDocumentPickerViewController)
    for _ in 0..<100 {
      if picker.viewIfLoaded?.window != nil && !picker.isBeingPresented && picker.transitionCoordinator == nil { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertNotNil(picker.viewIfLoaded?.window, "The Files picker must actually be presented")
    XCTAssertEqual(plugin.value(forKey: "allowedExtensions") as? [String], ["public.audio"])
    XCTAssertFalse(picker.allowsMultipleSelection)
    XCTAssertNil(plugin.value(forKey: "audioPickerController"), "Must not request Apple Music access")
    return (plugin, picker)
  }

  private func waitForDismissal(_ picker: UIDocumentPickerViewController) async throws {
    for _ in 0..<100 {
      if picker.presentingViewController == nil && picker.viewIfLoaded?.window == nil { return }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTFail("Picker dismissal did not finish")
  }

  func testAudioPickerPresentsFilesAndCancels() async throws {
    let returned = expectation(description: "Picker cancellation returns nil")
    let (plugin, picker) = try await openAudioPicker { value in
      XCTAssertNil(value)
      returned.fulfill()
    }
    picker.delegate?.documentPickerWasCancelled?(picker)
    await fulfillment(of: [returned], timeout: 5)
    withExtendedLifetime(plugin) {}
    try await waitForDismissal(picker)
  }

  func testAudioPickerImportsPlayableFixture() async throws {
    let fixture = Bundle.main.bundleURL.appendingPathComponent("Frameworks/App.framework/flutter_assets/assets/qa/whisper_check.m4a")
    let bytes = try Data(contentsOf: fixture)
    let inbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    let selected = inbox.appendingPathComponent("kraken-import-test-\(UUID().uuidString).m4a")
    try bytes.write(to: selected)
    defer { try? FileManager.default.removeItem(at: inbox) }
    let returned = expectation(description: "Imported audio returns a cached file path")
    var importedPath: String?
    let (plugin, picker) = try await openAudioPicker { value in
      let files = value as? [[String: Any]]
      XCTAssertEqual(files?.count, 1)
      importedPath = files?.first?["path"] as? String
      returned.fulfill()
    }
    // Supply a synthetic provider result to the real native import delegate.
    // Actual provider navigation and cloud downloads remain manual acceptance.
    picker.delegate?.documentPicker?(picker, didPickDocumentsAt: [selected])
    await fulfillment(of: [returned], timeout: 5)
    withExtendedLifetime(plugin) {}
    let cached = URL(fileURLWithPath: try XCTUnwrap(importedPath))
    defer { try? FileManager.default.removeItem(at: cached) }
    XCTAssertEqual(try Data(contentsOf: cached), bytes)
    let stored = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("kraken-import-test-\(UUID().uuidString).m4a")
    try FileManager.default.copyItem(at: cached, to: stored)
    defer { try? FileManager.default.removeItem(at: stored) }
    let player = try AVAudioPlayer(contentsOf: stored)
    XCTAssertGreaterThan(player.duration, 1)
    XCTAssertTrue(player.prepareToPlay())
    try await waitForDismissal(picker)
  }
}
