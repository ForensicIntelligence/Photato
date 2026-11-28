import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RawSensorReuseTests: XCTestCase {
  private func fixture(_ depth: PixelDepth = .u16) throws -> CraftDocument {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/Raw/synthetic-bayer.dng")
    return try RawSourceIO.open(Data(contentsOf: file), fileName: "Sensor.dng", depth: depth)
  }

  func testCachedRGBDevelopmentMatchesFreshColorManagedMaskedCommand() throws {
    var original = try fixture()
    let id = original.layers[0].id
    var settings = try XCTUnwrap(original.layers[0].smartObject?.rawDevelopment)
    let decoded = try RawSourceIO.developmentCommand(in: original, layerID: id, settings: settings, reusing: nil)
    original.workingICC = try ColorManagement.importedProfile(
      XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?), depth: .u16)
    var mask = try Surface(width: original.width, height: original.height, fill: .white)
    mask.setPixel(x: 30, y: 40, .black)
    original.layers[0].mask = mask
    settings.adjustments.exposure = 1.25
    settings.adjustments.vibrance = 18

    let reused = try RawSourceIO.developmentCommand(in: original, layerID: id, settings: settings,
      reusing: decoded.sensor)
    XCTAssertTrue(decoded.sensor === reused.sensor)
    var cached = original
    try reused.command.apply(to: &cached)
    var fresh = original
    try RawSourceIO.command(in: original, layerID: id, settings: settings).apply(to: &fresh)
    XCTAssertEqual(cached, fresh)
    XCTAssertEqual(cached.layers[0].mask, mask)
    XCTAssertEqual(cached.workingICC, original.workingICC)
    XCTAssertEqual(try Renderer.composite(cached), try Renderer.composite(fresh))
  }

  func testSensorReuseRequiresExactSourceDepthAndSensorSettings() throws {
    let original = try fixture()
    let id = original.layers[0].id
    let object = try XCTUnwrap(original.layers[0].smartObject)
    let settings = try XCTUnwrap(object.rawDevelopment)
    let first = try RawSourceIO.developmentCommand(in: original, layerID: id, settings: settings, reusing: nil)

    func refreshed(in document: CraftDocument, settings: RawDevelopment) throws -> RawSourceIO.SensorRaster {
      try RawSourceIO.developmentCommand(in: document, layerID: document.layers[0].id,
        settings: settings, reusing: first.sensor).sensor
    }

    var modifiedSource = original
    var modifiedObject = object
    modifiedObject.data.append(0)
    modifiedSource.layers[0].smartObject = modifiedObject
    XCTAssertEqual(modifiedObject.sourceID, object.sourceID)
    XCTAssertFalse(try refreshed(in: modifiedSource, settings: settings) === first.sensor)
    XCTAssertFalse(try refreshed(in: fixture(.f32), settings: settings) === first.sensor)

    var changed = settings
    changed.temperature = 5500
    XCTAssertFalse(try refreshed(in: original, settings: changed) === first.sensor)
    changed = settings
    changed.exposure = -0.0
    XCTAssertFalse(try refreshed(in: original, settings: changed) === first.sensor)
    changed = settings
    changed.decoderVersion = "unavailable"
    XCTAssertThrowsError(try refreshed(in: original, settings: changed))
  }

  @MainActor func testWorkspaceKeepsLatestPreviewAndSharesSensorWithCommit() async throws {
    let original = try fixture()
    let store = EditorStore(document: original)
    let model = CameraRawWorkspace()
    defer { model.close(); store.renderTask?.cancel() }
    store.beginRawDevelopment()
    let draft = try XCTUnwrap(store.filterDraft)
    await model.prepare(document: original, draft: draft)
    let firstSensor = try XCTUnwrap(model.sensorRaster)

    var rgb = model.settings
    rgb.exposure = 0.5
    model.change(rgb)
    let earlierTask = model.task
    rgb.exposure = 1.25
    model.change(rgb)
    await earlierTask?.value
    await model.task?.value
    XCTAssertTrue(model.ready)
    XCTAssertEqual(model.settings, rgb)
    XCTAssertTrue(model.sensorRaster === firstSensor)
    XCTAssertEqual(store.document, original)

    let cached = model.sensorRaster
    model.close()
    XCTAssertNil(model.sensorRaster)
    XCTAssertFalse(model.ready)
    store.filterDraft?.filter.cameraRaw = rgb
    var settings = try XCTUnwrap(model.sensorSettings)
    settings.adjustments = rgb
    store.filterDraft?.rawDevelopment = settings
    store.commitFilter(reusingRawSensor: cached)
    await store.geometryTask?.value
    var expected = original
    try RawSourceIO.command(in: original, layerID: draft.id, settings: settings).apply(to: &expected)
    XCTAssertEqual(store.document, expected)
    await store.undo()
    XCTAssertEqual(store.document, original)
    await store.redo()
    XCTAssertEqual(store.document, expected)
  }
}
