import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class PSBTaggedBlockWorkflowTests: XCTestCase {
  let display = Data([0,0,255,255,0,0,0,0,0,0,0,50])
  func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width: 8, height: 4)
    d.channelOnly = true; d.layers = []; d.activeLayerID = nil
    var mask = try Surface(width: 8, height: 4, fill: .black); mask.setPixel(x: 3, y: 2, .white)
    var alpha = AlphaChannel(name: "Owned API selection", pixels: mask); alpha.psdIdentifier = 2
    d.alphaChannels = [alpha]; d.sourceMetadata = ["psdGlobal_FMsk":display]
    return d
  }
  func assertWire(_ data: Data, psb: Bool, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNotNil(data.range(of: Data(((psb ? "8B64":"8BIM") + "FMsk").utf8)), file: file, line: line)
    XCTAssertNil(data.range(of: Data(((psb ? "8BIM":"8B64") + "FMsk").utf8)), file: file, line: line)
  }
  @MainActor func testNativeCopyDataAndReopenUseSameCorrectFramingWithoutDocumentMutation() async throws {
    let d = try fixture(), file = CraftNSDocument(model: d), folder = try DocumentPersistenceTests().directory()
    defer { file.store.renderTask?.cancel(); file.close(); try? FileManager.default.removeItem(at: folder) }
    for format in [DocumentIO.Format.psd,.psb] {
      let url = folder.appendingPathComponent("owned." + format.rawValue)
      try await file.copyDocument(to: url, format: format)
      let bytes = try Data(contentsOf: url)
      XCTAssertEqual(bytes, try DocumentIO.encode(d, format: format))
      assertWire(bytes, psb: format == .psb)
      let read = try DocumentIO.read(url)
      XCTAssertEqual(read.alphaChannels?.first?.pixels, d.alphaChannels?.first?.pixels)
      XCTAssertEqual(read.sourceMetadata?["psdGlobal_FMsk"], display)
      XCTAssertEqual(file.store.document, d); XCTAssertNil(file.fileURL); XCTAssertTrue(file.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testRealHTTPDownloadEqualsDesktopAndAdvertisesExistingSharedEncoding() async throws {
    try await AutomationTests().withService(pressedMouseButtons: {0}) { service, file in
      service.setDocumentTransfersEnabled(true)
      file.store.session = EditorSession(document: try self.fixture())
      try service.share(file)
      let id = try XCTUnwrap(service.shares.first(where: { $0.document === file })).id.uuidString
      let (response, bytes) = try await LargeSelectionFileWorkflowTests().request(service, "/v1/documents/\(id)/file.psb")
      XCTAssertEqual(response.statusCode, 200)
      self.assertWire(bytes, psb: true)
      XCTAssertEqual(bytes, try DocumentIO.encode(file.store.document, format: .psb))
      let read = try DocumentIO.decodeUpload(bytes, native: false, name: "HTTP")
      XCTAssertEqual(read.alphaChannels?.first?.pixels, file.store.document.alphaChannels?.first?.pixels)
      XCTAssertTrue(file.store.session.undoStack.isEmpty)
      let caps = try XCTUnwrap(DocumentEncodingOptions.capabilities["photoshopTaggedBlocks"] as? [String:Any])
      XCTAssertEqual(caps["psbWideSignature"] as? String, "8B64"); XCTAssertEqual(caps["psbWideLengthBytes"] as? Int, 8)
      XCTAssertEqual(AutomationCommand.definitions.count, 239)
    }
  }
  func testPublishedCompositePreservesPSBInputAndKeepsPSDOutputAtFourByteFraming() throws {
    let d = try fixture(), input = try DocumentIO.encode(d, format: .psb)
    assertWire(input, psb: true)
    let request = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: ["image":["source":["url":"https://example.test/owned.psb"]],"outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]), createComposite: true)
    let result = try XCTUnwrap(AdobeActionAssets.execute(request, input: input).first)
    assertWire(result.data, psb: false)
    let read = try PSDCodec.readPaged(result.data)
    XCTAssertEqual(read.alphaChannels?.first?.pixels, d.alphaChannels?.first?.pixels)
    XCTAssertEqual(read.sourceMetadata?["psdGlobal_FMsk"], display)
  }
}
