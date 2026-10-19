import XCTest

@testable import PhotoCraftCore

final class GroupDisclosureTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var doc = try CraftDocument(width: 4, height: 3)
    let base = Layer(name: "Base", content: .fill(.white))
    var outer = Layer(name: "Outer", content: .group(.init(passThrough: false)))
    outer.locked = true
    outer.opacity = 0.7
    outer.colorLabel = .orange
    var inner = Layer(name: "Inner", content: .group(.init()))
    inner.parentID = outer.id
    var child = Layer(name: "Child", content: .fill(.black))
    child.parentID = inner.id
    child.visible = false
    let other = Layer(name: "Other", content: .group(.init(expanded: false)))
    doc.layers = [base, child, inner, outer, other]
    doc.activeLayerID = child.id
    try doc.validate()
    return doc
  }

  func testDisclosureOnlyChangesRequestedExpandedFlagsDespiteLocks() throws {
    let before = try fixture()
    var session = EditorSession(document: before)
    let ids = Set(before.layers.filter(\.isGroup).map(\.id))
    XCTAssertTrue(try session.setGroupExpansion(ids, expanded: false))
    var expected = before
    for i in expected.layers.indices where expected.layers[i].isGroup {
      var group = expected.layers[i].group!
      group.expanded = false
      expected.layers[i].content = .group(group)
    }
    XCTAssertEqual(session.document, expected)
    XCTAssertTrue(session.undoStack.isEmpty)
    XCTAssertTrue(session.redoStack.isEmpty)
    XCTAssertFalse(try session.setGroupExpansion(ids, expanded: false))
    let inner = before.layers[2].id
    XCTAssertTrue(try session.setGroupExpansion([inner], expanded: true))
    XCTAssertTrue(session.document.layers[2].group!.expanded)
    XCTAssertFalse(session.document.layers[3].group!.expanded)
    XCTAssertFalse(session.document.layers[4].group!.expanded)
  }

  func testDisclosurePreservesHistorySnapshotsAndRedoBranch() throws {
    var session = EditorSession(document: try fixture())
    let base = session.document.layers[0].id
    try session.execute(.opacity(base, 0.5))
    try session.execute(.opacity(base, 0.25))
    session.undo()
    let undo = session.undoStack
    let redo = session.redoStack
    let ids = Set(session.document.layers.filter(\.isGroup).map(\.id))
    try session.setGroupExpansion(ids, expanded: false)
    XCTAssertEqual(session.undoStack.map(\.document), undo.map(\.document))
    XCTAssertEqual(session.undoStack.map(\.label), undo.map(\.label))
    XCTAssertEqual(session.redoStack.map(\.document), redo.map(\.document))
    XCTAssertEqual(session.redoStack.map(\.label), redo.map(\.label))
    // Source history snapshots keep their original disclosure state; a view change
    // does not rewrite them, so Undo may restore that earlier view metadata.
    session.undo()
    XCTAssertEqual(session.document.layers[0].opacity, 1)
    XCTAssertTrue(session.document.layers[2].group!.expanded)
    session.redo()
    XCTAssertEqual(session.document.layers[0].opacity, 0.5)
    XCTAssertFalse(session.document.layers[2].group!.expanded)
  }

  func testInvalidBatchIsRejectedBeforeAnyMutation() throws {
    var session = EditorSession(document: try fixture())
    let before = session.document
    let valid = before.layers[2].id
    for ids: Set<UUID> in [[], [valid, UUID()], [valid, before.layers[0].id]] {
      XCTAssertThrowsError(try session.setGroupExpansion(ids, expanded: false))
      XCTAssertEqual(session.document, before)
      XCTAssertTrue(session.undoStack.isEmpty)
    }
  }

  func testViewStateDoesNotInterruptAnExistingCoalescedEdit() throws {
    var session = EditorSession(document: try fixture())
    let before = session.document
    let base = before.layers[0].id
    session.beginCoalescing()
    try session.execute(.opacity(base, 0.5))
    try session.setGroupExpansion([before.layers[2].id], expanded: false)
    try session.execute(.opacity(base, 0.25))
    session.endCoalescing()
    XCTAssertEqual(session.undoStack.count, 1)
    session.undo()
    XCTAssertEqual(session.document, before)
  }

  func testNativeArchiveRetainsMixedDisclosureWithoutAnArchiveVersionChange() throws {
    var session = EditorSession(document: try fixture())
    try session.setGroupExpansion([session.document.layers[2].id], expanded: false)
    let back = try NativeArchive.decode(NativeArchive.encode(session.document))
    XCTAssertEqual(back, session.document)
    XCTAssertEqual(back.layers.compactMap { $0.group?.expanded }, [false, true, false])
  }
}
