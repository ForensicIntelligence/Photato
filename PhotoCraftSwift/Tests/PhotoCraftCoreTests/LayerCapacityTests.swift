import XCTest
@testable import PhotoCraftCore

final class LayerCapacityTests: XCTestCase {
  func fixture(_ count: Int = 8000, depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 2, height: 1, depth: depth)
    let pixels = try Surface(width: 2, height: 1, depth: depth, fill: Pixel(1, 0, 0))
    d.layers = (0..<count).map { Layer(name: "Layer \($0)", content: .raster(pixels)) }
    d.activeLayerID = d.layers.last?.id
    return d
  }
  func test8000LayerValidationAtEveryDepthAnd8001IsRejected() throws {
    XCTAssertEqual(LayerLimits.maximumLayers, 8000)
    for depth in PixelDepth.allCases {
      let d = try fixture(depth: depth); XCTAssertNoThrow(try d.validate())
      var invalid = d; invalid.layers.append(Layer(name: "Overflow", content: d.layers[0].content))
      XCTAssertThrowsError(try invalid.validate())
      var session = EditorSession(document: d)
      XCTAssertThrowsError(try session.execute(.newPixelLayer(.init(name: "Overflow"))))
      XCTAssertEqual(session.document, d); XCTAssertTrue(session.undoStack.isEmpty)
    }
  }
  func testCreationAtBoundaryHasOneUndoAndRedo() throws {
    let d = try fixture(7999); var session = EditorSession(document: d)
    try session.execute(.newPixelLayer(.init(name: "Last layer")))
    XCTAssertEqual(session.document.layers.count, 8000); XCTAssertEqual(session.undoStack.count, 1)
    let result = session.document; try session.undo(); XCTAssertEqual(session.document, d)
    try session.redo(); XCTAssertEqual(session.document, result)
  }
  func testGroupAll7999LayersAndInheritedProtection() throws {
    let d = try fixture(7999); var s = EditorSession(document: d)
    try s.execute(.newGroup(.init(name: "Entire stack"), children: d.layers.map(\.id)))
    XCTAssertEqual(s.document.layers.count, 8000)
    let group = try XCTUnwrap(s.document.layers.last); XCTAssertTrue(group.isGroup)
    XCTAssertEqual(LayerHierarchyIndex(s.document).subtreeIDs([group.id]).count, 8000)
    try s.execute(.protection([group.id: .position]))
    let index = LayerHierarchyIndex(s.document)
    XCTAssertTrue(d.layers.allSatisfy { index.effectiveProtection($0.id).locksPosition })
    XCTAssertEqual(try LayerDuplication.roots(in: s.document, selected: Set(s.document.layers.map(\.id))).map(\.id), [group.id])
    try s.undo(); try s.undo(); XCTAssertEqual(s.document, d)
  }
  func testDuplicateAndPasteCapacityRejectAtomically() throws {
    let d = try fixture(7999); var s = EditorSession(document: d)
    try s.execute(.duplicateLayer(try XCTUnwrap(d.activeLayerID)))
    XCTAssertEqual(s.document.layers.count, 8000)
    let full = s.document; XCTAssertFalse(LayerDuplication.canDuplicate(in: full, selected: [full.layers[0].id]))
    XCTAssertThrowsError(try s.execute(.duplicateLayer(full.layers[0].id)))
    let clip = try ClipboardContent.pixels(Surface(width: 1, height: 1, fill: .white))
    XCTAssertThrowsError(try s.execute(.paste(clip, .inPlace, nil)))
    XCTAssertEqual(s.document, full); XCTAssertEqual(s.undoStack.count, 1)
    try s.undo(); try s.execute(.paste(clip, .inPlace, nil)); XCTAssertEqual(s.document.layers.count, 8000)
  }
  func test8000WholeLayerMoveSharesExactOffsetsAndPositionLockFailure() throws {
    let d = try fixture(); var moved = d
    try Command.moveLayers(.init(layerIDs: d.layers.map(\.id), dx: 2, dy: 3)).apply(to: &moved)
    XCTAssertTrue(moved.layers.allSatisfy { $0.x == 2 && $0.y == 3 })
    XCTAssertEqual(moved.layers.map(\.content), d.layers.map(\.content))
    moved.layers[0].protection = .position; let locked = moved
    XCTAssertThrowsError(try Command.moveLayers(.init(layerIDs: moved.layers.map(\.id), dx: 1, dy: 0)).apply(to: &moved))
    XCTAssertEqual(moved, locked)
  }
  func testHierarchyIndexTerminatesCyclesAndMatchesOrderedAncestors() throws {
    var d = try fixture(3); d.layers[1].content = .group(GroupContent()); d.layers[2].content = .group(GroupContent())
    d.layers[0].parentID = d.layers[1].id; d.layers[1].parentID = d.layers[2].id
    let h = LayerHierarchyIndex(d)
    XCTAssertEqual(h.ancestors(of: d.layers[0].id), d.ancestors(of: d.layers[0].id))
    XCTAssertEqual(h.subtreeIDs([d.layers[2].id]), Set(d.layers.map(\.id)))
    d.layers[2].parentID = d.layers[1].id
    XCTAssertEqual(LayerHierarchyIndex(d).subtreeIDs([d.layers[2].id]).count, 3)
    XCTAssertThrowsError(try d.validate())
  }
  func test8000LayerStyleBatchIsOneAtomicUndoAndHonorsInheritedLocks() throws {
    let d = try fixture(); var style = LayerStyle(); style.fillOpacity = 0.5
    var session = EditorSession(document: d)
    try session.execute(.layerStyles(.init(layerIDs: Set(d.layers.map(\.id)), style: style)))
    XCTAssertTrue(session.document.layers.allSatisfy { $0.style?.fillOpacity == 0.5 })
    XCTAssertEqual(session.undoStack.count, 1)
    try session.undo(); XCTAssertEqual(session.document, d)
    var locked = d; locked.layers[0].protection = .all; let before = locked
    XCTAssertThrowsError(try Command.layerStyles(.init(layerIDs: Set(locked.layers.map(\.id)), style: style)).apply(to: &locked))
    XCTAssertEqual(locked, before)
  }

}
