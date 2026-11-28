import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RawGeometryWorkflowTests: XCTestCase {
  @MainActor func testRawGeometryPreviewAndHTTPPreserveTheOriginalAndUndo() async throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "synthetic-bayer", withExtension: "dng", subdirectory: "Fixtures/Raw"))
    let bytes = try Data(contentsOf: url)
    let original = try RawSourceIO.open(bytes, fileName: url.lastPathComponent)
    let source = try XCTUnwrap(original.layers.first)
    var settings = try XCTUnwrap(source.smartObject?.rawDevelopment)
    var geometry = RawGeometrySettings()
    geometry.offsetX = 10
    geometry.constrainCrop = true
    settings.geometry = geometry
    let raster = try RawSourceIO.render(bytes, settings: settings, depth: original.depth).0
    XCTAssertLessThan(raster.width, original.width)
    XCTAssertLessThan(raster.height, original.height)
    XCTAssertTrue(try raster.isOpaque())

    let workspace = CameraRawWorkspace()
    defer { workspace.close() }
    var filter = RasterFilter(.cameraRaw)
    filter.cameraRaw = settings.adjustments
    let draft = FilterDraft(id: source.id, filter: filter, rawDevelopment: source.smartObject?.rawDevelopment)
    await workspace.prepare(document: original, draft: draft, retainRawOutput: true)
    workspace.changeSensor(settings)
    await workspace.task?.value
    let preview = try XCTUnwrap(workspace.developedRawPreview)
    XCTAssertEqual([preview.width, preview.height], [raster.width, raster.height])
    XCTAssertEqual(preview.layers.first?.coordinateTransform, .identity)
    XCTAssertEqual(preview.layers.first?.smartObject?.data, bytes)
    let opened = try RawOpenMode.copy.output(from: preview)
    XCTAssertEqual([opened.width, opened.height], [raster.width, raster.height])
    XCTAssertNil(opened.layers.first?.smartObject)
    workspace.undo()
    await workspace.task?.value
    XCTAssertEqual(workspace.developedRawPreview?.width, original.width)
    XCTAssertNil(workspace.sensorSettings?.geometry)

    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }) { service, shared in
      shared.store.session = EditorSession(document: original)
      try service.share(shared)
      var expected = original
      try RawSourceIO.command(in: original, layerID: source.id, settings: settings).apply(to: &expected)
      let params: [String: Any] = ["layerID": source.id.uuidString,
        "settings": ["geometry": ["offsetX": 10, "constrainCrop": true]]]
      let status = try await api.edit(service, shared, "raw.develop", params)
      XCTAssertEqual(status, 200)
      XCTAssertEqual(shared.store.document, expected)
      XCTAssertEqual(shared.store.document.layers.first?.smartObject?.data, bytes)
      XCTAssertEqual(shared.store.document.layers.first?.smartObject?.rawDevelopment?.geometry, geometry)
      let invalid = try await api.edit(service, shared, "raw.develop",
        ["layerID": source.id.uuidString, "settings": ["geometry": ["constrainCrop": 1]]])
      XCTAssertEqual(invalid, 400)
      XCTAssertEqual(shared.store.document, expected)
      let undo = try await api.edit(service, shared, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(shared.store.document, original)
    }
  }
}
