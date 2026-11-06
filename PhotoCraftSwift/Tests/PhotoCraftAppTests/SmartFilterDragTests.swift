import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

private final class SmartDragGate: @unchecked Sendable {
  private let condition = NSCondition()
  private var started = false, released = false
  func wait() { condition.lock(); started = true; condition.broadcast(); while !released { condition.wait() }; condition.unlock() }
  func isStarted() -> Bool { condition.lock(); defer { condition.unlock() }; return started }
  func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}
private struct SmartDragCompletion: @unchecked Sendable { let body: (Data?, Error?) -> Void }

final class SmartFilterDragTests: XCTestCase {
  func blur(_ kind: RasterFilter.Kind, _ radius: Double) -> RasterFilter {
    var value = RasterFilter(kind); value.radius = radius; return value
  }
  func fixture(_ depth: PixelDepth = .u8, existing: Bool = true) throws -> CraftDocument {
    var d = try CraftDocument(width: 8, height: 8, depth: depth)
    var pixels = try Surface(width: 8, height: 8, depth: depth)
    for y in 0..<8 { for x in 0..<8 { pixels.setPixel(x: x, y: y, Pixel(Float(x)/8, Float(y)/8, x == y ? 0.8 : 0.2)) } }
    d.layers[0].content = .raster(pixels); d.layers[0].name = "Source"
    d.layers.append(Layer(name: "Target", content: .raster(pixels)))
    for name in ["Source", "Target"] {
      let id = try XCTUnwrap(d.layers.first(where: { $0.name == name })?.id)
      try SmartObjectIO.convert(in: d, selected: [id]).apply(to: &d)
    }
    let source = d.layers[0].id, target = d.layers[1].id
    var mosaic = RasterFilter(.mosaic); mosaic.cellSize = 2
    try Command.applyFilter(source, mosaic).apply(to: &d)
    try Command.applyFilter(source, blur(.boxBlur, 1)).apply(to: &d)
    try Command.applyFilter(source, blur(.gaussianBlur, 0.5)).apply(to: &d)
    d.layers[0].smartFilters!.filters[0].opacity = 0.375
    d.layers[0].smartFilters!.filters[0].blendMode = .screen
    d.layers[0].smartFilters!.filters[1].enabled = false
    if existing {
      try Command.applyFilter(target, blur(.boxBlur, 1)).apply(to: &d)
      d.layers[1].smartFilters!.maskProperties.density = 0.7
      d.layers[1].smartFilters!.maskProperties.transform = .translation(1, 0)
      d.layers[1].smartFilters!.enabled = false
    }
    d.selection = IntRect(x: 1, y: 1, width: 5, height: 5); d.activeLayerID = target
    return d
  }
  @MainActor func payload(_ provider: NSItemProvider) async throws -> Data {
    let data: Data? = await withCheckedContinuation { continuation in
      _ = provider.loadDataRepresentation(forTypeIdentifier: SmartFilterDrag.identifier) { data, _ in continuation.resume(returning: data) }
    }
    return try XCTUnwrap(data)
  }
  @MainActor func testCopyMatchesHTTPAllDepthsPreservesSourcesMasksHistoryAndPortableAction() async throws {
    for depth in PixelDepth.allCases { for existing in [false, true] {
      try await AutomationTests().withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, shared in
        let original = try fixture(depth, existing: existing), source = original.layers[0], target = original.layers[1]
        shared.store.session = EditorSession(document: original); shared.store.selectedLayerIDs = [target.id]; try service.share(shared)
        let native = EditorStore(document: original, actions: ActionLibrary())
        defer { native.renderTask?.cancel() }
        try native.startRecordingAction(name: "Copy Filter", set: "Test")
        let provider = SmartFilterDrag.provider(store: native, layerID: source.id, filterID: source.smartFilters!.filters[0].id)
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(SmartFilterDrag.identifier))
        XCTAssertFalse(provider.hasItemConformingToTypeIdentifier("public.text"))
        let accepted = await SmartFilterDrag.receive(provider, store: native, layerID: target.id, filterID: nil, copying: true)
        XCTAssertTrue(accepted); await native.geometryTask?.value
        XCTAssertNil(native.error); XCTAssertEqual(native.session.undoStack.count, 1)
        let result = native.document, stack = try XCTUnwrap(result.layers[1].smartFilters), copy = try XCTUnwrap(stack.filters.last)
        var expected = source.smartFilters!.filters[0]; expected.id = copy.id
        XCTAssertEqual(copy, expected); XCTAssertNotEqual(copy.id, source.smartFilters!.filters[0].id)
        XCTAssertEqual(result.layers[0], source); XCTAssertEqual(result.layers[1].smartObject, target.smartObject)
        if existing { XCTAssertEqual(stack.mask, target.smartFilters?.mask); XCTAssertEqual(stack.maskProperties, target.smartFilters!.maskProperties); XCTAssertFalse(stack.enabled) }
        else { var expectedMask = SmartFilterStack(); try expectedMask.createMask(in: original, selection: true); XCTAssertEqual(stack.mask, expectedMask.mask) }
        let replayed = await SmartFilterDrag.receive(provider, store: native, layerID: target.id, filterID: nil, copying: true)
        XCTAssertFalse(replayed)
        let action = try native.stopRecordingAction(); var playback = original; try action.apply(to: &playback); XCTAssertEqual(playback, result)
        let file = try native.actions.exportFile(action.id); XCTAssertNoThrow(try ActionLibraryFile.decode(file))
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)), result)
        var input = stack.apiState; input.removeValue(forKey: "hasMask"); input.removeValue(forKey: "maskTransform")
        let helper = AutomationTests()
        var status = try await helper.edit(service, shared, "smartFilter.set", ["layerID": target.id.uuidString, "stack": input])
        XCTAssertEqual(status, 200); XCTAssertEqual(shared.store.document, result)
        XCTAssertEqual(try NativeArchive.encodeChunked(shared.store.document), try NativeArchive.encodeChunked(result))
        status = try await helper.edit(service, shared, "smartFilter.set", ["layerID": target.id.uuidString, "stack": input], revision: "stale")
        XCTAssertEqual(status, 409)
        _ = await native.requestHistory(redo: false).value
        status = try await helper.edit(service, shared, "history.undo")
        XCTAssertEqual(status, 200); XCTAssertEqual(native.document, original); XCTAssertEqual(shared.store.document, original)
      }
    } }
  }
  @MainActor func testReorderNoopMalformedForeignLockedBudgetAndAllModifiers() async throws {
    let original = try fixture(), store = EditorStore(document: original), source = original.layers[0], target = original.layers[1]
    defer { store.renderTask?.cancel() }
    let first = source.smartFilters!.filters[0].id, last = source.smartFilters!.filters[2].id
    let flags: [NSEvent.ModifierFlags] = [.control, .command, .option, .shift]
    for bits in 0..<16 {
      let modifiers = flags.enumerated().reduce(into: NSEvent.ModifierFlags()) { if bits & (1 << $1.offset) != 0 { $0.insert($1.element) } }
      XCTAssertEqual(SmartFilterDrag.operation(modifiers), modifiers.contains(.option) ? .copy : .move)
    }
    var provider = SmartFilterDrag.provider(store: store, layerID: source.id, filterID: first)
    XCTAssertFalse(SmartFilterDrag.canReceive(store: store, layerID: source.id, filterID: first, copying: false))
    XCTAssertFalse(SmartFilterDrag.canReceive(store: store, layerID: target.id, filterID: nil, copying: false))
    var accepted = await SmartFilterDrag.receive(provider, store: store, layerID: source.id, filterID: last, copying: false)
    XCTAssertTrue(accepted); await store.geometryTask?.value; XCTAssertNil(store.error)
    var expected = source.smartFilters!; let moved = expected.filters.remove(at: 0); expected.filters.append(moved)
    XCTAssertEqual(store.document.layers[0].smartFilters, expected); XCTAssertEqual(store.document.layers[1], target)
    _ = await store.requestHistory(redo: false).value; XCTAssertEqual(store.document, original)
    accepted = await SmartFilterDrag.receive(provider, store: store, layerID: source.id, filterID: last, copying: false); XCTAssertFalse(accepted)
    for bytes in [Data(), Data("foreign".utf8), Data(repeating: 120, count: 97)] {
      _ = SmartFilterDrag.provider(store: store, layerID: source.id, filterID: first)
      let malformed = NSItemProvider(); malformed.registerDataRepresentation(forTypeIdentifier: SmartFilterDrag.identifier, visibility: .ownProcess) { completion in completion(bytes, nil); return nil }
      accepted = await SmartFilterDrag.receive(malformed, store: store, layerID: target.id, filterID: nil, copying: true); XCTAssertFalse(accepted)
    }
    provider = SmartFilterDrag.provider(store: store, layerID: source.id, filterID: first)
    let foreign = EditorStore(document: original); defer { foreign.renderTask?.cancel() }
    accepted = await SmartFilterDrag.receive(provider, store: foreign, layerID: target.id, filterID: nil, copying: true); XCTAssertFalse(accepted)
    store.geometryBusy = true; XCTAssertFalse(SmartFilterDrag.canReceive(store: store, layerID: target.id, filterID: nil, copying: true)); store.geometryBusy = false
    var limited = original; limited.layers[1].smartFilters!.filters = (0..<32).map { _ in SmartFilter(filter: blur(.boxBlur, 1)) }
    store.session = EditorSession(document: limited); _ = SmartFilterDrag.provider(store: store, layerID: source.id, filterID: first)
    XCTAssertFalse(SmartFilterDrag.canReceive(store: store, layerID: target.id, filterID: nil, copying: true))
    limited = original; limited.layers[1].locked = true; store.session = EditorSession(document: limited)
    _ = SmartFilterDrag.provider(store: store, layerID: source.id, filterID: first)
    XCTAssertFalse(SmartFilterDrag.canReceive(store: store, layerID: target.id, filterID: nil, copying: true))
    store.session = EditorSession(document: original)
    XCTAssertTrue(SmartFilterDrag.provider(store: store, layerID: source.id, filterID: UUID()).registeredTypeIdentifiers.isEmpty)
    XCTAssertNotNil(SmartFilterStack.apiCapabilities["nativeDrag"]); XCTAssertEqual(AutomationCommand.definitions.count, 256)
  }
  @MainActor func testDelayedCompletionRejectsEditCancellationSupersededGestureAndClosedDocument() async throws {
    for mode in ["edit", "cancel", "supersede", "close"] {
      try await AutomationTests().withService(pressedMouseButtons: { 0 }) { _, document in
        let original = try fixture(); document.store.session = EditorSession(document: original)
        let store = document.store, source = original.layers[0], target = original.layers[1]
        let active = SmartFilterDrag.provider(store: store, layerID: source.id, filterID: source.smartFilters!.filters[0].id)
        let bytes = try await payload(active), gate = SmartDragGate(); defer { gate.release() }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: SmartFilterDrag.identifier, visibility: .ownProcess) { completion in
          let callback = SmartDragCompletion(body: completion)
          DispatchQueue.global().async { gate.wait(); callback.body(bytes, nil) }; return nil
        }
        let task = Task { await SmartFilterDrag.receive(provider, store: store, layerID: target.id, filterID: nil, copying: true) }
        let deadline = Date().addingTimeInterval(10)
        while !gate.isStarted() && Date() < deadline { await Task.yield() }
        XCTAssertTrue(gate.isStarted())
        switch mode {
        case "edit": try store.executeEditorCommand(.renameLayer(target.id, "Changed"))
        case "cancel": task.cancel()
        case "supersede": _ = SmartFilterDrag.provider(store: store, layerID: source.id, filterID: source.smartFilters!.filters[1].id)
        default: document.ownerController?.removeDocument(document)
        }
        let before = store.document, history = store.session.undoStack.count
        gate.release(); let accepted = await task.value
        XCTAssertFalse(accepted, mode); XCTAssertEqual(store.document, before); XCTAssertEqual(store.session.undoStack.count, history)
      }
    }
  }
}
