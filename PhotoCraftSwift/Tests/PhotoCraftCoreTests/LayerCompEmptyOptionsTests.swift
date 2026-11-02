import XCTest
@testable import PhotoCraftCore

final class LayerCompEmptyOptionsTests: XCTestCase {
  func testNoPropertyCompIsValidRetainedByNative82AndDoesNotChangeLayers() throws {
    var d = try CraftDocument(width: 4, height: 3); let id = UUID()
    let options = LayerCompOptions(visibility: false, position: false, appearance: false)
    try Command.layerComp(.capture(id: id, name: "Named state", comment: "No captured properties", options: options)).apply(to: &d)
    XCTAssertEqual(d.minimumArchiveVersion, 82)
    d.layers[0].visible = false; d.layers[0].x = 2; let before = d.layers
    try Command.layerComp(.apply(id)).apply(to: &d); XCTAssertEqual(d.layers, before)
    for bytes in [try NativeArchive.encode(d), try NativeArchive.encodeChunked(d)] {
      XCTAssertEqual(try NativeArchive.decode(bytes), d); XCTAssertEqual(try NativeArchive.decodePaged(bytes), d)
    }
    XCTAssertThrowsError(try Command.layerComp(.capture(id: UUID(), name: " ", comment: "", options: options)).apply(to: &d))
  }
  func testClearingSourceCompsPersistsExplicitIntentThroughNativeHistoryAndRecapture() throws {
    var d = try CraftDocument(width: 4, height: 3); d.sourceMetadata = ["psdResources": Data()]
    try Command.layerComp(.capture(id: UUID(), name: "Original", comment: "", options: .init())).apply(to: &d)
    var session = EditorSession(document: d); try session.execute(.layerComp(.clear))
    XCTAssertNil(session.document.layerComps); XCTAssertTrue(session.document.clearedSourceLayerComps); XCTAssertEqual(session.document.minimumArchiveVersion, 82)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(session.document)), session.document)
    try session.undo(); XCTAssertEqual(session.document, d); try session.redo(); XCTAssertTrue(session.document.clearedSourceLayerComps)
    try session.execute(.layerComp(.capture(id: UUID(), name: "Replacement", comment: "", options: .init())))
    XCTAssertFalse(session.document.clearedSourceLayerComps); XCTAssertEqual(session.document.minimumArchiveVersion, 79)
  }
}
