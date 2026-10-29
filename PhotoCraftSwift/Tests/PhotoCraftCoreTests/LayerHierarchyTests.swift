import XCTest

@testable import PhotoCraftCore

final class LayerHierarchyTests: XCTestCase {
  func document() throws -> CraftDocument {
    var d = try CraftDocument(width: 8, height: 6)
    d.layers = (0..<3).map {
      Layer(
        name: "Layer \($0)",
        content: .shape(ShapeContent(kind: .rectangle, width: 2, height: 2, color: .white)))
    }
    d.activeLayerID = d.layers.last!.id
    return d
  }
  func testGroupDuplicateNestedSubtreeAndDeleteUndo() throws {
    var session = EditorSession(document: try document())
    let original = session.document
    try session.execute(.groupLayers(Array(original.layers.suffix(2)).map(\.id), "Inside"))
    let inner = session.document.activeLayerID!
    try session.execute(.groupLayers(session.document.children(of: nil).map(\.id), "Outer"))
    let outer = session.document.activeLayerID!
    XCTAssertEqual(session.document.ancestors(of: original.layers[1].id).map(\.id), [inner, outer])
    let grouped = session.document
    try session.execute(.duplicateLayer(outer))
    XCTAssertEqual(session.document.layers.count, 10)
    let copy = session.document.activeLayerID!
    XCTAssertEqual(session.document.subtreeIDs(copy).count, 5)
    XCTAssertTrue(session.document.subtreeIDs(copy).isDisjoint(with: grouped.subtreeIDs(outer)))
    try session.execute(.deleteLayer(copy))
    XCTAssertEqual(session.document.layers, grouped.layers)
    try session.undo()
    XCTAssertEqual(session.document.layers.count, 10)
    try session.undo()
    XCTAssertEqual(session.document, grouped)
    try session.undo()
    try session.undo()
    XCTAssertEqual(session.document, original)
  }
  func testRelocateRejectsCyclesAndSupportsSiblingOrderingAndReparenting() throws {
    var s = EditorSession(document: try document())
    let ids = s.document.layers.map(\.id)
    try s.execute(.groupLayers([ids[1]], "Group"))
    let folder = s.document.activeLayerID!
    try s.execute(.relocate(ids[0], folder, 0))
    XCTAssertEqual(s.document.children(of: folder).map(\.id), [ids[0], ids[1]])
    try s.execute(.relocate(ids[0], folder, 1))
    XCTAssertEqual(s.document.children(of: folder).map(\.id), [ids[1], ids[0]])
    let before = s.document
    XCTAssertThrowsError(try s.execute(.relocate(folder, folder, 0)))
    XCTAssertEqual(s.document, before)
    try s.execute(.relocate(ids[1], nil, 1))
    XCTAssertEqual(s.document.children(of: nil).map(\.id), [folder, ids[1], ids[2]])
    try s.execute(.ungroup(folder))
    XCTAssertEqual(s.document.layers.map(\.id), [ids[0], ids[1], ids[2]])
  }
  func testGroupsInheritLocksAndVisibilityAndAddInside() throws {
    var s = EditorSession(document: try document())
    let child = s.document.layers[1].id
    try s.execute(.groupLayers([child], "Folder"))
    let group = s.document.activeLayerID!
    let layer = Layer(name: "New", content: .fill(.white))
    try s.execute(.addLayer(layer))
    XCTAssertEqual(s.document.layers.first { $0.id == layer.id }?.parentID, group)
    try s.execute(.lock(group, true))
    for command: Command in [
      .deleteLayer(child), .opacity(child, 0.4), .move(child, 3, 2), .relocate(child, nil, 0),
    ] {
      XCTAssertThrowsError(try s.execute(command))
    }
    try s.execute(.visibility(group, false))
    XCTAssertFalse(s.document.isVisible(child))
    try s.execute(.groupProperties(group, GroupContent(expanded: false)))
    XCTAssertEqual(s.document.layers.last { $0.id == group }?.group?.expanded, false)
  }
  func testGroupMoveAndTransformMovesDescendantsExactlyOnce() throws {
    var s = EditorSession(document: try document())
    let child = s.document.layers[0].id
    try s.execute(.groupLayers([child], "Inner"))
    let inner = s.document.activeLayerID!
    try s.execute(.groupLayers([inner], "Outer"))
    let outer = s.document.activeLayerID!
    try s.execute(.move(outer, 3, 2))
    XCTAssertEqual(s.document.layers.first { $0.id == child }?.x, 3)
    XCTAssertEqual(s.document.layers.first { $0.id == inner }?.x, 3)
    try s.execute(.transform(outer, .translation(2, 1), .nearest))
    XCTAssertEqual(s.document.layers.first { $0.id == child }?.x, 5)
    try s.execute(.canvasSize(10, 8, .center, nil))
    XCTAssertEqual(s.document.layers.first { $0.id == child }?.x, 6)
  }
  func testMalformedHierarchyAndExcessiveNestingReject() throws {
    var d = try document()
    d.layers[0].parentID = d.layers[1].id
    XCTAssertThrowsError(try d.validate())
    d.layers[1].content = .group(GroupContent())
    XCTAssertNoThrow(try d.validate())
    d.layers.swapAt(0, 2)
    XCTAssertThrowsError(try d.validate())
    d = try document()
    d.layers = (0..<34).map { _ in Layer(name: "Group", content: .group(GroupContent())) }
    for i in 0..<33 { d.layers[i].parentID = d.layers[i + 1].id }
    d.activeLayerID = d.layers.last!.id
    XCTAssertThrowsError(try d.validate())
    d.layers = Array(d.layers.suffix(2))
    d.layers[1].parentID = d.layers[0].id
    XCTAssertThrowsError(try d.validate())
  }
  func testArchivePreservesGroupsAndLegacyOptionalDefaults() throws {
    var s = EditorSession(document: try document())
    try s.execute(.clipping(s.document.layers[2].id, true))
    try s.execute(.groupLayers(s.document.layers.map(\.id), "Folder"))
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(s.document)), s.document)
    let original = try document()
    var plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: NativeArchive.encode(original), format: nil)
        as? [String: Any])
    plist["version"] = 4
    let legacy = try NativeArchive.decode(
      PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0))
    XCTAssertEqual(legacy, original)
    XCTAssertFalse(legacy.layers[0].isClipped)
    XCTAssertTrue(legacy.layers[0].clipsBlendAsGroup)
  }
  func testClippingCannotCrossGroupBoundaryAndRejectsMissingBase() throws {
    var s = EditorSession(document: try document())
    let ids = s.document.layers.map(\.id)
    XCTAssertThrowsError(try s.execute(.clipping(ids[0], true)))
    try s.execute(.groupLayers([ids[1], ids[2]], "Folder"))
    XCTAssertThrowsError(try s.execute(.clipping(ids[1], true)))
    try s.execute(.clipping(ids[2], true))
    XCTAssertEqual(s.document.clippingBase(for: ids[2])?.id, ids[1])
    XCTAssertTrue(s.document.isClippingBase(ids[1]))
    let before = s.document
    XCTAssertThrowsError(try s.execute(.groupLayers([ids[2]], "Incomplete clipping chain")))
    XCTAssertEqual(s.document, before)
  }
}
