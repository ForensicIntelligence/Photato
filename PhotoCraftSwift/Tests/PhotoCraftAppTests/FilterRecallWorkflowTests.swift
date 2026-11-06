import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private final class RecallGate: @unchecked Sendable {
  let condition = NSCondition()
  private var ready = false
  func wait() { condition.lock(); while !ready { condition.wait() }; condition.unlock() }
  func release() { condition.lock(); ready = true; condition.broadcast(); condition.unlock() }
}

final class FilterRecallWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 12, height: 10, depth: depth)
    var pixels = try Surface(width: 12, height: 10, depth: depth)
    for y in 0..<10 { for x in 0..<12 {
      pixels.setPixel(x: x, y: y, .init(Float(x % 3)/2, Float(y % 4)/3, x == y ? 1 : 0.2, 0.8))
    } }
    d.layers[0].content = .raster(pixels)
    return d
  }
  @MainActor func stop(_ s: EditorStore) { s.renderTask?.cancel(); s.geometryTask?.cancel() }

  @MainActor func testNativeRecallUsesCurrentSelectionDepthAndOneUndo() async throws {
    for depth in PixelDepth.allCases {
      let original = try fixture(depth), s = EditorStore(document: original)
      defer { stop(s) }
      XCTAssertFalse(s.canRepeatFilter)
      s.beginFilter(.gaussianBlur)
      s.filterDraft?.filter.radius = 1.7
      s.commitFilter(); await s.geometryTask?.value
      XCTAssertNil(s.error)
      let filter = try XCTUnwrap(s.filterRecall.filter)
      XCTAssertEqual(filter.radius, 1.7)
      await s.undo()
      XCTAssertEqual(s.document, original)
      XCTAssertEqual(s.filterRecall.filter, filter)
      s.perform(.selection(.init(x: 3, y: 2, width: 5, height: 4)))
      let before = s.document, count = s.session.undoStack.count
      var expected = before
      try Command.applyFilter(before.layers[0].id, filter).apply(to: &expected)
      s.repeatLastFilter(); await s.geometryTask?.value
      XCTAssertNil(s.error)
      XCTAssertEqual(s.document, expected)
      XCTAssertEqual(try NativeArchive.encodeChunked(s.document), try NativeArchive.encodeChunked(expected))
      XCTAssertEqual(s.session.undoStack.count, count + 1)
      await s.undo(); XCTAssertEqual(s.document, before)
      await s.redo(); XCTAssertEqual(s.document, expected)
      XCTAssertEqual(s.filterRecall.filter, filter)
    }
  }

  @MainActor func testControllerSharesRecallAcrossTargetsAndClosingSourceDetachesIt() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let first = CraftNSDocument(model: try fixture()), second = CraftNSDocument(model: try fixture(.u16))
    controller.addDocument(first); controller.addDocument(second)
    defer {
      stop(first.store); stop(second.store)
      if controller.documents.contains(where: { $0 === first }) { controller.removeDocument(first) }
      controller.removeDocument(second)
    }
    let f = RasterFilter(.mosaic)
    first.store.performGeometry(.applyFilter(first.store.document.layers[0].id, f))
    await first.store.geometryTask?.value
    XCTAssertTrue(first.store.filterRecall === second.store.filterRecall)
    XCTAssertEqual(second.store.filterRecall.filter, f)
    let before = second.store.document
    var expected = before
    try Command.applyFilter(before.layers[0].id, f).apply(to: &expected)
    controller.removeDocument(first)
    XCTAssertFalse(first.store.filterRecall === second.store.filterRecall)
    second.store.repeatLastFilter(); await second.store.geometryTask?.value
    XCTAssertNil(second.store.error); XCTAssertEqual(second.store.document, expected)
    try first.store.executeEditorCommand(.applyFilter(first.store.document.layers[0].id, .init(.boxBlur)))
    XCTAssertEqual(second.store.filterRecall.filter, f)
    XCTAssertFalse(EditorStore(document: before).canRepeatFilter)
  }

  @MainActor func testImmediatePreviewCancelInvalidAndCancelledWorkRetainRecall() async throws {
    let original = try fixture(), s = EditorStore(document: original)
    defer { stop(s) }
    s.beginFilter(.sharpen); await s.geometryTask?.value
    let first = try XCTUnwrap(s.filterRecall.filter)
    XCTAssertEqual(first.kind, .sharpen)
    let before = s.document, revision = s.filterRecall.revision
    s.repeatLastFilter(showDialog: true)
    XCTAssertEqual(s.filterDraft?.filter, first)
    s.filterDraft?.filter = .init(.gaussianBlur)
    s.filterDraft?.filter.radius = 2.4
    await s.renderTask?.value
    XCTAssertEqual(s.document, before)
    s.cancelFilter(); XCTAssertEqual(s.filterRecall.filter, first)
    s.beginFilter(.boxBlur); s.filterDraft?.filter.radius = -1
    s.commitFilter(); XCTAssertNotNil(s.filterDraft)
    XCTAssertEqual(s.filterRecall.revision, revision)
    s.cancelFilter(); s.error = nil
    let gate = RecallGate(); defer { gate.release() }
    s.repeatFilterPreparation = { source, request in gate.wait(); try Task.checkCancellation(); return try request.command(in: source) }
    s.repeatLastFilter(); s.geometryTask?.cancel(); gate.release(); await s.geometryTask?.value
    XCTAssertEqual(s.document, before); XCTAssertEqual(s.filterRecall.filter, first)
    XCTAssertEqual(s.filterRecall.revision, revision)
    s.repeatFilterPreparation = { source, request in try request.command(in: source) }
    s.repeatLastFilter(showDialog: true); s.filterDraft?.filter = .init(.boxBlur)
    s.commitFilter(); await s.geometryTask?.value
    XCTAssertNil(s.error); XCTAssertEqual(s.filterRecall.filter?.kind, .boxBlur)
  }

  @MainActor func testAuxiliaryComponentAndSmartFilterEditsRetainResolvedPayloads() async throws {
    var source = try fixture()
    source.alphaChannels = [.init(name: "Alpha", pixels: try Surface(width: 12, height: 10, fill: .init(0.3,0.3,0.3)))]
    let s = EditorStore(document: source); defer { stop(s) }
    var noise = RasterFilter(.addNoise); noise.seed = 98765; noise.amount = 17; noise.monochromatic = true
    try s.session.startActionRecording(name: "Auxiliary repeat")
    let alpha = try XCTUnwrap(source.alphaChannels?.first?.id)
    try s.selectAlphaChannel(alpha)
    s.filterRecall.remember(noise)
    let original = s.document
    var expected = original
    try Command.channel(.filter(.alpha(alpha), noise)).apply(to: &expected)
    s.repeatLastFilter(); await s.geometryTask?.value
    XCTAssertNil(s.error); XCTAssertEqual(s.document, expected)
    XCTAssertEqual(s.document.layers, original.layers)
    XCTAssertEqual(s.editingChannel, .alpha(alpha)); XCTAssertEqual(s.filterRecall.filter, noise)
    s.select(source.layers[0].id); s.componentTarget = .red
    let componentSource = s.document
    var componentExpected = componentSource
    try Command.modeComponents(.init(layerID: source.layers[0].id, components: [0], operation: .filter(noise))).apply(to: &componentExpected)
    s.repeatLastFilter(); await s.geometryTask?.value
    XCTAssertNil(s.error); XCTAssertEqual(s.document, componentExpected)
    s.componentTarget = .composite
    var smart = try fixture()
    try SmartObjectIO.convert(in: smart, selected: [smart.layers[0].id]).apply(to: &smart)
    s.session = EditorSession(document: smart)
    s.select(smart.layers[0].id)
    s.repeatLastFilter(); await s.geometryTask?.value
    XCTAssertNil(s.error); XCTAssertEqual(s.document.layers[0].smartFilters?.filters.count, 1)
    let id = smart.layers[0].id, filterID = try XCTUnwrap(s.document.layers[0].smartFilters?.filters.first?.id)
    s.beginSmartFilter(id, filterID: filterID)
    s.filterDraft?.filter = .init(.gaussianBlur); s.filterDraft?.filter.radius = 2.25
    s.commitFilter(); await s.geometryTask?.value
    XCTAssertEqual(s.filterRecall.filter?.radius, 2.25)
    let remembered = s.filterRecall.revision
    s.editSmartFilters(id) { $0.filters[0].enabled.toggle() }; await s.geometryTask?.value
    XCTAssertEqual(s.filterRecall.revision, remembered)
    s.editSmartFilters(id) { $0.filters[0].opacity = 0.5 }; await s.geometryTask?.value
    XCTAssertEqual(s.filterRecall.revision, remembered)
  }

  @MainActor func testHTTPRecallMatchesDesktopAndPortableRecordedFilterIsIndependent() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let source = try fixture(.f32), s = doc.store
      s.session = EditorSession(document: source)
      try service.share(doc)
      let applied = try await h.edit(service, doc, "filter.apply", ["layerID": source.layers[0].id.uuidString, "filter": ["kind": "addNoise", "amount": 12.5, "seed": 442, "monochromatic": true]])
      XCTAssertEqual(applied, 200)
      let captured = try XCTUnwrap(s.filterRecall.filter), before = s.document
      try s.session.startActionRecording(name: "Repeat noise")
      let repeated = try await h.edit(service, doc, FilterRecallAPI.name)
      XCTAssertEqual(repeated, 200)
      var expected = before
      try Command.applyFilter(before.layers[0].id, captured).apply(to: &expected)
      XCTAssertEqual(s.document, expected)
      XCTAssertEqual(try NativeArchive.encodeChunked(s.document), try NativeArchive.encodeChunked(expected))
      let action = try XCTUnwrap(s.session.actionRecording?.snapshot)
      var file = ActionLibraryFile(); file.actions = [action]
      let reopened = try ActionLibraryFile.decode(file.encoded())
      XCTAssertLessThanOrEqual(reopened.version, 47)
      s.filterRecall.remember(.init(.mosaic))
      var replay = before
      try reopened.actions[0].apply(to: &replay)
      XCTAssertEqual(replay, expected)
      await s.undo(); XCTAssertEqual(s.document, before)
      XCTAssertEqual(s.filterRecall.filter?.kind, .mosaic)
    }
  }

  @MainActor func testHTTPInvalidBusyStaleUnavailableAndRevokedRequestsAreAtomic() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let source = try fixture(), s = doc.store
      s.session = EditorSession(document: source); s.filterRecall = FilterRecall()
      try service.share(doc)
      let responseCode1 = try await h.edit(service, doc, FilterRecallAPI.name)
      XCTAssertEqual(responseCode1, 422)
      s.filterRecall.remember(.init(.gaussianBlur))
      for params: [String: Any] in [["unknown": 1], ["layerID": source.layers[0].id.uuidString], ["showDialog": true]] {
        let responseCode2 = try await h.edit(service, doc, FilterRecallAPI.name, params)
        XCTAssertEqual(responseCode2, 400)
      }
      let responseCode3 = try await h.edit(service, doc, FilterRecallAPI.name, revision: "stale")
      XCTAssertEqual(responseCode3, 409)
      s.beginFilter(.boxBlur)
      let responseCode4 = try await h.edit(service, doc, FilterRecallAPI.name)
      XCTAssertEqual(responseCode4, 409)
      s.cancelFilter()
      var locked = source; locked.layers[0].protection = .image
      s.session = EditorSession(document: locked)
      let responseCode5 = try await h.edit(service, doc, FilterRecallAPI.name)
      XCTAssertEqual(responseCode5, 422)
      XCTAssertEqual(s.document, locked)
      s.session = EditorSession(document: source)
      let gate = RecallGate(); defer { gate.release() }
      s.repeatFilterPreparation = { source, request in gate.wait(); try Task.checkCancellation(); return try request.command(in: source) }
      let revision = s.filterRecall.revision
      let request = Task { try await h.edit(service, doc, FilterRecallAPI.name) }
      let deadline = Date().addingTimeInterval(10)
      while !s.geometryBusy && Date() < deadline { await Task.yield() }
      XCTAssertTrue(s.geometryBusy)
      service.revoke(try XCTUnwrap(service.shares.first?.id)); gate.release()
      let responseCode6 = try await request.value
      XCTAssertEqual(responseCode6, 409)
      XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
      XCTAssertEqual(s.filterRecall.revision, revision)
    }
  }

  @MainActor func testDiscoveryStateAndSharedRevisionDescribeTheCurrentRecall() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let source = try fixture(), s = doc.store
      s.session = EditorSession(document: source)
      let other = CraftNSDocument(model: try fixture())
      service.controller.addDocument(other)
      defer { stop(other.store); service.controller.removeDocument(other) }
      try service.share(doc)
      let old = service.revision(s)
      var filter = RasterFilter(.boxBlur); filter.radius = 3
      try other.store.executeEditorCommand(.applyFilter(other.store.document.layers[0].id, filter))
      XCTAssertNotEqual(service.revision(s), old)
      let responseCode7 = try await h.edit(service, doc, FilterRecallAPI.name, revision: old)
      XCTAssertEqual(responseCode7, 409)
      let state = FilterRecallAPI.state(s)
      XCTAssertEqual(state["name"] as? String, filter.kind.title)
      XCTAssertEqual(state["canRepeat"] as? Bool, true)
      XCTAssertEqual(try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject: try XCTUnwrap(state["filter"]))), filter)
      let definition = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == FilterRecallAPI.name })
      XCTAssertTrue(definition.parameters.isEmpty)
      XCTAssertEqual(definition.schema["additionalProperties"] as? Bool, false)
      XCTAssertEqual(AutomationCommand.definitions.count, 255)
      XCTAssertEqual(ActionLibraryFile.maximumVersion, 51)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: FilterRecallAPI.capabilities))
      let share = try XCTUnwrap(service.shares.first?.id)
      let response = try await h.request(service, path: "/v1/documents/\(share)")
      XCTAssertEqual(response.0.statusCode, 200)
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      XCTAssertNotNil(body["filterRecall"])
    }
  }

  @MainActor func testNativeMenuDefaultShortcutDynamicTitleAvailabilityAndAllModifierCursors() throws {
    try PhotoshopMenuTests().withMenus { app, menu in
      let item = try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first { $0.identifier?.rawValue == "Filter > Last Filter" })
      XCTAssertEqual(item.action, #selector(AppDelegate.repeatLastFilter(_:)))
      XCTAssertEqual(item.keyEquivalent, "f")
      XCTAssertEqual(item.keyEquivalentModifierMask, [.control, .command])
      let doc = CraftNSDocument(model: try fixture()); app.controller.addDocument(doc)
      defer { stop(doc.store); app.controller.removeDocument(doc) }
      doc.store.filterRecall = FilterRecall()
      XCTAssertFalse(doc.store.canRepeatFilter)
      var filter = RasterFilter(.gaussianBlur); filter.radius = 2
      app.controller.filterRecall.remember(filter); doc.store.filterRecall = app.controller.filterRecall
      _ = app.validateMenuItem(item)
      XCTAssertEqual(item.title, filter.kind.title)
      XCTAssertTrue(doc.store.canRepeatFilter)
      doc.store.beginFilter(.boxBlur); XCTAssertFalse(doc.store.canRepeatFilter)
      doc.store.cancelFilter()
      let canvas = CraftCanvas(store: doc.store), flags: [NSEvent.ModifierFlags] = [.control,.command,.option,.shift]
      for bits in 0..<16 {
        let current = flags.enumerated().reduce(NSEvent.ModifierFlags()) { bits & (1 << $1.offset) != 0 ? $0.union($1.element) : $0 }
        canvas.updateCursorModifiers(current); let before = canvas.toolCursor
        doc.store.repeatLastFilter(showDialog: true)
        canvas.updateCursorModifiers(current); XCTAssertEqual(canvas.toolCursor, .unavailable)
        doc.store.cancelFilter()
        canvas.updateCursorModifiers(current); XCTAssertEqual(canvas.toolCursor, before)
      }
    }
  }
}
