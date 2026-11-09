import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class Gray32ExportWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var document = try CraftDocument(width: 2, height: 1, depth: .f32, name: "Owned Gray32 API")
    var gray = try NativeModeRaster(width: 2, height: 1, mode: .grayscale, depth: .f32)
    for (i, value) in [Float(-0.25), 2.5].enumerated() {
      try gray.set(value, component: 0, index: i)
      try gray.set(1, component: 1, index: i)
    }
    document.modeDescriptor = try .init(mode: .grayscale, depth: .f32, profile: gray.profile)
    document.layers[0].nativeMode = gray; document.layers[0].content = .raster(try gray.surface())
    document.layers[0].background = true
    return document
  }
  func assertOutput(_ bytes: Data, source: CraftDocument,
    file: StaticString = #filePath, line: UInt = #line) throws {
    XCTAssertGreaterThanOrEqual(bytes.count, 140, file: file, line: line)
    XCTAssertEqual(Array(bytes[26..<30]), [0, 0, 0, 110], file: file, line: line)
    XCTAssertEqual(bytes[30..<34], Data("hdrt".utf8), file: file, line: line)
    let restored = try PSDCodec.read(bytes)
    XCTAssertEqual(restored.colorMode, .grayscale, file: file, line: line)
    XCTAssertEqual(try restored.layers[0].nativeMode?.planes, try source.layers[0].nativeMode?.planes, file: file, line: line)
  }
  @MainActor func testRealHTTPGray32PSDAndPSBDownloadsKeepPermissionsRevisionsAndSource() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.renderTask?.cancel(); document.store.session = EditorSession(document: try self.fixture())
      try service.share(document)
      let share = try XCTUnwrap(service.shares.first), source = document.store.document
      let revision = service.revision(document.store), dirty = document.isDocumentEdited
      for format in ["psd", "psb"] {
        let path = "/v1/documents/\(share.id)/file.\(format)"
        service.setDocumentTransfersEnabled(false)
        let denied = try await helper.request(service, path: path)
        XCTAssertEqual(denied.0.statusCode, 403)
        service.setDocumentTransfersEnabled(true)
        let stale = try await helper.request(service, path: path, headers: ["X-Photato-Revision":"old"])
        XCTAssertEqual(stale.0.statusCode, 409)
        let output = try await helper.request(service, path: path, headers: ["X-Photato-Revision":revision])
        XCTAssertEqual(output.0.statusCode, 200)
        try self.assertOutput(output.1, source: source)
      }
      XCTAssertEqual(document.store.document, source)
      XCTAssertEqual(service.revision(document.store), revision)
      XCTAssertEqual(document.isDocumentEdited, dirty)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let containers = try XCTUnwrap(AutomationService.documentTransferCapabilities["photoshopContainers"] as? [String:Any])
      let hdr = try XCTUnwrap(containers["hdrMetadata"] as? [String:Any])
      XCTAssertEqual(hdr["modes"] as? [String], ["rgb","grayscale"])
    }
  }
  func testAdobeResourceOutputUsesTheSameGray32MetadataAndSampleSerializer() throws {
    let source = try fixture()
    let body: [String:Any] = ["image":["width":2,"height":1,"mode":"grayscale","depth":32],
      "outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]
    for photato in [false, true] {
      let request = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: body),
        allowPhotatoOptions: photato, createComposite: true)
      let outputs = try AdobeActionAssets.encode(request, document: source)
      XCTAssertEqual(outputs.count, 1)
      try assertOutput(XCTUnwrap(outputs.first).data, source: source)
    }
  }
}
