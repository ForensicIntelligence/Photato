import XCTest
@testable import PhotoCraftCore

final class LayerCompsTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 8, height: 6, depth: depth)
    let top = Layer(name: "Red", content: .raster(try Surface(width: 2, height: 2, depth: depth, fill: Pixel(1, 0, 0))))
    d.layers.append(top); d.activeLayerID = top.id; return d
  }
  func capture(_ d: inout CraftDocument, id: UUID, options: LayerCompOptions = .init()) throws {
    try Command.layerComp(.capture(id: id, name: "Layout", comment: "Owned fixture", options: options)).apply(to: &d)
  }
  func testEveryPropertyCombinationAcrossDepthsLeavesUnrecordedPropertiesAlone() throws {
    for depth in PixelDepth.allCases {
      for bits in 1...7 {
        let id = UUID(), options = LayerCompOptions(visibility: bits & 1 != 0, position: bits & 2 != 0, appearance: bits & 4 != 0)
        var d = try fixture(depth); try capture(&d, id: id, options: options)
        let pixels = d.layers[1].content
        d.layers[1].visible = false; d.layers[1].x = 3; d.layers[1].y = 2; d.layers[1].opacity = 0.5; d.layers[1].blendMode = .multiply
        try Command.layerComp(.apply(id)).apply(to: &d)
        XCTAssertEqual(d.layers[1].visible, options.visibility)
        XCTAssertEqual(d.layers[1].x, options.position ? 0 : 3); XCTAssertEqual(d.layers[1].y, options.position ? 0 : 2)
        XCTAssertEqual(d.layers[1].opacity, options.appearance ? 1 : 0.5); XCTAssertEqual(d.layers[1].blendMode, options.appearance ? .normal : .multiply)
        XCTAssertEqual(d.layers[1].content, pixels); XCTAssertTrue(d.layerComps!.comps[0].matches(d))
      }
    }
  }
  func testPositionDoesNotRestoreRotationScaleOrPixelContent() throws {
    let id = UUID(); var d = try fixture(); d.layers[1].affine = .init(a: 1, b: 0, c: 0, d: 1, tx: 1.5, ty: 2.5)
    try capture(&d, id: id, options: .init(visibility: false, position: true, appearance: false))
    d.layers[1].affine = .init(a: 2, b: 0.5, c: 0.25, d: 3, tx: 4, ty: 5)
    d.layers[1].content = .raster(try Surface(width: 2, height: 2, depth: .u8, fill: Pixel(0, 1, 0)))
    let content = d.layers[1].content
    try Command.layerComp(.apply(id)).apply(to: &d)
    XCTAssertEqual(d.layers[1].affine, .init(a: 2, b: 0.5, c: 0.25, d: 3, tx: 1.5, ty: 2.5)); XCTAssertEqual(d.layers[1].content, content)
  }
  func testStyleAndNilStyleRestoreWithoutRestoringMasks() throws {
    var d = try fixture(); let first = UUID(), second = UUID(); try capture(&d, id: first)
    d.layers[1].style = LayerStyle(effects: [.init(.dropShadow)]); d.layers[1].style?.fillOpacity = 0.3
    try capture(&d, id: second); let style = d.layers[1].style
    let mask = try Surface(width: 2, height: 2, depth: .u8, fill: Pixel(0.25, 0.25, 0.25)); d.layers[1].mask = mask
    try Command.layerComp(.apply(first)).apply(to: &d); XCTAssertNil(d.layers[1].style); XCTAssertEqual(d.layers[1].mask, mask)
    try Command.layerComp(.apply(second)).apply(to: &d); XCTAssertEqual(d.layers[1].style, style); XCTAssertEqual(d.layers[1].mask, mask)
  }
  func testApplyLastStateAndHistoryAreAtomicAndIdempotent() throws {
    let id = UUID(); var d = try fixture(); try capture(&d, id: id); d.layers[1].x = 3
    var s = EditorSession(document: d); try s.execute(.layerComp(.apply(id))); let applied = s.document
    XCTAssertEqual(applied.layers[1].x, 0); try s.execute(.layerComp(.apply(id))); XCTAssertEqual(s.document, applied)
    try s.undo(); XCTAssertEqual(s.document, d); try s.redo(); XCTAssertEqual(s.document, applied)
    try s.execute(.layerComp(.restoreLast)); XCTAssertEqual(s.document.layers, d.layers); XCTAssertNil(s.document.layerComps?.lastDocumentState)
    try s.undo(); XCTAssertEqual(s.document, applied)
  }
  func testManageCompIdentitiesAndInvalidEditsRollback() throws {
    let a = UUID(), b = UUID(); var d = try fixture(); try capture(&d, id: a)
    try Command.layerComp(.duplicate(a, newID: b)).apply(to: &d)
    try Command.layerComp(.reorder([b, a])).apply(to: &d); XCTAssertEqual(d.layerComps?.comps.map(\.id), [b, a])
    try Command.layerComp(.update(a, name: "Renamed", comment: "", options: .init(), recapture: false)).apply(to: &d)
    XCTAssertEqual(d.layerComps?.comps[1].comment, "")
    let saved = d
    for command: LayerCompCommand in [.capture(id: a, name: "Duplicate ID", comment: "", options: .init()), .delete([a, a]), .reorder([a]), .update(a, name: "", comment: "", options: .init(), recapture: true), .update(a, name: "x", comment: "", options: .init(visibility: false), recapture: false)] {
      XCTAssertThrowsError(try Command.layerComp(command).apply(to: &d)); XCTAssertEqual(d, saved)
    }
    try Command.layerComp(.delete([a])).apply(to: &d); XCTAssertEqual(d.layerComps?.comps.map(\.id), [b])
    try Command.layerComp(.clear).apply(to: &d); XCTAssertNil(d.layerComps)
  }
  func testMissingLayersRemainWarnedAndNewLayersStayUntouched() throws {
    let id = UUID(); var d = try fixture(); try capture(&d, id: id); let removed = d.layers.removeLast()
    let new = Layer(name: "New", content: removed.content); d.layers.append(new); d.activeLayerID = new.id
    XCTAssertEqual(d.layerComps?.comps[0].missingLayers(in: d), [removed.id])
    try Command.layerComp(.apply(id)).apply(to: &d); XCTAssertEqual(d.layers[1], new); XCTAssertFalse(d.layerComps!.comps[0].matches(d))
    try Command.layerComp(.update(id, name: "Recaptured", comment: "", options: .init(), recapture: true)).apply(to: &d)
    XCTAssertEqual(d.layerComps?.comps[0].missingLayers(in: d), [])
  }
  func testNative79OrdinaryChunkedAndPagedRoundTripAndOldDocumentsStayOld() throws {
    var d = try fixture(); XCTAssertEqual(d.minimumArchiveVersion, 10); try capture(&d, id: UUID()); XCTAssertEqual(d.minimumArchiveVersion, 79)
    let data = try NativeArchive.encode(d); XCTAssertEqual(try NativeArchive.decode(data), d)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)), d)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("comps.photato"); try data.write(to: url)
    XCTAssertEqual(try NativeArchive.readPaged(url), d)
    try Command.layerComp(.clear).apply(to: &d); XCTAssertEqual(d.minimumArchiveVersion, 10)
  }
  func testMalformedAndExcessiveMetadataRejectsWithoutChangingDocument() throws {
    var d = try fixture(); try capture(&d, id: UUID()); let original = d
    d.layerComps?.comps[0].layers[0].appearance?.opacity = .nan; XCTAssertThrowsError(try d.validate())
    d = original; let duplicate = d.layerComps!.comps[0].layers[0]; d.layerComps?.comps[0].layers.append(duplicate); XCTAssertThrowsError(try d.validate())
    d = original; XCTAssertThrowsError(try Command.layerComp(.capture(id: UUID(), name: "x", comment: String(repeating: "é", count: 33_000), options: .init())).apply(to: &d)); XCTAssertEqual(d, original)
  }
}
