import XCTest

@testable import PhotoCraftCore

final class LayerDeletionTests: XCTestCase {
  func testDisjointDeletionChoosesSurvivorAndUndoesOnce() throws {
    let original = try LayerDuplicationTests().fixture()
    let ids = original.layers.map(\.id)
    var session = EditorSession(document: original)
    try session.execute(.deleteLayers([ids[1], ids[2]]))
    XCTAssertEqual(session.document.layers, [original.layers[0]])
    XCTAssertEqual(session.document.activeLayerID, ids[0])
    XCTAssertEqual(session.undoStack.count, 1)
    let result = session.document
    session.undo()
    XCTAssertEqual(session.document, original)
    session.redo()
    XCTAssertEqual(session.document, result)
    var alternate = original
    try Command.deleteLayers([ids[0], ids[2]]).apply(to: &alternate)
    XCTAssertEqual(alternate.activeLayerID, ids[1])
  }
  func testNestedSelectionDeletesSubtreesOnlyOnce() throws {
    var document = try LayerDuplicationTests().fixture(depth: .u16)
    let child = document.layers[0].id
    let survivor = document.layers[2]
    try Command.groupLayers([child], "Inner").apply(to: &document)
    let inner = document.activeLayerID!
    try Command.groupLayers([inner], "Outer").apply(to: &document)
    let outer = document.activeLayerID!
    try Command.deleteLayers([outer, inner, child]).apply(to: &document)
    XCTAssertEqual(document.layers.count, 2)
    XCTAssertEqual(document.layers.last, survivor)
    try document.validate()
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(document)), document)
  }
  func testInvalidAndFinalLayerRequestsAreAtomic() throws {
    let original = try LayerDuplicationTests().fixture()
    for ids: Set<UUID> in [[], [UUID()], Set(original.layers.map(\.id))] {
      var document = original
      XCTAssertFalse(LayerDeletion.canDelete(in: document, selected: ids))
      XCTAssertThrowsError(try Command.deleteLayers(ids).apply(to: &document))
      XCTAssertEqual(document, original)
    }
    var legacy = original
    for layer in original.layers { try Command.deleteLayer(layer.id).apply(to: &legacy) }
    XCTAssertTrue(legacy.layers.isEmpty)
  }
  func testLockedDescendantAndInheritedLocksRejectWholeTransaction() throws {
    var original = try LayerDuplicationTests().fixture()
    let child = original.layers[0].id
    let other = original.layers[2].id
    try Command.groupLayers([child], "Group").apply(to: &original)
    let group = original.activeLayerID!
    for locked in [child, group] {
      var document = original
      try Command.lock(locked, true).apply(to: &document)
      let before = document
      for ids: Set<UUID> in [[group, other], [child, other]] {
        XCTAssertFalse(LayerDeletion.canDelete(in: document, selected: ids))
        XCTAssertThrowsError(try Command.deleteLayers(ids).apply(to: &document))
        XCTAssertEqual(document, before)
      }
    }
  }
  func testRenameRejectsOversizedNameWithoutChangingDocument() throws {
    let original = try LayerDuplicationTests().fixture()
    var document = original
    XCTAssertThrowsError(
      try Command.renameLayer(original.layers[0].id, String(repeating: "a", count: 65_536)).apply(
        to: &document))
    XCTAssertEqual(document, original)
  }
}
