import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class RestrictedGeometryWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument { try RestrictedModeWorkflowTests().indexed() }
  func command(_ name: String, _ parameters: [String: Any]) throws -> AutomationCommand {
    try .init(data: JSONSerialization.data(withJSONObject: ["command": name, "revision": "test", "parameters": parameters]))
  }
  func testCropFillQuantizesOnlyNewGapsAndPreservesOriginalIndices() throws {
    let original = try fixture(); var request = CropRequest(x: -1, y: 0, width: 6, height: 3)
    request.fill = .background; request.backgroundColor = Pixel(20/255.0, 30/255.0, 40/255.0)
    let changed = try CropPreparation.prepare(request, document: original).result
    XCTAssertEqual(changed.layers.count, 1)
    guard case .indexed(let raster) = changed.restrictedMode else { return XCTFail() }
    XCTAssertEqual(raster.indices, Data([0, 0, 1, 2, 0, 0, 0, 1, 2, 0, 1, 0, 0, 2, 0, 1, 2, 0]))
    request.deleteCroppedPixels = false; XCTAssertThrowsError(try CropPreparation.prepare(request, document: original))
    let bitmap = try CraftDocument(width: 2, height: 2).replacingRestrictedMode(.bitmap(BitmapRaster(width: 2, height: 2, bits: Data([0, 0]))))
    request = CropRequest(x: -1, y: 0, width: 4, height: 2); request.fill = .background; request.backgroundColor = .black
    let binary = try CropPreparation.prepare(request, document: bitmap).result
    guard case .bitmap(let bits) = binary.restrictedMode else { return XCTFail() }
    XCTAssertEqual(bits.bits, Data([0x90, 0x90]))
  }
  func testGeometryFilesKeepStoredSamplesAndPalette() throws {
    var document = try fixture(); try Command.rotateCanvas(.clockwise).apply(to: &document)
    try Command.imageSize(6, 8, 144, .nearest).apply(to: &document)
    for format in [DocumentIO.Format.native, .psd, .psb, .png, .tiff] {
      let data = try DocumentIO.encodeForPersistence(document, format: format)
      let reopened = format == .native ? try NativeArchive.decode(data) : [.psd, .psb].contains(format) ? try PSDCodec.read(data) : try RasterIO.read(data)
      XCTAssertEqual(reopened.restrictedMode, document.restrictedMode)
      XCTAssertEqual(reopened.width, 6); XCTAssertEqual(reopened.height, 8)
    }
  }
  @MainActor func testHTTPGeometryMatchesDesktopAndHistoryInEachMode() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document)
      let bitmap = try CraftDocument(width: 4, height: 3).replacingRestrictedMode(.bitmap(BitmapRaster(width: 4, height: 3, bits: Data([0x50, 0xa0, 0x60]))))
      let fixtures = [try fixture(), bitmap, try CropWorkflowTests().fixture()]
      let operations: [(String, [String: Any])] = [("document.resize", ["width": 8, "height": 6]), ("document.canvasSize", ["width": 10, "height": 8, "anchor": "bottomRight", "fill": [0, 0, 0, 1]]), ("document.rotate", ["turn": "clockwise"]), ("document.resolution", ["resolution": 300])]
      for original in fixtures {
        for (name, parameters) in operations {
          document.store.session = EditorSession(document: original)
          let native = try command(name, parameters).geometryCommand(in: original)
          let desktop = EditorStore(document: original); defer { desktop.renderTask?.cancel() }
          desktop.performGeometry(native); await desktop.geometryTask?.value
          XCTAssertNil(desktop.error)
          let status = try await helper.edit(service, document, name, parameters); XCTAssertEqual(status, 200)
          XCTAssertTrue(document.store.document == desktop.document, name)
          let changed = document.store.document
          let undo = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo, 200); XCTAssertTrue(document.store.document == original)
          let redo = try await helper.edit(service, document, "history.redo"); XCTAssertEqual(redo, 200); XCTAssertTrue(document.store.document == changed)
        }
      }
    }
  }
  @MainActor func testStrictAPIInvalidBusyStaleAndCropEquivalence() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); document.store.session = EditorSession(document: try fixture()); let original = document.store.document
      for (name, parameters): (String, [String: Any]) in [("document.resize", ["width": 0, "height": 1]), ("document.resize", ["width": 4, "height": 3, "method": "fake"]), ("document.rotate", ["turn": "clockwise", "ignored": true]), ("document.canvasSize", ["width": 4, "height": 3, "fill": [1, 2, 3, 4]]), ("document.resolution", ["resolution": 0])] {
        let status = try await helper.edit(service, document, name, parameters); XCTAssertEqual(status, 400); XCTAssertTrue(document.store.document == original)
      }
      let stale = try await helper.edit(service, document, "document.rotate", ["turn": "clockwise"], revision: "stale"); XCTAssertEqual(stale, 409)
      document.store.geometryBusy = true
      let busy = try await helper.edit(service, document, "document.rotate", ["turn": "clockwise"]); XCTAssertEqual(busy, 409); document.store.geometryBusy = false
      let request = CropRequest(x: 1, y: 1, width: 2, height: 2)
      let expected = try CropPreparation.prepare(request, document: original).result
      let status = try await helper.edit(service, document, "document.crop", ["x": 1, "y": 1, "width": 2, "height": 2]); XCTAssertEqual(status, 200); XCTAssertTrue(document.store.document == expected)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: GeometryAPI.capabilities))
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }
}
