import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RawOpenModeTests: XCTestCase {
  private func fixture(_ name: String = "raw-with-embedded-xmp.dng") throws -> Data {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    return try Data(contentsOf: folder.appendingPathComponent("Fixtures/Raw/" + name))
  }

  private func assertExactPixels(_ actual: Surface, _ expected: Surface,
    expectedSample: (Pixel) -> Pixel = { $0 }, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.width, expected.width, file: file, line: line)
    XCTAssertEqual(actual.height, expected.height, file: file, line: line)
    XCTAssertEqual(actual.depth, expected.depth, file: file, line: line)
    XCTAssertEqual(actual.colorEncoding, expected.colorEncoding, file: file, line: line)
    for y in 0..<min(actual.height, expected.height) {
      for x in 0..<min(actual.width, expected.width) {
        let a = actual.pixel(x: x, y: y)
        let e = expectedSample(expected.pixel(x: x, y: y))
        if !a.hasSameBits(as: e) {
          XCTFail("First differing sample at (\(x), \(y)) was \(a); expected \(e).", file: file, line: line)
          return
        }
      }
    }
  }

  func testShiftInvertsTheDefaultAndOptionSelectsCopy() {
    XCTAssertEqual(RawOpenShortcuts.mode(for: [], defaultAsObject: false), .image)
    XCTAssertEqual(RawOpenShortcuts.mode(for: [.shift, .command], defaultAsObject: false), .object)
    XCTAssertEqual(RawOpenShortcuts.mode(for: [], defaultAsObject: true), .object)
    XCTAssertEqual(RawOpenShortcuts.mode(for: [.shift, .command], defaultAsObject: true), .image)
    for defaultAsObject in [false, true] {
      XCTAssertEqual(RawOpenShortcuts.mode(for: [.option, .command], defaultAsObject: defaultAsObject), .copy)
    }
  }

  @MainActor func testLocalOpenModesKeepIdenticalPixelsAndSaveOnlyForImageAndObject() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let original = try fixture()
    let existingXMP = try fixture("camera-raw-sidecar-override.xmp")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }

    for mode in RawOpenMode.allCases {
      let raw = folder.appendingPathComponent(mode.rawValue + ".dng")
      let xmp = raw.deletingPathExtension().appendingPathExtension("xmp")
      try original.write(to: raw)
      try existingXMP.write(to: xmp)
      let prepared = try PreparedLocalDocument.read(raw, format: .raw, dngStorage: .sidecarXMP)
      let file = prepared.makeDocument(url: raw)
      controller.addDocument(file)
      XCTAssertTrue(controller.document(for: raw) === file)
      let store = file.store
      let workspace = CameraRawWorkspace()
      defer { workspace.close(); file.close(); store.renderTask?.cancel() }
      store.beginRawDevelopment()
      store.initialRawDocument = file
      let draft = try XCTUnwrap(store.filterDraft)
      await workspace.prepare(document: store.document, draft: draft, retainRawOutput: true)
      var adjusted = workspace.settings
      adjusted.exposure = 1.75
      workspace.change(adjusted)
      XCTAssertFalse(workspace.canOpen(in: store.document))
      await workspace.task?.value
      XCTAssertTrue(workspace.canOpen(in: store.document))
      let developed = try XCTUnwrap(workspace.developedRawPreview)
      try await file.finishRawOpen(mode, from: developed, layerID: draft.id)

      let result = store.document
      XCTAssertEqual(result.id, developed.id)
      XCTAssertEqual(result.depth, .u16)
      XCTAssertEqual(result.resolution, developed.resolution)
      XCTAssertEqual(result.sourceMetadata, developed.sourceMetadata)
      let rendered = try Renderer.composite(developed)
      assertExactPixels(try Renderer.composite(result), rendered) { sample in
        mode == .object ? sample : NormalLayerComposite.composite(backdrop: .clear, source: sample, depth: .u16)
      }
      XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertNil(store.filterDraft)
      XCTAssertNil(store.initialRawDocument)
      XCTAssertNil(file.fileURL)
      XCTAssertNil(controller.document(for: raw))
      XCTAssertEqual(try Data(contentsOf: raw), original)
      if mode == .copy {
        XCTAssertEqual(try Data(contentsOf: xmp), existingXMP)
      } else {
        XCTAssertEqual(try RawSourceIO.relatedSettings(for: raw)?.adjustments.exposure, 1.75)
      }
      if mode == .object {
        XCTAssertEqual(result.layers[0].smartObject?.data, original)
        XCTAssertEqual(result.layers[0].smartObject?.rawDevelopment?.adjustments.exposure, 1.75)
        XCTAssertTrue(file.canSaveRawSourceSettings(layerID: draft.id))
        XCTAssertEqual(file.displayName, mode.rawValue + "-1")
      } else {
        if case .raster(let converted) = result.layers[0].content,
          case .raster(let source) = developed.layers[0].content {
          assertExactPixels(converted, source)
        }
        XCTAssertTrue(result.layers[0].isBackground)
        XCTAssertEqual(result.layers[0].name, "Background")
        XCTAssertNil(result.layers[0].smartObject)
        XCTAssertTrue(result.isPositionLocked(draft.id))
        XCTAssertFalse(file.canSaveRawSourceSettings(layerID: draft.id))
        XCTAssertEqual(file.displayName, raw.lastPathComponent)
      }
      XCTAssertEqual(file.hasRevertSource, mode != .copy)
      do {
        try await file.persistDocument(to: raw, format: .native, operation: .saveAsOperation)
        XCTFail("Save As should protect the original sensor file.")
      } catch let error as CraftError {
        XCTAssertTrue(error.localizedDescription.contains("original Camera Raw"))
      }
      XCTAssertEqual(try Data(contentsOf: raw), original)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(result)), result)
    }
  }

  @MainActor func testFailedSourceWriteKeepsCameraRawOpenAndAllowsCopy() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let original = try fixture()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let raw = folder.appendingPathComponent("Replaced.dng")
    let xmp = folder.appendingPathComponent("Replaced.xmp")
    try original.write(to: raw)
    let file = try PreparedLocalDocument.read(raw, format: .raw, dngStorage: .sidecarXMP).makeDocument(url: raw)
    controller.addDocument(file)
    let store = file.store
    defer { file.close(); store.renderTask?.cancel() }
    store.beginRawDevelopment()
    store.initialRawDocument = file
    let draft = try XCTUnwrap(store.filterDraft)
    let before = store.document
    var altered = original
    altered.append(0)
    try altered.write(to: raw)
    do {
      try await file.finishRawOpen(.object, from: before, layerID: draft.id)
      XCTFail("A changed source should prevent Open Object from saving settings.")
    } catch RawDNGSource.SaveError.sourceChanged {}
    XCTAssertTrue(store.initialRawDocument === file)
    XCTAssertEqual(store.document, before)
    XCTAssertFalse(file.fileOperationBusy)
    XCTAssertFalse(FileManager.default.fileExists(atPath: xmp.path))
    try await file.finishRawOpen(.copy, from: before, layerID: draft.id)
    XCTAssertTrue(store.document.layers[0].isBackground)
    XCTAssertEqual(try Data(contentsOf: raw), altered)
    XCTAssertFalse(FileManager.default.fileExists(atPath: xmp.path))
  }

  @MainActor func testRawUploadModesShareTheNativeOutputsAndKeepObjectDefault() async throws {
    let original = try fixture()
    let sidecar = try fixture("camera-raw-sidecar-override.xmp")
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }) { service, initial in
      defer { for file in service.controller.documents where file !== initial { file.close() } }
      service.setDocumentTransfersEnabled(true)
      let helper = AutomationOpeningTests()
      let header = "X-Photato-Raw-Open-Mode"
      let xmp = ["X-Photato-Raw-XMP": sidecar.base64EncodedString()]
      let invalidMode = try await helper.upload(service, bytes: original, type: "image/x-adobe-dng",
        headers: [header: "bogus"])
      XCTAssertEqual(invalidMode.0.statusCode, 400)
      let invalidType = try await helper.upload(service, bytes: original, type: "image/png",
        headers: [header: "copy"])
      XCTAssertEqual(invalidType.0.statusCode, 415)
      let invalidBytes = try await helper.upload(service, bytes: Data([1, 2, 3]), type: "image/x-adobe-dng",
        headers: [header: "image"])
      XCTAssertEqual(invalidBytes.0.statusCode, 422)
      XCTAssertTrue(service.shares.isEmpty)

      let baseline = try await helper.upload(service, bytes: original, type: "image/x-adobe-dng", headers: xmp)
      XCTAssertEqual(baseline.0.statusCode, 201)
      let baselineFile = try XCTUnwrap(service.shares.last?.document)
      let reference = try Renderer.composite(baselineFile.store.document)
      XCTAssertEqual(baselineFile.store.document.layers[0].smartObject?.data, original)

      for mode in RawOpenMode.allCases {
        let response = try await helper.upload(service, bytes: original, type: "application/octet-stream",
          format: "raw", headers: xmp.merging([header: mode.rawValue]) { _, new in new })
        XCTAssertEqual(response.0.statusCode, 201, String(decoding: response.1, as: UTF8.self))
        let opened = try XCTUnwrap(service.shares.last?.document)
        let result = opened.store.document
        assertExactPixels(try Renderer.composite(result), reference) { sample in
          mode == .object ? sample : NormalLayerComposite.composite(backdrop: .clear, source: sample, depth: .u16)
        }
        XCTAssertNil(opened.localRawSource)
        XCTAssertNil(opened.importedSourceURL)
        if mode == .object {
          XCTAssertEqual(result.layers[0].smartObject?.rawDevelopment?.adjustments.exposure, 1.25)
          XCTAssertEqual(result.layers[0].smartObject?.data, original)
        } else {
          XCTAssertTrue(result.layers[0].isBackground)
          XCTAssertNil(result.layers[0].smartObject)
        }
      }
    }
  }

  @MainActor func testOpeningPreferencePersistsAndCanBeUpdatedOnItsOwnThroughAPI() async throws {
    let domain = "Photato.CameraRawOpenModeTests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = CameraRawPreferences(defaults: defaults)
    XCTAssertFalse(preferences.openAsSmartObject)
    let initial = preferences.revision
    preferences.openAsSmartObject = true
    XCTAssertNotEqual(preferences.revision, initial)
    XCTAssertTrue(CameraRawPreferences(defaults: defaults).openAsSmartObject)

    let api = AutomationTests()
    try await api.withService { service, _ in
      let route = AutomationService.cameraRawPreferencesPath
      service.setPhotoshopPreferenceChangesEnabled(true)
      let previous = service.controller.cameraRawPreferences.revision.uuidString
      let response = try await api.request(service, path: route,
        body: ["revision": previous, "openAsSmartObject": true])
      XCTAssertEqual(response.0.statusCode, 200)
      let result = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      XCTAssertEqual(result["dngStorage"] as? String, "embedXMP")
      XCTAssertEqual(result["openAsSmartObject"] as? Bool, true)
      XCTAssertTrue(service.controller.cameraRawPreferences.openAsSmartObject)
      let stale = try await api.request(service, path: route, body: ["revision": previous, "openAsSmartObject": false])
      XCTAssertEqual(stale.0.statusCode, 409)
    }
  }
}
