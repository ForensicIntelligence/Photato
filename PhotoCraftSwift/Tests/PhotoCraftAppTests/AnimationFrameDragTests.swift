import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class FrameDragGate: @unchecked Sendable {
  private let condition = NSCondition()
  private var started = false, released = false
  func wait() { condition.lock(); started = true; condition.broadcast(); while !released { condition.wait() }; condition.unlock() }
  func isStarted() -> Bool { condition.lock(); defer { condition.unlock() }; return started }
  func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}
private struct FrameDragCompletion: @unchecked Sendable { let body: (Data?, Error?) -> Void }

final class AnimationFrameDragTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 6, height: 4, depth: depth, name: "Owned frames")
    d.layers[0].content = .raster(try Surface(width: 1, height: 1, depth: depth, fill: Pixel(0.25, 0.5, 0.75)))
    try Command.animation(.create).apply(to: &d)
    for n in 0..<4 {
      if n > 0 { try Command.animation(.duplicate).apply(to: &d) }
      try Command.move(d.layers[0].id, n, n % 2).apply(to: &d)
      try Command.animation(.delay(Double(n + 1) / 10)).apply(to: &d)
    }
    try Command.animation(.loop(3)).apply(to: &d)
    return d
  }
  @MainActor func payload(_ provider: NSItemProvider) async throws -> Data {
    let bytes: Data? = await withCheckedContinuation { continuation in
      _ = provider.loadDataRepresentation(forTypeIdentifier: AnimationFrameDrag.identifier) { data, _ in continuation.resume(returning: data) }
    }
    return try XCTUnwrap(bytes)
  }
  @MainActor func testNativeDragMatchesHTTPPreservesEveryFramePixelsArchiveAndOneUndo() async throws {
    let cases: [(Int, Int, Bool, [Int])] = [(0, 3, true, [1, 2, 3, 0]), (3, 0, false, [3, 0, 1, 2]), (2, 0, true, [0, 2, 1, 3])]
    for depth in PixelDepth.allCases { for (source, target, after, expectedOrder) in cases {
      let original = try fixture(depth), frames = try XCTUnwrap(original.animation).frames
      let native = EditorStore(document: original, actions: ActionLibrary())
      defer { AnimationFrameDrag.cancel(store: native); native.stopTimelinePlayback(); native.renderTask?.cancel() }
      let provider = AnimationFrameDrag.provider(store: native, frameID: frames[source].id)
      XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(AnimationFrameDrag.identifier))
      XCTAssertFalse(provider.hasItemConformingToTypeIdentifier("public.text"))
      let token = try await payload(provider)
      XCTAssertEqual(token.count, 53)
      let before = try original.animationDocument(at: frames[source].id)
      XCTAssertEqual(native.document, before); XCTAssertTrue(native.session.undoStack.isEmpty)
      let accepted = await AnimationFrameDrag.receive(provider, store: native, target: frames[target].id, after: after)
      XCTAssertTrue(accepted); XCTAssertNil(native.error)
      let result = native.document
      XCTAssertEqual(result.animation?.frames, expectedOrder.map { frames[$0] })
      XCTAssertEqual(result.animation?.selectedFrameID, frames[source].id)
      XCTAssertEqual(result.animation?.loopCount, 3)
      XCTAssertEqual(try Renderer.composite(result), try Renderer.composite(before))
      XCTAssertEqual(result.layers, before.layers); XCTAssertEqual(native.session.undoStack.count, 1)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)), result)
      let replay = await AnimationFrameDrag.receive(provider, store: native, target: frames[target].id, after: after); XCTAssertFalse(replay)
      let undo = await native.requestHistory(redo: false).value; XCTAssertTrue(undo); XCTAssertEqual(native.document, before)
      let redo = await native.requestHistory(redo: true).value; XCTAssertTrue(redo); XCTAssertEqual(native.document, result)
      let helper = AutomationTests()
      try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
        document.store.session = EditorSession(document: original); try service.share(document)
        let selected = try await helper.edit(service, document, "animation.view", ["frameID": frames[source].id.uuidString, "visible": true]); XCTAssertEqual(selected, 200)
        XCTAssertTrue(document.store.session.undoStack.isEmpty)
        let index = try XCTUnwrap(expectedOrder.firstIndex(of: source))
        let moved = try await helper.edit(service, document, "animation.edit", ["operation": "reorder", "index": index]); XCTAssertEqual(moved, 200)
        XCTAssertEqual(document.store.document, result); XCTAssertEqual(document.store.session.undoStack.count, 1)
        XCTAssertEqual(try NativeArchive.encodeChunked(document.store.document), try NativeArchive.encodeChunked(result))
        let undone = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undone, 200); XCTAssertEqual(document.store.document, before)
        let redone = try await helper.edit(service, document, "history.redo"); XCTAssertEqual(redone, 200); XCTAssertEqual(document.store.document, result)
      }
    } }
  }
  @MainActor func testEveryInsertionEdgeNoopForeignMalformedBusyHiddenAndModifierPolicy() async throws {
    let original = try fixture(), frames = try XCTUnwrap(original.animation).frames
    let store = EditorStore(document: original)
    defer { AnimationFrameDrag.cancel(store: store); store.stopTimelinePlayback(); store.renderTask?.cancel() }
    for source in frames.indices { for target in frames.indices { for after in [false, true] {
      store.session = EditorSession(document: original)
      _ = AnimationFrameDrag.provider(store: store, frameID: frames[source].id)
      // Independent ordered-list expectation: remove source, then insert beside the retained target.
      var expected = Array(frames.indices)
      if source != target {
        expected.removeAll { $0 == source }
        let targetPosition = try XCTUnwrap(expected.firstIndex(of: target))
        expected.insert(source, at: targetPosition + (after ? 1 : 0))
      }
      let index = try XCTUnwrap(expected.firstIndex(of: source))
      XCTAssertEqual(AnimationFrameDrag.destination(store: store, target: frames[target].id, after: after), index == source ? nil : index)
    } } }
    let flags: [NSEvent.ModifierFlags] = [.control, .command, .option, .shift]
    for bits in 0..<16 {
      let modifiers = flags.enumerated().reduce(into: NSEvent.ModifierFlags()) { if bits & (1 << $1.offset) != 0 { $0.insert($1.element) } }
      XCTAssertEqual(AnimationFrameDrag.operation(modifiers), .move)
    }
    for bytes in [Data(), Data("foreign".utf8), Data(repeating: 120, count: 97)] {
      _ = AnimationFrameDrag.provider(store: store, frameID: frames[0].id)
      let before = store.document
      let invalid = NSItemProvider(); invalid.registerDataRepresentation(forTypeIdentifier: AnimationFrameDrag.identifier, visibility: .ownProcess) { completion in completion(bytes, nil); return nil }
      let accepted = await AnimationFrameDrag.receive(invalid, store: store, target: frames[3].id, after: true)
      XCTAssertFalse(accepted); XCTAssertEqual(store.document, before); XCTAssertTrue(store.session.undoStack.isEmpty)
    }
    let provider = AnimationFrameDrag.provider(store: store, frameID: frames[0].id)
    let foreign = EditorStore(document: store.document); defer { foreign.renderTask?.cancel() }
    let accepted = await AnimationFrameDrag.receive(provider, store: foreign, target: frames[3].id, after: true); XCTAssertFalse(accepted)
    store.geometryBusy = true; XCTAssertNil(AnimationFrameDrag.destination(store: store, target: frames[3].id, after: true)); store.geometryBusy = false
    store.timelineVisible = false; store.timelineVisible = true
    XCTAssertNil(AnimationFrameDrag.destination(store: store, target: frames[3].id, after: true))
    XCTAssertTrue(AnimationFrameDrag.provider(store: store, frameID: UUID()).registeredTypeIdentifiers.isEmpty)
    let view = NSHostingView(rootView: TimelinePanel(store: store)); view.frame = NSRect(x: 0, y: 0, width: 1100, height: 166); view.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(view.fittingSize.width, 1100); XCTAssertLessThanOrEqual(view.fittingSize.height, 180)
    XCTAssertNotNil(AnimationAPI.capabilities["nativeFrameDrag"]); XCTAssertEqual(AutomationCommand.definitions.count, 255)
  }
  @MainActor func testDelayedProvidersRejectChangedSelectionSourceSessionPanelOwnerAndCancellation() async throws {
    for mode in ["edit", "select", "session", "hide", "close", "supersede", "cancel", "playing"] {
      try await AutomationTests().withService(pressedMouseButtons: { 0 }) { _, document in
        let original = try fixture(), frames = try XCTUnwrap(original.animation).frames
        let store = document.store; store.session = EditorSession(document: original); store.timelineVisible = true
        defer { AnimationFrameDrag.cancel(store: store); store.stopTimelinePlayback() }
        let provider = AnimationFrameDrag.provider(store: store, frameID: frames[0].id)
        let bytes = try await payload(provider), gate = FrameDragGate(); defer { gate.release() }
        let delayed = NSItemProvider()
        delayed.registerDataRepresentation(forTypeIdentifier: AnimationFrameDrag.identifier, visibility: .ownProcess) { completion in
          let callback = FrameDragCompletion(body: completion)
          DispatchQueue.global().async { gate.wait(); callback.body(bytes, nil) }; return nil
        }
        let task = Task { await AnimationFrameDrag.receive(delayed, store: store, target: frames[3].id, after: true) }
        let deadline = Date().addingTimeInterval(10)
        while !gate.isStarted() && Date() < deadline { await Task.yield() }
        XCTAssertTrue(gate.isStarted(), mode)
        switch mode {
        case "edit": store.editTimeline(.delay(0.8))
        case "select": try store.selectTimelineFrame(frames[1].id)
        case "session": store.session = EditorSession(document: store.document)
        case "hide": store.timelineVisible = false; store.timelineVisible = true
        case "close": document.ownerController?.removeDocument(document)
        case "supersede": _ = AnimationFrameDrag.provider(store: store, frameID: frames[1].id)
        case "playing": try store.startTimelinePlayback()
        default: task.cancel()
        }
        let before = store.document, count = store.session.undoStack.count
        gate.release(); let accepted = await task.value
        XCTAssertFalse(accepted, mode); XCTAssertEqual(store.document, before, mode); XCTAssertEqual(store.session.undoStack.count, count, mode)
      }
    }
  }
}
