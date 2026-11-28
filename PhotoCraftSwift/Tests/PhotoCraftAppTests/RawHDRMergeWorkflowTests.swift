import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft
@testable import PhotoCraftImaging

final class RawHDRMergeWorkflowTests: XCTestCase {
  @MainActor func testFilmstripHDRSaveAddsEditablePhotoAndKeepsBracketsAndDrafts() async throws {
    _ = NSApplication.shared
    let (folder, urls, bytes) = try makeBrackets()
    defer { try? FileManager.default.removeItem(at: folder) }
    let suite = "PhotatoTests.HDR.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = CameraRawPreferences(defaults: defaults)
    preferences.dngStorage = .embedXMP
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary(), cameraRawPreferences: preferences)
    let workspace = RawFilmstripWorkspace(controller: controller)
    defer { workspace.close() }
    workspace.start(urls)
    await workspace.waitUntilIdle()
    workspace.selectAll()
    let selection = workspace.selection

    workspace.beginHDRMerge(skipPreview: true)
    let cancelled = try XCTUnwrap(workspace.hdrMergeRequest)
    XCTAssertTrue(cancelled.skipPreview)
    XCTAssertEqual(cancelled.settings, RawHDRMergeSettings())
    XCTAssertEqual(cancelled.photos.map(\.original.url), urls)
    workspace.dismissHDRMerge()
    XCTAssertEqual(workspace.selection, selection)
    XCTAssertEqual(workspace.photos.count, 3)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
      urls.map(\.lastPathComponent).sorted())

    workspace.beginHDRMerge()
    let request = try XCTUnwrap(workspace.hdrMergeRequest)
    let sources = try RawHDRMerge.prepareSources(request.photos.map { $0.original.hdrMergeSource(settings: $0.settings) })
    var options = RawHDRMergeSettings()
    options.align = false
    options.deghost = .medium
    let preview = try RawHDRMerge.prepare(sources, options: options, name: request.name)
    XCTAssertEqual(preview.exposureEV, [0, 1, 2])
    XCTAssertNotNil(preview.preview)
    XCTAssertNotNil(preview.overlayPreview)
    let expectedSettings = try XCTUnwrap(preview.settings)
    XCTAssertNotEqual(expectedSettings.contrast, 0)
    do {
      _ = try await workspace.saveHDRMerge(preview, to: urls[0], requestID: request.id)
      XCTFail("The merge must protect source exposures.")
    } catch CraftError.invalid { }
    let destination = folder.appendingPathComponent("Merged-HDR.dng")
    let output = try await workspace.saveHDRMerge(preview, to: destination, requestID: request.id)
    workspace.acceptHDRMerge(output, requestID: request.id, settings: options)
    await workspace.waitUntilIdle()
    XCTAssertNil(workspace.hdrMergeRequest)
    XCTAssertEqual(workspace.photos.count, 4)
    XCTAssertEqual(workspace.selection, [output.id])
    XCTAssertEqual(workspace.activeID, output.id)
    XCTAssertEqual(workspace.activeInformation?.width, 512)
    XCTAssertEqual(workspace.activeInformation?.height, 384)
    XCTAssertEqual(workspace.activeSettings?.adjustments, expectedSettings)
    XCTAssertTrue(controller.documents.isEmpty)
    XCTAssertFalse(workspace.canUndo)
    XCTAssertEqual(CameraRawPreferences(defaults: defaults).hdrMerge, options)
    for (url, expected) in zip(urls, bytes) { XCTAssertEqual(try Data(contentsOf: url), expected) }
  }

  @MainActor func testAuthenticatedHDRDownloadMatchesNativeDNGAndDoesNotEditDocument() async throws {
    let (folder, urls, bytes) = try makeBrackets()
    defer { try? FileManager.default.removeItem(at: folder) }
    let options: [String: Any] = ["align": false, "autoSettings": true, "deghost": "off"]
    let originals = try zip(urls, bytes).map {
      try RawSourceIO.open($0.1, fileName: $0.0.lastPathComponent)
    }
    let sourceLayers = try originals.map { try XCTUnwrap($0.layers.first) }
    var file = try CraftDocument(width: 512, height: 384, depth: .u16, name: "Brackets")
    file.layers = sourceLayers
    file.activeLayerID = sourceLayers[0].id
    var settings = RawHDRMergeSettings()
    settings.align = false
    let brackets = try sourceLayers.map { layer -> RawHDRMerge.Source in
      let object = try XCTUnwrap(layer.smartObject)
      return .init(bytes: object.sourceBytes, fileName: object.fileName, settings: try XCTUnwrap(object.rawDevelopment))
    }
    let exposures = try RawHDRMerge.prepareSources(brackets)
    let nativeResult = try RawHDRMerge.prepare(exposures, options: settings, name: "Native HDR")
    let nativeURL = folder.appendingPathComponent("Native-HDR.dng")
    try nativeResult.write(to: nativeURL)
    let expected = try Data(contentsOf: nativeURL)

    let fixture = AutomationTests()
    let sourceDocument = file
    try await fixture.withService(pressedMouseButtons: { 0 }) { service, _ in
      let document = CraftNSDocument(model: sourceDocument)
      service.controller.addDocument(document)
      defer { document.close() }
      try service.share(document)
      let share = try XCTUnwrap(service.shares.last)
      let route = "/v1/documents/\(share.id)/commands"
      let revision = service.revision(document.store)
      var params = options
      params["layerIDs"] = sourceLayers.map { $0.id.uuidString }
      let body: [String: Any] = ["command": "raw.mergeHDR", "revision": revision, "parameters": params]
      service.setDocumentTransfersEnabled(false)
      let disabled = try await fixture.request(service, path: route, body: body)
      XCTAssertEqual(disabled.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      let response = try await fixture.request(service, path: route, body: body)
      XCTAssertEqual(response.0.statusCode, 200)
      XCTAssertEqual(response.0.value(forHTTPHeaderField: "Content-Type"), "image/x-adobe-dng")
      XCTAssertEqual(response.1, expected)
      XCTAssertEqual(document.store.document, sourceDocument)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertEqual(service.revision(document.store), revision)
      XCTAssertEqual(service.shares.count, 1)
    }
  }

  private func makeBrackets() throws -> (URL, [URL], [Data]) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/Raw/synthetic-bayer.dng")
    let original = try Data(contentsOf: fixture)
    let exposures = [(120, 0.5), (60, 1.0), (30, 2.0)]
    let urls = exposures.indices.map { folder.appendingPathComponent("Bracket-\($0 + 1).dng") }
    let bytes = try exposures.map { try bracket(original, shutter: $0.0, multiplier: $0.1) }
    for (url, data) in zip(urls, bytes) { try data.write(to: url) }
    return (folder, urls, bytes)
  }

  private func bracket(_ original: Data, shutter: Int, multiplier: Double) throws -> Data {
    func read(_ start: Int, _ size: Int) -> Int {
      (0..<size).reduce(0) { $0 | (Int(original[start + $1]) << (8 * $1)) }
    }
    func little(_ value: Int, _ size: Int) -> Data {
      Data((0..<size).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
    }
    func record(_ tag: Int, _ type: Int, _ value: Int) -> Data {
      little(tag, 2) + little(type, 2) + little(1, 4) + little(value, 4)
    }
    let root = read(4, 4), count = read(root, 2)
    var fields: [Int: Data] = [:], raster = 0
    for i in 0..<count {
      let entry = root + 2 + i * 12, tag = read(entry, 2)
      fields[tag] = original.subdata(in: entry..<entry + 12)
      if tag == 273 { raster = read(entry + 8, 4) }
    }
    guard raster > 0 else { throw CocoaError(.fileReadCorruptFile) }
    var result = original
    for position in stride(from: raster, to: original.count, by: 2) {
      let sample = max(64, min(4_095, Int((64 + Double(read(position, 2) - 64) * multiplier).rounded())))
      result.replaceSubrange(position..<position + 2, with: little(sample, 2))
    }
    let exposureOffset = result.count
    result += little(1, 4) + little(shutter, 4)
    let apertureOffset = result.count
    result += little(8, 4) + little(1, 4)
    let exifOffset = result.count
    result += little(3, 2) + record(33_434, 5, exposureOffset) + record(33_437, 5, apertureOffset)
      + record(34_855, 3, 100) + little(0, 4)
    let changedRoot = result.count
    fields[34_665] = record(34_665, 4, exifOffset)
    result += little(fields.count, 2)
    for key in fields.keys.sorted() { result += fields[key]! }
    result += little(0, 4)
    result.replaceSubrange(4..<8, with: little(changedRoot, 4))
    return result
  }
}
