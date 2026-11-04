import XCTest
@testable import PhotoCraftCore

final class EmptyLayerDeletionTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 8, height: 8, depth: depth)
    let base = Layer(name: "Keep base", content: .raster(try Surface(width: 8, height: 8, depth: depth, fill: .white)))
    let empty = Layer(name: "Empty", content: .raster(try Surface(width: 65, height: 1, depth: depth, fill: Pixel(0.8, 0.4, 0.2, 0))))
    var hidden = Layer(name: "Hidden content", content: .raster(try Surface(width: 2, height: 2, depth: depth, fill: .black)))
    hidden.visible = false
    var zero = hidden; zero.id = UUID(); zero.name = "Opacity zero"; zero.visible = true; zero.opacity = 0
    var outside = hidden; outside.id = UUID(); outside.name = "Off canvas"; outside.visible = true; outside.x = 100; outside.y = -100
    d.layers = [base, empty, hidden, zero, outside]; d.activeLayerID = hidden.id
    try d.validate(); return d
  }
  func testEveryDepthDeletesStorageEmptyNotInvisibleContentWithOneUndo() throws {
    for depth in PixelDepth.allCases {
      let original = try fixture(depth), removed = original.layers[1].id
      var session = EditorSession(document: original)
      try session.execute(EmptyLayerDeletion.prepare(original))
      XCTAssertEqual(session.document.layers, original.layers.filter { $0.id != removed })
      XCTAssertEqual(session.document.activeLayerID, original.activeLayerID)
      XCTAssertEqual(session.undoStack.count, 1)
      XCTAssertEqual(session.undoStack.last?.label, EmptyLayerDeletion.title)
      let after = session.document
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(after)), after)
      try session.undo(); XCTAssertEqual(session.document, original)
      try session.redo(); XCTAssertEqual(session.document, after)
    }
  }
  func testRecursiveEmptyGroupsDisappearButMixedGroupsAndTheirContentRemain() throws {
    var d = try fixture(); let empty = d.layers[1].id, content = d.layers[2].id
    try Command.groupLayers([empty], "Inner empty").apply(to: &d); let inner = d.activeLayerID!
    try Command.groupLayers([inner], "Outer empty").apply(to: &d); let outer = d.activeLayerID!
    try Command.groupLayers([content], "Mixed").apply(to: &d); let mixed = d.activeLayerID!
    let original = d
    XCTAssertEqual(try EmptyLayerDeletion.layerIDs(in: d), [empty, inner, outer])
    try EmptyLayerDeletion.prepare(d).apply(to: &d)
    XCTAssertNotNil(d.layers.first { $0.id == mixed })
    XCTAssertEqual(d.layers.first { $0.id == content }, original.layers.first { $0.id == content })
    try d.validate()
  }
  func testLocksAndExtendedEditableDataArePreserved() throws {
    var d = try fixture(); let template = d.layers[1]
    var locked = template; locked.id = UUID(); locked.name = "Locked"; locked.locked = true
    var masked = template; masked.id = UUID(); masked.mask = try Surface(width: 2, height: 2, depth: .u8, fill: .black)
    var retained = template; retained.id = UUID(); retained.sourceTags = ["TEST":Data([1,2,3])]
    let type = Layer(name: "Empty type", content: .text(.init(text: "")))
    let adjustment = Layer(name: "Adjustment", content: .adjustment(.invert))
    d.layers += [locked, masked, retained, type, adjustment]
    var partial = template; partial.id = UUID(); partial.protection = [.transparency, .position]
    d.layers.append(partial)
    let child = template.id
    try Command.groupLayers([child], "Locked ancestor").apply(to: &d)
    try Command.lock(d.activeLayerID!, true).apply(to: &d)
    let before = d
    XCTAssertEqual(try EmptyLayerDeletion.layerIDs(in: d), [partial.id])
    try EmptyLayerDeletion.prepare(d).apply(to: &d)
    XCTAssertEqual(d.layers, before.layers.filter { $0.id != partial.id })
  }
  func testMaximumSparseCanvasUsesStoredAlphaAndPreservesBoundaryContent() throws {
    var d = try CraftDocument(width: 300_000, height: 300_000)
    var pixels = try Surface(width: 300_000, height: 300_000, depth: .u8)
    pixels.setPixel(x: 299_999, y: 299_999, Pixel(1, 0, 0, 1))
    let keep = Layer(name: "Boundary pixel", content: .raster(pixels))
    let empty = Layer(name: "Uniform empty", content: .raster(try Surface(width: 300_000, height: 300_000, depth: .u8, fill: Pixel(1, 1, 1, 0))))
    d.layers = [keep, empty]; d.activeLayerID = keep.id
    try EmptyLayerDeletion.prepare(d).apply(to: &d)
    XCTAssertEqual(d.layers, [keep])
    XCTAssertEqual(pixels.tileCount, 1)
  }
  func testLastEditableLayerAndNoOpHaveNoHistoryOrDirtyChange() throws {
    var d = try CraftDocument(width: 3, height: 2)
    d.layers = [Layer(name: "Bottom", content: .raster(try Surface(width: 3, height: 2, depth: .u8))), Layer(name: "Top", content: .raster(try Surface(width: 3, height: 2, depth: .u8)))]
    d.activeLayerID = d.layers.last!.id
    var session = EditorSession(document: d)
    try session.execute(EmptyLayerDeletion.prepare(d))
    XCTAssertEqual(session.document.layers, [d.layers[0]])
    let before = session.document, count = session.undoStack.count
    try session.execute(EmptyLayerDeletion.prepare(before))
    XCTAssertEqual(session.document, before); XCTAssertEqual(session.undoStack.count, count)
  }
  func testPreparedResultRejectsStaleSourceAtomically() throws {
    let original = try fixture(), command = try EmptyLayerDeletion.prepare(original)
    var changed = original; changed.name = "Changed elsewhere"; let before = changed
    XCTAssertThrowsError(try command.apply(to: &changed))
    XCTAssertEqual(changed, before)
  }
  func testTransparentClippingBaseIsNotRemovedOrReassigned() throws {
    var d = try CraftDocument(width: 8, height: 8)
    let bottom = Layer(name: "Opaque bottom", content: .raster(try Surface(width: 8, height: 8, fill: .white)))
    let base = Layer(name: "Empty clipping base", content: .raster(try Surface(width: 8, height: 8)))
    var clipped = Layer(name: "Clipped artwork", content: .raster(try Surface(width: 8, height: 8, fill: .black))); clipped.clipped = true
    let empty = Layer(name: "Unrelated empty", content: .raster(try Surface(width: 8, height: 8)))
    d.layers = [bottom, base, clipped, empty]; d.activeLayerID = clipped.id
    XCTAssertEqual(try EmptyLayerDeletion.layerIDs(in: d), [empty.id])
    try EmptyLayerDeletion.prepare(d).apply(to: &d)
    XCTAssertEqual(d.layers, [bottom, base, clipped]); XCTAssertEqual(d.clippingBase(for: clipped.id)?.id, base.id)
  }
}
