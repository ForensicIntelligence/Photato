import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RawWorkflowOutputTests: XCTestCase {
  private func fixture() throws -> CraftDocument {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let file = folder.appendingPathComponent("Fixtures/Raw/raw-with-embedded-xmp.dng")
    return try RawSourceIO.open(Data(contentsOf: file), fileName: file.lastPathComponent)
  }

  func testWorkflowDPIAndColorSpacePreserveTheOriginalSensor() throws {
    let source = try fixture()
    let object = try XCTUnwrap(source.layers[0].smartObject)
    let dpiOnly = try RawOpenMode.object.output(from: source, workflow: .init(pixelsPerInch: 300))
    XCTAssertEqual(dpiOnly.width, source.width)
    XCTAssertEqual(dpiOnly.height, source.height)
    XCTAssertEqual(dpiOnly.layers[0].content, source.layers[0].content)
    XCTAssertEqual(dpiOnly.pixelsPerInch, 300)

    let recipe = RawWorkflowOutput(profile: .displayP3, depth: .u8, pixelsPerInch: 240)
    let smart = try RawOpenMode.object.output(from: source, workflow: recipe)
    let pixels = try RawOpenMode.image.output(from: source, workflow: recipe)
    XCTAssertEqual(smart.workingICC, try RawWorkflowOutput.Profile.displayP3.icc())
    XCTAssertEqual(pixels.workingICC, smart.workingICC)
    XCTAssertEqual(pixels.layers[0].content, smart.layers[0].content)
    XCTAssertNotEqual(smart.layers[0].content, source.layers[0].content)
    XCTAssertEqual(smart.pixelsPerInch, 240)
    XCTAssertEqual(pixels.pixelsPerInch, 240)
    XCTAssertEqual(smart.depth, .u8)
    XCTAssertEqual(pixels.depth, .u8)
    XCTAssertTrue(pixels.layers[0].isBackground)
    XCTAssertEqual(smart.layers[0].smartObject?.data, object.data)
    XCTAssertEqual(smart.layers[0].smartObject?.rawDevelopment, object.rawDevelopment)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(smart)), smart)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(pixels)), pixels)

    var redeveloped = smart
    let settings = try XCTUnwrap(object.rawDevelopment)
    try RawSourceIO.command(in: smart, layerID: smart.layers[0].id, settings: settings).apply(to: &redeveloped)
    XCTAssertEqual(redeveloped.layers[0].content, smart.layers[0].content)
    XCTAssertEqual(redeveloped.workingICC, smart.workingICC)
  }

  func testResizeModesFitBothOrientationsAndRejectInvalidGeometry() throws {
    typealias Resize = RawWorkflowOutput.Resize
    let modes: [(Resize, Int, Int)] = [
      (.init(mode: .widthHeight, value: 700, secondValue: 300), 451, 300),
      (.init(mode: .dimensions, value: 300, secondValue: 700), 451, 300),
      (.init(mode: .longSide, value: 1_504), 1_504, 1_000),
      (.init(mode: .shortSide, value: 1_000), 1_504, 1_000),
      (.init(mode: .megapixels, value: 1.504), 1_504, 1_000),
      (.init(mode: .percentage, value: 50), 1_504, 1_000),
      (.init(mode: .percentage, value: 200, dontEnlarge: true), 3_008, 2_000),
    ]
    for (settings, width, height) in modes {
      let size = try settings.dimensions(width: 3_008, height: 2_000)
      XCTAssertEqual(size.width, width, settings.mode.rawValue)
      XCTAssertEqual(size.height, height, settings.mode.rawValue)
    }
    let rotated = try Resize(mode: .dimensions, value: 700, secondValue: 300)
      .dimensions(width: 2_000, height: 3_008)
    XCTAssertEqual(rotated.width, 300)
    XCTAssertEqual(rotated.height, 451)
    XCTAssertThrowsError(try Resize(mode: .widthHeight, value: 700).dimensions(width: 3_008, height: 2_000))
    XCTAssertThrowsError(try Resize(mode: .percentage, value: .greatestFiniteMagnitude).dimensions(width: 3_008, height: 2_000))
    XCTAssertThrowsError(try RawWorkflowOutput(depth: .f32).validate())
    XCTAssertThrowsError(try RawWorkflowOutput(pixelsPerInch: 0).validate())
  }

  func testResizedObjectKeepsOriginalDimensionsAndCanRedevelop() throws {
    let source = try fixture()
    let recipe = RawWorkflowOutput(pixelsPerInch: 240, resize: .init(mode: .percentage, value: 50))
    let object = try RawOpenMode.object.output(from: source, workflow: recipe)
    let image = try RawOpenMode.image.output(from: source, workflow: recipe)
    let raw = try XCTUnwrap(object.layers[0].smartObject)
    XCTAssertEqual(raw.width, source.width)
    XCTAssertEqual(raw.height, source.height)
    XCTAssertEqual(object.width, 256)
    XCTAssertEqual(object.height, 192)
    XCTAssertEqual(image.width, object.width)
    XCTAssertEqual(image.height, object.height)
    XCTAssertEqual(image.pixelsPerInch, object.pixelsPerInch)
    XCTAssertEqual(object.layers[0].coordinateTransform, .scale(0.5, 0.5))
    XCTAssertTrue(image.layers[0].isBackground)
    var refreshed = object
    try RawSourceIO.command(in: object, layerID: object.layers[0].id, settings: XCTUnwrap(raw.rawDevelopment))
      .apply(to: &refreshed)
    XCTAssertEqual(refreshed.layers[0].coordinateTransform, object.layers[0].coordinateTransform)
    XCTAssertEqual(refreshed.layers[0].content, object.layers[0].content)
  }
  @MainActor func testHTTPWorkflowOutputAndPersistentPreferences() async throws {
    let source = try XCTUnwrap(try fixture().layers[0].smartObject?.data)
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }) { service, original in
      defer { for document in service.controller.documents where document !== original { document.close() } }
      service.setDocumentTransfersEnabled(true)
      service.setPhotoshopPreferenceChangesEnabled(true)
      let value: [String: Any] = [
        "profile": "displayP3", "depth": PixelDepth.u8.rawValue, "pixelsPerInch": 300,
        "resize": ["mode": "percentage", "value": 50, "dontEnlarge": false]
      ]
      let json = try JSONSerialization.data(withJSONObject: value)
      let header = ["X-Photato-Raw-Workflow": json.base64EncodedString(), "X-Photato-Raw-Open-Mode": "image"]
      let helper = AutomationOpeningTests()
      let wrongType = try await helper.upload(service, bytes: source, type: "image/png", headers: header)
      XCTAssertEqual(wrongType.0.statusCode, 415)
      let invalid = try await helper.upload(service, bytes: source, type: "image/x-adobe-dng",
        headers: ["X-Photato-Raw-Workflow": Data("{\"pixelsPerInch\":-1}".utf8).base64EncodedString()])
      XCTAssertEqual(invalid.0.statusCode, 400)
      let result = try await helper.upload(service, bytes: source, type: "image/x-adobe-dng", headers: header)
      XCTAssertEqual(result.0.statusCode, 201, String(decoding: result.1, as: UTF8.self))
      let document = try XCTUnwrap(service.shares.last?.document)
      let opened = document.store.document
      XCTAssertEqual(opened.width, 256)
      XCTAssertEqual(opened.height, 192)
      XCTAssertEqual(opened.pixelsPerInch, 300)
      XCTAssertEqual(opened.depth, .u8)
      XCTAssertEqual(opened.workingICC, try RawWorkflowOutput.Profile.displayP3.icc())
      XCTAssertTrue(opened.layers[0].isBackground)

      let preferences = service.controller.cameraRawPreferences
      let update = try await api.request(service, path: AutomationService.cameraRawPreferencesPath,
        body: ["revision": preferences.revision.uuidString, "workflow": value])
      XCTAssertEqual(update.0.statusCode, 200)
      XCTAssertEqual(preferences.workflowOutput, try RawWorkflowOutput.apiValue(value))
      let ordinary = try await helper.upload(service, bytes: source, type: "image/x-adobe-dng")
      XCTAssertEqual(ordinary.0.statusCode, 201)
      XCTAssertEqual(service.shares.last?.document?.store.document.width, 512)
      XCTAssertEqual(service.shares.last?.document?.store.document.depth, .u16)
    }
  }
}
