import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest

@testable import PhotoCraft

final class NewGroupWorkflowTests: XCTestCase {
  @MainActor func testCancelAndConfiguredGroupCreationHaveOneDocumentChange() async throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let original = store.document
    var changes = 0
    store.onChange = { _ in changes += 1 }
    store.beginNewGroup()
    var draft = try XCTUnwrap(store.newGroupDraft)
    XCTAssertEqual(draft.options.name, "Group 1")
    XCTAssertNil(draft.options.mode)
    XCTAssertEqual(draft.opacityText, "100")
    store.cancelNewGroup()
    store.commitNewGroup(draft)
    XCTAssertEqual(store.document, original)
    XCTAssertEqual(changes, 0)
    store.beginNewGroup(fromSelection: true)
    draft = try XCTUnwrap(store.newGroupDraft)
    draft.options.name = "Artwork"
    draft.options.color = .violet
    draft.options.mode = .normal
    draft.opacityText = "45.5"
    store.commitNewGroup(draft)
    let group = try XCTUnwrap(store.activeLayer)
    XCTAssertEqual(group.name, "Artwork")
    XCTAssertEqual(group.colorLabel, .violet)
    XCTAssertEqual(group.group?.passThrough, false)
    XCTAssertEqual(group.opacity, 0.455)
    XCTAssertEqual(changes, 1)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.selectedLayerIDs, [group.id])
    XCTAssertNil(store.newGroupDraft)
    let result = store.document
    await store.undo()
    XCTAssertEqual(store.document, original)
    await store.redo()
    XCTAssertEqual(store.document, result)
  }

  @MainActor func testDraftBlocksOtherEditsAndRejectsChangedSelectionOrDocument() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    store.selectedLayerIDs = Set(store.document.layers.prefix(2).map(\.id))
    let original = store.document
    store.beginNewGroup(fromSelection: true)
    let draft = try XCTUnwrap(store.newGroupDraft)
    XCTAssertFalse(store.canCreateGroup())
    XCTAssertFalse(store.canCreatePixelLayer())
    XCTAssertFalse(store.canBeginLevels)
    store.select(store.document.layers[2].id)
    store.beginNewLayer()
    store.newGroup()
    store.groupSelection()
    store.perform(.renameLayer(original.layers[0].id, "Wrong"))
    XCTAssertEqual(store.document, original)
    XCTAssertNil(store.newLayerDraft)
    store.selectedLayerIDs = [original.layers[2].id]
    store.commitNewGroup(draft)
    XCTAssertTrue(store.newGroupDraft === draft)
    XCTAssertNotNil(draft.error)
    XCTAssertEqual(store.document, original)
    store.selectedLayerIDs = draft.children
    try store.session.execute(.renameLayer(original.layers[0].id, "External change"))
    let changed = store.document
    store.commitNewGroup(draft)
    XCTAssertEqual(store.document, changed)
    XCTAssertEqual(store.session.undoStack.count, 1)
  }

  @MainActor func testInvalidFieldsRetainDraftAndDocument() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    store.beginNewGroup()
    let draft = try XCTUnwrap(store.newGroupDraft)
    let original = store.document
    for text in ["", "bad", "nan", "inf", "-1", "101"] {
      draft.opacityText = text
      XCTAssertNil(draft.validatedOptions)
      store.commitNewGroup(draft)
      XCTAssertEqual(store.document, original)
    }
    draft.opacityText = "100"
    draft.options.name = " "
    XCTAssertNil(draft.validatedOptions)
    draft.options.name = "Named"
    XCTAssertNotNil(draft.validatedOptions)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertTrue(store.newGroupDraft === draft)
  }

  @MainActor func testFooterModifierRoutesEmptySelectedAndBelowGroups() throws {
    for bits in 0..<8 {
      let store = try GroupWorkflowTests().store()
      defer { store.renderTask?.cancel() }
      let selected = Set(store.document.layers.prefix(2).map(\.id))
      store.selectedLayerIDs = selected
      let base = try XCTUnwrap(store.activeLayer?.id)
      var flags: NSEvent.ModifierFlags = []
      if bits & 1 != 0 { flags.insert(.option) }
      if bits & 2 != 0 { flags.insert(.shift) }
      if bits & 4 != 0 { flags.insert(.command) }
      store.createGroupFromFooter(modifiers: flags)
      if flags.contains(.option) {
        XCTAssertEqual(store.document.layers.count, 3)
        store.commitNewGroup(try XCTUnwrap(store.newGroupDraft))
      }
      let group = try XCTUnwrap(store.activeLayer)
      XCTAssertTrue(group.isGroup)
      XCTAssertEqual(group.group?.passThrough, true)
      XCTAssertEqual(
        Set(store.document.children(of: group.id).map(\.id)), flags.contains(.shift) ? selected : []
      )
      if !flags.contains(.shift) {
        let index = try XCTUnwrap(store.document.activeIndex)
        let baseIndex = try XCTUnwrap(store.document.layers.firstIndex { $0.id == base })
        XCTAssertEqual(index, flags.contains(.command) ? baseIndex - 1 : baseIndex + 1)
      }
      XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }

  @MainActor func testSharedCreationGuardCoversSheetsAlertsAndEmptySelection() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    store.showGaps = true
    XCTAssertFalse(store.canCreateGroup())
    XCTAssertFalse(store.canCreatePixelLayer())
    store.showGaps = false
    store.error = "Pending alert"
    XCTAssertFalse(store.canCreateGroup())
    XCTAssertFalse(store.canCreatePixelLayer())
    store.error = nil
    store.beginNewLayer()
    store.beginNewGroup()
    XCTAssertNil(store.newGroupDraft)
    store.cancelNewLayer()
    var empty = store.document
    empty.layers = []
    empty.activeLayerID = nil
    store.session = EditorSession(document: empty)
    store.selectedLayerIDs = []
    XCTAssertFalse(store.canCreateGroup(fromSelection: true))
    store.groupSelection()
    XCTAssertTrue(store.document.layers.isEmpty)
    XCTAssertTrue(store.canCreateGroup())
    store.newGroup()
    XCTAssertEqual(store.document.layers.count, 1)
  }

  @MainActor func testMenuDialogsRemainDistinctFromImmediateCommandG() throws {
    try PhotoshopMenuTests().withMenus { app, menu in
      let controller = app.controller
      let doc = CraftNSDocument(model: try CraftDocument(width: 2, height: 2))
      let other = CraftNSDocument(model: try CraftDocument(width: 2, height: 2))
      defer {
        doc.close()
        other.close()
        doc.store.renderTask?.cancel()
        other.store.renderTask?.cancel()
      }
      for d in [doc, other] {
        controller.addDocument(d)
        d.makeWindowControllers()
      }
      XCTAssertTrue(controller.documentWindows.activate(doc))
      let layerMenu = try XCTUnwrap(menu.item(withTitle: "Layer")?.submenu)
      let newMenu = try XCTUnwrap(layerMenu.item(withTitle: "New")?.submenu)
      let new = try XCTUnwrap(newMenu.item(withTitle: "Group…"))
      let from = try XCTUnwrap(newMenu.item(withTitle: "Group from Layers…"))
      let immediate = try XCTUnwrap(layerMenu.item(withTitle: "Group Layers"))
      XCTAssertNotEqual(from.action, immediate.action)
      XCTAssertEqual(immediate.keyEquivalent, "g")
      XCTAssertEqual(immediate.keyEquivalentModifierMask, [.command])
      for item in [new, from] {
        let original = doc.store.document
        XCTAssertTrue(app.validateMenuItem(item))
        newMenu.performActionForItem(at: newMenu.index(of: item))
        XCTAssertNotNil(doc.store.newGroupDraft)
        XCTAssertEqual(doc.store.document, original)
        XCTAssertEqual(doc.store.newGroupDraft?.children.isEmpty, item === new)
        XCTAssertFalse(app.validateMenuItem(immediate))
        XCTAssertFalse(controller.documentWindows.activate(other))
        doc.store.cancelNewGroup()
      }
      layerMenu.performActionForItem(at: layerMenu.index(of: immediate))
      XCTAssertNil(doc.store.newGroupDraft)
      XCTAssertEqual(doc.store.activeLayer?.name, "Group 1")
      XCTAssertEqual(doc.store.document.layers.count, 2)
      XCTAssertEqual(doc.store.session.undoStack.count, 1)
      XCTAssertTrue(controller.documentWindows.activate(other))
    }
  }

  @MainActor func testNativeFieldsFitNewGroupContent() throws {
    _ = NSApplication.shared
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    store.beginNewGroup()
    let draft = try XCTUnwrap(store.newGroupDraft)
    let host = NSHostingView(rootView: NewGroupSheet(store: store, draft: draft))
    let window = NSWindow(
      contentRect: .init(x: 0, y: 0, width: 560, height: 200),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    host.layoutSubtreeIfNeeded()
    func fields(_ view: NSView) -> [NSTextField] {
      (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
    }
    let controls = fields(host).filter(\.isEditable)
    XCTAssertEqual(controls.count, 2)
    XCTAssertEqual(Set(controls.map(\.stringValue)), ["Group 1", "100"])
    for control in controls {
      let bounds = control.convert(control.bounds, to: host)
      XCTAssertGreaterThanOrEqual(bounds.minX, 0)
      XCTAssertGreaterThanOrEqual(bounds.minY, 0)
      XCTAssertLessThanOrEqual(bounds.maxX, host.bounds.width)
      XCTAssertLessThanOrEqual(bounds.maxY, host.bounds.height)
    }
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  func testPassThroughGroupingPreservesNativePixelsAndPSDGroupSettingsAtAllDepths() throws {
    for depth in PixelDepth.allCases {
      var original = try CraftDocument(width: 4, height: 3, depth: depth)
      original.layers.append(
        Layer(
          name: "Paint",
          content: .raster(
            try Surface(width: 2, height: 2, depth: depth, fill: Pixel(0.3, 0.6, 0.9)))))
      var session = EditorSession(document: original)
      try session.execute(
        .newGroup(.init(name: "Pass Through"), children: original.layers.map(\.id)))
      XCTAssertEqual(try Renderer.composite(session.document), try Renderer.composite(original))
      for mode: PhotoCraftCore.BlendMode? in [nil, .normal, .multiply] {
        session = EditorSession(document: original)
        var options = NewLayerGroupOptions(name: "Saved Group")
        options.mode = mode
        options.opacity = 0.4
        options.color = .seafoam
        try session.execute(.newGroup(options, children: original.layers.map(\.id)))
        XCTAssertEqual(
          try NativeArchive.decode(NativeArchive.encode(session.document)), session.document)
        let decoded = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document))
        let group = try XCTUnwrap(decoded.layers.first { $0.name == "Saved Group" })
        XCTAssertEqual(group.group?.passThrough, mode == nil)
        XCTAssertEqual(group.blendMode, mode ?? .normal)
        XCTAssertEqual(group.colorLabel, .seafoam)
        XCTAssertEqual(group.opacity, 0.4, accuracy: 0.000001)
        XCTAssertEqual(decoded.children(of: group.id).map(\.name), original.layers.map(\.name))
      }
    }
  }
}
