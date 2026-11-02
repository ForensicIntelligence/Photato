import XCTest
@testable import PhotoCraftCore

final class ParentLayerCompModelTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width: 4, height: 3)
    var object = try SmartObjectLayerCompModelTests().model()
    let id = object.layerComps!.entries[0].id; object.layerComps?.selectedID = id
    d.layers[0].smartObject = object; return d
  }
  func testSmartOnlyCaptureStoresIdentifiersAndNative81RetainsBothEncodings() throws {
    var d = try fixture(); let id = UUID(), options = LayerCompOptions(visibility: false, position: false, appearance: false, smartObjects: true)
    try Command.layerComp(.capture(id: id, name: "Source choice", comment: "", options: options)).apply(to: &d)
    let state = d.layerComps!.comps[0].layers[0]
    XCTAssertNil(state.visible); XCTAssertNil(state.appearance); XCTAssertNil(state.x)
    XCTAssertEqual(state.smartObjectSelection?.sourceID, d.layers[0].smartObject?.sourceID)
    XCTAssertEqual(state.smartObjectSelection?.compID, d.layers[0].smartObject?.layerComps?.selectedID)
    XCTAssertEqual(d.minimumArchiveVersion, 81)
    for bytes in [try NativeArchive.encode(d), try NativeArchive.encodeChunked(d)] {
      XCTAssertEqual(try NativeArchive.decode(bytes), d); XCTAssertEqual(try NativeArchive.decodePaged(bytes), d)
    }
    let encoded = try JSONEncoder().encode(state); XCTAssertLessThan(encoded.count, 256)
  }
  func testOlderOptionsDecodeWithoutFourthPropertyAndOrdinaryCaptureDoesNotRecordChoice() throws {
    let old = Data(#"{"visibility":true,"position":true,"appearance":true}"#.utf8)
    let options = try JSONDecoder().decode(LayerCompOptions.self, from: old)
    XCTAssertFalse(options.recordsSmartObjects); XCTAssertNil(options.smartObjects)
    var d = try fixture(); let id = UUID()
    try Command.layerComp(.capture(id: id, name: "Ordinary", comment: "", options: options)).apply(to: &d)
    XCTAssertNil(d.layerComps?.comps[0].layers[0].smartObjectSelection)
    d.layers[0].smartObject?.layerComps?.selectedID = nil
    try Command.layerComp(.apply(id)).apply(to: &d)
    XCTAssertNil(d.layers[0].smartObject?.layerComps?.selectedID)
  }
  func testUnpreparedChoiceChangedOrConvertedSourceRejectsAtomicallyAndWarns() throws {
    var d = try fixture(); let id = UUID()
    try Command.layerComp(.capture(id: id, name: "Recorded", comment: "", options: .init(smartObjects: true))).apply(to: &d)
    d.layers[0].smartObject?.layerComps?.selectedID = nil; let before = d
    XCTAssertThrowsError(try Command.layerComp(.apply(id)).apply(to: &d)); XCTAssertEqual(d, before)
    d.layers[0].smartObject?.sourceID = UUID()
    XCTAssertEqual(d.layerComps?.comps[0].unavailableSmartObjectLayers(in: d), [d.layers[0].id])
    let changed = d; XCTAssertThrowsError(try Command.layerComp(.apply(id)).apply(to: &d)); XCTAssertEqual(d, changed)
    d.layers[0].smartObject = nil
    XCTAssertEqual(d.layerComps?.comps[0].unavailableSmartObjectLayers(in: d), [d.layers[0].id])
  }
}
