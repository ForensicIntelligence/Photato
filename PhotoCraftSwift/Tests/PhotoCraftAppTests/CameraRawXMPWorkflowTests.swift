import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class CameraRawXMPWorkflowTests: XCTestCase {
  private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Raw")

  private func reference(_ mode: String) throws -> Data {
    try Data(contentsOf: fixtures.appendingPathComponent("camera-raw-\(mode)-settings.xmp"))
  }

  func testPhotoshopXMPUsesSeparateWhiteBalanceAndPreservesUnspecifiedSettings() throws {
    var base = RawDevelopment()
    base.temperature = 5000
    base.tint = 8
    base.exposure = 0.25
    base.decoderVersion = "Apple-test"
    let raw = try CameraRawXMP.read(reference("source"), into: base)
    XCTAssertNil(raw.temperature)
    XCTAssertNil(raw.tint)
    XCTAssertEqual(raw.exposure, 0.25)
    XCTAssertEqual(raw.decoderVersion, "Apple-test")
    XCTAssertEqual(raw.adjustments.exposure, 0.75)
    XCTAssertEqual(raw.adjustments.contrast, 21)
    XCTAssertEqual(raw.adjustments.highlights, -17)
    XCTAssertEqual(raw.adjustments.vibrance, 9)
    XCTAssertEqual(raw.adjustments.sharpenAmount, 40)
    XCTAssertTrue(raw.adjustments.pointCurve.isEmpty)
    let rendered = try CameraRawXMP.read(reference("filter"))
    XCTAssertEqual(rendered.exposure, -0.35)
    XCTAssertEqual(rendered.temperature, 31)
    XCTAssertEqual(rendered.tint, -24)
    XCTAssertEqual(rendered.vibrance, 12)
    let alias = String(decoding: try reference("filter"), as: UTF8.self)
      .replacingOccurrences(of: "xmlns:crs=", with: "xmlns:reference=")
      .replacingOccurrences(of: "crs:", with: "reference:")
    XCTAssertEqual(try CameraRawXMP.read(Data(alias.utf8)), rendered)
  }

  func testNativeXMPConvertsCurvesMixerAndGradingAndRejectsInvalidValues() throws {
    var settings = try CameraRawXMP.read(reference("filter"))
    settings.pointCurve = [[0, 0], [128, 173], [255, 255]]
    settings.pointCurveBlue = [[0, 19], [255, 242]]
    settings.curveSplits = [21, 48, 76]
    settings.hslHue[4] = -26
    settings.hslSat[2] = 35
    settings.gradeShadows.hue = 219
    settings.gradeShadows.sat = 11
    settings.gradeGlobal.lum = 7
    settings.vignetteStyle = "paintOverlay"
    settings.vignetteAmount = -15
    let xmp = try CameraRawXMP.write(settings)
    XCTAssertEqual(try CameraRawXMP.read(xmp), settings)
    var raw = RawDevelopment()
    raw.temperature = 6800
    raw.tint = -4
    raw.adjustments.exposure = 0.75
    XCTAssertEqual(try CameraRawXMP.read(CameraRawXMP.write(raw), into: RawDevelopment()), raw)
    let original = String(decoding: xmp, as: UTF8.self)
    let invalidValues = [
      original.replacingOccurrences(of: ">-0.35<", with: ">NaN<"),
      original.replacingOccurrences(of: ">128, 173<", with: ">0, 173<"),
      original.replacingOccurrences(of: ">3<", with: ">-9223372036854775808<"),
    ]
    for text in invalidValues {
      XCTAssertNotEqual(text, original)
      XCTAssertThrowsError(try CameraRawXMP.read(Data(text.utf8)))
    }
    XCTAssertThrowsError(try CameraRawXMP.read(Data(repeating: 0x20, count: CameraRawXMP.maximumBytes + 1)))
    XCTAssertThrowsError(try CameraRawXMP.read(Data("not XMP".utf8)))
  }

  @MainActor func testNativeRawWorkspaceXMPUsesDraftUndoAndKeepsJSONAndSource() async throws {
    let bytes = try Data(contentsOf: fixtures.appendingPathComponent("synthetic-bayer.dng"))
    let document = try RawSourceIO.open(bytes, fileName: "Sensor.dng")
    let layer = document.layers[0]
    let model = CameraRawWorkspace()
    defer { model.close() }
    await model.prepare(document: document,
      draft: FilterDraft(id: layer.id, filter: RasterFilter(.cameraRaw), rawDevelopment: layer.smartObject?.rawDevelopment))
    XCTAssertTrue(model.ready)
    try model.loadSettings(reference("source"), xmp: true)
    await model.task?.value
    XCTAssertTrue(model.ready)
    XCTAssertEqual(model.settings.exposure, 0.75)
    XCTAssertEqual(model.undoStates.count, 1)
    model.error = "Previous load failed"
    try model.loadSettings(reference("source"), xmp: true)
    XCTAssertNil(model.error)
    XCTAssertEqual(model.undoStates.count, 1)
    let json = try model.settingsData(xmp: false)
    let xmp = try model.settingsData(xmp: true)
    XCTAssertEqual(LUTDocument(data: xmp).outputWrapper().regularFileContents, xmp)
    XCTAssertEqual(LUTDocument(data: xmp, filename: "Camera Raw.xmp").outputWrapper().preferredFilename, "Camera Raw.xmp")
    XCTAssertEqual(try RawDevelopment.decodeJSON(json), model.sensorSettings)
    XCTAssertEqual(try CameraRawXMP.read(xmp, into: RawDevelopment()).adjustments, model.settings)
    model.undo()
    await model.task?.value
    XCTAssertEqual(model.settings.exposure, 0)
    model.redo()
    await model.task?.value
    XCTAssertEqual(model.settings.exposure, 0.75)
    XCTAssertEqual(document.layers[0].smartObject?.data, bytes)
  }

  @MainActor func testAuthenticatedConversionAndRenderedFilterUseSameXMPAdjustments() async throws {
    let helper = AutomationTests()
    let data = try reference("filter")
    let xmp = String(decoding: data, as: UTF8.self)
    let parsed = try CameraRawXMP.read(data)
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      var original = try CraftDocument(width: 24, height: 18)
      original.layers[0].content = .raster(try Surface(width: 24, height: 18, fill: Pixel(0.45, 0.25, 0.6)))
      shared.store.session = EditorSession(document: original)
      try service.share(shared)
      let share = try XCTUnwrap(service.shares.first)
      let route = "/v1/documents/\(share.id)/commands"
      let revision = service.revision(shared.store)
      @MainActor func convert(_ fields: [String: Any]) async throws -> (HTTPURLResponse, Data) {
        try await helper.request(service, path: route, body: ["command": CameraRawXMPAPI.name,
          "revision": revision, "parameters": fields])
      }
      let loaded = try await convert(["mode": "rendered", "xmp": xmp])
      XCTAssertEqual(loaded.0.statusCode, 200, String(decoding: loaded.1, as: UTF8.self))
      let result = try XCTUnwrap(JSONSerialization.jsonObject(with: loaded.1) as? [String: Any])
      let settings = try XCTUnwrap(result["settings"])
      let json = try JSONSerialization.data(withJSONObject: settings)
      XCTAssertEqual(try CameraRawSettings.decodeJSON(json), parsed)
      let exported = try await convert(["mode": "rendered", "settings": settings])
      XCTAssertEqual(exported.0.statusCode, 200, String(decoding: exported.1, as: UTF8.self))
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: exported.1) as? [String: Any])
      let serialized = try XCTUnwrap(object["xmp"] as? String)
      XCTAssertEqual(try CameraRawXMP.read(Data(serialized.utf8)), parsed)
      let conflict = try await convert(["mode": "rendered", "xmp": xmp, "settings": settings])
      XCTAssertEqual(conflict.0.statusCode, 400)
      XCTAssertEqual(shared.store.document, original)
      XCTAssertEqual(service.revision(shared.store), revision)
      let layer = try XCTUnwrap(original.activeLayerID)
      var filter = RasterFilter(.cameraRaw)
      filter.cameraRaw = parsed
      var expected = original
      try Command.applyFilter(layer, filter).apply(to: &expected)
      XCTAssertNotEqual(expected, original)
      let status = try await helper.edit(service, shared, "filter.apply",
        ["layerID": layer.uuidString, "filter": ["kind": "cameraRaw", "cameraRaw": settings]])
      XCTAssertEqual(status, 200)
      XCTAssertEqual(shared.store.document, expected)
    }
  }

  @MainActor func testRawDevelopXMPResetsAsShotAndUsesSharedTransaction() async throws {
    let image = try Data(contentsOf: fixtures.appendingPathComponent("synthetic-bayer.dng"))
    var custom = RawDevelopment()
    custom.temperature = 5500
    custom.tint = 10
    custom.exposure = 0.2
    let original = try RawSourceIO.open(image, fileName: "Native source.dng", settings: custom)
    let xmp = try reference("source")
    let layer = try XCTUnwrap(original.activeLayerID)
    let base = try XCTUnwrap(original.layers.first?.smartObject?.rawDevelopment)
    let settings = try CameraRawXMP.read(xmp, into: base)
    var expected = original
    try RawSourceIO.command(in: original, layerID: layer, settings: settings).apply(to: &expected)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      shared.store.session = EditorSession(document: original)
      try service.share(shared)
      let share = try XCTUnwrap(service.shares.first)
      let route = "/v1/documents/\(share.id)/commands"
      let text = String(decoding: xmp, as: UTF8.self)
      let converted = try await helper.request(service, path: route, body: ["command": CameraRawXMPAPI.name,
        "revision": service.revision(shared.store), "parameters": ["mode": "raw", "xmp": text]])
      XCTAssertEqual(converted.0.statusCode, 200, String(decoding: converted.1, as: UTF8.self))
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: converted.1) as? [String: Any])
      let portable = try XCTUnwrap(object["settings"] as? [String: Any])
      XCTAssertTrue(portable["temperature"] is NSNull)
      XCTAssertTrue(portable["tint"] is NSNull)
      let status = try await helper.edit(service, shared, "raw.develop", ["layerID": layer.uuidString, "xmp": text])
      XCTAssertEqual(status, 200)
      XCTAssertEqual(shared.store.document, expected)
      XCTAssertNil(shared.store.document.layers[0].smartObject?.rawDevelopment?.temperature)
      XCTAssertEqual(shared.store.document.layers[0].smartObject?.rawDevelopment?.exposure, 0.2)
      XCTAssertEqual(shared.store.document.layers[0].smartObject?.data, image)
      let undo = try await helper.edit(service, shared, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(shared.store.document, original)
    }
  }
}
