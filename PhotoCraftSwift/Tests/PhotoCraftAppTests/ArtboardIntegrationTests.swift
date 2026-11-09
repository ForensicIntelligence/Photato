import AppKit
import CoreGraphics
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ArtboardIntegrationTests: XCTestCase {
  func fixture() throws -> CraftDocument { try ArtboardWorkflowTests().fixture() }
  func testExtractionAndImagePDFExportsPreserveSourceAndBounds() throws {
    var source = try fixture()
    try Command.artboard(.create(name: "Small", bounds: .init(x: 40, y: 0, width: 5, height: 7), background: Pixel(0, 0, 1), children: [])).apply(to: &source)
    let original = source, ids = source.artboards.map(\.id)
    let extracted = try source.extractedArtboard(ids[0])
    XCTAssertEqual(extracted.width, 20); XCTAssertEqual(extracted.height, 10)
    XCTAssertEqual(extracted.layers[0].content, source.layers[0].content)
    let pixels = try Renderer.composite(extracted)
    XCTAssertEqual(pixels.pixel(x: 5, y: 2), Pixel(1, 0, 0)); XCTAssertEqual(pixels.pixel(x: 5, y: 8), .white)
    let png = try ArtboardExport.encode(source, ids: [ids[0]], format: "png")
    XCTAssertEqual(try Renderer.composite(RasterIO.read(png, name: "Result")), pixels)
    let archive = try ArtboardExport.encode(source, ids: [ids[0]], format: "photato")
    let restored = try NativeArchive.decode(archive); XCTAssertEqual(restored.artboards.count, 1); XCTAssertEqual(restored.width, 20)
    let pdf = try ArtboardExport.encode(source, ids: ids, format: "pdf")
    let parsed = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: pdf as CFData)!))
    XCTAssertEqual(parsed.numberOfPages, 2); XCTAssertEqual(parsed.page(at: 1)?.getBoxRect(.mediaBox).size, CGSize(width: 20, height: 10)); XCTAssertEqual(parsed.page(at: 2)?.getBoxRect(.mediaBox).size, CGSize(width: 5, height: 7))
    XCTAssertEqual(source, original)
    XCTAssertThrowsError(try ArtboardExport.encode(source, ids: ids, format: "png"))
    XCTAssertThrowsError(try ArtboardExport.encode(source, ids: [ids[0], ids[0]], format: "pdf"))
    let photoshop = try PSDCodec.read(DocumentIO.encode(source,format:.psd))
    XCTAssertEqual(photoshop.artboards.count,source.artboards.count)
    XCTAssertEqual(photoshop.artboards.compactMap{photoshop.logicalArtboardBounds($0)},source.artboards.compactMap{source.logicalArtboardBounds($0)})
  }
  func testArtboardGradientExtractionMatchesOriginalComposite() throws {
    var document = try fixture()
    document.layers[0].content = .gradientFill(GradientFill(dither: false))
    let composite = try Renderer.composite(document), board = document.artboards[0]
    let extracted = try Renderer.composite(document.extractedArtboard(board.id))
    for y in 0..<extracted.height { for x in 0..<extracted.width {
      XCTAssertEqual(extracted.pixel(x: x, y: y), composite.pixel(x: x + board.x, y: y + board.y))
    } }
  }
  func testExclusiveExportNeverOverwrites() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("board.png")
    try ArtboardExport.writeNew(Data([1,2,3]), to: file)
    XCTAssertThrowsError(try ArtboardExport.writeNew(Data([4,5]), to: file)); XCTAssertEqual(try Data(contentsOf: file), Data([1,2,3]))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["board.png"])
  }
  @MainActor func testNativePropertiesGestureCancelAndUndo() async throws {
    let source = try fixture(), store = EditorStore(document: source, actions: ActionLibrary())
    defer { store.renderTask?.cancel() }
    store.beginArtboard(edit: true)
    let draft = try XCTUnwrap(store.artboardDraft)
    draft.name = "Web"; draft.width = 24; draft.x = 12; draft.moveContents = false
    store.commitArtboard(draft)
    XCTAssertNil(store.artboardDraft); XCTAssertNil(store.error)
    XCTAssertEqual(store.document.artboards[0].name, "Web"); XCTAssertEqual(store.document.artboards[0].x, 12)
    XCTAssertEqual(store.document.layers[0].x, source.layers[0].x)
    let edited = store.document
    let undone = await store.requestHistory(redo: false).value; XCTAssertTrue(undone); XCTAssertEqual(store.document, source)
    let redone = await store.requestHistory(redo: true).value; XCTAssertTrue(redone); XCTAssertEqual(store.document, edited)
    let board = store.document.artboards[0], bounds = board.artboardBounds!
    var gesture = ArtboardGesture(original: store.document, layerID: board.id, start: .zero, bounds: bounds, corner: nil, current: bounds)
    gesture.drag(to: CGPoint(x: 5, y: 4), square: false); store.artboardGesture = gesture
    XCTAssertEqual(store.document, edited)
    store.artboardGesture = nil; XCTAssertEqual(store.document, edited)
    store.artboardGesture = gesture; store.finishArtboardGesture()
    XCTAssertEqual(store.document.artboards[0].x, bounds.x + 5); XCTAssertEqual(store.document.layers[0].x, edited.layers[0].x + 5)
    store.fitArtboard(store.document.artboards[0].artboardBounds!); XCTAssertGreaterThan(store.zoom, 0)
  }
  @MainActor func testPhotatoAPIHistoryBusyStaleAndExport() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
      try service.share(document)
      let layerID = document.store.document.layers[0].id.uuidString
      let create: [String: Any] = ["operation": "create", "name": "API Board", "bounds": ["x": 1, "y": 1, "width": 3, "height": 2], "layerIDs": [layerID]]
      let status = try await helper.edit(service, document, "artboard.edit", create); XCTAssertEqual(status, 200)
      let board = try XCTUnwrap(document.store.document.artboards.first), before = document.store.document
      let bounds: [String: Any] = ["x": 2, "y": 0, "width": 4, "height": 3]
      let parameters: [String: Any] = ["operation": "configure", "layerID": board.id.uuidString, "bounds": bounds, "name": "Changed", "moveContents": false]
      var expected = before; try Command.artboard(.configure(board.id, name: "Changed", bounds: .init(x: 2, y: 0, width: 4, height: 3), appearance: .init(width: 4, height: 3), moveContents: false)).apply(to: &expected)
      let configure = try await helper.edit(service, document, "artboard.edit", parameters); XCTAssertEqual(configure, 200); XCTAssertEqual(document.store.document, expected)
      let undo = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo, 200); XCTAssertEqual(document.store.document, before)
      document.store.beginArtboard(edit: true)
      let busy = try await helper.edit(service, document, "artboard.edit", parameters); XCTAssertEqual(busy, 409); document.store.artboardDraft = nil
      let bad = try await helper.edit(service, document, "artboard.edit", ["operation": "configure", "layerID": board.id.uuidString, "bounds": bounds, "moveContents": "yes"]); XCTAssertEqual(bad, 400); XCTAssertEqual(document.store.document, before)
      let path = "/v1/documents/\(try XCTUnwrap(service.shares.first?.id))/commands"
      let stale = try await helper.request(service, path: path, body: ["command": "artboard.edit", "revision": "stale", "parameters": parameters]); XCTAssertEqual(stale.0.statusCode, 409)
      service.setDocumentTransfersEnabled(true)
      let exported = try await helper.request(service, path: path, body: ["command": "artboard.export", "revision": service.revision(document.store), "parameters": ["layerIDs": [board.id.uuidString], "format": "png"]])
      XCTAssertEqual(exported.0.statusCode, 200); XCTAssertEqual(try RasterIO.read(exported.1, name: "Export").width, 3)
      XCTAssertEqual(document.store.document, before)
      let nativePath = path.replacingOccurrences(of: "/commands", with: "/file.photato")
      let oldArchive = try await helper.request(service, path: nativePath); XCTAssertEqual(oldArchive.0.statusCode, 422)
      let native = try await helper.request(service, path: nativePath, headers: ["X-Photato-Archive-Version": "27"])
      XCTAssertEqual(native.0.statusCode, 200); XCTAssertEqual(try NativeArchive.decode(native.1), before)
      for name in ["artboard.edit", "artboard.export"] { XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: AutomationCommand.definitions.first { $0.name == name }!.schema)) }
    }
  }
}
