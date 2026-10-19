import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest

@testable import PhotoCraft

final class LayerPanelOptionsTests: XCTestCase {
  @MainActor func testLegacyMigrationAndGlobalPersistenceAcrossWorkspaceReset() throws {
    let url = try SavedWorkspaceTests().temporaryURL()
    // Old state has no layerPanelOptions key.
    let data = try JSONEncoder().encode(WorkspaceState())
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("layerPanelOptions"))
    try data.write(to: url)
    let library = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNil(library.error)
    XCTAssertEqual(library.layerPanelOptions, LayerPanelOptions())
    let options = LayerPanelOptions(thumbnailSize: .large, thumbnailContents: .layerBounds)
    try library.setLayerPanelOptions(options)
    try library.save(name: "Retouch")
    try library.select("Essentials")
    try library.reset()
    XCTAssertEqual(library.layerPanelOptions, options)
    XCTAssertEqual(WorkspaceLibrary(persistenceURL: url).layerPanelOptions, options)
  }

  @MainActor func testUnknownOptionsPreserveOriginalFile() throws {
    let url = try SavedWorkspaceTests().temporaryURL()
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(WorkspaceState())) as? [String: Any])
    json["layerPanelOptions"] = [
      "thumbnailSize": "enormous", "thumbnailContents": "entireDocument",
    ]
    let original = try JSONSerialization.data(withJSONObject: json)
    try original.write(to: url)
    let library = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNotNil(library.error)
    XCTAssertThrowsError(try library.setLayerPanelOptions(.init(thumbnailSize: .none)))
    XCTAssertEqual(try Data(contentsOf: url), original)
  }

  @MainActor func testCancelCommitAndSharedDocumentsLeavePixelsHistoryAndArchiveUnchanged() throws {
    let doc = try GroupDisclosureWorkflowTests().fixture()
    let copy = CraftNSDocument(model: doc.store.document)
    defer {
      doc.close()
      copy.close()
    }
    copy.store.renderTask?.cancel()
    copy.store.workspaceLibrary = doc.store.workspaceLibrary
    let store = doc.store
    let archive = try doc.data(ofType: CraftNSDocument.nativeType)
    let pixels = try Renderer.composite(store.document)
    let revision = store.revision
    store.beginLayerPanelOptions()
    let cancelled = try XCTUnwrap(store.layerPanelOptionsDraft)
    cancelled.options.thumbnailSize = .large
    XCTAssertTrue(store.hasToneDraft)
    XCTAssertFalse(store.canBeginLayerCreation)
    store.cancelLayerPanelOptions()
    store.commitLayerPanelOptions(cancelled)
    XCTAssertEqual(store.workspaceLibrary.layerPanelOptions, LayerPanelOptions())
    store.beginLayerPanelOptions()
    let draft = try XCTUnwrap(store.layerPanelOptionsDraft)
    draft.options = .init(thumbnailSize: .none, thumbnailContents: .layerBounds)
    store.commitLayerPanelOptions(draft)
    XCTAssertNil(store.layerPanelOptionsDraft)
    XCTAssertEqual(copy.store.workspaceLibrary.layerPanelOptions, draft.options)
    XCTAssertEqual(try doc.data(ofType: CraftNSDocument.nativeType), archive)
    XCTAssertEqual(try Renderer.composite(store.document), pixels)
    XCTAssertEqual(store.revision, revision)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertFalse(doc.isDocumentEdited)
  }

  @MainActor func testWriteFailureRetainsDraftAndAtomicPreferenceState() throws {
    enum Failure: Error { case injected }
    let url = try SavedWorkspaceTests().temporaryURL()
    let original = try JSONEncoder().encode(WorkspaceState())
    try original.write(to: url)
    let doc = try GroupDisclosureWorkflowTests().fixture()
    defer { doc.close() }
    let store = doc.store
    store.workspaceLibrary = WorkspaceLibrary(
      persistenceURL: url, writer: { _, _ in throw Failure.injected })
    store.beginLayerPanelOptions()
    let draft = try XCTUnwrap(store.layerPanelOptionsDraft)
    draft.options.thumbnailSize = .small
    store.commitLayerPanelOptions(draft)
    XCTAssertTrue(store.layerPanelOptionsDraft === draft)
    XCTAssertNotNil(draft.error)
    XCTAssertEqual(store.workspaceLibrary.layerPanelOptions, LayerPanelOptions())
    XCTAssertEqual(try Data(contentsOf: url), original)
  }

  @MainActor func testStaleLibraryConcurrentSettingsReadAndCloseInvalidateDraft() throws {
    let doc = try GroupDisclosureWorkflowTests().fixture()
    defer { doc.close() }
    let store = doc.store
    store.beginLayerPanelOptions()
    let foreign = try XCTUnwrap(store.layerPanelOptionsDraft)
    foreign.options.thumbnailSize = .large
    store.workspaceLibrary = WorkspaceLibrary()
    store.commitLayerPanelOptions(foreign)
    XCTAssertNotNil(foreign.error)
    XCTAssertEqual(store.workspaceLibrary.layerPanelOptions, LayerPanelOptions())
    store.cancelLayerPanelOptions()
    store.beginLayerPanelOptions()
    let concurrent = try XCTUnwrap(store.layerPanelOptionsDraft)
    try store.workspaceLibrary.setLayerPanelOptions(.init(thumbnailSize: .small))
    store.commitLayerPanelOptions(concurrent)
    XCTAssertNotNil(concurrent.error)
    XCTAssertEqual(store.workspaceLibrary.layerPanelOptions.thumbnailSize, .small)
    let saved = try doc.data(ofType: CraftNSDocument.nativeType)
    try doc.read(from: saved, ofType: CraftNSDocument.nativeType)
    XCTAssertNil(store.layerPanelOptionsDraft)
    store.commitLayerPanelOptions(concurrent)
    store.beginLayerPanelOptions()
    XCTAssertNotNil(store.layerPanelOptionsDraft)
    doc.close()
    XCTAssertNil(store.layerPanelOptionsDraft)
  }

  @MainActor func testCompetingModalCannotOpenOptions() throws {
    let doc = try GroupDisclosureWorkflowTests().fixture()
    defer { doc.close() }
    doc.store.beginNewLayer()
    XCTAssertNotNil(doc.store.newLayerDraft)
    doc.store.beginLayerPanelOptions()
    XCTAssertNil(doc.store.layerPanelOptionsDraft)
  }

  @MainActor func testHostedNarrowRowsKeepNameAndNativeTargetsAtAllSizes() async throws {
    let helper = LayerRevealTests()
    let doc = try GroupDisclosureWorkflowTests().fixture()
    defer { doc.close() }
    let store = doc.store
    var model = store.document
    var mask = try Surface(width: 8, height: 6, fill: .black)
    for y in 0..<6 { for x in 0..<8 where x <= y { mask.setPixel(x: x, y: y, .white) } }
    model.layers[1].mask = mask
    model.layers[1].vectorMask = VectorMask(
      path: VectorPath(components: [
        PathComponent(
          knots: [
            PathKnot(PathPoint(1, 1)), PathKnot(PathPoint(7, 1)), PathKnot(PathPoint(7, 5)),
          ], closed: true)
      ]))
    store.session = EditorSession(document: model)
    store.workspaceLibrary.resizeDock(to: 275)
    store.workspaceLibrary.resizeProperties(to: 160)
    try store.session.setGroupExpansion(
      Set(model.layers.filter(\.isGroup).map(\.id)), expanded: true)
    let window = try await helper.host(store)
    defer { window.close() }
    let child = model.layers[1].id
    for size in LayerThumbnailSize.allCases {
      try store.workspaceLibrary.setLayerPanelOptions(.init(thumbnailSize: size))
      store.beginLayerName(child)
      try await helper.settle(window)
      let field = try XCTUnwrap(
        helper.descendants(window.contentView!).compactMap { $0 as? LayerNameField.NameField }.first
      )
      XCTAssertGreaterThanOrEqual(field.bounds.width, 24)
      XCTAssertGreaterThanOrEqual(field.visibleRect.intersection(field.bounds).width, 24)
      let eye = try XCTUnwrap(helper.eye(child, in: window))
      XCTAssertEqual(eye.bounds.height, size.controlHeight, accuracy: 0.5)
      XCTAssertEqual(eye.bounds.width, 22, accuracy: 0.5)
      helper.assertVisible(eye)
      let maskButtons = helper.descendants(window.contentView!).compactMap {
        $0 as? MaskThumbnailButton
      }
      .filter { $0.layerID == child }
      XCTAssertEqual(maskButtons.count, 2)
      for button in maskButtons {
        XCTAssertGreaterThanOrEqual(button.bounds.width, 14)
        XCTAssertGreaterThanOrEqual(button.bounds.height, 14)
        XCTAssertGreaterThanOrEqual(button.visibleRect.intersection(button.bounds).width, 14)
        XCTAssertEqual(button.accessibilityRole(), .button)
        XCTAssertNotNil(button.accessibilityLabel())
      }
      try helper.capture(window, named: "layer-options-" + size.rawValue)
      store.finishLayerName(cancel: true)
    }
    XCTAssertFalse(doc.isDocumentEdited)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }
}
