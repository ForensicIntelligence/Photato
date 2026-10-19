import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest

@testable import PhotoCraft

final class ChannelPanelTests: XCTestCase {
  @MainActor func testHostedOptionsAndChannelPanelsAtEverySize() async throws {
    let doc = try GroupDisclosureWorkflowTests().fixture()
    defer { doc.close() }
    let helper = LayerRevealTests()
    var model = try CraftNSDocument.blankModel(
      width: 64, height: 48, background: Pixel(0.2, 0.6, 0.9))
    var colors = try Surface(width: 64, height: 48, fill: Pixel(0.2, 0.6, 0.9))
    for y in 8..<40 {
      for x in 8..<56 {
        colors.setPixel(x: x, y: y, x < 32 ? Pixel(0.9, 0.2, 0.1) : Pixel(0.1, 0.8, 0.2))
      }
    }
    model.layers[0].content = .raster(colors)
    doc.store.session = EditorSession(document: model)
    doc.store.surface = try Renderer.composite(doc.store.document)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 275, height: 420),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.appearance = NSAppearance(named: .darkAqua)
    for size in ChannelThumbnailSize.allCases {
      try doc.store.workspaceLibrary.setChannelPanelOptions(.init(thumbnailSize: size))
      let host = NSHostingView(
        rootView: ChannelsPanel(store: doc.store).background(StudioTheme.panel)
          .foregroundStyle(Color(white: 0.88)).preferredColorScheme(.dark))
      window.contentView = host
      try await helper.settle(window)
      XCTAssertEqual(host.bounds.width, 275, accuracy: 0.5)
      // The footer wraps within the actual host. Its unconstrained ideal width is wider.
      try helper.capture(window, named: "channels-" + size.rawValue)
    }
    doc.store.beginChannelPanelOptions()
    let draft = try XCTUnwrap(doc.store.channelPanelOptionsDraft)
    let dialog = NSHostingView(
      rootView: ChannelPanelOptionsSheet(store: doc.store, draft: draft).preferredColorScheme(.dark)
    )
    window.contentView = dialog
    window.setContentSize(dialog.fittingSize)
    try await helper.settle(window)
    XCTAssertLessThanOrEqual(dialog.fittingSize.width, 420)
    XCTAssertLessThanOrEqual(dialog.fittingSize.height, 500)
    try helper.capture(window, named: "channels-panel-options")
    doc.store.cancelChannelPanelOptions()
    XCTAssertFalse(doc.isDocumentEdited)
    XCTAssertTrue(doc.store.session.undoStack.isEmpty)
  }

  @MainActor func testLegacyMigrationPersistenceAndWorkspaceResetIndependence() throws {
    let url = try SavedWorkspaceTests().temporaryURL()
    try JSONEncoder().encode(WorkspaceState()).write(to: url)
    let library = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNil(library.error)
    XCTAssertEqual(library.channelPanelOptions.thumbnailSize, .small)
    for size in ChannelThumbnailSize.allCases {
      try library.setChannelPanelOptions(.init(thumbnailSize: size))
      try library.save(name: "Channels", replacing: library.customNames.contains("Channels"))
      try library.select("Essentials")
      try library.reset()
      XCTAssertEqual(library.channelPanelOptions.thumbnailSize, size)
      XCTAssertEqual(WorkspaceLibrary(persistenceURL: url).channelPanelOptions.thumbnailSize, size)
      XCTAssertEqual(library.layerPanelOptions, LayerPanelOptions())
    }
  }

  @MainActor func testUnsupportedPreferencePreservesFileAndRejectsOverwrite() throws {
    let url = try SavedWorkspaceTests().temporaryURL()
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(WorkspaceState())) as? [String: Any])
    json["channelPanelOptions"] = ["thumbnailSize": "futureSize"]
    let bytes = try JSONSerialization.data(withJSONObject: json)
    try bytes.write(to: url)
    let library = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNotNil(library.error)
    XCTAssertThrowsError(try library.setChannelPanelOptions(.init(thumbnailSize: .large)))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  @MainActor func testOptionsCancelCommitAndSharedDocumentsPreserveArchivePixelsAndHistory() throws
  {
    let doc = try GroupDisclosureWorkflowTests().fixture()
    let second = CraftNSDocument(model: doc.store.document)
    defer {
      doc.close()
      second.close()
    }
    second.store.renderTask?.cancel()
    second.store.workspaceLibrary = doc.store.workspaceLibrary
    let store = doc.store
    let before = try doc.data(ofType: CraftNSDocument.nativeType)
    let pixels = try Renderer.composite(store.document)
    store.beginChannelPanelOptions()
    let cancelled = try XCTUnwrap(store.channelPanelOptionsDraft)
    cancelled.options.thumbnailSize = .large
    XCTAssertTrue(store.hasToneDraft)
    store.beginLayerPanelOptions()
    XCTAssertNil(store.layerPanelOptionsDraft)
    store.previewChannel(.blue)
    XCTAssertNil(store.displayChannel)
    store.cancelChannelPanelOptions()
    store.commitChannelPanelOptions(cancelled)
    XCTAssertEqual(store.workspaceLibrary.channelPanelOptions.thumbnailSize, .small)
    store.beginChannelPanelOptions()
    let draft = try XCTUnwrap(store.channelPanelOptionsDraft)
    draft.options.thumbnailSize = .none
    store.commitChannelPanelOptions(draft)
    XCTAssertNil(store.channelPanelOptionsDraft)
    XCTAssertEqual(second.store.workspaceLibrary.channelPanelOptions.thumbnailSize, .none)
    XCTAssertEqual(try doc.data(ofType: CraftNSDocument.nativeType), before)
    XCTAssertEqual(try Renderer.composite(store.document), pixels)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertFalse(doc.isDocumentEdited)
  }

  @MainActor func testWriteFailureIsAtomicAndKeepsDraft() throws {
    enum Failure: Error { case write }
    let doc = try GroupDisclosureWorkflowTests().fixture()
    defer { doc.close() }
    let url = try SavedWorkspaceTests().temporaryURL()
    let bytes = try JSONEncoder().encode(WorkspaceState())
    try bytes.write(to: url)
    doc.store.workspaceLibrary = WorkspaceLibrary(
      persistenceURL: url, writer: { _, _ in throw Failure.write })
    doc.store.beginChannelPanelOptions()
    let draft = try XCTUnwrap(doc.store.channelPanelOptionsDraft)
    draft.options.thumbnailSize = .large
    doc.store.commitChannelPanelOptions(draft)
    XCTAssertTrue(doc.store.channelPanelOptionsDraft === draft)
    XCTAssertNotNil(draft.error)
    XCTAssertEqual(doc.store.workspaceLibrary.channelPanelOptions.thumbnailSize, .small)
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  @MainActor func testStaleLibraryConcurrentChangeReadAndCloseCannotCommitOldDraft() throws {
    let doc = try GroupDisclosureWorkflowTests().fixture()
    defer { doc.close() }
    let store = doc.store
    store.beginChannelPanelOptions()
    let foreign = try XCTUnwrap(store.channelPanelOptionsDraft)
    foreign.options.thumbnailSize = .large
    store.workspaceLibrary = WorkspaceLibrary()
    store.commitChannelPanelOptions(foreign)
    XCTAssertNotNil(foreign.error)
    XCTAssertEqual(store.workspaceLibrary.channelPanelOptions.thumbnailSize, .small)
    store.cancelChannelPanelOptions()
    store.beginChannelPanelOptions()
    let concurrent = try XCTUnwrap(store.channelPanelOptionsDraft)
    try store.workspaceLibrary.setChannelPanelOptions(.init(thumbnailSize: .none))
    store.commitChannelPanelOptions(concurrent)
    XCTAssertNotNil(concurrent.error)
    let bytes = try doc.data(ofType: CraftNSDocument.nativeType)
    try doc.read(from: bytes, ofType: CraftNSDocument.nativeType)
    XCTAssertNil(store.channelPanelOptionsDraft)
    store.commitChannelPanelOptions(concurrent)
    store.beginChannelPanelOptions()
    XCTAssertNotNil(store.channelPanelOptionsDraft)
    doc.close()
    XCTAssertNil(store.channelPanelOptionsDraft)
  }

  @MainActor func testIndependentThumbnailsUseUnfilteredCompositeThroughComponentPreviewChanges()
    async throws
  {
    // Match product startup before NSDocument can create AppKit's base controller singleton.
    _ = NSApplication.shared
    _ = CraftDocumentController(workspaces: WorkspaceLibrary())
    let doc = CraftNSDocument(
      model: try CraftNSDocument.blankModel(width: 3, height: 2, background: Pixel(0.2, 0.6, 0.9)))
    defer { doc.close() }
    let store = doc.store
    let bytes = try doc.data(ofType: CraftNSDocument.nativeType)
    let cache = ChannelThumbnailCache()
    var baseline: [Surface]?
    var previousRevision = store.channelCompositeRevision
    for component in RGBChannelPreview.allCases {
      store.previewChannel(component)
      await store.renderTask?.value
      XCTAssertNotEqual(store.channelCompositeRevision, previousRevision)
      previousRevision = store.channelCompositeRevision
      await cache.update(
        .init(
          owner: store.identity, generation: store.layerPanelGeneration,
          composite: store.channelCompositeRevision, maximumSize: 32), source: store.surface)
      XCTAssertNil(cache.error)
      XCTAssertEqual(cache.images.count, 4)
      let images = try cache.images.map { try RasterIO.surface($0) }
      if let baseline { XCTAssertEqual(images, baseline) } else { baseline = images }
      let samples = images.map { $0.pixel(x: 1, y: 1) }
      XCTAssertEqual(samples[0].g, 0.6, accuracy: 0.01)
      for (sample, expected) in zip(samples.dropFirst(), [Float(0.2), 0.6, 0.9]) {
        XCTAssertEqual(sample.r, expected, accuracy: 0.01)
        XCTAssertEqual(sample.r, sample.g)
        XCTAssertEqual(sample.g, sample.b)
      }
    }
    XCTAssertEqual(try doc.data(ofType: CraftNSDocument.nativeType), bytes)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertFalse(doc.isDocumentEdited)
  }

  @MainActor func testNoneSkipsRenderingAndClearsPreviousImages() async throws {
    let cache = ChannelThumbnailCache()
    let source = try Surface(width: 1, height: 1, fill: .white)
    let owner = UUID()
    let generation = UUID()
    let composite = UUID()
    await cache.update(
      .init(owner: owner, generation: generation, composite: composite, maximumSize: 32),
      source: source)
    XCTAssertEqual(cache.images.count, 4)
    await cache.update(
      .init(owner: owner, generation: generation, composite: composite, maximumSize: 0),
      source: source,
      render: { _, _ in
        XCTFail("None must skip rasterization")
        return []
      })
    XCTAssertTrue(cache.images.isEmpty)
    XCTAssertNil(cache.error)
  }

  @MainActor func testDelayedOldDocumentCannotReplaceNewThumbnailRequest() async throws {
    let cache = ChannelThumbnailCache()
    let source = try Surface(width: 1, height: 1, fill: .white)
    let gate = DispatchSemaphore(value: 0)
    let began = XCTestExpectation(description: "Old render started")
    let first = ChannelThumbnailRequest(
      owner: UUID(), generation: UUID(), composite: UUID(), maximumSize: 32)
    let second = ChannelThumbnailRequest(
      owner: UUID(), generation: UUID(), composite: UUID(), maximumSize: 0)
    let task = Task {
      await cache.update(
        first, source: source,
        render: { _, _ in
          began.fulfill()
          _ = gate.wait(timeout: .now() + 5)
          return [try RasterIO.displayImage(source)]
        })
    }
    await fulfillment(of: [began], timeout: 3)
    await cache.update(second, source: source)
    gate.signal()
    await task.value
    XCTAssertEqual(cache.request, second)
    XCTAssertTrue(cache.images.isEmpty)
  }
}
