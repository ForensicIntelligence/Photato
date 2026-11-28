import AppKit
import ImageIO
import PhotoCraftCore
import XCTest
@testable import PhotoCraft
@testable import PhotoCraftImaging

final class RawPhotoMarkingTests: XCTestCase {
  private func original() throws -> Data {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    return try Data(contentsOf: directory.appendingPathComponent("Fixtures/Raw/synthetic-bayer.dng"))
  }

  private func packet(rating: Int, label: String, exposure: String) -> Data {
    Data("""
      <x:xmpmeta xmlns:x="adobe:ns:meta/">
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
      <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/"
       xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
       xmlns:lab="https://example.test/archive/" xmp:Rating="\(rating)" xmp:Label="\(label)"
       crs:Exposure2012="\(exposure)" crs:ProcessVersion="22.0" lab:CreatorCode="A42"/>
      </rdf:RDF>
      </x:xmpmeta>
      """.utf8)
  }

  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
  }

  private func value(_ path: String, in packet: Data) -> String? {
    CGImageMetadataCreateFromXMPData(packet as CFData).flatMap {
      CGImageMetadataCopyStringValueWithPath($0, nil, path as CFString) as String?
    }
  }

  @MainActor func testFilmstripFiltersSelectionAndSavesMarkingWithoutChangingAdjustments() async throws {
    _ = NSApplication.shared
    let preferences = CameraRawPreferences()
    preferences.dngStorage = .sidecarXMP
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary(), cameraRawPreferences: preferences)
    let directory = try folder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let raw = try original()
    let files = ["A", "B", "C"].map { directory.appendingPathComponent($0 + ".dng") }
    let packets = [packet(rating: 0, label: "Review Later", exposure: "0.25"),
      packet(rating: 2, label: "Yellow", exposure: "1.25"),
      packet(rating: 5, label: "Green", exposure: "-0.5")]
    let sidecars = files.map { $0.deletingPathExtension().appendingPathExtension("xmp") }
    for (index, file) in files.enumerated() {
      try raw.write(to: file)
      try packets[index].write(to: sidecars[index])
    }

    let workspace = RawFilmstripWorkspace(controller: controller)
    workspace.start(files)
    await workspace.waitUntilIdle()
    XCTAssertNil(workspace.error)
    XCTAssertEqual(workspace.photos.map(\.marking.rating), [0, 2, 5])
    workspace.order = .rating
    workspace.reverseOrder = true
    XCTAssertEqual(workspace.displayedPhotos.map(\.name), ["C.dng", "B.dng", "A.dng"])
    workspace.setRatingFilter(.four)
    XCTAssertEqual(workspace.displayedPhotos.map(\.name), ["C.dng"])
    workspace.toggleLabelFilter(.yellow)
    XCTAssertTrue(workspace.displayedPhotos.isEmpty)
    XCTAssertNil(workspace.activeID)
    XCTAssertTrue(workspace.selection.isEmpty)
    workspace.setRatingFilter(.all)
    workspace.toggleLabelFilter(.green)
    workspace.selectAll()
    XCTAssertEqual(workspace.selection, Set(workspace.photos.dropFirst().map(\.id)))
    workspace.setRating(4)
    XCTAssertEqual(workspace.photos.map(\.marking.rating), [0, 4, 4])
    workspace.undoEdit()
    XCTAssertEqual(workspace.photos.map(\.marking.rating), [0, 2, 5])
    workspace.redoEdit()
    workspace.setLabel(.red)
    XCTAssertEqual(workspace.photos.map(\.marking.label), ["Review Later", "Red", "Red"])
    workspace.clearFilters()
    workspace.selectRated()
    XCTAssertEqual(workspace.selection.count, 2)
    workspace.finish(nil)
    await workspace.waitUntilIdle()
    XCTAssertNil(workspace.error)
    XCTAssertTrue(workspace.closed)

    XCTAssertEqual(try Data(contentsOf: sidecars[0]), packets[0])
    for index in 1...2 {
      let edited = try Data(contentsOf: sidecars[index])
      XCTAssertEqual(RawPhotoMarking.read(edited), RawPhotoMarking(rating: 4, label: "Red"))
      XCTAssertEqual(value("crs:Exposure2012", in: edited), value("crs:Exposure2012", in: packets[index]))
      XCTAssertEqual(value("crs:ProcessVersion", in: edited), "22.0")
      XCTAssertEqual(value("lab:CreatorCode", in: edited), "A42")
    }
    for file in files { XCTAssertEqual(try Data(contentsOf: file), raw) }
  }

  @MainActor func testDoneSavesChangedPhotosEvenWhenFiltersLeaveNoSelection() async throws {
    _ = NSApplication.shared
    let preferences = CameraRawPreferences()
    preferences.dngStorage = .embedXMP
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary(), cameraRawPreferences: preferences)
    let directory = try folder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let raw = try original()
    let edited = directory.appendingPathComponent("01-Edited.dng")
    let unedited = directory.appendingPathComponent("02-Unedited.dng")
    try raw.write(to: edited)
    try raw.write(to: unedited)

    let workspace = RawFilmstripWorkspace(controller: controller)
    defer { workspace.close() }
    workspace.start([edited, unedited])
    await workspace.waitUntilIdle()
    workspace.setRating(4)
    workspace.setLabel(.red)
    let second = try XCTUnwrap(workspace.photos.last)
    workspace.select(second.id)
    XCTAssertEqual(workspace.activeID, second.id)
    workspace.toggleLabelFilter(.blue)
    XCTAssertTrue(workspace.selection.isEmpty)
    XCTAssertFalse(workspace.canFinish)
    XCTAssertTrue(workspace.canWrite)
    workspace.finish(nil)
    await workspace.waitUntilIdle()
    XCTAssertTrue(workspace.closed)
    XCTAssertNil(workspace.error)
    let changed = try Data(contentsOf: edited)
    let packet = try XCTUnwrap(RawSourceIO.embeddedDNGXMP(changed))
    XCTAssertEqual(RawPhotoMarking.read(packet), .init(rating: 4, label: "Red"))
    XCTAssertEqual(changed[8..<raw.count], raw[8..<raw.count])
    XCTAssertEqual(try Data(contentsOf: unedited), raw)
    XCTAssertTrue(controller.documents.isEmpty)
  }

  func testMarkingOnlySidecarOverridesEmbeddedTagsWithoutResettingDevelopment() throws {
    let directory = try folder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let raw = try original()
    let embedded = try RawSourceIO.replacingDNGXMP(raw) { _ in
      packet(rating: 2, label: "Green", exposure: "1.25")
    }
    let file = directory.appendingPathComponent("Capture.dng")
    try embedded.write(to: file)
    let sidecar = file.deletingPathExtension().appendingPathExtension("xmp")
    let sidecarMarking = RawPhotoMarking(rating: 4, label: "")
    let alternatePrefix = Data("""
      <x:xmpmeta xmlns:x="adobe:ns:meta/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:RDF><rdf:Description xmlns:mark="http://ns.adobe.com/xap/1.0/" mark:Rating="4" mark:Label=""/></rdf:RDF>
      </x:xmpmeta>
      """.utf8)
    XCTAssertEqual(RawPhotoMarking.read(alternatePrefix), sidecarMarking)
    try CameraRawXMP.writeMarking(sidecarMarking, replacing: nil).write(to: sidecar)
    let source = try RawSourceIO.prepareLocalOriginal(file, dngStorage: .sidecarXMP, rawDefaults: .init())
    XCTAssertEqual(source.marking, sidecarMarking)
    XCTAssertEqual(source.settings.adjustments.exposure, 1.25)
    let opened = try source.document()
    XCTAssertEqual(try RawPhotoMarking.read(in: opened), sidecarMarking)

    let target = try XCTUnwrap(source.settingsSource)
    let next = RawPhotoMarking(rating: 5, label: "Purple")
    _ = try target.save(settings: nil, marking: next)
    XCTAssertEqual(try Data(contentsOf: file), embedded)
    XCTAssertEqual(RawPhotoMarking.read(try Data(contentsOf: sidecar)), next)
    let reopened = try RawSourceIO.prepareLocalOriginal(file, dngStorage: .sidecarXMP, rawDefaults: .init())
    XCTAssertEqual(reopened.settings.adjustments.exposure, 1.25)
    XCTAssertEqual(reopened.marking, next)
  }

  @MainActor func testAuthenticatedPhotoMarkingIsUndoableAndKeepsDevelopedPixels() async throws {
    let raw = try original()
    let directory = try folder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Owned.dng")
    let sidecar = url.deletingPathExtension().appendingPathExtension("xmp")
    try raw.write(to: url)
    try packet(rating: 1, label: "Yellow", exposure: "1").write(to: sidecar)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, _ in
      let prepared = try PreparedLocalDocument.read(url, format: .raw, dngStorage: .sidecarXMP)
      let layer = try XCTUnwrap(prepared.model.layers.first)
      let document = prepared.makeDocument(url: url)
      service.controller.addDocument(document)
      defer { document.close() }
      try service.share(document)
      let share = try XCTUnwrap(service.shares.last)
      let path = "/v1/documents/\(share.id)/commands"
      let result = try await helper.request(service, path: path, body: [
        "command": "raw.markPhoto", "revision": service.revision(document.store),
        "parameters": ["layerID": layer.id.uuidString, "rating": 4, "label": "Red"],
      ])
      XCTAssertEqual(result.0.statusCode, 200, String(decoding: result.1.prefix(400), as: UTF8.self))
      XCTAssertEqual(document.store.session.undoStack.count, 1)
      XCTAssertEqual(document.store.document.layers.first, layer)
      XCTAssertEqual(try RawPhotoMarking.read(in: document.store.document), .init(rating: 4, label: "Red"))
      let inspect = try await helper.request(service, path: path, body: [
        "command": "raw.inspect", "revision": service.revision(document.store),
        "parameters": ["layerID": layer.id.uuidString],
      ])
      XCTAssertEqual(inspect.0.statusCode, 200)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: inspect.1) as? [String: Any])
      let marking = try XCTUnwrap(json["photoMarking"] as? [String: Any])
      XCTAssertEqual(marking["rating"] as? Int, 4)
      XCTAssertEqual(marking["label"] as? String, "Red")
      service.setDocumentSavesEnabled(true)
      let save = try await helper.request(service, path: path, body: [
        "command": "raw.saveSourceSettings", "revision": service.revision(document.store),
        "parameters": ["layerID": layer.id.uuidString, "photoMarkingOnly": true],
      ])
      XCTAssertEqual(save.0.statusCode, 200, String(decoding: save.1.prefix(400), as: UTF8.self))
      let written = try Data(contentsOf: sidecar)
      XCTAssertEqual(RawPhotoMarking.read(written), .init(rating: 4, label: "Red"))
      XCTAssertEqual(value("crs:Exposure2012", in: written), "1")
      XCTAssertEqual(value("crs:ProcessVersion", in: written), "22.0")
      XCTAssertEqual(value("lab:CreatorCode", in: written), "A42")
      XCTAssertEqual(try Data(contentsOf: url), raw)
    }
  }
}
