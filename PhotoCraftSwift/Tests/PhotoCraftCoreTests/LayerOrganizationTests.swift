import Foundation
import PhotoCraftCore
import XCTest

final class LayerOrganizationTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var document = try CraftDocument(width: 4, height: 3)
    var group = Layer(name: "Folder", content: .group(.init()))
    group.locked = true
    var child = Layer(name: "Child", content: .fill(.white))
    child.parentID = group.id
    var hidden = Layer(name: "Hidden child", content: .fill(.black))
    hidden.parentID = group.id
    hidden.visible = false
    document.layers += [hidden, child, group]
    return document
  }

  func testSelectedLabelsPreservePixelsReservedBytesAndLockedHierarchy() throws {
    var original = try fixture()
    original.layers[1].sourceTags = ["lclr": Data([0, 250, 1, 2, 3, 4, 5, 6]), "test": Data([9])]
    let ids = Set([original.layers[1].id, original.layers[3].id])
    var session = EditorSession(document: original)
    try session.execute(.layerColor(ids, .indigo))
    let edited = session.document
    XCTAssertEqual(edited.layers[1].sourceTags?["lclr"], Data([0, 9, 1, 2, 3, 4, 5, 6]))
    XCTAssertEqual(edited.layers[1].sourceTags?["test"], Data([9]))
    XCTAssertEqual(edited.layers[3].colorLabel, .indigo)
    XCTAssertEqual(
      edited.layers[2], original.layers[2], "Labeling a group does not rewrite its children")
    XCTAssertEqual(edited.layers.map(\.content), original.layers.map(\.content))
    XCTAssertEqual(edited.layers.map(\.visible), original.layers.map(\.visible))
    XCTAssertEqual(edited.layers.map(\.locked), original.layers.map(\.locked))
    XCTAssertEqual(edited.activeLayerID, original.activeLayerID)
    XCTAssertEqual(session.undoStack.count, 1)
    try session.undo()
    XCTAssertEqual(session.document, original)
    try session.redo()
    XCTAssertEqual(session.document, edited)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(edited)), edited)
  }

  func testNoOpNoneRetainsAbsentEncodingAndCreatesNoHistory() throws {
    let original = try fixture()
    var session = EditorSession(document: original)
    try session.execute(.layerColor(Set(original.layers.map(\.id)), .none))
    XCTAssertEqual(session.document, original)
    XCTAssertTrue(session.undoStack.isEmpty)
    try session.execute(.layerColor([original.layers[0].id], .red))
    try session.execute(.layerColor([original.layers[0].id], .red))
    XCTAssertEqual(session.undoStack.count, 1)
    try session.execute(.layerColor([original.layers[0].id], .none))
    XCTAssertEqual(session.document.layers[0].colorLabel, LayerColorLabel.none)
    XCTAssertEqual(session.undoStack.count, 2)
  }

  func testInvalidColorAndVisibilityTargetsRejectAtomically() throws {
    let original = try fixture()
    for command: Command in [
      .layerColor([], .red), .layerColor([original.layers[0].id, UUID()], .blue),
      .layerVisibility([:]), .layerVisibility([original.layers[0].id: false, UUID(): true]),
    ] {
      var direct = original
      XCTAssertThrowsError(try command.apply(to: &direct))
      XCTAssertEqual(direct, original)
      var session = EditorSession(document: original)
      XCTAssertThrowsError(try session.execute(command))
      XCTAssertEqual(session.document, original)
      XCTAssertTrue(session.undoStack.isEmpty)
    }
  }

  func testSelectedVisibilityKeepsChildFlagsAndOneUndo() throws {
    let original = try fixture()
    let ids = [original.layers[0].id, original.layers[3].id]
    var session = EditorSession(document: original)
    try session.execute(.layerVisibility(Dictionary(uniqueKeysWithValues: ids.map { ($0, false) })))
    XCTAssertFalse(session.document.layers[0].visible)
    XCTAssertFalse(session.document.layers[3].visible)
    XCTAssertTrue(session.document.layers[2].visible)
    XCTAssertFalse(session.document.isVisible(original.layers[2].id))
    XCTAssertEqual(session.document.layers.map(\.content), original.layers.map(\.content))
    XCTAssertEqual(session.undoStack.count, 1)
    try session.undo()
    XCTAssertEqual(session.document, original)
  }

  func testIsolateChildRevealsAncestorsAndGroupRetainsHiddenChildren() throws {
    var document = try fixture()
    document.layers[3].visible = false
    let ids = document.layers.map(\.id)
    let child = try LayerOrganization.isolatedVisibility(ids[2], in: document)
    XCTAssertEqual(child, [ids[0]: false, ids[1]: false, ids[2]: true, ids[3]: true])
    let group = try LayerOrganization.isolatedVisibility(ids[3], in: document)
    XCTAssertEqual(group, child)
    let hidden = try LayerOrganization.isolatedVisibility(ids[1], in: document)
    XCTAssertEqual(hidden, [ids[0]: false, ids[1]: true, ids[2]: false, ids[3]: true])
    XCTAssertThrowsError(try LayerOrganization.isolatedVisibility(UUID(), in: document))
  }

  func testIsolatedClippedLayerUsesSourceVisibilityFlags() throws {
    var document = try fixture()
    document.layers[3].locked = false
    document.layers[2].clipped = true
    let ids = document.layers.map(\.id)
    let values = try LayerOrganization.isolatedVisibility(ids[2], in: document)
    XCTAssertEqual(values, [ids[0]: false, ids[1]: false, ids[2]: true, ids[3]: true])
    XCTAssertFalse(document.layers[1].visible, "The map calculation is read-only")
  }
}
