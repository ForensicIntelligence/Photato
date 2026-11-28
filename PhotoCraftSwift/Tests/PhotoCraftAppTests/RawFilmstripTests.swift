import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RawFilmstripTests: XCTestCase {
  private func fixture() throws -> Data {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    return try Data(contentsOf: directory.appendingPathComponent("Fixtures/Raw/synthetic-bayer.dng"))
  }

  @MainActor func testFilmstripSelectionSynchronizationUndoAndOpenCopies() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let raw = try fixture()
    let urls = (1...3).map { folder.appendingPathComponent("Capture-\($0).dng") }
    defer {
      for doc in controller.documents { doc.close() }
      try? FileManager.default.removeItem(at: folder)
    }
    var sidecars: [URL: Data] = [:]
    for (index, url) in urls.enumerated() {
      try raw.write(to: url)
      var settings = RawDevelopment()
      settings.adjustments.exposure = Float(index) / 2
      settings.adjustments.saturation = Float(index) * 10
      let packet = try CameraRawXMP.write(settings)
      let sidecar = url.deletingPathExtension().appendingPathExtension("xmp")
      try packet.write(to: sidecar)
      sidecars[sidecar] = packet
    }

    let workspace = RawFilmstripWorkspace(controller: controller)
    workspace.start(urls)
    await workspace.waitUntilIdle()
    XCTAssertNil(workspace.error)
    XCTAssertTrue(controller.documents.isEmpty)
    XCTAssertEqual(workspace.photos.map(\.name), urls.map(\.lastPathComponent))
    let ids = workspace.photos.map(\.id)
    guard ids.count == 3 else { return XCTFail("Expected three RAW photographs.") }
    XCTAssertEqual(workspace.editor?.id, ids[0])
    workspace.select(ids[2], extending: true)
    XCTAssertEqual(workspace.selection, Set(ids))
    workspace.navigate(-1)
    XCTAssertEqual(workspace.selection, Set(ids))
    XCTAssertEqual(workspace.activeID, ids[1])
    workspace.select(ids[0], toggling: true)
    XCTAssertEqual(workspace.selection, Set(ids[1...]))
    XCTAssertEqual(workspace.activeID, ids[1])

    var delta = try XCTUnwrap(workspace.activeSettings)
    workspace.slider(true)
    delta.adjustments.exposure = 1.2
    workspace.apply(delta, to: ids[1])
    delta.adjustments.exposure = 1.75
    workspace.apply(delta, to: ids[1])
    workspace.slider(false)
    XCTAssertEqual(workspace.photos.map { $0.settings.adjustments.exposure }, [0, 1.75, 1.75])
    XCTAssertEqual(workspace.photos.map { $0.settings.adjustments.saturation }, [0, 10, 20])
    workspace.synchronize([.color])
    XCTAssertEqual(workspace.photos.map { $0.settings.adjustments.saturation }, [0, 10, 10])
    workspace.undoEdit()
    XCTAssertEqual(workspace.photos.map { $0.settings.adjustments.saturation }, [0, 10, 20])
    workspace.undoEdit()
    XCTAssertEqual(workspace.photos.map { $0.settings.adjustments.exposure }, [0, 0.5, 1])
    workspace.redoEdit()
    workspace.redoEdit()
    let drafts = workspace.photos
    workspace.finish(.copy)
    await workspace.waitUntilIdle()
    XCTAssertTrue(workspace.closed)
    let documents = controller.documents.compactMap { $0 as? CraftNSDocument }
    XCTAssertEqual(Set(documents.compactMap(\.importedSourceURL)), Set(urls[1...]))
    XCTAssertEqual(documents.count, 2)
    for document in documents {
      let photo = try XCTUnwrap(drafts.first { $0.original.url == document.importedSourceURL })
      let baseline = try RawOpenMode.copy.output(from: photo.original.document(settings: photo.settings))
      XCTAssertEqual(document.store.document.layers.first?.content, baseline.layers.first?.content)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
    for url in urls { XCTAssertEqual(try Data(contentsOf: url), raw) }
    for (file, data) in sidecars { XCTAssertEqual(try Data(contentsOf: file), data) }
  }

  @MainActor func testAuthenticatedSynchronizationCommitsOnceAndRejectsPartialTargets() async throws {
    let raw = try fixture()
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, _ in
      var sourceSettings = RawDevelopment()
      sourceSettings.adjustments.exposure = 1.4
      sourceSettings.adjustments.saturation = 70
      var original = try RawSourceIO.open(raw, fileName: "Source.dng", settings: sourceSettings)
      let source = try XCTUnwrap(original.layers.first?.id)
      for saturation: Float in [12, -16] {
        var target = RawDevelopment()
        target.adjustments.saturation = saturation
        let document = try RawSourceIO.open(raw, fileName: "Target.dng", settings: target)
        original.layers.append(try XCTUnwrap(document.layers.first))
      }
      let document = CraftNSDocument(model: original)
      service.controller.addDocument(document)
      defer { document.close() }
      try service.share(document)
      let share = try XCTUnwrap(service.shares.last)
      let path = "/v1/documents/\(share.id)/commands"
      let ids = original.layers.dropFirst().map(\.id)
      @MainActor func execute(_ requested: [UUID]) async throws -> (HTTPURLResponse, Data) {
        try await helper.request(service, path: path, body: [
          "command": "raw.synchronize", "revision": service.revision(document.store),
          "parameters": ["sourceLayerID": source.uuidString, "targetLayerIDs": requested.map(\.uuidString), "groups": ["Light"]],
        ])
      }
      let rejection = try await execute([ids[0], UUID()])
      XCTAssertEqual(rejection.0.statusCode, 422, String(decoding: rejection.1, as: UTF8.self))
      XCTAssertEqual(document.store.document, original)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let applied = try await execute(ids)
      XCTAssertEqual(applied.0.statusCode, 200, String(decoding: applied.1, as: UTF8.self))
      XCTAssertEqual(document.store.session.undoStack.count, 1)
      for (index, layer) in document.store.document.layers.enumerated() {
        XCTAssertEqual(layer.smartObject?.rawDevelopment?.adjustments.exposure, 1.4)
        XCTAssertEqual(layer.smartObject?.rawDevelopment?.adjustments.saturation, [70, 12, -16][index])
        XCTAssertEqual(layer.smartObject?.data, raw)
      }
    }
  }
}
