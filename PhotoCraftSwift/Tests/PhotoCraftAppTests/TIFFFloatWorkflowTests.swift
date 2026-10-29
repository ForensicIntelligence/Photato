import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class TIFFFloatWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width: 5, height: 3, depth: .f32)
    var pixels = try Surface(width: 5, height: 3, depth: .f32, colorEncoding: .linearRGB)
    for y in 0..<3 {
      for x in 0..<5 {
        pixels.setLinearPixel(x: x, y: y, Pixel(Float(x) * 1.25 - 0.4,
          Float(y) * 1.5, Float(bitPattern: 0x3eaaaaab),
          x == 0 ? 0 : Float(x) / 4))
      }
    }
    d.layers[0].content = .raster(pixels)
    return d
  }
  func raw(_ d: CraftDocument) throws -> Data {
    guard case .raster(let p) = d.layers[0].content else { throw CraftError.invalid("Expected raster") }
    return try p.rgbaData(depth: .f32, colorEncoding: .linearRGB)
  }
  @MainActor func testNativeSaveAsSaveCopyReopenAndHistoryRetainHDRSamples() async throws {
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let d = CraftNSDocument(model: try fixture())
    controller.addDocument(d); defer { d.close() }
    XCTAssertTrue(d.saveFormats.contains(.tiff))
    let panel = NSSavePanel(); XCTAssertTrue(d.prepareSavePanel(panel))
    let accessory = try XCTUnwrap(d.saveAccessory)
    accessory.formats.selectItem(at: try XCTUnwrap(accessory.availableFormats.firstIndex(of: .tiff)))
    accessory.updateFormat(); XCTAssertFalse(accessory.tiffRow.isHidden)
    let target = folder.appendingPathComponent("float.tiff")
    let before = d.store.document
    try await DocumentSaveWorkflowTests().save(d, to: target, format: .tiff)
    XCTAssertEqual(d.persistenceFormat, .tiff); XCTAssertFalse(d.isDocumentEdited)
    XCTAssertEqual(try raw(DocumentIO.read(target)), try raw(before))
    try d.store.executeEditorCommand(.renameLayer(before.layers[0].id, "Renamed"))
    let snapshot = d.store.document
    try await DocumentSaveWorkflowTests().save(d, to: target, format: .tiff, operation: .saveOperation)
    XCTAssertEqual(d.store.session.undoStack.count, 1)
    XCTAssertEqual(try raw(DocumentIO.read(target)), try raw(snapshot))
    let copy = folder.appendingPathComponent("copy.tiff")
    try await d.copyDocument(to: copy, format: .tiff, options: .init(tiffCompression: .zip))
    XCTAssertEqual(try raw(DocumentIO.read(copy)), try raw(snapshot))
    XCTAssertEqual(d.fileURL, target); XCTAssertEqual(d.store.document, snapshot)
    await d.store.undo(); XCTAssertTrue(d.isDocumentEdited)
    await d.store.redo(); XCTAssertEqual(d.store.document, snapshot)
    let reopened = try XCTUnwrap(controller.makeDocument(withContentsOf: target,
      ofType: DocumentIO.Format.tiff.typeIdentifier) as? CraftNSDocument)
    defer { reopened.close() }
    XCTAssertEqual(reopened.persistenceFormat, .tiff)
    XCTAssertEqual(try raw(reopened.store.document), try raw(snapshot))
  }
  @MainActor func testActualHTTPFloatDownloadsSaveAndDeniedMismatchedRequests() async throws {
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, d in
      d.store.session = EditorSession(document: try fixture())
      service.setDocumentTransfersEnabled(true); service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(folder); try service.share(d)
      let id = try XCTUnwrap(service.shares.first?.id), before = d.store.document
      for method in RasterEncodingOptions.TIFFCompression.allCases {
        let options = RasterEncodingOptions(tiffCompression: method)
        let fields = DocumentEncodingOptions.json(options)
        let header = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
        let download = try await helper.request(service, path: "/v1/documents/\(id)/file.tiff",
          headers: ["X-Photato-Export-Options": header])
        XCTAssertEqual(download.0.statusCode, 200)
        XCTAssertEqual(download.1, try DocumentIO.encode(before, format: .tiff, options: options))
        XCTAssertEqual(try raw(RasterIO.read(download.1)), try raw(before))
      }
      let saved = try await helper.edit(service, d, "document.saveAs",
        ["name": "float", "format": "tiff", "replace": false, "options": ["tiffCompression": "lzw"]])
      XCTAssertEqual(saved, 200)
      let target = folder.appendingPathComponent("float.tiff"), bytes = try Data(contentsOf: target)
      XCTAssertEqual(try raw(RasterIO.read(bytes)), try raw(before))
      let invalid = try await helper.edit(service, d, "document.save",
        ["options": ["pngCompression": 5]])
      XCTAssertEqual(invalid, 400)
      service.setDocumentSavesEnabled(false)
      let forbidden = try await helper.edit(service, d, "document.save", [:])
      XCTAssertEqual(forbidden, 403)
      XCTAssertEqual(try Data(contentsOf: target), bytes)
      XCTAssertEqual(d.store.document, before)
    }
  }
  private struct Transport: AdobeResourceTransport {
    let data: Data
    func fetch(_ url: URL) async throws -> Data { data }
    func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
      throw CraftError.invalid("Owned hosted-output test")
    }
  }
  @MainActor func testBothActualActionJobsProduceFloatTIFFWithoutExtendingAdobeSchema() async throws {
    let input = try PSDCodec.writeRasterLayers(fixture())
    let model = try AdobeActionAssets.decode(input), helper = AutomationEncodingOptionsTests()
    try await AutomationTests().withService(pressedMouseButtons: { 0 },
      resourceTransport: Transport(data: input)) { service, shared in
      service.setResourceJobsEnabled(true)
      let before = shared.store.document
      let payload = helper.body(outputs: [helper.output("image/tiff")])
      for route in ["/v1/action-jobs", "/v2/execute-actions"] {
        let outputs = try await helper.outputs(service, route: route, payload: payload)
        XCTAssertEqual(outputs, [try DocumentIO.encode(model, format: .tiff)])
        XCTAssertEqual(try raw(RasterIO.read(XCTUnwrap(outputs.first))), try raw(model))
      }
      let options = RasterEncodingOptions.TIFFCompression.allCases.map {
        RasterEncodingOptions(tiffCompression: $0)
      }
      let extended = helper.body(outputs: options.map {
        helper.output("image/tiff", extra: ["encodingOptions": DocumentEncodingOptions.json($0)])
      })
      let native = try await helper.outputs(service, route: "/v1/action-jobs", payload: extended)
      XCTAssertEqual(native, try options.map { try DocumentIO.encode(model, format: .tiff, options: $0) })
      let rejected = try await AutomationTests().request(service, path: "/v2/execute-actions", body: extended)
      XCTAssertEqual(rejected.0.statusCode, 422)
      let png = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject:
        helper.body(outputs: [helper.output("image/png")])))
      XCTAssertThrowsError(try AdobeActionAssets.execute(png, input: input))
      XCTAssertEqual(shared.store.document, before)
    }
  }
}
