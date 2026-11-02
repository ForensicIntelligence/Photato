import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class SmartObjectLayerCompIOTests: XCTestCase {
  func source(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 4, height: 3, depth: depth)
    d.layers[0].content = .raster(try Surface(width: 4, height: 3, depth: depth, fill: Pixel(1, 0, 0)))
    var top = Layer(name: "Blue", content: .raster(try Surface(width: 4, height: 3, depth: depth, fill: Pixel(0, 0, 1)))); top.visible = false; d.layers.append(top)
    try Command.layerComp(.capture(id: UUID(), name: "Red", comment: "", options: .init())).apply(to: &d)
    d.layers[1].visible = true
    try Command.layerComp(.capture(id: UUID(), name: "Blue", comment: "", options: .init())).apply(to: &d)
    return d
  }
  func parent(_ source: CraftDocument) throws -> CraftDocument {
    var d = try CraftDocument(width: 10, height: 8, depth: source.depth)
    let bytes = try NativeArchive.encode(source)
    var layer = try SmartObjectIO.placed(data: bytes, fileName: "Owned.photato", in: d, fit: false)
    layer.affine = .init(a: 0.5, b: 0.25, c: 0, d: 1.5, tx: 0.25, ty: 0.5)
    layer.mask = try Surface(width: 4, height: 3, depth: source.depth, fill: .white)
    layer.style = .init(effects: [.init(.dropShadow)]); layer.style?.fillOpacity = 0.75
    layer.smartFilters = SmartFilterStack(); layer.smartFilters?.enabled = false
    d.layers = [layer]; d.activeLayerID = layer.id; return d
  }
  func cache(_ layer: Layer) throws -> Surface { guard case .raster(let pixels) = layer.content else { throw CraftError.invalid("Missing cache") }; return pixels }
  func testChoiceAcrossDepthsChangesOnlyPresentationAndPreservesEveryParentProperty() throws {
    for depth in PixelDepth.allCases {
      let source = try source(depth), d = try parent(source), original = d.layers[0], red = source.layerComps!.comps[0].id
      XCTAssertEqual(original.smartObject?.layerComps?.entries.map(\.name), ["Red", "Blue"])
      var session = EditorSession(document: d)
      try session.execute(SmartObjectLayerCompIO.selection(in: session.document, layerID: original.id, compID: red))
      let result = session.document, selected = result.layers[0]
      XCTAssertEqual(try cache(selected).pixel(x: 0, y: 0), Pixel(1, 0, 0)); XCTAssertEqual(selected.smartObject?.data, original.smartObject?.data)
      XCTAssertEqual(selected.smartObject?.sourceID, original.smartObject?.sourceID); XCTAssertEqual(selected.smartObject?.layerComps?.selectedID, red)
      var expected = original; expected.content = selected.content; expected.smartObject = selected.smartObject
      XCTAssertEqual(selected, expected)
      let count = session.undoStack.count
      try session.execute(SmartObjectLayerCompIO.selection(in: session.document, layerID: original.id, compID: red)); XCTAssertEqual(session.undoStack.count, count)
      try session.undo(); XCTAssertEqual(session.document, d); try session.redo(); XCTAssertEqual(session.document, result)
      try session.execute(SmartObjectLayerCompIO.selection(in: session.document, layerID: original.id, compID: nil)); XCTAssertEqual(try cache(session.document.layers[0]).pixel(x: 0, y: 0), Pixel(0, 0, 1))
    }
  }
  func testSharedInstancesKeepIndependentChoicesAndSourceUpdatesRerenderEachChoice() throws {
    var source = try source(), d = try parent(source); let first = d.layers[0].id
    try Command.duplicateLayer(first).apply(to: &d); let second = d.activeLayerID!
    let red = source.layerComps!.comps[0].id, blue = source.layerComps!.comps[1].id
    try SmartObjectLayerCompIO.selection(in: d, layerID: first, compID: red).apply(to: &d)
    try SmartObjectLayerCompIO.selection(in: d, layerID: second, compID: blue).apply(to: &d)
    XCTAssertEqual(d.layers[0].smartObject?.sourceID, d.layers[1].smartObject?.sourceID); XCTAssertNoThrow(try d.validate())
    XCTAssertEqual(try cache(d.layers[0]).pixel(x: 0, y: 0), Pixel(1, 0, 0)); XCTAssertEqual(try cache(d.layers[1]).pixel(x: 0, y: 0), Pixel(0, 0, 1))
    source.layers[1].content = .raster(try Surface(width: 4, height: 3, fill: Pixel(0, 1, 0))); source.layerComps?.comps[1].name = "Green"
    let command = try SmartObjectIO.replacement(in: d, layerID: first, source: source, preserveSize: false)
    var session = EditorSession(document: d); try session.execute(command)
    XCTAssertEqual(try cache(session.document.layers[0]).pixel(x: 0, y: 0), Pixel(1, 0, 0)); XCTAssertEqual(try cache(session.document.layers[1]).pixel(x: 0, y: 0), Pixel(0, 1, 0))
    XCTAssertEqual(session.document.layers[0].smartObject?.layerComps?.selectedID, red); XCTAssertEqual(session.document.layers[1].smartObject?.layerComps?.selectedID, blue)
    XCTAssertEqual(session.document.layers[0].smartObject?.layerComps?.entries.last?.name, "Green")
    try session.undo(); XCTAssertEqual(session.document, d)
  }
  func testDeletedSelectedCompAndImageLocksRejectWholeSourceUpdateAtomically() throws {
    var source = try source(), d = try parent(source); let id = d.layers[0].id, red = source.layerComps!.comps[0].id
    try SmartObjectLayerCompIO.selection(in: d, layerID: id, compID: red).apply(to: &d); let before = d
    try Command.layerComp(.delete([red])).apply(to: &source)
    XCTAssertThrowsError(try SmartObjectIO.replacement(in: d, layerID: id, source: source)); XCTAssertEqual(d, before)
    d.layers[0].locked = true; XCTAssertThrowsError(try SmartObjectLayerCompIO.selection(in: d, layerID: id, compID: nil))
    XCTAssertThrowsError(try SmartObjectLayerCompIO.selection(in: before, layerID: id, compID: UUID()))
  }
  func testLinkedNativeArchiveReopensWithCachedChoiceAndHydratesOnlyMatchingOriginalBytes() throws {
    let source = try source(), bytes = try NativeArchive.encode(source); var d = try parent(source)
    let reference = try LinkedSmartObjectSource(reference: "file:///owned/Contents.photato", contentHash: LinkedSmartObjectSource.fingerprint(bytes), byteLength: UInt64(bytes.count))
    // Use these exact retained bytes; native encoding is not assumed to serialize twice identically.
    d.layers[0].smartObject?.data = bytes; d.layers[0] = try LinkedSmartObjectIO.linked(d.layers[0], reference: reference)
    let id = d.layers[0].id, red = source.layerComps!.comps[0].id
    try SmartObjectLayerCompIO.selection(in: d, layerID: id, compID: red).apply(to: &d)
    var opened = try NativeArchive.decode(NativeArchive.encode(d)); XCTAssertTrue(opened.layers[0].smartObject!.data.isEmpty)
    XCTAssertEqual(try cache(opened.layers[0]).pixel(x: 0, y: 0), Pixel(1, 0, 0)); XCTAssertEqual(opened.layers[0].smartObject?.layerComps?.selectedID, red)
    XCTAssertThrowsError(try SmartObjectLayerCompIO.selection(in: opened, layerID: id, compID: nil))
    XCTAssertThrowsError(try SmartObjectLayerCompIO.selection(in: opened, layerID: id, compID: nil, sourceData: Data([1])))
    try SmartObjectLayerCompIO.selection(in: opened, layerID: id, compID: nil, sourceData: bytes).apply(to: &opened)
    XCTAssertEqual(try cache(opened.layers[0]).pixel(x: 0, y: 0), Pixel(0, 0, 1)); XCTAssertEqual(opened.layers[0].smartObject?.linkedSource, reference)
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(opened))
  }
  func testStackModeRecalculationUsesSelectedCompAndNativeSelectionPersists() throws {
    let source = try source(); var d = try parent(source); let id = d.layers[0].id, red = source.layerComps!.comps[0].id
    try SmartObjectLayerCompIO.selection(in: d, layerID: id, compID: red).apply(to: &d)
    try ImageStack.command(in: d, layerID: id, mode: .mean).apply(to: &d)
    let variation = try SmartObjectLayerCompIO.presentation(source, compID: red), expected = try ImageStack.render(variation, mode: .mean, in: d)
    XCTAssertEqual(try cache(d.layers[0]), expected)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encode(d)), d)
    try ImageStack.command(in: d, layerID: id, mode: nil).apply(to: &d); XCTAssertEqual(try cache(d.layers[0]).pixel(x: 0, y: 0), Pixel(1, 0, 0))
  }
  func testConvertingSelectedLayersDoesNotInheritParentDocumentCompLibrary() throws {
    var d = try source(); let parentComps = d.layerComps
    try SmartObjectIO.convert(in: d, selected: [d.layers[0].id]).apply(to: &d)
    let object = try XCTUnwrap(d.layers.first(where: { $0.smartObject != nil })?.smartObject)
    XCTAssertNil(try SmartObjectIO.sourceDocument(object).layerComps); XCTAssertNil(object.layerComps)
    XCTAssertEqual(d.layerComps, parentComps)
  }
}
