import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ModeClipboardActionTests: XCTestCase {
  func source(_ color: Pixel = Pixel(0.2, 0.7, 0.4), width: Int = 4) throws -> CraftDocument {
    var document = try CraftDocument(width: width, height: 3)
    var surface = try Surface(width: width, height: 3, fill: color)
    surface.setPixel(x: 0, y: 0, .black); surface.setPixel(x: width - 1, y: 2, .white)
    document.layers[0].content = .raster(surface); return document
  }
  func indexedRequest(master: Bool = false) -> RestrictedModeRequest {
    var request = RestrictedModeRequest(.indexed)
    request.indexed.colors = 4; request.indexed.transparency = false; request.indexed.dither = .none
    if master { request.indexed.palette = .masterAdaptive }
    return request
  }
  func apply(_ action: RecordedAction, to source: CraftDocument, clipboard: ClipboardContent? = nil, masters: [CraftDocument] = []) throws -> CraftDocument {
    var result = source
    try RecordedActionRenderer.prepare(action, in: source, clipboard: clipboard, masters: masters).command.apply(to: &result)
    return result
  }
  func testRecordPortableModeSettingsVersion19AndAtomicFailure() throws {
    let first = try source(), second = try source(Pixel(0.9, 0.2, 0.1), width: 7)
    var session = EditorSession(document: first)
    try session.startActionRecording(name: "Indexed")
    let request = indexedRequest()
    try session.execute(request.command(in: session.document))
    let recorded = try XCTUnwrap(session.actionRecording?.snapshot)
    guard case .restrictedMode(let retained) = recorded.steps[0].operation else { return XCTFail("Missing semantic request") }
    XCTAssertEqual(retained, request)
    let bytes = try ActionLibraryFile(actions: [recorded]).encoded()
    let decoded = try ActionLibraryFile.decode(bytes); XCTAssertEqual(decoded.version, 19)
    var downgraded = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any]); downgraded["version"] = 18
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject: downgraded)))
    var expected = second; try request.command(in: second).apply(to: &expected)
    XCTAssertEqual(try apply(decoded.actions[0], to: second), expected)
    XCTAssertNotEqual(expected.restrictedMode, session.document.restrictedMode)
    var failed = recorded; failed.steps.append(.init(name: "Failure", operation: .unsupported("Intentional")))
    XCTAssertThrowsError(try RecordedActionRenderer.prepare(failed, in: second))
    XCTAssertEqual(second.width, 7)
  }
  func testComponentMergeHDRConsentBitmapAndColorTableSettings() throws {
    var rich = try source(); rich.layers.append(Layer(name: "Overlay", content: .fill(Pixel(0.8, 0.1, 0.2))))
    let gray = DocumentModeRequest(.init(mode: .grayscale, depth: .u8), mergeVisible: true)
    var bitmap = RestrictedModeRequest(.bitmap); bitmap.bitmap.outputResolution = rich.pixelsPerInch * 2
    let action = RecordedAction(name: "Print", steps: [.init(name: "Gray", operation: .documentMode(gray)), .init(name: "Bitmap", operation: .restrictedMode(bitmap))])
    let converted = try apply(action, to: rich)
    XCTAssertEqual(converted.colorMode, .bitmap); XCTAssertEqual(converted.width, rich.width * 2)
    var direct = rich; try DocumentModeInput.command(gray, in: direct).apply(to: &direct); try bitmap.command(in: direct).apply(to: &direct)
    XCTAssertEqual(converted, direct)
    var denied = action; denied.steps[0].operation = .documentMode(.init(gray.conversion))
    XCTAssertThrowsError(try apply(denied, to: rich))
    let hdr = try source().convertingMode(.init(mode: .rgb, depth: .f32))
    XCTAssertThrowsError(try apply(.init(name: "No consent", steps: [.init(name: "Reduce", operation: .documentMode(.init(.init(mode: .rgb, depth: .u8))))]), to: hdr))
    let allowed = RecordedAction(name: "Reduce", steps: [.init(name: "Reduce", operation: .documentMode(.init(.init(mode: .rgb, depth: .u8), clipHDR: true)))])
    XCTAssertEqual(try apply(allowed, to: hdr).depth, .u8)
    let indexed = try RestrictedModeWorkflowTests().indexed()
    var table = RestrictedModeRequest(.colorTable); table.colors = [.init(1, 2, 3), .init(20, 200, 40), .init(255, 255, 255)]; table.transparentIndex = 2
    let recolored = try apply(.init(name: "Table", steps: [.init(name: "Table", operation: .restrictedMode(table))]), to: indexed)
    guard case .indexed(let before) = indexed.restrictedMode, case .indexed(let after) = recolored.restrictedMode else { return XCTFail() }
    XCTAssertEqual(after.indices, before.indices); XCTAssertEqual(after.palette, table.colors)
  }
  func testMasterAndPreviousUsePaletteSettingsWithoutRetainingSourceImages() throws {
    let a = try source(), b = try source(Pixel(0.95, 0.1, 0.8), width: 6), request = indexedRequest(master: true)
    let action = RecordedAction(name: "Master", steps: [.init(name: "Master", operation: .restrictedMode(request))])
    var direct = a; try request.command(in: a, masters: [b]).apply(to: &direct)
    XCTAssertEqual(try apply(action, to: a, masters: [a, b]), direct)
    XCTAssertTrue(action.usesMasterPalette)
    var previous = indexedRequest(); previous.indexed.palette = .previous
    XCTAssertThrowsError(try previous.validate())
    previous.previousPalette = [.init(0, 0, 0), .init(255, 0, 0), .init(255, 255, 255)]
    let previousAction = RecordedAction(name: "Previous", steps: [.init(name: "Previous", operation: .restrictedMode(previous))])
    guard case .indexed(let result) = try apply(previousAction, to: b).restrictedMode else { return XCTFail() }
    XCTAssertEqual(result.palette, previous.previousPalette)
    XCTAssertLessThan(try ActionLibraryFile(actions: [action]).encoded().count, 4096)
    var returned = action; returned.steps.append(.init(name: "RGB", operation: .documentMode(.init(.init(mode: .rgb, depth: .u8)))))
    let replay = try RecordedActionRenderer.prepare(returned, in: a, masters: [b])
    guard case .indexed(let indexed) = direct.restrictedMode else { return XCTFail() }
    XCTAssertEqual(replay.lastIndexedPalette, indexed.palette)
    XCTAssertEqual(try apply(returned, to: a, masters: [b]).colorMode, .rgb)
  }
  @MainActor func testNativeModeControlsRecordReplayAndUndo() async throws {
    let original = try source(), store = EditorStore(document: original, actions: ActionLibrary())
    defer { store.cancelDocumentMode(); store.cancelRestrictedMode(); store.renderTask?.cancel() }
    try store.startRecordingAction(name: "Mode workflow", set: "Tests")
    store.beginDocumentMode(.grayscale, depth: .u8)
    let gray = try XCTUnwrap(store.documentModeWorkspace); await gray.task?.value
    store.commitDocumentMode(); await gray.commitTask?.value; XCTAssertNil(gray.error)
    store.beginRestrictedMode(.bitmap)
    let bitmap = try XCTUnwrap(store.restrictedModeWorkspace); await bitmap.task?.value
    store.commitRestrictedMode(); await bitmap.commitTask?.value; XCTAssertNil(bitmap.error)
    let action = try store.stopRecordingAction(); XCTAssertEqual(action.steps.count, 2)
    XCTAssertTrue(action.steps.allSatisfy { $0.operation.unsupportedReason == nil })
    let replaySource = try source(Pixel(0.8, 0.2, 0.6), width: 5), replay = EditorStore(document: replaySource)
    defer { replay.renderTask?.cancel() }
    replay.playAction(action); await replay.geometryTask?.value
    XCTAssertNil(replay.error); XCTAssertEqual(replay.document, try apply(action, to: replaySource)); XCTAssertEqual(replay.session.undoStack.count, 1)
    await replay.undo(); XCTAssertEqual(replay.document, replaySource)
    await replay.redo(); XCTAssertEqual(replay.document.colorMode, .bitmap)
  }
  @MainActor func testCopyRecordingContainsCommandsAndPlaybackUsesCurrentPixels() async throws {
    let clipboard = MemoryClipboard(), original = try source(), store = EditorStore(document: original, clipboard: clipboard, actions: ActionLibrary())
    defer { store.renderTask?.cancel() }
    try store.startRecordingAction(name: "Copy", set: "Tests")
    store.copyImage(merged: true); await store.geometryTask?.value
    let action = try store.stopRecordingAction(); XCTAssertEqual(action.steps.count, 1)
    guard case .clipboardCopy(_, let merged) = action.steps[0].operation else { return XCTFail() }; XCTAssertTrue(merged)
    XCTAssertTrue(store.session.undoStack.isEmpty); XCTAssertEqual(store.document, original)
    XCTAssertLessThan(try ActionLibraryFile(actions: [action]).encoded().count, 1200)
    let second = try source(Pixel(0.7, 0.1, 0.9), width: 7), replay = EditorStore(document: second, clipboard: clipboard)
    defer { replay.renderTask?.cancel() }
    replay.playAction(action); await replay.geometryTask?.value
    XCTAssertNil(replay.error); XCTAssertTrue(replay.session.undoStack.isEmpty)
    let copied = try ClipboardContent.decode(XCTUnwrap(clipboard.value).native)
    let preview = try ClipboardRenderer.preview(copied), expected = try Renderer.composite(second).converted(to: second.depth)
    XCTAssertEqual(preview.width, expected.width); XCTAssertEqual(preview.height, expected.height)
    for y in 0..<expected.height { for x in 0..<expected.width { XCTAssertEqual(preview.pixel(x: x, y: y), expected.pixel(x: x, y: y)) } }
  }
  @MainActor func testClipboardPlaybackFailureCancellationStaleAndWriteRejectionAreAtomic() async throws {
    let original = try RestrictedModeWorkflowTests().indexed(), clipboard = MemoryClipboard()
    let store = EditorStore(document: original, clipboard: clipboard); defer { store.renderTask?.cancel() }
    let cut = RecordedAction(name: "Cut", steps: [.init(name: "Cut", operation: .clipboardCut([.active], background: .white))])
    var lateFailure = cut; lateFailure.steps.append(.init(name: "Fail", operation: .unsupported("Fail")))
    store.playAction(lateFailure); await store.geometryTask?.value
    XCTAssertNotNil(store.error); XCTAssertEqual(store.document, original); XCTAssertNil(clipboard.value)
    clipboard.rejectWrites = true; store.error = nil; store.playAction(cut); await store.geometryTask?.value
    XCTAssertNotNil(store.error); XCTAssertEqual(store.document, original); XCTAssertTrue(store.session.undoStack.isEmpty)
    clipboard.rejectWrites = false; store.error = nil; store.playAction(cut); clipboard.changeCount += 1; await store.geometryTask?.value
    XCTAssertNotNil(store.error); XCTAssertEqual(store.document, original); XCTAssertNil(clipboard.value)
    store.error = nil; store.playAction(cut); store.geometryTask?.cancel(); await store.geometryTask?.value
    XCTAssertEqual(store.document, original); XCTAssertNil(clipboard.value)
    store.playAction(cut); await store.geometryTask?.value
    XCTAssertNotNil(clipboard.value); XCTAssertNotEqual(store.document, original); XCTAssertEqual(store.session.undoStack.count, 1)
    await store.undo(); XCTAssertEqual(store.document, original); XCTAssertNotNil(clipboard.value)
  }
  func testPrivateClipboardPasteRequiresInputAndKeepsDuplicateIndices() throws {
    let original = try RestrictedModeWorkflowTests().indexed()
    let content = try ClipboardRenderer.copy(original, layerIDs: [original.activeLayerID!], merged: false)
    let paste = RecordedAction(name: "Paste", steps: [.init(name: "Paste", operation: .clipboardPaste(.inPlace, center: nil))])
    XCTAssertTrue(paste.requiresInitialClipboard); XCTAssertFalse(paste.writesClipboard)
    XCTAssertThrowsError(try apply(paste, to: original))
    var cleared = original; try Command.cut([original.activeLayerID!], background: .white).apply(to: &cleared)
    XCTAssertEqual(try apply(paste, to: cleared, clipboard: content).restrictedMode, original.restrictedMode)
    let action = RecordedAction(name: "Restore", steps: [.init(name: "Copy", operation: .clipboardCopy([.active], merged: false)), .init(name: "Cut", operation: .clipboardCut([.active], background: .white)), paste.steps[0]])
    XCTAssertFalse(action.requiresInitialClipboard); XCTAssertTrue(action.writesClipboard)
    let output = try RecordedActionRenderer.prepare(action, in: original)
    XCTAssertNotNil(output.clipboard); XCTAssertEqual(try apply(action, to: original).restrictedMode, original.restrictedMode)
  }
  @MainActor func testAPIModeAndCopyRecordingReplayPayloadAndGuards() async throws {
    let helper = AutomationTests(), library = ActionLibrary()
    try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: try source())
      try service.share(document)
      let share = try XCTUnwrap(service.shares.first), before = document.store.document
      let clipboardRevision = document.store.clipboard.changeCount
      let start = try await helper.edit(service, document, "actions.manage", ["operation": "record", "name": "Recorded modes"]); XCTAssertEqual(start, 200)
      let mode = try await helper.edit(service, document, "document.convertIndexed", ["settings": BrushAPI.json(indexedRequest().indexed)]); XCTAssertEqual(mode, 200)
      let copied = try await helper.edit(service, document, "clipboard.copy"); XCTAssertEqual(copied, 200)
      let stop = try await helper.edit(service, document, "actions.manage", ["operation": "stop"]); XCTAssertEqual(stop, 200)
      let action = try XCTUnwrap(library.file.actions.first); XCTAssertEqual(action.steps.count, 2); XCTAssertEqual(library.file.version, 19)
      let expected = document.store.document
      let undo = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo, 200); XCTAssertEqual(document.store.document, before)
      let response = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: ["command": "actions.play", "revision": service.revision(document.store), "parameters": ["actionID": action.id.uuidString]])
      XCTAssertEqual(response.0.statusCode, 200, String(decoding: response.1, as: UTF8.self))
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let bytes = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(body["clipboardPayloadBase64"] as? String)))
      XCTAssertEqual(try ClipboardContent.decode(bytes).restrictedSamples, expected.restrictedMode)
      XCTAssertEqual(document.store.document, expected); XCTAssertEqual(document.store.clipboard.changeCount, clipboardRevision)
      let paste = RecordedAction(name: "Paste", steps: [.init(name: "Paste", operation: .clipboardPaste(.inPlace, center: nil))]); try library.save(paste)
      let missing = try await helper.edit(service, document, "actions.play", ["actionID": paste.id.uuidString]); XCTAssertEqual(missing, 422)
      let invalid = try await helper.edit(service, document, "actions.play", ["actionID": paste.id.uuidString, "clipboardPayloadBase64": "invalid"]); XCTAssertEqual(invalid, 400)
      let valid = try await helper.edit(service, document, "actions.play", ["actionID": paste.id.uuidString, "clipboardPayloadBase64": bytes.base64EncodedString()]); XCTAssertEqual(valid, 200)
      XCTAssertEqual(document.store.document.restrictedMode, expected.restrictedMode)
      let state = document.store.actionState; XCTAssertTrue((state["supportedVersions"] as? [Int])?.contains(19) == true)
      let playback = try XCTUnwrap(state["playback"] as? [String: Any]); let resultSchema = try XCTUnwrap(playback["resultSchema"] as? [String: Any])
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: resultSchema))
      for name in ["actions.play", "actions.batch"] {
        let definition = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == name }); XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: definition.schema))
      }
    }
  }
  @MainActor func testAPIMasterSourcesReplayAndRejectConcurrentChanges() async throws {
    let helper = AutomationTests(), library = ActionLibrary(), request = indexedRequest(master: true)
    let action = RecordedAction(name: "Master", steps: [.init(name: "Master", operation: .restrictedMode(request))]); try library.save(action)
    try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: try source())
      let master = CraftNSDocument(model: try source(Pixel(0.9, 0.2, 0.8), width: 7))
      defer { master.store.renderTask?.cancel(); service.controller.removeDocument(master) }
      service.controller.addDocument(master); try service.share(document); try service.share(master)
      let share = try XCTUnwrap(service.shares.first { $0.document === document }), other = try XCTUnwrap(service.shares.first { $0.document === master })
      let original = document.store.document
      let parameters: [String: Any] = ["actionID": action.id.uuidString, "sources": [["id": other.id.uuidString, "revision": service.revision(master.store)]]]
      let success = try await helper.edit(service, document, "actions.play", parameters); XCTAssertEqual(success, 200)
      XCTAssertEqual(document.store.document, try apply(action, to: original, masters: [master.store.document]))
      let undo = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo, 200)
      let command = try AutomationCommand(data: JSONSerialization.data(withJSONObject: ["command": "actions.play", "revision": service.revision(document.store), "parameters": parameters]))
      let task = Task { try await service.executeRecordedAction(command, document: document, share: share) }
      for _ in 0..<100 where !document.store.geometryBusy { await Task.yield() }
      XCTAssertTrue(document.store.geometryBusy)
      try master.store.session.execute(.renameLayer(master.store.document.activeLayerID!, "Changed"))
      do { _ = try await task.value; XCTFail("Changed master accepted") }
      catch let error as AutomationFailure { XCTAssertEqual(error.status, 409); XCTAssertTrue(error.message.contains("master source")) }
      catch { XCTFail("Unexpected error: \(error)") }
      XCTAssertEqual(document.store.document, original)
      master.store.render()
      let stale = try await helper.edit(service, document, "actions.play", parameters); XCTAssertEqual(stale, 409)
    }
  }
  @MainActor func testBatchFileMasterPalettesAndIndependentClipboard() async throws {
    let root = try ActionBatchTests().folder(); defer { try? FileManager.default.removeItem(at: root) }
    let a = try source(), b = try source(Pixel(0.8, 0.1, 0.9), width: 6)
    var request = indexedRequest(master: true); request.indexed.colors = 2
    let action = RecordedAction(name: "Master", steps: [.init(name: "Master", operation: .restrictedMode(request))])
    let urls = [root.appendingPathComponent("a.png"), root.appendingPathComponent("b.png")]
    for (document, url) in zip([a, b], urls) { try DocumentIO.encode(document, format: .png).write(to: url) }
    let inputs = try urls.map(DocumentIO.read)
    var changedFile = false
    let results = try await ActionBatch.run(sources: urls.map { .init(url: $0) }, action: action, destination: root, format: .native, validatePublication: {
      if !changedFile { try DocumentIO.encode(source(.black), format: .png).write(to: urls[0]); changedFile = true }
    })
    XCTAssertTrue(changedFile)
    XCTAssertEqual(results.filter { $0.output != nil }.count, 2)
    for (index, result) in results.enumerated() {
      let output = try DocumentIO.read(root.appendingPathComponent(XCTUnwrap(result.output)))
      let expected = try apply(action, to: inputs[index], masters: [inputs[1 - index]])
      XCTAssertEqual(output.restrictedMode, expected.restrictedMode)
    }
    let original = try RestrictedModeWorkflowTests().indexed()
    let clipboard = try ClipboardRenderer.copy(original, layerIDs: [original.activeLayerID!], merged: false)
    var empty = original; try Command.cut([empty.activeLayerID!], background: .white).apply(to: &empty)
    let paste = RecordedAction(name: "Paste", steps: [.init(name: "Paste", operation: .clipboardPaste(.inPlace, center: nil))])
    let copies = try await ActionBatch.run(sources: [.init(document: empty), .init(document: empty)], action: paste, destination: root, format: .native, suffix: "-paste", clipboard: clipboard)
    for result in copies {
      let output = try DocumentIO.read(root.appendingPathComponent(XCTUnwrap(result.output)))
      XCTAssertEqual(output.restrictedMode, original.restrictedMode)
    }
  }
  func testPlaybackChecksIntermediateLimitsBeforeFinalShrink() throws {
    let document = try source()
    let action = RecordedAction(name: "Temporary expansion", steps: [
      .init(name: "Expand", operation: .imageSize(5, 3, 72, .nearest)),
      .init(name: "Shrink", operation: .imageSize(4, 3, 72, .nearest))])
    let limits = ActionPlaybackLimits(maximumPixels: 12, maximumLayers: 4, maximumBytes: 16 * 1024 * 1024)
    XCTAssertThrowsError(try RecordedActionRenderer.prepare(action, in: document, validate: limits.validate))
    XCTAssertEqual(try apply(action, to: document).width, 4)
  }
  func testNoOpPasteStillRecordsAndIntermediateClipboardIsValidated() throws {
    let original = try RestrictedModeWorkflowTests().indexed()
    let content = try ClipboardRenderer.copy(original, layerIDs: [original.activeLayerID!], merged: false)
    var session = EditorSession(document: original); try session.startActionRecording(name: "Paste")
    try session.execute(ClipboardRenderer.pasteCommand(content, into: original, placement: .inPlace))
    XCTAssertEqual(session.document, original); XCTAssertTrue(session.undoStack.isEmpty)
    let action = try XCTUnwrap(session.actionRecording?.snapshot); XCTAssertEqual(action.steps.count, 1)
    guard case .clipboardPaste = action.steps[0].operation else { return XCTFail("No-op paste was omitted") }
    let copy = RecordedAction(name: "Copy", steps: [.init(name: "Copy", operation: .clipboardCopy([.active], merged: false))])
    XCTAssertThrowsError(try RecordedActionRenderer.prepare(copy, in: original, validateClipboard: { _ in throw CraftError.invalid("Clipboard budget") }))
    XCTAssertThrowsError(try RecordedActionRenderer.prepare(action, in: original, clipboard: content, validateClipboard: { _ in throw CraftError.invalid("Clipboard budget") }))
  }
}
