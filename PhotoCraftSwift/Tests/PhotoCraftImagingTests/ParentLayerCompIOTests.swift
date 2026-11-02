import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class ParentLayerCompIOTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> (CraftDocument, CraftDocument, UUID) {
    let helper = SmartObjectLayerCompIOTests(), source = try helper.source(depth)
    var parent = try helper.parent(source); let layer = parent.layers[0].id, red = source.layerComps!.comps[0].id, id = UUID()
    try SmartObjectLayerCompIO.selection(in: parent, layerID: layer, compID: red).apply(to: &parent)
    try Command.layerComp(.capture(id: id, name: "Parent Red", comment: "", options: .init(smartObjects: true))).apply(to: &parent)
    try SmartObjectLayerCompIO.selection(in: parent, layerID: layer, compID: nil).apply(to: &parent)
    return (parent, source, id)
  }
  func testPreparedApplyHistoryLastStateAndRepeatedApplyPreserveOriginalChoicesAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      let (d, source, id) = try fixture(depth); var s = EditorSession(document: d)
      try s.execute(LayerCompIO.command(.apply(id), in: s.document)); let applied = s.document
      XCTAssertEqual(applied.layers[0].smartObject?.layerComps?.selectedID, source.layerComps!.comps[0].id)
      XCTAssertEqual(try SmartObjectLayerCompIOTests().cache(applied.layers[0]).pixel(x: 0, y: 0), Pixel(1, 0, 0))
      XCTAssertNil(applied.layerComps?.lastDocumentState?[0].smartObjectSelection?.compID)
      XCTAssertEqual(applied.layers[0].smartObject?.data, d.layers[0].smartObject?.data)
      try s.execute(LayerCompIO.command(.apply(id), in: s.document)); XCTAssertEqual(s.document, applied); XCTAssertEqual(s.undoStack.count, 1)
      try s.undo(); XCTAssertEqual(s.document, d); try s.redo(); XCTAssertEqual(s.document, applied)
      try s.execute(LayerCompIO.command(.restoreLast, in: s.document)); XCTAssertEqual(s.document.layers, d.layers)
      XCTAssertNil(s.document.layerComps?.lastDocumentState); try s.undo(); XCTAssertEqual(s.document, applied)
      // Reapplying the already selected parent comp after editing its child is a real change.
      try s.execute(SmartObjectLayerCompIO.selection(in: s.document, layerID: d.layers[0].id, compID: nil))
      try s.execute(LayerCompIO.command(.apply(id), in: s.document)); XCTAssertEqual(s.document.layers, applied.layers)
      XCTAssertNil(s.document.layerComps?.lastDocumentState?[0].smartObjectSelection?.compID)
    }
  }
  func testSharedInstancesDecodeOncePerSourceAndRenderOncePerDistinctChoice() throws {
    let (base, source, _) = try fixture(); var d = base
    try Command.duplicateLayer(d.layers[0].id).apply(to: &d)
    try Command.duplicateLayer(d.layers[0].id).apply(to: &d)
    let ids = d.layers.map(\.id), red = source.layerComps!.comps[0].id, blue = source.layerComps!.comps[1].id
    var cache = SmartObjectCompPreparationCache()
    for (id, choice) in zip(ids, [red, blue, red]) {
      try SmartObjectLayerCompIO.selection(in: d, layerID: id, compID: choice, sourceData: nil, cache: &cache).apply(to: &d)
    }
    XCTAssertEqual(cache.decodedSources, 1); XCTAssertEqual(cache.renderedVariations, 2)
    XCTAssertEqual(d.layers.map { $0.smartObject?.layerComps?.selectedID }, [red, blue, red])
    let parentID = UUID(); try Command.layerComp(.capture(id: parentID, name: "Mixed", comment: "", options: .init(smartObjects: true))).apply(to: &d)
    for id in ids { try SmartObjectLayerCompIO.selection(in: d, layerID: id, compID: nil).apply(to: &d) }
    let restored = try LayerCompIO.document(d, applying: parentID)
    XCTAssertEqual(restored.layers.map { $0.smartObject?.layerComps?.selectedID }, [red, blue, red])
  }
  func testParentRecordsUseUpdatedSourceArtworkAndRejectDeletedChoiceWithoutMutation() throws {
    let (original, source, id) = try fixture(); var d = original, updated = source
    updated.layers[0].content = .raster(try Surface(width: 4, height: 3, fill: Pixel(0, 1, 0)))
    try SmartObjectIO.replacement(in: d, layerID: d.layers[0].id, source: updated, preserveSize: false).apply(to: &d)
    let result = try LayerCompIO.document(d, applying: id)
    XCTAssertEqual(try SmartObjectLayerCompIOTests().cache(result.layers[0]).pixel(x: 0, y: 0), Pixel(0, 1, 0))
    let red = updated.layerComps!.comps[0].id
    try Command.layerComp(.delete([red])).apply(to: &updated)
    try SmartObjectIO.replacement(in: d, layerID: d.layers[0].id, source: updated, preserveSize: false).apply(to: &d)
    let before = d
    XCTAssertEqual(d.layerComps!.comps[0].unavailableSmartObjectLayers(in: d), [d.layers[0].id])
    XCTAssertThrowsError(try LayerCompIO.command(.apply(id), in: d)); XCTAssertEqual(d, before)
  }
  func testLinkedReopenedParentCompRequiresMatchingExplicitBytes() throws {
    let (original, source, id) = try fixture(), bytes = try NativeArchive.encode(source)
    var linked = original; linked.layers[0].smartObject?.data = bytes
    let reference = try LinkedSmartObjectSource(reference: "file:///owned/Source.photato", contentHash: LinkedSmartObjectSource.fingerprint(bytes), byteLength: UInt64(bytes.count))
    linked.layers[0] = try LinkedSmartObjectIO.linked(linked.layers[0], reference: reference)
    let d = try NativeArchive.decode(NativeArchive.encode(linked)), sourceID = d.layers[0].smartObject!.sourceID
    XCTAssertThrowsError(try LayerCompIO.document(d, applying: id)); XCTAssertThrowsError(try LayerCompIO.document(d, applying: id, sourceData: [sourceID: Data([1])]))
    let result = try LayerCompIO.document(d, applying: id, sourceData: [sourceID: bytes])
    XCTAssertEqual(result.layers[0].smartObject?.layerComps?.selectedID, source.layerComps!.comps[0].id)
    XCTAssertTrue(d.layers[0].smartObject!.data.isEmpty)
  }
  func testNestedEmbeddedParentCompPropagatesAndNestingBudgetRemainsEnforced() throws {
    let (middle, source, compID) = try fixture(); var outer = try CraftDocument(width: 10, height: 8)
    let placed = try SmartObjectIO.placed(data: NativeArchive.encode(middle), fileName: "Middle.photato", in: outer, fit: false)
    outer.layers = [placed]; outer.activeLayerID = placed.id
    let command = try SmartObjectLayerCompIO.selection(in: outer, layerID: placed.id, compID: compID)
    try command.apply(to: &outer)
    var manual = middle
    try SmartObjectLayerCompIO.selection(in: manual, layerID: middle.layers[0].id, compID: source.layerComps!.comps[0].id).apply(to: &manual)
    let expected = try ColorManagement.converted(SmartObjectIO.sourceComposite(manual), from: manual, to: outer)
    XCTAssertEqual(try SmartObjectLayerCompIOTests().cache(outer.layers[0]), expected)
    XCTAssertThrowsError(try SmartObjectIO.$nesting.withValue(8) { try LayerCompIO.document(middle, applying: compID) })
  }
}
