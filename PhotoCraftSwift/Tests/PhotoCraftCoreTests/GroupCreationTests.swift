import PhotoCraftCore
import XCTest

final class GroupCreationTests: XCTestCase {
  func testNoncontiguousRootsKeepRelativeOrderAtTopSelectedPosition() throws {
    var document = try CraftDocument(width: 2, height: 2)
    document.layers = ["A", "B", "C", "D"].map { Layer(name: $0, content: .fill(.white)) }
    document.activeLayerID = document.layers[0].id
    let selected = [document.layers[2].id, document.layers[0].id]
    var session = EditorSession(document: document)
    try session.execute(.newGroup(.init(name: "Grouped"), children: selected))
    XCTAssertEqual(session.document.layers.map(\.name), ["B", "A", "C", "Grouped", "D"])
    let group = try XCTUnwrap(session.document.activeLayerID)
    XCTAssertEqual(session.document.children(of: group).map(\.name), ["A", "C"])
    XCTAssertEqual(session.document.children(of: nil).map(\.name), ["B", "Grouped", "D"])
    session.undo()
    XCTAssertEqual(session.document, document)
  }
  func testEmptyGroupDefaultsInsertionAndNaming() throws {
    let document = try CraftDocument(width: 2, height: 2)
    var session = EditorSession(document: document)
    XCTAssertEqual(document.suggestedGroupName, "Group 1")
    try session.execute(.newGroup(.init(name: document.suggestedGroupName)))
    let outer = try XCTUnwrap(session.document.layers.last)
    XCTAssertEqual(outer.name, "Group 1")
    XCTAssertEqual(outer.group, GroupContent(passThrough: true, expanded: true))
    XCTAssertEqual(outer.opacity, 1)
    XCTAssertNil(outer.parentID)
    XCTAssertEqual(session.undoStack.last?.label, "New Group")
    try session.execute(.newGroup(.init(name: session.document.suggestedGroupName)))
    let inner = try XCTUnwrap(session.document.layers.first { $0.name == "Group 2" })
    XCTAssertEqual(inner.parentID, outer.id)
    session.selectLayer(outer.id)
    try session.execute(.newGroup(.init(name: "Below"), below: true))
    XCTAssertEqual(
      session.document.layers.map(\.name), ["Background", "Below", "Group 2", "Group 1"])
    XCTAssertNil(session.document.layers[1].parentID)
    session.undo()
    session.undo()
    session.undo()
    XCTAssertEqual(session.document, document)
  }

  func testConfiguredGroupingPreservesDescendantsAndIsSingleUndo() throws {
    var document = try CraftDocument(width: 3, height: 2)
    let folder = Layer(name: "Inner", content: .group(.init()))
    var child = Layer(
      name: "Pixel", content: .raster(try Surface(width: 2, height: 2, fill: .black)))
    child.parentID = folder.id
    child.x = -3
    child.colorLabel = .indigo
    child.mask = try Surface(width: 2, height: 2, fill: .white)
    var other = Layer(name: "Other", content: .fill(.white))
    other.opacity = 0.7
    document.layers += [child, folder, other]
    document.activeLayerID = other.id
    document.selection = .init(x: 0, y: 0, width: 1, height: 1)
    var options = NewLayerGroupOptions(name: "Grade")
    options.color = .orange
    options.mode = .multiply
    options.opacity = 0.4
    var session = EditorSession(document: document)
    try session.execute(.newGroup(options, children: [other.id, child.id, folder.id]))
    let grouped = session.document
    let group = try XCTUnwrap(grouped.layers.last)
    XCTAssertEqual(group.name, "Grade")
    XCTAssertEqual(group.colorLabel, .orange)
    XCTAssertEqual(group.blendMode, .multiply)
    XCTAssertEqual(group.group?.passThrough, false)
    XCTAssertEqual(group.opacity, 0.4)
    XCTAssertEqual(grouped.children(of: group.id).map(\.id), [folder.id, other.id])
    XCTAssertEqual(grouped.layers.first { $0.id == child.id }, child)
    XCTAssertEqual(
      grouped.layers.map(\.id).prefix(document.layers.count), document.layers.map(\.id)[...])
    XCTAssertEqual(grouped.selection, document.selection)
    XCTAssertEqual(session.undoStack.count, 1)
    XCTAssertEqual(session.undoStack.last?.label, "Group Layers")
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(grouped)), grouped)
    session.undo()
    XCTAssertEqual(session.document, document)
    session.redo()
    XCTAssertEqual(session.document, grouped)
  }

  func testHierarchyLimitRejectsDirectAndSessionMutationAtomically() throws {
    var document = try CraftDocument(width: 2, height: 2)
    document.layers = (0..<32).map { Layer(name: "Group \($0)", content: .group(.init())) }
    for i in 0..<31 { document.layers[i].parentID = document.layers[i + 1].id }
    document.activeLayerID = document.layers[0].id
    XCTAssertNoThrow(try document.validate())
    let original = document
    XCTAssertThrowsError(try Command.newGroup(.init(name: "Too deep")).apply(to: &document))
    XCTAssertEqual(document, original)
    var session = EditorSession(document: original)
    XCTAssertThrowsError(try session.execute(.newGroup(.init(name: "Too deep"))))
    XCTAssertEqual(session.document, original)
    XCTAssertTrue(session.undoStack.isEmpty)
  }

  func testInvalidAndLockedSelectionsCannotPartiallyGroup() throws {
    var document = try CraftDocument(width: 2, height: 2)
    let folder = Layer(name: "Folder", content: .group(.init()))
    var child = Layer(name: "Child", content: .fill(.white))
    child.parentID = folder.id
    var clipped = Layer(name: "Clipped", content: .fill(.black))
    clipped.parentID = folder.id
    clipped.clipped = true
    document.layers += [child, clipped, folder]
    document.activeLayerID = child.id
    for ids in [[UUID()], [document.layers[0].id, child.id], [clipped.id]] {
      var session = EditorSession(document: document)
      XCTAssertThrowsError(try session.execute(.newGroup(.init(name: "Invalid"), children: ids)))
      XCTAssertEqual(session.document, document)
      XCTAssertTrue(session.undoStack.isEmpty)
    }
    var session = EditorSession(document: document)
    XCTAssertThrowsError(
      try session.execute(.newGroup(.init(name: "Bad position"), children: [child.id], below: true))
    )
    try session.execute(.newGroup(.init(name: "Clip chain"), children: [child.id, clipped.id]))
    XCTAssertEqual(session.document.clippingBase(for: clipped.id)?.id, child.id)
    document.layers[3].locked = true
    session = EditorSession(document: document)
    XCTAssertThrowsError(
      try session.execute(.newGroup(.init(name: "Locked"), children: [child.id])))
    XCTAssertThrowsError(try session.execute(.newGroup(.init(name: "Inside locked"))))
    XCTAssertEqual(session.document, document)
    session.selectLayer(folder.id)
    XCTAssertNoThrow(try session.execute(.newGroup(.init(name: "Outside"), below: true)))
  }

  func testInvalidOptionsAndLayerCapLeaveHistoryUntouched() throws {
    let document = try CraftDocument(width: 2, height: 2)
    for value: Float in [.nan, .infinity, -0.1, 1.1] {
      var options = NewLayerGroupOptions(name: "Options")
      options.opacity = value
      var session = EditorSession(document: document)
      XCTAssertThrowsError(try session.execute(.newGroup(options)))
      XCTAssertEqual(session.document, document)
      XCTAssertTrue(session.undoStack.isEmpty)
    }
    var options = NewLayerGroupOptions(name: "  ")
    XCTAssertThrowsError(try options.layer())
    options.name = "Zero opacity"
    options.opacity = 0
    XCTAssertEqual(try options.layer().opacity, 0)
    var full = document
    full.layers += (1..<512).map { Layer(name: "\($0)", content: .fill(.white)) }
    var session = EditorSession(document: full)
    XCTAssertThrowsError(
      try session.execute(.newGroup(.init(name: "Over cap"), children: [full.layers[0].id])))
    XCTAssertEqual(session.document, full)
  }
}
