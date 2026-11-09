import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

private final class MeshRecallGate: @unchecked Sendable {
  private let condition = NSCondition()
  private var released = false
  func wait() { condition.lock(); while !released { condition.wait() }; condition.unlock() }
  func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}

final class LiquifyMeshRecallTests: XCTestCase {
  var program: LiquifySettings { LiquifyWorkflowTests().settings }
  func filter(_ settings: LiquifySettings) -> RasterFilter {
    var result = RasterFilter(.liquify); result.liquify = settings; return result
  }
  func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("PhotatoMeshTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  @MainActor func drain(_ model: LiquifyWorkspace) async {
    while model.rendering { await model.task?.value }
  }
  @MainActor func stop(_ store: EditorStore) { store.renderTask?.cancel(); store.geometryTask?.cancel() }

  @MainActor func testCommittedMeshSurvivesOtherFiltersUndoAndRestart() async throws {
    let directory = try folder(), url = directory.appendingPathComponent("last.photatoliquify")
    let library = LiquifyMeshLibrary(persistenceURL: url)
    let original = try LiquifyWorkflowTests().fixture(), store = EditorStore(document: original)
    store.filterRecall = FilterRecall(liquifyMeshes: library)
    defer { stop(store); library.flush(); try? FileManager.default.removeItem(at: directory) }
    store.performGeometry(.applyFilter(original.layers[0].id, filter(program)))
    await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(library.settings, program)
    await store.undo(); XCTAssertEqual(store.document, original)
    XCTAssertEqual(library.settings, program)
    store.performGeometry(.applyFilter(original.layers[0].id, .init(.boxBlur)))
    await store.geometryTask?.value
    XCTAssertEqual(store.filterRecall.filter?.kind, .boxBlur)
    XCTAssertEqual(library.settings, program)
    library.flush()
    let reopened = LiquifyMeshLibrary(persistenceURL: url)
    XCTAssertNil(reopened.error); XCTAssertEqual(reopened.settings, program)
    XCTAssertEqual(try LiquifyMeshFile.decode(Data(contentsOf: url)), program)
  }

  @MainActor func testUnreadableAndOversizedSavedFilesArePreserved() throws {
    let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
    for bytes in [Data("not a mesh".utf8), Data(repeating: 32, count: LiquifyMeshFile.maximumBytes + 1)] {
      let url = directory.appendingPathComponent(UUID().uuidString)
      try bytes.write(to: url)
      let library = LiquifyMeshLibrary(persistenceURL: url)
      XCTAssertNil(library.settings); XCTAssertNotNil(library.error)
      library.remember(program); library.flush()
      XCTAssertEqual(library.settings, program); XCTAssertNotNil(library.error)
      XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
  }

  @MainActor func testWriteFailureKeepsUsableMeshAndInvalidInputKeepsPreviousValue() async throws {
    let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
    let obstruction = directory.appendingPathComponent("file-not-directory")
    try Data([1, 2, 3]).write(to: obstruction)
    let library = LiquifyMeshLibrary(persistenceURL: obstruction.appendingPathComponent("mesh"))
    library.remember(program); library.flush(); await Task.yield()
    XCTAssertEqual(library.settings, program); XCTAssertNotNil(library.error)
    XCTAssertEqual(try Data(contentsOf: obstruction), Data([1, 2, 3]))
    var invalid = program; invalid.strokes[0].size = .nan
    library.remember(invalid); library.flush()
    XCTAssertEqual(library.settings, program); XCTAssertNotNil(library.error)
    try FileManager.default.removeItem(at: obstruction)
    library.remember(program); library.flush(); await Task.yield()
    XCTAssertNil(library.error)
    XCTAssertEqual(try LiquifyMeshFile.decode(Data(contentsOf: obstruction.appendingPathComponent("mesh"))), program)
  }

  @MainActor func testQueuedWritesKeepNewestMeshAndNormalTerminationDrainsThem() throws {
    let directory = try folder(), url = directory.appendingPathComponent("last.photatoliquify")
    let library = LiquifyMeshLibrary(persistenceURL: url)
    let app = AppDelegate(workspaces: WorkspaceLibrary(), liquifyMeshes: library)
    defer {
      library.flush(); app.controller.filterRecall.liquifyMeshes = LiquifyMeshLibrary()
      try? FileManager.default.removeItem(at: directory)
    }
    var last = program
    for i in 0..<12 {
      last.strokes[0].pressure = Double(i + 1)
      app.controller.filterRecall.remember(filter(last))
    }
    app.applicationWillTerminate(.init(name: NSApplication.willTerminateNotification))
    XCTAssertEqual(try LiquifyMeshFile.decode(Data(contentsOf: url)), last)
    XCTAssertEqual(LiquifyMeshLibrary(persistenceURL: url).settings, last)
  }

  @MainActor func testNativeLoadUsesLocalHistoryCancelAndOneDocumentTransaction() async throws {
    for depth in PixelDepth.allCases {
      let original = try LiquifyWorkflowTests().fixture(depth), store = EditorStore(document: original)
      let library = LiquifyMeshLibrary(initialSettings: program), model = LiquifyWorkspace()
      store.filterRecall = FilterRecall(liquifyMeshes: library)
      defer { model.close(); stop(store) }
      store.beginFilter(.liquify)
      model.meshLibrary = library
      model.onChange = { store.filterDraft?.filter.liquify = $0 }
      await model.prepare(document: original, draft: try XCTUnwrap(store.filterDraft)); await drain(model)
      let empty = model.settings
      XCTAssertTrue(model.canLoadLastMesh)
      model.loadLastMesh(); await drain(model)
      XCTAssertEqual(model.settings, program); XCTAssertEqual(store.document, original)
      XCTAssertEqual(model.undoStates.count, 1)
      model.undo(); await drain(model); XCTAssertEqual(model.settings, empty)
      model.redo(); await drain(model); XCTAssertEqual(model.settings, program)
      store.cancelFilter(); XCTAssertEqual(store.document, original)
      XCTAssertTrue(store.session.undoStack.isEmpty); XCTAssertEqual(library.settings, program)
      store.beginFilter(.liquify); store.filterDraft?.filter.liquify = model.settings
      var expected = original; try Command.applyFilter(original.layers[0].id, filter(program)).apply(to: &expected)
      store.commitFilter(); await store.geometryTask?.value
      XCTAssertNil(store.error); XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo(); XCTAssertEqual(store.document, original)
      await store.redo(); XCTAssertEqual(store.document, expected)
    }
  }

  @MainActor func testControllerSharingAndClosingSourceKeepIndependentSnapshots() throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let first = CraftNSDocument(model: try LiquifyWorkflowTests().fixture())
    let second = CraftNSDocument(model: try LiquifyWorkflowTests().fixture(.u16))
    let library = LiquifyMeshLibrary()
    controller.filterRecall.liquifyMeshes = library
    controller.addDocument(first); controller.addDocument(second)
    defer {
      stop(first.store); stop(second.store)
      if controller.documents.contains(where: { $0 === first }) { controller.removeDocument(first) }
      controller.removeDocument(second)
      controller.filterRecall.liquifyMeshes = LiquifyMeshLibrary()
    }
    try first.store.executeEditorCommand(.applyFilter(first.store.document.layers[0].id, filter(program)))
    XCTAssertTrue(second.store.filterRecall.liquifyMeshes === library)
    controller.removeDocument(first)
    XCTAssertFalse(first.store.filterRecall.liquifyMeshes === library)
    XCTAssertEqual(first.store.filterRecall.liquifyMeshes.settings, program)
    var changed = program; changed.strokes[0].pressure = 14
    try first.store.executeEditorCommand(.applyFilter(first.store.document.layers[0].id, filter(changed)))
    XCTAssertEqual(second.store.filterRecall.liquifyMeshes.settings, program)
    XCTAssertNil(EditorStore(document: second.store.document).filterRecall.liquifyMeshes.settings)
  }

  @MainActor func testHTTPStateReplayUndoAndRejectedRequestsMatchNative() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let original = try LiquifyWorkflowTests().fixture(), store = doc.store
      store.session = EditorSession(document: original)
      store.filterRecall = FilterRecall()
      try service.share(doc)
      XCTAssertTrue(FilterRecallAPI.state(store)["lastLiquifyMesh"] is NSNull)
      let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(program))
      let parameters: [String: Any] = ["layerID": original.layers[0].id.uuidString, "filter": ["kind": "liquify", "liquify": payload]]
      let result = try await h.edit(service, doc, "filter.apply", parameters)
      XCTAssertEqual(result, 200)
      let shareID = try XCTUnwrap(service.shares.first?.id)
      let response = try await h.request(service, path: "/v1/documents/\(shareID)")
      XCTAssertEqual(response.0.statusCode, 200)
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let recall = try XCTUnwrap(body["filterRecall"] as? [String: Any])
      let saved = try XCTUnwrap(recall["lastLiquifyMesh"])
      XCTAssertTrue(recall["lastLiquifyMeshError"] is NSNull)
      XCTAssertEqual(try LiquifySettings.decodeJSON(JSONSerialization.data(withJSONObject: saved)), program)
      let undo = try await h.edit(service, doc, "history.undo"); XCTAssertEqual(undo, 200)
      XCTAssertEqual(store.document, original)
      let replay = try await h.edit(service, doc, "filter.apply", ["layerID": original.layers[0].id.uuidString, "filter": ["kind": "liquify", "liquify": saved]])
      XCTAssertEqual(replay, 200)
      var expected = original; try Command.applyFilter(original.layers[0].id, filter(program)).apply(to: &expected)
      XCTAssertEqual(store.document, expected)
      let before = store.document, revision = store.filterRecall.liquifyMeshes.revision
      let invalid = try await h.edit(service, doc, "filter.apply", ["layerID": original.layers[0].id.uuidString, "filter": ["kind": "liquify", "liquify": ["strokes": [["size": true]]]]])
      XCTAssertEqual(invalid, 400)
      let stale = try await h.edit(service, doc, "filter.apply", parameters, revision: "stale")
      XCTAssertEqual(stale, 409)
      store.beginFilter(.liquify)
      let busy = try await h.edit(service, doc, "filter.apply", parameters); XCTAssertEqual(busy, 409)
      store.cancelFilter()
      XCTAssertEqual(store.document, before); XCTAssertEqual(store.filterRecall.liquifyMeshes.revision, revision)
      XCTAssertEqual(AutomationCommand.definitions.count, 267)
      XCTAssertEqual(ActionLibraryFile.maximumVersion, 61)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: FilterRecallAPI.capabilities))
      XCTAssertTrue((FilterRecallAPI.stateSchema["required"] as? [String] ?? []).contains("lastLiquifyMesh"))
    }
  }

  @MainActor func testCancelledAndRevokedPreparationDoNotReplaceLastMesh() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let original = try LiquifyWorkflowTests().fixture(), store = doc.store
      store.session = EditorSession(document: original); store.filterRecall = FilterRecall(filter(program))
      try service.share(doc)
      let before = store.filterRecall.liquifyMeshes.settings, revision = store.filterRecall.liquifyMeshes.revision
      let gate = MeshRecallGate(); defer { gate.release() }
      store.repeatFilterPreparation = { source, request in gate.wait(); try Task.checkCancellation(); return try request.command(in: source) }
      let request = Task { try await h.edit(service, doc, FilterRecallAPI.name) }
      let deadline = Date().addingTimeInterval(10)
      while !store.geometryBusy && Date() < deadline { await Task.yield() }
      XCTAssertTrue(store.geometryBusy)
      service.revoke(try XCTUnwrap(service.shares.first?.id)); gate.release()
      let result = try await request.value; XCTAssertEqual(result, 409)
      XCTAssertEqual(store.document, original); XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertEqual(store.filterRecall.liquifyMeshes.settings, before)
      XCTAssertEqual(store.filterRecall.liquifyMeshes.revision, revision)
      let second = MeshRecallGate(); defer { second.release() }
      store.repeatFilterPreparation = { source, request in second.wait(); try Task.checkCancellation(); return try request.command(in: source) }
      store.repeatLastFilter(); store.geometryTask?.cancel(); second.release(); await store.geometryTask?.value
      XCTAssertEqual(store.document, original); XCTAssertEqual(store.filterRecall.liquifyMeshes.revision, revision)
    }
  }

  @MainActor func testSmartFilterAppendAndReeditUpdateRecallWithoutReplacingOriginalPixels() async throws {
    var original = try LiquifyWorkflowTests().fixture()
    try SmartObjectIO.convert(in: original, selected: [original.layers[0].id]).apply(to: &original)
    let id = original.layers[0].id
    let pixels = original.layers[0].content, store = EditorStore(document: original)
    defer { stop(store) }
    store.performGeometry(.applyFilter(id, filter(program))); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.document.layers[0].content, pixels)
    XCTAssertEqual(store.filterRecall.liquifyMeshes.settings, program)
    var stack = try XCTUnwrap(store.document.layers[0].smartFilters)
    var changed = program; changed.strokes[0].pressure = 28
    stack.filters[0].filter.liquify = changed
    store.performGeometry(.smartFilters(id, stack)); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.filterRecall.liquifyMeshes.settings, changed)
    await store.undo(); XCTAssertEqual(store.filterRecall.liquifyMeshes.settings, changed)
    XCTAssertEqual(store.document.layers[0].content, pixels)
  }

  @MainActor func testImplicitCoordinatesFreezeFacesAndStoredValueRemainIndependent() async throws {
    var settings = program
    settings.width = 0; settings.height = 0
    settings.strokes.insert(.init(tool: .freezeAll), at: 0)
    let geometry = LiquifyFaceGeometry(bounds: [0.1,0.1,0.8,0.8], leftEye: [0.2,0.3,0.15,0.08], rightEye: [0.6,0.3,0.15,0.08], nose: [0.4,0.4,0.15,0.2], mouth: [0.3,0.65,0.4,0.12])
    settings.faces = [.init(geometry: geometry)]; settings.faces[0][.smile] = 23
    let library = LiquifyMeshLibrary(initialSettings: settings), model = LiquifyWorkspace()
    defer { model.close() }
    let document = try LiquifyWorkflowTests().fixture()
    await model.prepare(document: document, draft: .init(id: document.layers[0].id, filter: filter(.init())))
    model.meshLibrary = library; model.loadLastMesh(); await drain(model)
    var resolved = settings; resolved.width = 64; resolved.height = 48
    XCTAssertEqual(model.settings, resolved)
    XCTAssertEqual(try XCTUnwrap(model.field).frozen(x: 6, y: 6), 1)
    XCTAssertEqual(try XCTUnwrap(model.field).maximumDisplacement, 0)
    model.setFace(.smile, value: 70)
    XCTAssertEqual(library.settings, settings)
    XCTAssertEqual(try LiquifyMeshFile.decode(LiquifyMeshFile.encode(try XCTUnwrap(library.settings))), settings)
  }

  @MainActor func testCanvasPlainMShortcutAllModifierCombinationsAndOffscreenControls() async throws {
    _ = NSApplication.shared
    let document = try LiquifyWorkflowTests().fixture(), store = EditorStore(document: document), model = LiquifyWorkspace()
    defer { model.close(); stop(store) }
    store.beginFilter(.liquify)
    await model.prepare(document: document, draft: try XCTUnwrap(store.filterDraft)); await drain(model)
    model.meshLibrary = LiquifyMeshLibrary(initialSettings: program)
    let canvas = LiquifyCanvasView(frame: .init(x: 0, y: 0, width: 400, height: 300)); canvas.model = model
    let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = canvas; window.makeFirstResponder(canvas)
    defer { window.close() }
    let flags: [NSEvent.ModifierFlags] = [.control, .command, .option, .shift]
    for bits in 0..<16 {
      model.restore(); await drain(model)
      let empty = model.settings
      let current = flags.enumerated().reduce(NSEvent.ModifierFlags()) { bits & (1 << $1.offset) == 0 ? $0 : $0.union($1.element) }
      let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: current, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "m", charactersIgnoringModifiers: "m", isARepeat: false, keyCode: 46))
      canvas.keyDown(with: event); await drain(model)
      XCTAssertEqual(model.settings, bits == 0 ? program : empty, "modifiers \(bits)")
      XCTAssertEqual(model.tool, .forwardWarp)
    }
    store.filterRecall.liquifyMeshes = try XCTUnwrap(model.meshLibrary)
    let host = NSHostingView(rootView: LiquifySheet(store: store, workspace: model))
    host.frame = .init(origin: .zero, size: host.fittingSize); host.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(host.fittingSize.width, 800)
    if let capture = ProcessInfo.processInfo.environment["PHOTATO_LIQUIFY_CAPTURE450"] {
      for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        host.appearance = NSAppearance(named: appearance)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: capture).appendingPathComponent("last-mesh-\(name).png"))
      }
    }
  }
}
