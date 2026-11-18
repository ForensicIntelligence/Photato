import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class ColorRegionWorkflowTests: XCTestCase {
  @MainActor func store(empty: Bool = false) throws -> EditorStore {
    var d = try CraftDocument(width: 20, height: 12, depth: .u16)
    var pixels = try Surface(width: 20, height: 12, depth: .u16, fill: .white)
    for y in 0..<12 { pixels.setPixel(x: 10, y: y, .black) }
    d.layers[0].content = .raster(pixels)
    if empty {
      let target = Layer(
        name: "Fill", content: .raster(try Surface(width: 20, height: 12, depth: .u16)))
      d.layers.append(target)
      d.activeLayerID = target.id
    }
    let s = EditorStore(document: d)
    s.wandOptions.antiAlias = false
    s.bucketOptions.match.antiAlias = false
    s.renderTask?.cancel()
    return s
  }
  @MainActor func finish(_ s: EditorStore) async {
    await s.geometryTask?.value
    await s.renderTask?.value
    XCTAssertNil(s.error)
  }
  @MainActor func testNativeBucketActionCapturesPatternAndReplaysWithNewSelection() async throws {
    let patterns = PatternLibrary(), actions = ActionLibrary()
    var texture = try Surface(width: 2, height: 1, depth: .u16, fill: .white)
    texture.setPixel(x: 1, y: 0, .clear)
    let pattern = try RasterPattern(name: "Alternating", surface: texture, id: "portable-bucket")
    try await patterns.install([pattern])
    let source = try store().document
    let native = EditorStore(document: source, patterns: patterns, actions: actions)
    defer { native.renderTask?.cancel() }
    native.chooseTool(WorkspaceCatalog.tool("paintBucket"))
    native.bucketOptions.clearsAlpha = true
    native.bucketOptions.match.antiAlias = false
    native.bucketUsesPattern = true
    native.bucketPatternPlacement.phaseX = 1
    try native.startRecordingAction(name: "Pattern Clear", set: "Tests")
    let click = PathPoint(3.5, 2.5)
    native.colorRegionClick(at: click, modifiers: [.option])
    XCTAssertEqual(native.session.actionRecording?.snapshot.steps.count, 0)
    native.colorRegionClick(at: click)
    await finish(native)
    XCTAssertEqual(native.session.undoStack.count, 1)
    _ = await native.requestHistory(redo: false).value
    XCTAssertEqual(native.session.actionRecording?.snapshot.steps.count, 0)
    _ = await native.requestHistory(redo: true).value
    let action = try native.stopRecordingAction()
    let step = try XCTUnwrap(action.steps.first)
    XCTAssertEqual(action.steps.count, 1)
    guard case .paintBucket(let recipe) = step.operation else { return XCTFail("Expected a portable bucket step") }
    XCTAssertEqual(recipe.target, .active)
    XCTAssertEqual(recipe.point, click)
    XCTAssertEqual(recipe.pattern, pattern)
    XCTAssertEqual(recipe.placement.phaseX, 1)
    XCTAssertTrue(recipe.options.clearsAlpha)
    let exported = try actions.exportFile(action.id)
    XCTAssertEqual(try ActionLibraryFile.decode(exported).version, 67)
    var downgraded = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String: Any])
    downgraded["version"] = 66
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject: downgraded)))
    XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains(source.layers[0].id.uuidString))
    XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains(source.id.uuidString))
    let replacement = try RasterPattern(name: "Replacement",
      surface: Surface(width: 2, height: 1, depth: .u16, fill: .clear), id: pattern.id)
    try await patterns.install([replacement])
    var destination = try store().document
    destination.selection = .init(x: 2, y: 1, width: 4, height: 3)
    XCTAssertNotEqual(destination.activeLayerID, source.activeLayerID)
    let playback = EditorStore(document: destination, patterns: patterns, actions: ActionLibrary())
    defer { playback.renderTask?.cancel() }
    try playback.actions.importFile(exported)
    playback.playAction(try XCTUnwrap(playback.actions.file.actions.first))
    await finish(playback)
    guard case .raster(let result) = playback.document.layers[0].content else { return XCTFail("Expected pixel layer") }
    XCTAssertEqual(result.pixel(x: 3, y: 2), .clear)
    XCTAssertEqual(result.pixel(x: 2, y: 2), .white)
    XCTAssertEqual(result.pixel(x: 7, y: 2), .white)
    XCTAssertEqual(playback.document.selection, destination.selection)
    XCTAssertEqual(playback.session.undoStack.count, 1)
    _ = await playback.requestHistory(redo: false).value
    XCTAssertEqual(playback.document, destination)
  }

  @MainActor func testHTTPBucketRecordsNativeMaskRecipeAndRollsBackOnInvalidPlayback() async throws {
    let helper = AutomationTests(), actions = ActionLibrary()
    var source = try store().document
    source.layers[0].mask = try Surface(width: source.width, height: source.height, depth: .u16, fill: .white)
    try await helper.withService(actions: actions, pressedMouseButtons: { 0 }) { service, file in
      let s = file.store, point = PathPoint(7.5, 2.5)
      s.session = EditorSession(document: source)
      try service.share(file)
      let started = try await helper.edit(service, file, "actions.manage", ["operation": "record", "name": "Mask Fill"])
      XCTAssertEqual(started, 200)
      let oldRevision = service.revision(s)
      let configured = try await helper.edit(service, file, "paint.bucket",
        ["operation": "configure", "antiAlias": false, "tolerance": 0, "sampleAllLayers": true])
      XCTAssertEqual(configured, 200)
      let parameters: [String: Any] = ["operation": "fill", "x": point.x, "y": point.y,
        "target": "layerMask", "color": ["r": 0, "g": 0, "b": 0, "a": 1]]
      let stale = try await helper.edit(service, file, "paint.bucket", parameters, revision: oldRevision)
      XCTAssertEqual(stale, 409)
      XCTAssertEqual(s.session.actionRecording?.snapshot.steps.count, 0)
      let changed = try await helper.edit(service, file, "paint.bucket", parameters)
      XCTAssertEqual(changed, 200)
      let noop = try await helper.edit(service, file, "paint.bucket", parameters)
      XCTAssertEqual(noop, 200)
      XCTAssertEqual(s.session.actionRecording?.snapshot.steps.count, 1)
      XCTAssertEqual(s.session.undoStack.count, 1)
      let stopped = try await helper.edit(service, file, "actions.manage", ["operation": "stop"])
      XCTAssertEqual(stopped, 200)
      let action = try XCTUnwrap(actions.file.actions.first)
      guard case .paintBucket(let recipe) = action.steps.first?.operation else { return XCTFail("Expected a mask bucket recipe") }
      XCTAssertTrue(recipe.mask)
      XCTAssertEqual(recipe.point, point)
      XCTAssertEqual(recipe.options.sampling(mask: recipe.mask), .current)
      let documentBefore = s.document
      XCTAssertEqual(documentBefore.layers[0].content, source.layers[0].content)
      XCTAssertEqual(documentBefore.layers[0].mask?.pixel(x: 7, y: 2), .black)
      var replay = try self.store().document
      replay.layers[0].mask = source.layers[0].mask
      XCTAssertNotEqual(replay.activeLayerID, source.activeLayerID)
      s.session = EditorSession(document: replay)
      let committed = try await helper.edit(service, file, "actions.play", ["actionID": action.id.uuidString])
      XCTAssertEqual(committed, 200)
      XCTAssertEqual(s.document.layers[0].mask, documentBefore.layers[0].mask)
      XCTAssertEqual(s.document.layers[0].content, replay.layers[0].content)
      let undo = try await helper.edit(service, file, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(s.document, replay)
      var missingMask = replay
      missingMask.layers[0].mask = nil
      s.session = EditorSession(document: missingMask)
      let multi = RecordedAction(name: "Mask Rollback", steps: [
        .init(name: "Rename", operation: .rename(.active, "Changed")), action.steps[0],
      ])
      try actions.save(multi)
      let denied = try await helper.edit(service, file, "actions.play", ["actionID": multi.id.uuidString])
      XCTAssertEqual(denied, 422)
      XCTAssertEqual(s.document, missingMask)
      XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }

  @MainActor func testBucketClearDesktopHTTPAndModifierFeedback() async throws {
    let native = try store()
    defer { native.renderTask?.cancel() }
    let original = native.document, click = PathPoint(5.5, 2.5)
    native.chooseTool(WorkspaceCatalog.tool("paintBucket"))
    XCTAssertTrue(native.bucketOptions.chooseMode("Clear"))
    native.bucketOptions.opacity = 0.5
    native.brush.color = .clear
    let canvas = CraftCanvas(store: native)
    let modifiers: [NSEvent.ModifierFlags] = [.control, .command, .option, .shift]
    await native.renderTask?.value
    for bits in 0..<16 {
      let flags = modifiers.enumerated().reduce(NSEvent.ModifierFlags()) {
        bits & (1 << $1.offset) == 0 ? $0 : $0.union($1.element)
      }
      canvas.updateCursorModifiers(flags)
      let expected: ToolCursor = flags.contains(.option)
        ? .colorSample(target: .foreground, available: native.surface != nil)
        : .symbol("drop.fill", .subtract)
      XCTAssertEqual(canvas.toolCursor, expected, "modifier case \(bits)")
    }
    native.colorRegionClick(at: click)
    await finish(native)
    let expected = native.document
    XCTAssertEqual(native.session.undoStack.count, 1)
    guard case .raster(let raster) = expected.layers[0].content else { return XCTFail("Expected raster") }
    XCTAssertEqual(raster.pixel(x: 5, y: 2).a, 0.5, accuracy: 1 / 65_535)
    XCTAssertEqual(raster.pixel(x: 15, y: 2), .white)
    await native.undo()
    XCTAssertEqual(native.document, original)

    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      let store = file.store
      store.session = .init(document: original)
      try service.share(file)
      let start = service.revision(store)
      let configure: [String: Any] = ["operation":"configure", "mode":"Clear", "opacity":0.5, "antiAlias":false]
      let fill: [String: Any] = ["operation":"fill", "x":click.x, "y":click.y, "color":["r":0,"g":0,"b":0,"a":0]]
      let configured = try await helper.edit(service, file, "paint.bucket", configure)
      XCTAssertEqual(configured, 200)
      XCTAssertEqual(store.bucketOptions.modeName, "Clear")
      XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertNotEqual(service.revision(store), start)
      let stale = try await helper.edit(service, file, "paint.bucket", fill, revision: start)
      XCTAssertEqual(stale, 409)
      let result = try await helper.edit(service, file, "paint.bucket", fill)
      XCTAssertEqual(result, 200)
      XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let state = try JSONDecoder().decode(AutomationValue.self,
        from: JSONSerialization.data(withJSONObject: PaintBucketAPI.state(store)))
      XCTAssertNoThrow(try BrushAPI.merge(state, schema: PaintBucketAPI.stateSchema))
    }
    var locked = original
    locked.layers[0].protection = .transparency
    native.session = .init(document: locked)
    canvas.updateCursorModifiers([])
    XCTAssertEqual(canvas.toolCursor, .unavailable)
    native.colorRegionClick(at: click)
    XCTAssertNotNil(native.error)
    XCTAssertEqual(native.document, locked)
    XCTAssertTrue(native.session.undoStack.isEmpty)
  }

  @MainActor func testBucketPatternClearHTTPMatchesNativeAndKeepsFillOverridesLocal() async throws {
    let library = PatternLibrary()
    var patternSurface = try Surface(width: 2, height: 1, depth: .u16, fill: .white)
    patternSurface.setPixel(x: 1, y: 0, .clear)
    let pattern = try RasterPattern(name: "Owned Bucket pattern", surface: patternSurface, id: "bucket-test-pattern")
    try await library.install([pattern])
    let original = try store().document
    let native = EditorStore(document: original, patterns: library)
    defer { native.renderTask?.cancel() }
    native.chooseTool(WorkspaceCatalog.tool("paintBucket"))
    native.bucketOptions.clearsAlpha = true
    native.bucketOptions.match.antiAlias = false
    native.bucketUsesPattern = true
    native.bucketPatternPlacement.phaseX = 1
    native.brush.color = .black
    try native.session.startActionRecording(name: "Pattern Clear")
    native.colorRegionClick(at: .init(3.5, 2.5))
    await finish(native)
    let expected = native.document
    let nativeOperation = try XCTUnwrap(native.session.actionRecording?.snapshot.steps.first?.operation)
    guard case .raster(let pixels) = expected.layers[0].content else { return XCTFail("Expected raster") }
    XCTAssertEqual(pixels.pixel(x: 2, y: 2), .white)
    XCTAssertEqual(pixels.pixel(x: 3, y: 2), .clear)

    let helper = AutomationTests()
    try await helper.withService(patterns: library, pressedMouseButtons: { 0 }) { service, file in
      let store = file.store
      store.session = .init(document: original)
      store.brush.color = .black
      try store.session.startActionRecording(name: "Pattern Clear")
      try service.share(file)
      let defaults = store.bucketOptions
      let parameters: [String: Any] = ["operation":"fill", "x":3.5, "y":2.5, "mode":"Clear",
        "antiAlias":false, "patternID":pattern.id, "placement":["phaseX":1]]
      let status = try await helper.edit(service, file, "paint.bucket", parameters)
      XCTAssertEqual(status, 200)
      XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.bucketOptions, defaults)
      XCTAssertFalse(store.bucketUsesPattern)
      XCTAssertEqual(store.bucketPatternPlacement, PatternPlacement())
      XCTAssertEqual(store.session.undoStack.count, 1)
      let apiOperation = try XCTUnwrap(store.session.actionRecording?.snapshot.steps.first?.operation)
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      XCTAssertEqual(try encoder.encode(apiOperation), try encoder.encode(nativeOperation))
      await store.undo()
      XCTAssertEqual(store.document, original)
      var missing = parameters
      missing["patternID"] = "missing"
      let missingStatus = try await helper.edit(service, file, "paint.bucket", missing)
      XCTAssertEqual(missingStatus, 404)
      XCTAssertEqual(store.document, original)
    }
  }

  @MainActor func testBucketAPIRejectsInvalidTargetsParametersBusyAndLockedWithoutHistory() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      var original = try store().document
      original.layers[0].mask = try Surface(width: original.width, height: original.height, fill: .white)
      file.store.session = .init(document: original)
      try service.share(file)
      let fill: [String: Any] = ["operation":"fill", "x":3.5, "y":2.5, "mode":"Clear"]
      for bad: [String: Any] in [["operation":"configure"], ["operation":"configure","x":1],
        ["operation":"fill","x":3.5], ["operation":"fill","x":300000,"y":2.5],
        fill.merging(["opacity":2]) { _, new in new }, fill.merging(["mode":"Behind"]) { _, new in new },
        fill.merging(["patternID":"unused","source":"foreground"]) { _, new in new },
        fill.merging(["placement":["bad":1]]) { _, new in new }] {
        let status = try await helper.edit(service, file, "paint.bucket", bad)
        XCTAssertEqual(status, 400, "\(bad)")
      }
      let maskClear = try await helper.edit(service, file, "paint.bucket", fill.merging(["target":"layerMask"]) { _, new in new })
      XCTAssertEqual(maskClear, 422)
      file.store.geometryBusy = true
      let busy = try await helper.edit(service, file, "paint.bucket", fill)
      XCTAssertEqual(busy, 409)
      file.store.geometryBusy = false
      var locked = original
      locked.layers[0].protection = .transparency
      file.store.session = .init(document: locked)
      let unavailable = try await helper.edit(service, file, "paint.bucket", fill)
      XCTAssertEqual(unavailable, 422)
      XCTAssertEqual(file.store.document, locked)
      XCTAssertTrue(file.store.session.undoStack.isEmpty)

      file.store.session = .init(document: original)
      let normalMask: [String: Any] = ["operation":"fill","x":3.5,"y":2.5,
        "target":"layerMask","mode":"Normal","color":["r":0,"g":0,"b":0,"a":1]]
      let filled = try await helper.edit(service, file, "paint.bucket", normalMask)
      XCTAssertEqual(filled, 200)
      XCTAssertEqual(file.store.document.layers[0].mask?.pixel(x: 3, y: 2), .black)
      XCTAssertEqual(file.store.document.layers[0].content, original.layers[0].content)
    }
  }

  @MainActor func testWandModifiersShortcutGroupAndReadOnlyLockedLayer() async throws {
    let s = try store()
    defer { s.renderTask?.cancel() }
    s.chooseTool(WorkspaceCatalog.tool("magicWand"))
    try s.session.execute(.lock(s.document.layers[0].id, true))
    let original = s.document
    s.colorRegionClick(at: .init(2, 2))
    await finish(s)
    XCTAssertEqual(s.document.selectionMask?.coverage(x: 2, y: 2), 1)
    XCTAssertEqual(s.document.selectionMask?.coverage(x: 15, y: 2), 0)
    s.colorRegionClick(at: .init(15, 2), modifiers: .shift)
    await finish(s)
    XCTAssertEqual(s.document.selectionMask?.coverage(x: 15, y: 2), 1)
    s.colorRegionClick(at: .init(2, 2), modifiers: .option)
    await finish(s)
    XCTAssertEqual(s.document.selectionMask?.coverage(x: 2, y: 2), 0)
    s.colorRegionClick(at: .init(15, 2), modifiers: [.shift, .option])
    await finish(s)
    XCTAssertEqual(s.document.layers, original.layers)
    XCTAssertTrue(s.chooseShortcut("v", cycle: false))
    XCTAssertTrue(s.chooseShortcut("w", cycle: false))
    XCTAssertEqual(s.tool, .magicWand)
    XCTAssertTrue(s.chooseShortcut("w", cycle: true))
    XCTAssertEqual(s.tool, .objectSelection)
    XCTAssertNil(s.unavailableToolID)
  }
  @MainActor func testBucketCapturesForegroundAndAllLayersWithoutChangingSource() async throws {
    let s = try store(empty: true)
    defer { s.renderTask?.cancel() }
    s.chooseTool(WorkspaceCatalog.tool("paintBucket"))
    s.bucketOptions.sampleAllLayers = true
    s.brush.color = Pixel(1, 0, 0)
    let before = s.document
    s.colorRegionClick(at: .init(2, 2))
    XCTAssertTrue(s.geometryBusy)
    s.brush.color = .black
    s.bucketOptions.sampleAllLayers = false
    s.bucketOptions.match.contiguous = false
    await finish(s)
    guard case .raster(let pixels) = s.activeLayer?.content else {
      return XCTFail("Expected pixels")
    }
    XCTAssertEqual(pixels.pixel(x: 2, y: 2), Pixel(1, 0, 0))
    XCTAssertEqual(pixels.pixel(x: 15, y: 2), .clear)
    XCTAssertEqual(s.document.layers[0], before.layers[0])
    XCTAssertEqual(s.session.undoStack.count, 1)
    let after = s.document
    await s.undo()
    XCTAssertEqual(s.document, before)
    await s.redo()
    XCTAssertEqual(s.document, after)
    XCTAssertTrue(s.chooseShortcut("v", cycle: false))
    XCTAssertTrue(s.chooseShortcut("g", cycle: false))
    XCTAssertEqual(s.tool, .paintBucket)
    await s.renderTask?.value
    s.colorRegionClick(at: .init(15, 2), modifiers: .option)
    XCTAssertEqual(s.brush.color, .white)
    XCTAssertEqual(s.document, after)
    XCTAssertEqual(s.session.undoStack.count, 1)
  }
  @MainActor func testCanvasClickAndEscapeCancelAreSingleAtomicOperations() async throws {
    let s = try store()
    defer { s.renderTask?.cancel() }
    s.chooseTool(WorkspaceCatalog.tool("magicWand"))
    let canvas = CraftCanvas(store: s)
    canvas.frame = NSRect(x: 0, y: 0, width: 300, height: 240)
    // This interaction fixture requires 10× magnification, independent of initial-fit policy.
    s.zoom = 10
    let event = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: .init(x: 90, y: 100), modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    XCTAssertEqual(canvas.docPoint(event), CGPoint(x: 4, y: 8))
    canvas.mouseDown(with: event)
    await finish(s)
    XCTAssertNotNil(s.document.selectionMask)
    XCTAssertEqual(s.session.undoStack.count, 1)
    s.chooseTool(WorkspaceCatalog.tool("paintBucket"))
    s.brush.color = .black
    let before = s.document
    s.colorRegionClick(at: .init(2, 2))
    let escape = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
    canvas.keyDown(with: escape)
    await finish(s)
    XCTAssertEqual(s.document, before)
    XCTAssertEqual(s.session.undoStack.count, 1)
    XCTAssertFalse(s.geometryBusy)
  }
  @MainActor func testPixelMaskTargetAndLockedBucket() async throws {
    let s = try store()
    defer { s.renderTask?.cancel() }
    try s.session.execute(
      .mask(
        s.document.layers[0].id,
        Surface(width: 20, height: 12, depth: .u16, fill: .white)))
    s.maskEditingLayerID = s.activeLayer?.id
    s.chooseTool(WorkspaceCatalog.tool("paintBucket"))
    s.brush.color = .black
    s.bucketOptions.sampleAllLayers = true
    let originalContent = s.document.layers[0].content
    s.colorRegionClick(at: .init(2, 2))
    await finish(s)
    XCTAssertEqual(s.document.layers[0].content, originalContent)
    XCTAssertEqual(s.activeLayer?.mask?.pixel(x: 2, y: 2), .black)
    try s.session.execute(.lock(s.document.layers[0].id, true))
    let locked = s.document
    s.brush.color = .white
    s.colorRegionClick(at: .init(2, 2))
    XCTAssertNotNil(s.error)
    XCTAssertFalse(s.geometryBusy)
    XCTAssertEqual(s.document, locked)
  }
}
