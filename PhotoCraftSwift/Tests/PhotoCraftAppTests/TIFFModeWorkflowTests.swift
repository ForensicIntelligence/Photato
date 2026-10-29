import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class TIFFModeWorkflowTests: XCTestCase {
  func fixture(_ mode: DocumentColorMode, _ depth: PixelDepth) throws -> CraftDocument {
    var document = try CraftDocument(width: 4, height: 3, depth: depth)
    document = try document.convertingMode(.init(mode: mode, depth: depth))
    var native = try XCTUnwrap(document.layers[0].nativeMode)
    for c in 0..<mode.componentCount { for i in 0..<12 {
      try native.set(Float((c * 41 + i * 17) % 256) / 255, component: c, index: i)
    } }
    for i in 0..<12 { try native.set(i % 2 == 0 ? 1 : 0.5, component: mode.componentCount, index: i) }
    document.layers[0].nativeMode = native; document.layers[0].content = .raster(try native.surface())
    try document.validate(); return document
  }
  @MainActor func testNativeSaveAccessoryKeepsModeLayersAndDocumentOwnership() async throws {
    for mode in [DocumentColorMode.grayscale, .cmyk, .lab] {
      let (controller, doc, folder) = try DocumentEncodingOptionsTests().fixture()
      defer { doc.updateChangeCount(.changeCleared); doc.close(); _ = controller }
      doc.store.session = EditorSession(document: try fixture(mode, .u16))
      let before = doc.store.document, panel = NSSavePanel()
      XCTAssertTrue(doc.prepareSavePanel(panel))
      let a = try XCTUnwrap(doc.saveAccessory)
      a.formats.selectItem(at: try XCTUnwrap(a.availableFormats.firstIndex(of: .tiff))); a.updateFormat()
      let options = a.encodingOptions
      XCTAssertEqual(options.tiffLayers, true)
      let url = folder.appendingPathComponent("\(mode.rawValue).tiff")
      try await DocumentSaveWorkflowTests().save(doc, to: url, format: .tiff)
      let read = try DocumentIO.read(url)
      XCTAssertEqual(read.layers[0].nativeMode, before.layers[0].nativeMode)
      XCTAssertEqual(doc.fileURL, url); XCTAssertFalse(doc.isDocumentEdited)
      XCTAssertEqual(doc.store.document, before)
    }
  }
  private struct Transport: AdobeResourceTransport {
    let data: Data
    func fetch(_ url: URL) async throws -> Data { data }
    func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws { throw CraftError.invalid("Expected hosted output") }
  }
  @MainActor func testBothJobRoutesKeepTIFFModeComponentsAndAdobeOutputContract() async throws {
    let helper = AutomationEncodingOptionsTests()
    func payload(_ outputs: [[String: Any]]) -> [String: Any] {
      var body = helper.body(outputs: outputs)
      body["options"] = ["actions": [["source": [
        "content": "[{\"_obj\":\"selectAllLayers\",\"_target\":[{\"_ref\":\"layer\",\"_enum\":\"ordinal\",\"_value\":\"targetEnum\"}]}]",
        "contentType": "application/json"]]]]
      return body
    }
    for mode in [DocumentColorMode.grayscale, .cmyk, .lab] {
      let source = try fixture(mode, .u16)
      let data = try RasterIO.encoded(source, type: .tiff, options: .init(tiffLayers: true))
      try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: Transport(data: data)) { service, shared in
        service.setResourceJobsEnabled(true); let before = shared.store.document
        let native = try await helper.outputs(service, route: "/v1/action-jobs", payload: payload([
          helper.output("image/tiff", extra: ["encodingOptions": ["tiffLayers": true, "tiffCompression": "zip"]])]))
        XCTAssertEqual(try RasterIO.read(XCTUnwrap(native.first)).layers[0].nativeMode, source.layers[0].nativeMode)
        let adobe = try await helper.outputs(service, route: "/v2/execute-actions", payload: payload([helper.output("image/tiff")]))
        let expected = try RasterIO.read(RasterIO.encoded(source, type: .tiff))
        let actual = try RasterIO.read(XCTUnwrap(adobe.first))
        XCTAssertEqual(actual.colorMode, mode); XCTAssertEqual(actual.layers[0].nativeMode?.planes, expected.layers[0].nativeMode?.planes)
        XCTAssertEqual(shared.store.document, before)
      }
    }
  }
}
