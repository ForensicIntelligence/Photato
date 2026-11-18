import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class BrushWorkflowTests:XCTestCase {
  @MainActor func testWideSoftMigratesOnlyUntouchedFactoryCopies() throws {
    let factory = BrushPresets.builtins()
    var saved = factory.filter { $0.brush.settings?.roundTipProfile == .calibratedRound }
    XCTAssertEqual(saved.count, 4)
    saved.removeAll { $0.name == "Hard Round Pressure Size" }
    for index in saved.indices {
      let wasSoft = saved[index].brush.hardness == 0
      saved[index].brush.settings?.roundTipProfile = wasSoft ? .wideSoft : nil
    }
    saved[2].name = "My pressure brush"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let data = try BrushPresetFile(presets: saved).encoded()
    try data.write(to: url)
    let library = BrushLibrary(persistenceURL: url)
    XCTAssertEqual(library.file.version, 3)
    XCTAssertEqual(library.file.presets.count, 3)
    XCTAssertEqual(library.file.presets[0], factory.first { $0.id == saved[0].id })
    XCTAssertEqual(library.file.presets[1], factory.first { $0.id == saved[1].id })
    XCTAssertEqual(library.file.presets[2], saved[2])
    XCTAssertEqual(try Data(contentsOf: url), data)
    try library.save(saved[2])
    XCTAssertEqual(try BrushPresetFile.decode(Data(contentsOf: url)), library.file)
  }

  @MainActor func testWideSoftDesktopHTTPUndoAndVersionedActionReplay() async throws {
    try await checkRoundProfile(.wideSoft, version: 63)
  }

  @MainActor func testCalibratedRoundDesktopHTTPUndoAndVersionedActionReplay() async throws {
    try await checkRoundProfile(.calibratedRound, version: 64)
  }

  @MainActor private func checkRoundProfile(_ profile: BrushSettings.RoundTipProfile, version: Int) async throws {
    let original = try CraftDocument(width: 128, height: 96)
    let store = EditorStore(document: original, actions: ActionLibrary(), brushes: BrushLibrary())
    defer { store.cancelBrush(); store.renderTask?.cancel() }
    store.tool = .brush
    let preset = try XCTUnwrap(store.brushes.file.presets.first { $0.name == "Soft Round" })
    try store.selectBrush(preset.id)
    store.brush.color = .black
    store.brushOptions.smoothing.amount = 0
    XCTAssertEqual(store.brushOptions.roundTipProfile, .calibratedRound)
    store.brushOptions.roundTipProfile = profile
    if profile == .calibratedRound { store.brush.hardness = 0.5 }
    let activeBrush = store.brush
    let point = StrokePoint(x: 64.5, y: 48.5)
    try store.startRecordingAction(name: "Wide Soft", set: "Test")
    store.beginBrush(point, zoom: 1)
    store.finishBrush()
    await store.geometryTask?.value
    let painted = store.document
    XCTAssertFalse(painted == original)
    XCTAssertEqual(store.session.undoStack.count, 1)
    let action = try store.stopRecordingAction()
    let data = try store.actions.exportFile(action.id)
    let decoded = try ActionLibraryFile.decode(data)
    XCTAssertEqual(decoded.version, version)
    var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    old["version"] = version - 1
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject: old)))
    var replay = original
    try XCTUnwrap(decoded.actions.first).apply(to: &replay)
    XCTAssertTrue(replay == painted)
    _ = await store.requestHistory(redo: false).value
    XCTAssertTrue(store.document == original)

    let helper = AutomationTests()
    try await helper.withService(brushes: BrushLibrary(), pressedMouseButtons: { 0 }) { service, file in
      file.store.session = EditorSession(document: original)
      try service.share(file)
      let before = file.store.brush
      var status = try await helper.edit(service, file, "brush.configure",
        ["brush": ["settings": ["roundTipProfile": "unknown"]]])
      XCTAssertEqual(status, 400)
      XCTAssertEqual(file.store.brush, before)
      status = try await helper.edit(service, file, "brush.configure", ["brush": BrushAPI.json(activeBrush)])
      XCTAssertEqual(status, 200)
      let state = try XCTUnwrap(file.store.brushState["brush"] as? [String: Any])
      let settings = try XCTUnwrap(state["settings"] as? [String: Any])
      XCTAssertEqual(settings["roundTipProfile"] as? String, profile.rawValue)
      status = try await helper.edit(service, file, "paint.stroke", ["points": BrushAPI.json([point])])
      XCTAssertEqual(status, 200)
      XCTAssertTrue(file.store.document == painted)
      XCTAssertEqual(file.store.session.undoStack.count, 1)
      status = try await helper.edit(service, file, "brush.configure",
        ["brush": ["settings": ["roundTipProfile": NSNull()]]])
      XCTAssertEqual(status, 200)
      XCTAssertNil(file.store.brushOptions.roundTipProfile)
      XCTAssertTrue(file.store.document == painted)
      XCTAssertEqual(file.store.session.undoStack.count, 1)
    }
  }

  @MainActor private func brushDigit(_ digit: Int, at time: TimeInterval, modifiers: NSEvent.ModifierFlags = [],
    repeatKey: Bool = false) throws -> NSEvent {
    let keyCodes: [UInt16] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
    return try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
      timestamp: time, windowNumber: 0, context: nil, characters: String(digit), charactersIgnoringModifiers: String(digit),
      isARepeat: repeatKey, keyCode: keyCodes[digit]))
  }

  @MainActor private func tipKey(_ character: String, keyCode: UInt16 = 0,
    unmodified: String? = nil, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
      timestamp: 1, windowNumber: 0, context: nil, characters: character,
      charactersIgnoringModifiers: unmodified ?? character, isARepeat: false, keyCode: keyCode))
  }

  @MainActor private func tipArrow(_ key: Int, keyCode: UInt16, shift: Bool = false) throws -> NSEvent {
    try tipKey(String(XCTUnwrap(UnicodeScalar(key))), keyCode: keyCode,
      modifiers: shift ? [.numericPad, .function, .shift] : [.numericPad, .function])
  }

  @MainActor func testBrushTipKeysRespectModifiersShapeAndRotationDirection() throws {
    let store = EditorStore(document: try CraftDocument(width: 60, height: 54))
    defer { store.renderTask?.cancel() }
    let canvas = CraftCanvas(store: store)
    let original = store.document, size = store.brush.size
    store.tool = .brush
    store.brush.hardness = 0.625
    canvas.keyDown(with: try tipKey("{", keyCode: 33, modifiers: .shift))
    XCTAssertEqual(store.brush.hardness, 0.375)
    canvas.keyDown(with: try tipKey("]", keyCode: 30, modifiers: .shift))
    XCTAssertEqual(store.brush.hardness, 0.625)
    canvas.keyDown(with: try tipKey("{", keyCode: 28, unmodified: "8", modifiers: .option))
    XCTAssertEqual(store.brush.hardness, 0.375)
    XCTAssertEqual(store.brush.size, size)
    canvas.keyDown(with: try tipKey("{", keyCode: 33, modifiers: .shift))
    canvas.keyDown(with: try tipKey("{", keyCode: 33, modifiers: .shift))
    XCTAssertEqual(store.brush.hardness, 0)
    store.brush.hardness = 0.875
    canvas.keyDown(with: try tipKey("}", keyCode: 30, modifiers: .shift))
    XCTAssertEqual(store.brush.hardness, 1)
    canvas.keyDown(with: try tipArrow(NSRightArrowFunctionKey, keyCode: 124))
    XCTAssertEqual(store.brushOptions.angle, -1)
    canvas.keyDown(with: try tipArrow(NSLeftArrowFunctionKey, keyCode: 123, shift: true))
    XCTAssertEqual(store.brushOptions.angle, 14)
    store.brushOptions.angle = 179
    canvas.keyDown(with: try tipArrow(NSLeftArrowFunctionKey, keyCode: 123, shift: true))
    XCTAssertEqual(store.brushOptions.angle, -166)

    let stored = store.brush
    for flags: NSEvent.ModifierFlags in [[.shift, .command], [.shift, .control], [.shift, .function], [.shift, .option]] {
      let event = try tipKey("]", keyCode: 30, modifiers: flags)
      XCTAssertFalse(store.applyBrushTipKey(event))
      canvas.keyDown(with: event)
    }
    canvas.keyDown(with: try tipArrow(NSHomeFunctionKey, keyCode: 123))
    XCTAssertEqual(store.brush, stored)
    store.brushOptions.aliased = true
    XCTAssertFalse(store.applyBrushTipKey(try tipKey("{", keyCode: 33, modifiers: .shift)))
    store.brushOptions.aliased = false
    store.brushOptions.tip = try BrushPresets.generatedTip("leaf", size: 8)
    XCTAssertFalse(store.applyBrushTipKey(try tipKey("{", keyCode: 33, modifiers: .shift)))
    XCTAssertTrue(store.applyBrushTipKey(try tipArrow(NSRightArrowFunctionKey, keyCode: 124)))
    XCTAssertEqual(store.brushOptions.angle, -167)
    store.tool = .eraser
    for mode in [EraserMode.pencil, .block] {
      store.eraserMode = mode
      XCTAssertFalse(store.applyBrushTipKey(try tipArrow(NSRightArrowFunctionKey, keyCode: 124)))
    }
    store.eraserMode = .brush
    XCTAssertTrue(store.applyBrushTipKey(try tipArrow(NSRightArrowFunctionKey, keyCode: 124)))
    store.tool = .move
    XCTAssertFalse(store.applyBrushTipKey(try tipArrow(NSRightArrowFunctionKey, keyCode: 124)))
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testBrushSmoothingKeysUseSeparateToolAndPercentageState() throws {
    let store = EditorStore(document: try CraftDocument(width: 40, height: 32))
    defer { store.renderTask?.cancel() }
    let canvas = CraftCanvas(store: store)
    store.tool = .brush
    canvas.keyDown(with: try brushDigit(4, at: 1))
    canvas.keyDown(with: try brushDigit(3, at: 1.1, modifiers: .option))
    canvas.keyDown(with: try brushDigit(7, at: 1.2, modifiers: .option))
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0.37)
    XCTAssertEqual(store.brush.opacity, 0.4)
    canvas.keyDown(with: try brushDigit(0, at: 2, modifiers: .option))
    XCTAssertEqual(store.brushOptions.smoothing.amount, 1)
    canvas.keyDown(with: try brushDigit(0, at: 2.1, modifiers: .option))
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0)
    canvas.keyDown(with: try brushDigit(4, at: 3, modifiers: .option))
    canvas.keyDown(with: try brushDigit(5, at: 3.1, modifiers: .option, repeatKey: true))
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0.4)
    canvas.keyDown(with: try brushDigit(5, at: 3.2, modifiers: .option))
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0.45)
    store.tool = .mixerBrush
    canvas.keyDown(with: try brushDigit(2, at: 4, modifiers: .option))
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0.2)
    store.tool = .pencil
    canvas.keyDown(with: try brushDigit(3, at: 5, modifiers: .option))
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0.3)
    store.tool = .eraser
    store.eraserMode = .block
    let blocked = store.brushOptions.smoothing.amount
    canvas.keyDown(with: try brushDigit(8, at: 6, modifiers: .option))
    XCTAssertEqual(store.brushOptions.smoothing.amount, blocked)
    store.eraserMode = .brush
    canvas.keyDown(with: try brushDigit(9, at: 7, modifiers: .option))
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0.9)
    store.tool = .brush
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0.45)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testBrushNumberKeysUseExactPercentagesAndAirbrushModifiers() throws {
    _ = NSApplication.shared
    let store = EditorStore(document: try CraftDocument(width: 48, height: 32))
    defer { store.renderTask?.cancel() }
    store.tool = .brush
    let canvas = CraftCanvas(store: store)

    canvas.keyDown(with: try brushDigit(4, at: 1))
    XCTAssertEqual(store.brush.opacity, 0.4)
    canvas.keyDown(with: try brushDigit(4, at: 1.1, repeatKey: true))
    XCTAssertEqual(store.brush.opacity, 0.4)
    canvas.keyDown(with: try brushDigit(5, at: 1.2))
    XCTAssertEqual(store.brush.opacity, 0.45)
    canvas.keyDown(with: try brushDigit(3, at: 2, modifiers: .shift))
    canvas.keyDown(with: try brushDigit(7, at: 2.4, modifiers: .shift))
    XCTAssertEqual(store.brushOptions.flow, 0.37)
    canvas.keyDown(with: try brushDigit(0, at: 3))
    XCTAssertEqual(store.brush.opacity, 1)
    canvas.keyDown(with: try brushDigit(0, at: 3.2))
    XCTAssertEqual(store.brush.opacity, 0)
    canvas.keyDown(with: try brushDigit(4, at: 4))
    canvas.keyDown(with: try brushDigit(5, at: 4.6))
    XCTAssertEqual(store.brush.opacity, 0.5)

    canvas.keyDown(with: try brushDigit(5, at: 5))
    store.brushOptions.buildUp = true
    canvas.keyDown(with: try brushDigit(6, at: 5.1, modifiers: .shift))
    XCTAssertEqual(store.brush.opacity, 0.6, "Airbrush changes interrupt even when the value adjusted is still opacity")
    canvas.keyDown(with: try brushDigit(4, at: 5.2))
    XCTAssertEqual(store.brushOptions.flow, 0.4)
    canvas.keyDown(with: try brushDigit(7, at: 5.3))
    XCTAssertEqual(store.brushOptions.flow, 0.47)

    for modifier in [NSEvent.ModifierFlags.command, .control, .function] {
      let revision = store.brushRevision
      canvas.keyDown(with: try brushDigit(2, at: 6, modifiers: modifier))
      canvas.keyDown(with: try brushDigit(2, at: 6.1, modifiers: [modifier, .shift]))
      XCTAssertEqual(store.brushRevision, revision)
    }
    let unmodified = store.brushRevision
    canvas.keyDown(with: try brushDigit(2, at: 6.2, modifiers: [.option, .shift]))
    XCTAssertEqual(store.brushRevision, unmodified)
    store.tool = .pencil
    canvas.keyDown(with: try brushDigit(2, at: 7, modifiers: .shift))
    XCTAssertEqual(store.brush.opacity, 0.6)
    canvas.keyDown(with: try brushDigit(7, at: 7.1))
    XCTAssertEqual(store.brush.opacity, 0.7)
    XCTAssertEqual(store.brushOptions.flow, 0.47)

    store.tool = .eraser
    store.eraserMode = .block
    canvas.keyDown(with: try brushDigit(9, at: 8))
    XCTAssertEqual(store.brush.opacity, 0.7)
    store.eraserMode = .pencil
    canvas.keyDown(with: try brushDigit(8, at: 8.1))
    XCTAssertEqual(store.brush.opacity, 0.8)
    store.eraserMode = .brush
    canvas.keyDown(with: try brushDigit(3, at: 8.2))
    XCTAssertEqual(store.brushOptions.flow, 0.3)
    XCTAssertEqual(store.brush.opacity, 0.8)
  }

  @MainActor func testBrushNumberKeysRespectFocusAndCapturedStroke() async throws {
    _ = NSApplication.shared
    let original = try CraftDocument(width: 48, height: 32)
    let store = EditorStore(document: original)
    store.tool = .brush
    store.brush.color = .black
    store.brushOptions.smoothing.amount = 0
    let canvas = CraftCanvas(store: store)
    let rect = NSRect(x: 0, y: 0, width: 400, height: 300)
    let window = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let contents = NSView(frame: rect)
    window.contentView = contents
    canvas.frame = NSRect(x: 0, y: 24, width: 400, height: 276)
    contents.addSubview(canvas)
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 60, height: 24))
    contents.addSubview(field)
    defer { store.cancelBrush(); store.renderTask?.cancel(); window.contentView = nil; window.close() }

    XCTAssertTrue(window.makeFirstResponder(canvas))
    canvas.keyDown(with: try brushDigit(4, at: 1))
    XCTAssertEqual(store.brush.opacity, 0.4)
    XCTAssertTrue(window.makeFirstResponder(field))
    XCTAssertFalse(window.firstResponder === canvas)
    let beforeTextEdit = store.brush
    canvas.keyDown(with: try brushDigit(9, at: 1.1))
    canvas.keyDown(with: try brushDigit(8, at: 1.1, modifiers: .option))
    canvas.keyDown(with: try tipKey("{", keyCode: 33, modifiers: .shift))
    canvas.keyDown(with: try tipArrow(NSLeftArrowFunctionKey, keyCode: 123))
    XCTAssertEqual(store.brush, beforeTextEdit)
    XCTAssertEqual(store.brush.opacity, 0.4)
    XCTAssertTrue(window.makeFirstResponder(canvas))
    canvas.keyDown(with: try brushDigit(5, at: 1.2))
    XCTAssertEqual(store.brush.opacity, 0.5, "Focus transfer discards the earlier digit")

    let point = StrokePoint(x: 18, y: 16)
    store.beginBrush(point, zoom: 1)
    let captured = try XCTUnwrap(store.brushGesture?.brush)
    canvas.keyDown(with: try brushDigit(2, at: 2))
    canvas.keyDown(with: try brushDigit(1, at: 2.1, modifiers: .option))
    canvas.keyDown(with: try tipKey("{", keyCode: 33, modifiers: .shift))
    canvas.keyDown(with: try tipArrow(NSRightArrowFunctionKey, keyCode: 124))
    XCTAssertEqual(store.brush.opacity, 0.2)
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0.1)
    XCTAssertEqual(store.brush.hardness, captured.hardness - 0.25)
    XCTAssertEqual(store.brushOptions.angle, -1)
    XCTAssertEqual(store.brushGesture?.brush, captured)
    XCTAssertEqual(store.session.undoStack.count, 0)
    var expected = original
    try Command.stroke(XCTUnwrap(expected.activeLayerID), [point], captured).apply(to: &expected)
    store.finishBrush()
    await store.geometryTask?.value
    XCTAssertEqual(store.document, expected)
    XCTAssertEqual(store.session.undoStack.count, 1)
    _ = await store.requestHistory(redo: false).value
    XCTAssertEqual(store.document, original)
  }

  @MainActor func testBrushNumericSettingsMatchHTTPStateAndStroke() async throws {
    let original = try CraftDocument(width: 48, height: 32)
    let helper = AutomationTests()
    try await helper.withService(brushes: BrushLibrary(), pressedMouseButtons: { 0 }) { service, file in
      file.store.session = EditorSession(document: original)
      let store = file.store
      store.tool = .brush
      store.brush.color = .black
      store.brush.hardness = 0.75
      store.brushOptions.roundness = 0.48
      store.brushOptions.roundTipProfile = .calibratedRound
      store.brushOptions.smoothing.amount = 0
      try service.share(file)
      let canvas = CraftCanvas(store: store)
      let oldRevision = service.revision(store)
      canvas.keyDown(with: try brushDigit(4, at: 1))
      canvas.keyDown(with: try brushDigit(5, at: 1.1))
      canvas.keyDown(with: try brushDigit(3, at: 2, modifiers: .shift))
      canvas.keyDown(with: try brushDigit(7, at: 2.2, modifiers: .shift))
      canvas.keyDown(with: try brushDigit(4, at: 3, modifiers: .option))
      canvas.keyDown(with: try brushDigit(2, at: 3.1, modifiers: .option))
      canvas.keyDown(with: try tipKey("{", keyCode: 33, modifiers: .shift))
      canvas.keyDown(with: try tipArrow(NSLeftArrowFunctionKey, keyCode: 123))
      canvas.keyDown(with: try tipArrow(NSRightArrowFunctionKey, keyCode: 124, shift: true))
      XCTAssertNotEqual(service.revision(store), oldRevision)
      XCTAssertEqual(store.session.undoStack.count, 0)
      let keyboardSetting = store.brush
      let nested = try XCTUnwrap(store.brushState["brush"] as? [String: Any])
      let settings = try XCTUnwrap(nested["settings"] as? [String: Any])
      XCTAssertEqual((nested["opacity"] as? NSNumber)?.floatValue, 0.45)
      XCTAssertEqual((settings["flow"] as? NSNumber)?.doubleValue, 0.37)
      XCTAssertEqual((nested["hardness"] as? NSNumber)?.floatValue, 0.5)
      XCTAssertEqual((settings["angle"] as? NSNumber)?.doubleValue, -14)
      XCTAssertEqual((settings["smoothing"] as? [String: NSNumber])?["amount"]?.doubleValue, 0.42)
      let patch: [String: Any] = ["brush": ["opacity": 0.45, "hardness": 0.5,
        "settings": ["flow": 0.37, "angle": -14, "smoothing": ["amount": 0.42]]]]
      var status = try await helper.edit(service, file, "brush.configure", patch, revision: oldRevision)
      XCTAssertEqual(status, 409)
      store.brush.hardness = 1
      store.brushOptions.angle = 0
      store.brushOptions.smoothing.amount = 0
      status = try await helper.edit(service, file, "brush.configure", patch)
      XCTAssertEqual(status, 200)
      XCTAssertEqual(store.brush, keyboardSetting)
      let samples = [StrokePoint(x: 17, y: 13, time: 0), StrokePoint(x: 25, y: 20, time: 18)]
      var expected = original
      try Command.stroke(XCTUnwrap(expected.activeLayerID), samples, keyboardSetting).apply(to: &expected)
      status = try await helper.edit(service, file, "paint.stroke", ["points": BrushAPI.json(samples)])
      XCTAssertEqual(status, 200)
      XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }

  @MainActor func testMaximumBrushDiameterNativePreviewActionUndoAndHTTP() async throws {
    let original = try CraftDocument(width:128,height:96)
    let store = EditorStore(document:original,actions:ActionLibrary(),brushes:BrushLibrary())
    defer { store.cancelBrush(); store.renderTask?.cancel() }
    store.tool = .brush
    store.brush.color = .black
    store.setBrushDiameter(4998)
    let canvas = CraftCanvas(store:store)
    canvas.frame = NSRect(x:0,y:0,width:320,height:240)
    store.updateViewport(size:canvas.bounds.size,backingScale:1)
    store.setZoom(1,center:true)
    await store.renderTask?.value
    let key = try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:1,
      windowNumber:0,context:nil,characters:"]",charactersIgnoringModifiers:"]",isARepeat:false,keyCode:30))
    canvas.keyDown(with:key)
    XCTAssertEqual(store.brush.size,5_000)

    try store.startRecordingAction(name:"Large Brush",set:"Test")
    let point = StrokePoint(x:64,y:48)
    store.beginBrush(point,zoom:1)
    let captured = try XCTUnwrap(store.brushGesture?.brush)
    XCTAssertEqual(captured.size,5_000)
    await store.brushPreviewTask?.value
    await store.renderTask?.value
    XCTAssertTrue(store.document == original)
    XCTAssertEqual(store.surface?.pixel(x:64,y:48),.black)
    store.finishBrush()
    await store.geometryTask?.value
    let final = store.document
    XCTAssertTrue(final != original)
    XCTAssertEqual(store.session.undoStack.count,1)
    let action = try store.stopRecordingAction()
    var replay = original
    try action.apply(to:&replay)
    XCTAssertTrue(replay == final)
    _ = await store.requestHistory(redo:false).value
    XCTAssertTrue(store.document == original)

    let helper = AutomationTests()
    try await helper.withService(brushes:BrushLibrary(),pressedMouseButtons:{0}) { service,file in
      file.store.session = EditorSession(document:original)
      try service.share(file)
      let bad = try await helper.edit(service,file,"brush.configure",["brush":["size":5001]])
      XCTAssertEqual(bad,400)
      let configure = try await helper.edit(service,file,"brush.configure",["brush":BrushAPI.json(captured)])
      XCTAssertEqual(configure,200)
      XCTAssertEqual(file.store.brush.size,5_000)
      let status = try await helper.edit(service,file,"paint.stroke",["points":BrushAPI.json([point])])
      XCTAssertEqual(status,200)
      XCTAssertTrue(file.store.document == final)
      XCTAssertEqual(file.store.session.undoStack.count,1)
    }
  }

  @MainActor func testDefinedBrushRetainsSampleDiameterAbovePreviousLimit() async throws {
    var document = try CraftDocument(width:2_400,height:2)
    document.layers[0].content = .raster(try Surface(width:2_400,height:2,fill:.black))
    let store = EditorStore(document:document,brushes:BrushLibrary())
    defer { store.renderTask?.cancel() }
    let preset = try await store.defineBrush(name:"Wide sample")
    XCTAssertEqual(preset.brush.size,2_400)
    XCTAssertEqual(preset.brush.settings?.tip?.width,2_400)
    XCTAssertEqual(store.brush.size,2_400)
  }

  @MainActor func testShiftClickConnectsBrushAndPencilWithOneUndo() async throws {
    for tool in [EditorTool.brush, .pencil] {
      let original = try CraftDocument(width: 128,height: 96)
      let store = EditorStore(document:original,actions:ActionLibrary(),brushes:BrushLibrary())
      defer { store.cancelBrush(); store.renderTask?.cancel() }
      store.tool = tool; store.brush.size = 8; store.brush.color = .black
      store.brushOptions.smoothing.amount = 0
      let canvas = CraftCanvas(store:store); canvas.frame = NSRect(x:0,y:0,width:320,height:240)
      store.updateViewport(size: canvas.bounds.size, backingScale: 1)
      store.setZoom(1,center:true); await store.renderTask?.value
      func event(_ type:NSEvent.EventType, x:Double, time:Double, flags:NSEvent.ModifierFlags=[]) throws -> NSEvent {
        let p = canvas.convert(canvas.viewPoint(CGPoint(x:x,y:48)),to:nil)
        return try XCTUnwrap(NSEvent.mouseEvent(with:type,location:p,modifierFlags:flags,timestamp:time,
          windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1))
      }
      canvas.mouseDown(with:try event(.leftMouseDown,x:24,time:1))
      canvas.mouseUp(with:try event(.leftMouseUp,x:24,time:1.01))
      await store.geometryTask?.value; await store.renderTask?.value
      let first = store.document
      XCTAssertTrue(store.canConnectBrushStroke)
      XCTAssertEqual(store.session.undoStack.count,1)

      try store.startRecordingAction(name:"Connect",set:"Test")
      canvas.updateCursorModifiers(.shift)
      let cursor = ToolCursor.symbol(tool == .brush ? "paintbrush.pointed" : "pencil.tip", .constrain)
      XCTAssertEqual(canvas.toolCursor,cursor)
      canvas.mouseDown(with:try event(.leftMouseDown,x:104,time:2,flags:[.shift]))
      let gesture = try XCTUnwrap(store.brushGesture)
      XCTAssertTrue(gesture.connectsToPrevious)
      XCTAssertEqual(gesture.points.map(\.x),[24,104])
      canvas.updateCursorModifiers([])
      XCTAssertEqual(canvas.toolCursor,cursor)
      canvas.mouseUp(with:try event(.leftMouseUp,x:104,time:2.01))
      await store.geometryTask?.value; await store.renderTask?.value
      XCTAssertNil(store.error)
      XCTAssertEqual(store.session.undoStack.count,2)
      let final = store.document
      XCTAssertEqual(try Renderer.composite(final).pixel(x:64,y:48),.black)
      let action = try store.stopRecordingAction()
      XCTAssertTrue(store.canConnectBrushStroke)
      var replay = first; try action.apply(to:&replay)
      XCTAssertTrue(replay == final,"Action replay must reproduce the connected stroke")
      let helper = AutomationTests()
      try await helper.withService(brushes:BrushLibrary(),pressedMouseButtons:{0}) { service,file in
        file.store.session = EditorSession(document:first)
        try service.share(file)
        var parameters = ["points":BrushAPI.json(gesture.points),"brush":BrushAPI.json(gesture.brush)]
        if let request = gesture.paintingRequest {
          parameters["tool"] = request.tool.rawValue
          parameters["options"] = ["autoErase":request.options.autoErase]
        }
        let command = tool == .brush ? "paint.stroke" : "paint.tool"
        let status = try await helper.edit(service,file,command,parameters)
        XCTAssertEqual(status,200)
        XCTAssertTrue(file.store.document == final,"Explicit API samples must reproduce the connected stroke")
        XCTAssertEqual(file.store.session.undoStack.count,1)
      }
      await store.undo(); await store.renderTask?.value
      XCTAssertEqual(store.document,first)
      XCTAssertFalse(store.canConnectBrushStroke)
      store.playAction(action); await store.geometryTask?.value
      XCTAssertTrue(store.document == final)
      _ = await store.requestHistory(redo:false).value
      XCTAssertTrue(store.document == first)
    }
  }

  @MainActor func testPencilActionHTTPAndAutoEraseSampleThePlaybackTarget() async throws {
    var source = try CraftDocument(width:64,height:48)
    let id = try XCTUnwrap(source.activeLayerID)
    guard case .raster(var pixels) = source.layers[0].content else { return XCTFail("Expected raster layer") }
    pixels.setPixel(x:16,y:16,.black)
    source.layers[0].content = .raster(pixels)
    var brush = Brush()
    brush.size = 3
    brush.color = .black
    brush.backgroundColor = .white
    let samples = [StrokePoint(x:16.5,y:16.5),StrokePoint(x:36.5,y:16.5)]

    let library = ActionLibrary(), helper = AutomationTests()
    try await helper.withService(actions:library,pressedMouseButtons:{0}) { service,file in
      file.store.session = EditorSession(document:source)
      try service.share(file)
      let record = try await helper.edit(service,file,"actions.manage",["operation":"record","name":"Pencil Auto Erase"])
      XCTAssertEqual(record,200)
      let paint = try await helper.edit(service,file,"paint.tool",[
        "tool":"pencil","points":BrushAPI.json(samples),"brush":BrushAPI.json(brush),"options":["autoErase":true]])
      XCTAssertEqual(paint,200)
      let stop = try await helper.edit(service,file,"actions.manage",["operation":"stop"])
      XCTAssertEqual(stop,200)
      let action = try XCTUnwrap(library.file.actions.first)
      guard case .pencilStroke = try XCTUnwrap(action.steps.first).operation else {
        return XCTFail("Expected a portable Pencil step")
      }
      let saved = try library.exportFile(action.id)
      let decoded = try ActionLibraryFile.decode(saved)
      XCTAssertEqual(decoded.version,62)
      var older = try XCTUnwrap(JSONSerialization.jsonObject(with:saved) as? [String:Any])
      older["version"] = 61
      XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:older)))
      XCTAssertEqual(try Renderer.composite(file.store.document).pixel(x:16,y:16),.white)

      let destination = try CraftDocument(width:64,height:48)
      XCTAssertNotEqual(destination.activeLayerID,id)
      file.store.session = EditorSession(document:destination)
      let status = try await helper.edit(service,file,"actions.play",["actionID":action.id.uuidString])
      XCTAssertEqual(status,200)
      XCTAssertEqual(try Renderer.composite(file.store.document).pixel(x:24,y:16),.black)
      XCTAssertEqual(file.store.session.undoStack.count,1)
      let undo = try await helper.edit(service,file,"history.undo")
      XCTAssertEqual(undo,200)
      XCTAssertTrue(file.store.document == destination)
    }
  }

  @MainActor func testBrushConnectionRejectsWrongTargetsAndCancelledEndpoints() async throws {
    var document = try CraftDocument(width:128,height:96)
    document.layers[0].mask = try Surface(width:128,height:96,fill:.white)
    let store = EditorStore(document:document,brushes:BrushLibrary())
    defer { store.cancelBrush(); store.renderTask?.cancel() }
    store.tool = .brush; store.brush.color = .black
    store.beginBrush(.init(x:20,y:40),zoom:1)
    store.finishBrush(); await store.geometryTask?.value
    XCTAssertTrue(store.canConnectBrushStroke)
    store.beginBrush(.init(x:45,y:40),zoom:1)
    store.cancelBrush(); await store.renderTask?.value
    store.maskEditingLayerID = document.layers[0].id
    XCTAssertFalse(store.canConnectBrushStroke)
    store.beginBrush(.init(x:80,y:40),zoom:1,connectToPrevious:true)
    XCTAssertEqual(store.brushGesture?.points.map(\.x),[80]); store.cancelBrush()
    store.maskEditingLayerID = nil
    store.beginBrush(.init(x:90,y:40),zoom:1,connectToPrevious:true)
    XCTAssertEqual(store.brushGesture?.points.map(\.x),[20,90]); store.cancelBrush()
    store.session = EditorSession(document:try CraftDocument(width:128,height:96))
    XCTAssertFalse(store.canConnectBrushStroke)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    for i in 0..<16 {
      let flags: [NSEvent.ModifierFlags] = [.control,.command,.option,.shift]
      let modifiers = flags.enumerated().reduce(into:NSEvent.ModifierFlags()) { flags,bit in
        if i & (1<<bit.offset) != 0 { flags.insert(bit.element) }
      }
      XCTAssertEqual(ToolCursor.connectsBrushStroke(modifiers),[8,9,10,11].contains(i))
    }
  }

  @MainActor func testNativeGesturePreviewCancelCommitAndRecordedPlayback()async throws {
    let doc=try CraftDocument(width:64,height:48),store=EditorStore(document:doc,actions:ActionLibrary(),brushes:BrushLibrary())
    defer {store.renderTask?.cancel();store.cancelBrush()}
    store.tool = .brush;store.brush.size=10;store.brush.color=Pixel(1,0,0);store.brushOptions.flow=0.5
    try store.startRecordingAction(name:"Paint",set:"Test")
    store.beginBrush(.init(x:12,y:20,time:0),zoom:1);store.extendBrush(.init(x:44,y:25,pressure:0.4,tiltX:30,rotation:45,time:100));await store.brushPreviewTask?.value;await store.renderTask?.value
    XCTAssertTrue(store.hasToneDraft);XCTAssertEqual(store.document,doc);XCTAssertNotNil(store.brushPreviewCommand)
    var expected=doc;try XCTUnwrap(store.brushPreviewCommand).apply(to:&expected)
    XCTAssertTrue(store.surface == (try Renderer.composite(expected)),"Preview must include every queued sample");store.cancelBrush();await store.renderTask?.value;XCTAssertEqual(store.document,doc);XCTAssertFalse(store.hasToneDraft)
    store.beginBrush(.init(x:12,y:20,time:0),zoom:1);store.extendBrush(.init(x:44,y:25,time:100));let command=try XCTUnwrap(store.brushGesture?.command);expected=doc;try command.apply(to:&expected)
    store.finishBrush();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.document,expected);XCTAssertEqual(store.session.undoStack.count,1)
    let action=try store.stopRecordingAction();let saved=try store.actions.exportFile(action.id);XCTAssertEqual(try ActionLibraryFile.decode(saved).version,2)
    var replay=doc;try action.apply(to:&replay);XCTAssertEqual(replay,expected)
    _=await store.requestHistory(redo:false).value;XCTAssertEqual(store.document,doc);_=await store.requestHistory(redo:true).value;XCTAssertEqual(store.document,expected)
    let legacy=RecordedAction(name:"Legacy",steps:[.init(name:"Select",operation:.select(.active))]);try store.actions.save(legacy)
    XCTAssertEqual(try ActionLibraryFile.decode(store.actions.exportFile(legacy.id)).version,store.actions.file.version)
    var downgraded=try JSONSerialization.jsonObject(with:saved) as! [String:Any];downgraded["version"]=1;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:downgraded)))
  }
  @MainActor func testFactoryBrushSmoothingAndOtherToolAmountsAreIndependent() throws {
    let store = EditorStore(document: try CraftDocument(width: 160, height: 100), brushes: BrushLibrary())
    defer { store.cancelBrush(); store.renderTask?.cancel() }
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0.1)
    XCTAssertEqual(store.brushOptions.spacing, 0.25)
    func apiBrush(_ tool: PaintTool) throws -> Brush {
      let request = try AutomationCommand(data: JSONSerialization.data(withJSONObject: [
        "command": "paint.tool", "revision": "test", "parameters": ["tool": tool.rawValue, "points": [["x": 18, "y": 22]]]
      ]))
      return try request.paintingRequest(store: store).brush
    }
    XCTAssertEqual(try apiBrush(.pencil).settings?.smoothing.amount, 0)
    store.tool = .brush
    try store.selectBrush(store.brushes.file.presets[0].id)
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0.1)
    store.brushOptions.smoothing.amount = 0
    store.brush.size = 48
    store.tool = .eraser
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0)
    XCTAssertEqual(store.brush.size, 48)
    store.brushOptions.smoothing.amount = 0.37
    XCTAssertEqual(try apiBrush(.brush).settings?.smoothing.amount, 0)
    store.tool = .pencil
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0.37)
    store.tool = .brush
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0)
    store.tool = .selectionBrush
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0.37)
    store.tool = .brush
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0)
    XCTAssertTrue(store.session.undoStack.isEmpty)

    let source = EditorStore(document: store.document, brushes: BrushLibrary())
    defer { source.renderTask?.cancel() }
    source.tool = .brush; source.brush = store.brush
    source.tool = .pencil; source.brushOptions.smoothing.amount = 0.59; source.tool = .brush
    XCTAssertEqual(source.brush, store.brush)
    let revision = store.brushRevision
    store.inheritBrushSettings(from: source)
    XCTAssertGreaterThan(store.brushRevision, revision)
    store.tool = .eraser
    XCTAssertEqual(store.brushOptions.smoothing.amount, 0.59)
  }

  @MainActor func testFactorySmoothingThroughDesktopAndHTTPAndLegacyReplay() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), brushes: BrushLibrary(), pressedMouseButtons: { 0 }) { service, file in
      let document = try CraftDocument(width: 168, height: 128)
      let store = file.store
      store.session = EditorSession(document: document)
      try service.share(file)
      let points: [StrokePoint] = [.init(x: 18, y: 38, time: 0), .init(x: 66, y: 95, time: 8),
        .init(x: 105, y: 20, time: 16), .init(x: 150, y: 86, time: 24)]
      let input = BrushAPI.json(points)
      let metadata = try XCTUnwrap(BrushAPI.capabilities["factoryBrush"] as? [String: Any])
      XCTAssertEqual(metadata["smoothingAmount"] as? Double, 0.1)
      XCTAssertEqual(store.brushOptions.smoothing.amount, 0.1)

      store.tool = .brush
      try store.startRecordingAction(name: "Factory Brush", set: "Test")
      store.beginBrush(try XCTUnwrap(points.first), zoom: 1)
      for point in points.dropFirst() { store.extendBrush(point) }
      XCTAssertEqual(store.brushGesture?.brush.settings?.smoothing.amount, 0.1)
      store.finishBrush(); await store.geometryTask?.value; await store.renderTask?.value
      XCTAssertNil(store.error)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let smoothed = store.document
      let recorded = try store.stopRecordingAction()
      let exported = try store.actions.exportFile(recorded.id)
      let imported = try XCTUnwrap(try ActionLibraryFile.decode(exported).actions.first)
      var replay = document; try imported.apply(to: &replay)
      XCTAssertEqual(replay, smoothed)

      await store.undo()
      store.tool = .move
      var status = try await helper.edit(service, file, "paint.stroke", ["points": input])
      XCTAssertEqual(status, 200)
      XCTAssertEqual(store.document, smoothed)
      await store.undo()
      status = try await helper.edit(service, file, "paint.stroke", ["points": input,
        "brush": ["settings": ["smoothing": ["amount": 0]]]])
      XCTAssertEqual(status, 200)
      var brush = store.brush
      brush.settings!.smoothing.amount = 0
      var explicitZero = document
      try Command.stroke(document.layers[0].id, points, brush).apply(to: &explicitZero)
      XCTAssertEqual(store.document, explicitZero)
      XCTAssertFalse(explicitZero == smoothed, "Explicit zero must produce a different stroke on the corner fixture")
      XCTAssertEqual(store.brushOptions.smoothing.amount, 0.1)
      await store.undo()

      var legacy = store.brush
      legacy.settings = nil
      let legacyStep = RecordedActionStep(name: "Legacy Brush", operation: .stroke(.active, points, legacy, mask: false))
      let legacyAction = RecordedAction(name: "Legacy Brush", steps: [legacyStep])
      try store.actions.save(legacyAction)
      let legacyFile = try ActionLibraryFile.decode(store.actions.exportFile(legacyAction.id))
      let decoded = try XCTUnwrap(legacyFile.actions.first)
      var originalLegacy = document, decodedLegacy = document
      try Command.stroke(document.layers[0].id, points, legacy).apply(to: &originalLegacy)
      try decoded.apply(to: &decodedLegacy)
      XCTAssertEqual(decodedLegacy, originalLegacy)
      XCTAssertEqual(store.document, document)
    }
  }

  @MainActor func testLibraryAtomicPersistenceDefineAndPresetLocks()async throws {
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:folder)}
    let url=folder.appendingPathComponent("Brushes.photatobrushes"),library=BrushLibrary(persistenceURL:url)
    var doc=try CraftDocument(width:8,height:8);var s=try Surface(width:8,height:8,fill:.white);s.setPixel(x:2,y:2,.black);doc.layers[0].content = .raster(s)
    let store=EditorStore(document:doc,brushes:library);defer{store.renderTask?.cancel()}
    let preset=try await store.defineBrush(name:"Ink Tip");XCTAssertEqual(preset.brush.settings?.tip?.bytes[18],255);XCTAssertEqual(store.document,doc)
    XCTAssertEqual(BrushLibrary(persistenceURL:url).file.presets,library.file.presets)
    store.brushOptions.shape.enabled=true;store.brushOptions.shape.size.jitter=0.8;store.brushOptions.lockedSections=["shape"]
    try store.selectBrush(library.file.presets[0].id);XCTAssertEqual(store.brushOptions.shape.size.jitter,0.8)
    let before=try Data(contentsOf:url);var bad=preset;bad.name="";XCTAssertThrowsError(try library.save(bad));XCTAssertEqual(try Data(contentsOf:url),before)
    try library.remove(preset.id);let exported=try library.exportData(library.file.presets[0].id,abr:true);let count=library.file.presets.count;XCTAssertEqual(try library.importData(exported,abr:true),[]);XCTAssertEqual(library.file.presets.count,count+1)
    try Data("invalid".utf8).write(to:url);let damaged=BrushLibrary(persistenceURL:url);XCTAssertNotNil(damaged.loadError);XCTAssertThrowsError(try damaged.save(preset));XCTAssertEqual(try Data(contentsOf:url),Data("invalid".utf8))
  }
  @MainActor func testHTTPBrushSettingsPresetsStrokeEqualityAndGuards()async throws {
    let helper=AutomationTests(),library=BrushLibrary()
    try await helper.withService(actions:ActionLibrary(),brushes:library,pressedMouseButtons:{0}){service,document in
      let doc=try CraftDocument(width:64,height:48);document.store.session=EditorSession(document:doc);try service.share(document)
      let configured:[String:Any]=["size":10,"color":["r":1,"g":0,"b":0,"a":1],"settings":["flow":0.5,"spacing":0.5,"shape":["enabled":true,"size":["control":"penPressure"]],"symmetry":["mode":"vertical","center":["x":32,"y":24]],"seed":21]]
      var status=try await helper.edit(service,document,"brush.configure",["brush":configured]);XCTAssertEqual(status,200)
      status=try await helper.edit(service,document,"brush.presets",["operation":"save","name":"API Brush","includeColor":true]);XCTAssertEqual(status,200);XCTAssertEqual(library.file.presets.last?.name,"API Brush")
      let points:[StrokePoint]=[.init(x:12,y:12,pressure:0.5,tiltX:30,time:0),.init(x:20,y:36,time:150)]
      let params:[String:Any]=["points":BrushAPI.json(points),"target":"pixels"]
      var expected=doc;try Command.stroke(doc.layers[0].id,points,document.store.brush).apply(to:&expected)
      status=try await helper.edit(service,document,"paint.stroke",params);XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,expected);XCTAssertEqual(document.store.session.undoStack.count,1)
      status=try await helper.edit(service,document,"paint.stroke",params,revision:"stale");XCTAssertEqual(status,409)
      document.store.tool = .brush;document.store.beginBrush(.init(x:1,y:1),zoom:1)
      status=try await helper.edit(service,document,"paint.stroke",params);XCTAssertEqual(status,409);document.store.cancelBrush()
      for patch:[String:Any] in [["settings":["flow":true]],["settings":["shape":["unknown":1]]],["size":0],["settings":["tip":["width":2,"height":2,"bytes":"AA=="]]],["settings":["symmetry":["count":1.5]]],["settings":["mode":"unknown"]]] {
        status=try await helper.edit(service,document,"brush.configure",["brush":patch]);XCTAssertEqual(status,400)
      }
      XCTAssertEqual(document.store.document,expected);status=try await helper.edit(service,document,"history.undo");XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,doc)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:BrushAPI.capabilities));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:document.store.brushState))
    }
  }
  @MainActor func testAPIAllMaskTargetsAndDefinitionRevocation()async throws {
    let helper=AutomationTests(),library=BrushLibrary()
    try await helper.withService(brushes:library,pressedMouseButtons:{0}){service,document in
      var doc=try CraftDocument(width:32,height:24);let layer=doc.layers[0].id
      doc.layers[0].mask=try Surface(width:32,height:24,fill:.white)
      try SmartObjectIO.convert(in:doc,selected:[layer]).apply(to:&doc)
      doc.layers[0].mask=try Surface(width:32,height:24,fill:.white)
      doc.layers[0].smartFilters = .init();doc.layers[0].smartFilters!.mask=try Surface(width:32,height:24,fill:.white)
      let alpha=AlphaChannel(name:"Test",pixels:try Surface(width:32,height:24,fill:.white))
      try Command.channel(.create(alpha)).apply(to:&doc);try Command.channel(.quickMask(true,.init())).apply(to:&doc)
      document.store.session=EditorSession(document:doc);try service.share(document)
      for target in ["layerMask","smartFilterMask","alpha","quickMask"] {
        var p:[String:Any]=["target":target,"points":[["x":10,"y":10]],"brush":["size":8,"color":["r":0,"g":0,"b":0,"a":1],"settings":["flow":0.7]]]
        if target=="alpha"{p["channelID"]=alpha.id.uuidString}
        let input=try JSONSerialization.data(withJSONObject:["command":"paint.stroke","revision":"test","parameters":p])
        let command=try AutomationCommand(data:input)
        var expected=document.store.document;try command.brushStroke(document:expected,current:document.store.brush,library:library.file).apply(to:&expected)
        let status=try await helper.edit(service,document,"paint.stroke",p);XCTAssertEqual(status,200,target);XCTAssertEqual(document.store.document,expected)
      }
    }
    var dark=try CraftDocument(width:16,height:16);dark.layers[0].content = .raster(try Surface(width:16,height:16,fill:.black))
    let store=EditorStore(document:dark,brushes:library);defer{store.renderTask?.cancel()}
    let original=library.file
    do {_ = try await store.defineBrush(name:"Rejected"){throw AutomationFailure(status:409,message:"revoked")};XCTFail("Commit guard ignored")}catch{}
    XCTAssertEqual(library.file,original);XCTAssertFalse(store.geometryBusy)
  }
  func testExpandedMaskSymmetryAndTypedTargets()throws {
    var doc=try CraftDocument(width:64,height:48);let id=doc.layers[0].id;doc.layers[0].mask=try Surface(width:1,height:1,fill:.white)
    var brush=Brush();brush.size=10;brush.color = .black;brush.settings = .init();brush.settings!.symmetry.mode = .vertical;brush.settings!.symmetry.center = .init(32,24)
    try Command.maskStroke(id,[.init(x:10,y:20)],brush).apply(to:&doc)
    XCTAssertGreaterThan(doc.layers[0].mask!.width,45)
    let result=try NativeArchive.decode(NativeArchive.encodeChunked(doc));XCTAssertEqual(result,doc)
  }
  @MainActor func testCanvasPointerStrokeEscapeAndFrozenToolSettings()async throws {
    let store=EditorStore(document:try CraftDocument(width:64,height:48),brushes:BrushLibrary());defer{store.cancelBrush();store.renderTask?.cancel()}
    store.tool = .brush;store.brush.size=8;store.brush.color = .black
    let canvas=CraftCanvas(store:store);canvas.frame=NSRect(x:0,y:0,width:320,height:240)
    func event(_ type:NSEvent.EventType,_ x:Double,_ time:Double)throws->NSEvent {
      let point=canvas.viewPoint(CGPoint(x:x,y:24))
      return try XCTUnwrap(NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:time,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1))
    }
    canvas.mouseDown(with:try event(.leftMouseDown,10,1));canvas.mouseDragged(with:try event(.leftMouseDragged,25,1.1))
    XCTAssertEqual(store.brushGesture?.points.count,2);store.brush.size=80
    XCTAssertEqual(store.brushGesture?.brush.size,8)
    canvas.mouseUp(with:try event(.leftMouseUp,30,1.2));await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1);let before=store.document
    canvas.mouseDown(with:try event(.leftMouseDown,15,2))
    let escape=try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:2.1,windowNumber:0,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53))
    canvas.keyDown(with:escape);canvas.mouseUp(with:try event(.leftMouseUp,20,2.2))
    XCTAssertNil(store.brushGesture);XCTAssertEqual(store.document,before);XCTAssertNil(canvas.airbrushTimer)
  }
  @MainActor func testToolRevisionIgnoresNoopsAndDoesNotInvalidateDocumentClose()async throws {
    try await AutomationTests().withService(brushes:BrushLibrary(),pressedMouseButtons:{0}){service,document in
      let store=document.store,initial=service.revision(document.store),closing=service.documentClosingRevision
      let same=store.brush;store.brush=same;XCTAssertEqual(service.revision(store),initial)
      store.brush.size += 1;XCTAssertNotEqual(service.revision(store),initial);XCTAssertEqual(service.documentClosingRevision,closing)
      try store.executeEditorCommand(.renameLayer(store.document.layers[0].id,"Changed"));XCTAssertNotEqual(service.documentClosingRevision,closing)
    }
  }
  @MainActor func testFactoryBindingsAndOffscreenPanels()throws {
    try PhotoshopMenuTests().withMenus{app,menu in
      let all=PhotoshopMenuTests().allItems(menu)
      for (path,selector) in [("Window > Brush Settings",#selector(AppDelegate.showBrushSettings)),("Window > Brushes",#selector(AppDelegate.showBrushes)),("Edit > Define Brush Preset…",#selector(AppDelegate.defineBrushPreset))] {
        let item=try XCTUnwrap(all.first{$0.identifier?.rawValue==path});XCTAssertEqual(item.action,selector)
        if path=="Window > Brush Settings"{XCTAssertEqual(item.keyEquivalent,"\u{f708}");XCTAssertTrue(app.validateMenuItem(item))}
      }
    }
    let store=EditorStore(document:try CraftDocument(width:64,height:48),brushes:BrushLibrary());defer{store.renderTask?.cancel()}
    let view=NSHostingView(rootView:BrushSettingsPanel(store:store));view.frame=NSRect(x:0,y:0,width:600,height:500);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,500)
    let presets=NSHostingView(rootView:BrushesPanel(store:store));presets.frame=NSRect(x:0,y:0,width:500,height:600);presets.layoutSubtreeIfNeeded();XCTAssertGreaterThan(presets.fittingSize.width,350)
  }
}
