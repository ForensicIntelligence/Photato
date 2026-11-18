import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class QuickMaskHiddenCommandsWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try CraftDocument(width: 24, height: 16, depth: depth)
    document.selection = .init(x: 4, y: 4, width: 12, height: 8)
    return document
  }

  @MainActor func testNativeQuickMaskActionRecordsBothToolsAndReplaysWithOneUndo() async throws {
    let source = try fixture(.u16), library = ActionLibrary()
    let store = EditorStore(document: source, actions: library)
    defer { store.renderTask?.cancel() }
    try store.setAllowToolRecording(true)
    try store.startRecordingAction(name: "Refine Quick Mask", set: "Tests")
    store.toggleQuickMask()
    for tool in [EditorTool.brush, .pencil] {
      store.tool = tool
      store.brush.color = .black
      store.brush.size = 3
      let y = tool == .brush ? 7.5 : 10.5
      store.beginBrush(.init(x: 7.5, y: y, pressure: 0.9), zoom: 1)
      store.extendBrush(.init(x: 12.5, y: y, pressure: 0.8))
      store.finishBrush()
      await store.geometryTask?.value
      XCTAssertNil(store.error)
    }
    store.toggleQuickMask()
    let action = try store.stopRecordingAction()
    XCTAssertEqual(action.steps.count, 4)
    XCTAssertTrue(action.usesQuickMask)
    XCTAssertTrue(action.requiresVisibleQuickMask)
    XCTAssertTrue(action.canStartInQuickMask)
    guard case .targetedBrushStroke = action.steps[1].operation,
      case .pencilStroke = action.steps[2].operation else { return XCTFail("Expected Brush and Pencil steps") }
    let bytes = try library.exportFile(action.id)
    XCTAssertEqual(try ActionLibraryFile.decode(bytes).version, 69)
    var old = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    old["version"] = 68
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject: old)))

    var destination = try fixture(.u16)
    destination.selection = .init(x: 6, y: 6, width: 9, height: 6)
    var expected = destination
    try action.apply(to: &expected)
    XCTAssertNotEqual(expected.selectionMask, source.selectionMask)
    let replay = EditorStore(document: destination, actions: ActionLibrary())
    defer { replay.renderTask?.cancel() }
    try replay.actions.importFile(bytes)
    replay.playAction(try XCTUnwrap(replay.actions.file.actions.first))
    await replay.geometryTask?.value
    XCTAssertNil(replay.error)
    XCTAssertEqual(replay.document, expected)
    XCTAssertNil(replay.document.quickMask)
    XCTAssertNil(replay.editingChannel)
    XCTAssertEqual(replay.session.undoStack.count, 1)
    await replay.undo()
    XCTAssertEqual(replay.document, destination)
    await replay.redo()
    XCTAssertEqual(replay.document, expected)
  }

  @MainActor func testQuickMaskActionRechecksVisibilityBeforeNativeCommit() async throws {
    let store = EditorStore(document: try fixture(), actions: ActionLibrary())
    defer { store.renderTask?.cancel() }
    store.toggleQuickMask()
    XCTAssertTrue(store.canStartRecordingAction)
    try store.setAllowToolRecording(true)
    try store.startRecordingAction(name: "Existing Quick Mask", set: "Tests")
    store.tool = .brush
    store.brush.color = .black
    store.brush.size = 4
    store.beginBrush(.init(x: 8.5, y: 8.5), zoom: 1)
    store.finishBrush()
    await store.geometryTask?.value
    let action = try store.stopRecordingAction()
    XCTAssertEqual(action.steps.count, 1)
    await store.undo()
    XCTAssertTrue(store.canPlayAction(action))
    let source = store.document, history = store.session.undoStack.count
    var validations = 0
    store.playPreparedAction(action, validate: {
      validations += 1
      if validations == 2 {
        store.hiddenQuickMaskDocumentID = source.id
        store.hiddenQuickMaskID = source.quickMask?.id
      }
    })
    await store.geometryTask?.value
    XCTAssertEqual(validations, 2)
    XCTAssertTrue(store.error?.contains("visibility changed") == true)
    XCTAssertEqual(store.document, source)
    XCTAssertEqual(store.session.undoStack.count, history)
  }

  @MainActor func testHTTPQuickMaskActionRecordsEntryStrokeAndExitOnDestinationSelection() async throws {
    let helper = AutomationTests(), library = ActionLibrary(), original = try fixture(.u16)
    try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, file in
      let store = file.store
      store.session = EditorSession(document: original)
      try service.share(file)
      try store.setAllowToolRecording(true)
      let start = try await helper.edit(service, file, "actions.manage", ["operation": "record", "name": "Refine"])
      let enter = try await helper.edit(service, file, "channel.edit",
        ["action": "quickMask", "enabled": true, "indicates": "selectedAreas"])
      let brush: [String: Any] = ["size": 5, "color": ["r": 0, "g": 0, "b": 0, "a": 1]]
      let points = [["x": 16.5, "y": 9.5], ["x": 19.5, "y": 10.5]]
      let stroke = try await helper.edit(service, file, "paint.stroke", ["target": "quickMask", "points": points, "brush": brush])
      let pencil = try await helper.edit(service, file, "paint.tool",
        ["tool": "pencil", "target": "quickMask", "points": [["x": 18.5, "y": 14.5]], "brush": brush])
      let exit = try await helper.edit(service, file, "channel.edit", ["action": "quickMask", "enabled": false])
      let stop = try await helper.edit(service, file, "actions.manage", ["operation": "stop"])
      XCTAssertEqual([start, enter, stroke, pencil, exit, stop], Array(repeating: 200, count: 6))
      let action = try XCTUnwrap(library.file.actions.first)
      XCTAssertEqual(action.steps.count, 4)
      var destination = try self.fixture(.u16)
      destination.selection = nil
      var expected = destination
      try action.apply(to: &expected)
      store.session = EditorSession(document: destination)
      let result = try await helper.edit(service, file, "actions.play", ["actionID": action.id.uuidString])
      XCTAssertEqual(result, 200)
      XCTAssertEqual(store.document, expected)
      XCTAssertNil(store.editingChannel)
      XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }

  @MainActor func testHTTPQuickMaskActionsGuardHiddenPlaneAllowFiltersAndResetAfterReentry() async throws {
    let helper = AutomationTests(), library = ActionLibrary()
    let original = try fixture(.u16)
    try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, file in
      let store = file.store
      store.session = EditorSession(document: original)
      try service.share(file)
      let enter = try await helper.edit(service, file, "channel.edit", ["action": "quickMask", "enabled": true])
      let hide = try await helper.edit(service, file, "channel.view", ["target": "quickMask", "visible": false])
      XCTAssertEqual([enter, hide], [200, 200])
      XCTAssertTrue(store.canUseQuickMaskActions)
      XCTAssertFalse(store.isQuickMaskVisible)
      let old = store.document, history = store.session.undoStack.count
      let fill = RecordedActionStep(name: "Fill", operation: .pixelPaint(.fill, .channel(.quickMask), .init(color: .black)))
      let blocked = RecordedAction(name: "Hidden legacy Fill", steps: [fill])
      try library.save(blocked)
      let rejected = try await helper.edit(service, file, "actions.play", ["actionID": blocked.id.uuidString])
      XCTAssertEqual(rejected, 422)
      XCTAssertEqual(store.document, old)
      XCTAssertEqual(store.session.undoStack.count, history)
      let filter = RecordedAction(name: "Hidden Gaussian", steps: [
        .init(name: "Gaussian", operation: .quickMaskEdit(.filter(RasterFilter(.gaussianBlur)))),
      ])
      try library.save(filter)
      let filtered = try await helper.edit(service, file, "actions.play", ["actionID": filter.id.uuidString])
      XCTAssertEqual(filtered, 200)
      XCTAssertFalse(store.isQuickMaskVisible)
      XCTAssertEqual(store.document.quickMask?.id, old.quickMask?.id)
      XCTAssertNotEqual(store.document.quickMask?.pixels, old.quickMask?.pixels)
      let replacement = RecordedAction(name: "Re-enter and Fill", steps: [
        .init(name: "Exit", operation: .quickMaskEdit(.transition(false, .init()))),
        .init(name: "Enter", operation: .quickMaskEdit(.transition(true, .init()))), fill,
      ])
      try library.save(replacement)
      let replaced = try await helper.edit(service, file, "actions.play", ["actionID": replacement.id.uuidString])
      XCTAssertEqual(replaced, 200)
      XCTAssertNotEqual(store.document.quickMask?.id, old.quickMask?.id)
      XCTAssertTrue(store.isQuickMaskVisible)
      XCTAssertEqual(store.editingChannel, .quickMask)
      XCTAssertEqual(store.document.layers, original.layers)
    }
  }

  @MainActor func testHiddenFillAndInvertRejectDirectAndPreparedEditsAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      let store = EditorStore(document: try fixture(depth))
      defer { store.renderTask?.cancel() }
      store.toggleQuickMask()
      let original = store.document, history = store.session.undoStack.count
      let commands: [Command] = [.channel(.fill(.quickMask, 0, 1)), .channel(.invert(.quickMask)),
        .pixelPaint(.init(.fill, target: .channel(.quickMask), settings: .init(color: .black)))]
      let prepared = try commands.map { try PreparedEdit(command: $0, document: original) }
      try store.setQuickMaskVisibility(false)
      XCTAssertTrue(store.canUseMenuFill) // Photoshop opens Fill before rejecting its commit.
      XCTAssertTrue(store.canUsePixelPaint)
      XCTAssertFalse(store.canUseMenuPixelEdit)
      XCTAssertFalse(store.canUsePixelStroke)
      XCTAssertFalse(store.canInvertPixels)
      for (command, edit) in zip(commands, prepared) {
        XCTAssertThrowsError(try store.executeEditorCommand(command))
        XCTAssertThrowsError(try store.executeCompositePreparedEdit(edit, allowAuxiliary: true))
        XCTAssertEqual(store.document, original)
        XCTAssertEqual(store.session.undoStack.count, history)
      }
      store.fill(color: .black)
      XCTAssertEqual(store.error, EditorStore.hiddenQuickMaskFillMessage)
      store.error = nil
      store.applyPixelPaint(.fill, settings: .init(color: .black))
      XCTAssertEqual(store.error, EditorStore.hiddenQuickMaskFillMessage)
      XCTAssertFalse(store.geometryBusy)
      XCTAssertEqual(store.document, original)
      try store.setQuickMaskVisibility(true)
      XCTAssertTrue(store.canInvertPixels)
      XCTAssertNoThrow(try store.executeEditorCommand(commands[0]))
      XCTAssertEqual(store.document.layers, original.layers)
      XCTAssertEqual(store.document.quickMask?.pixels.pixel(x: 8, y: 8).r, 0)
    }
  }

  @MainActor func testHiddenGaussianPreviewCancelCommitUndoAndRedoKeepTargetAndVisibility() async throws {
    let store = EditorStore(document: try fixture())
    defer { store.renderTask?.cancel(); store.geometryTask?.cancel() }
    store.toggleQuickMask()
    try store.setQuickMaskVisibility(false)
    let original = store.document, history = store.session.undoStack.count
    XCTAssertTrue(store.canBeginFilterKind(.gaussianBlur))
    store.beginFilter(.gaussianBlur)
    await store.renderTask?.value
    XCTAssertNotNil(store.filterDraft)
    XCTAssertEqual(store.document, original)
    store.cancelFilter()
    XCTAssertEqual(store.document, original)
    store.beginFilter(.gaussianBlur)
    store.commitFilter()
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertNotEqual(store.document.quickMask, original.quickMask)
    XCTAssertEqual(store.document.layers, original.layers)
    XCTAssertEqual(store.editingChannel, .quickMask)
    XCTAssertFalse(store.isQuickMaskVisible)
    XCTAssertEqual(store.session.undoStack.count, history + 1)
    let filtered = store.document
    await store.undo()
    XCTAssertEqual(store.document, original)
    await store.redo()
    XCTAssertEqual(store.document, filtered)
    XCTAssertFalse(store.isQuickMaskVisible)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(filtered)), filtered)
  }

  @MainActor func testNativeInvertUsesRGBAndAuxiliaryPlanesWithoutAddingLayers() async throws {
    for depth in PixelDepth.allCases {
      let store = EditorStore(document: try fixture(depth))
      defer { store.renderTask?.cancel(); store.geometryTask?.cancel() }
      let original = store.document
      XCTAssertTrue(store.canInvertPixels)
      store.invertPixels()
      await store.geometryTask?.value
      XCTAssertNil(store.error)
      var expected = original
      try Command.applyAdjustment(original.layers[0].id, .invert).apply(to: &expected)
      XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.session.undoStack.last?.label, "Invert")
      XCTAssertEqual(store.document.layers.count, original.layers.count)
      await store.undo()
      XCTAssertEqual(store.document, original)
      store.toggleQuickMask()
      let mask = store.document
      store.invertPixels()
      await store.geometryTask?.value
      XCTAssertNil(store.error)
      XCTAssertEqual(store.document.layers, mask.layers)
      XCTAssertNotEqual(store.document.quickMask, mask.quickMask)
      await store.undo()
      XCTAssertEqual(store.document, mask)
    }
  }

  @MainActor func testHTTPHiddenPaintAndInvertRejectButFilterMatchesNativeHistory() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      file.store.session = EditorSession(document: try self.fixture())
      file.store.toggleQuickMask()
      try file.store.setQuickMaskVisibility(false)
      try service.share(file)
      let original = file.store.document, history = file.store.session.undoStack.count
      for params: [String: Any] in [["action":"fill", "target":"quickMask", "value":0], ["action":"invert", "target":"quickMask"]] {
        let response1 = try await helper.edit(service, file, "channel.edit", params)
        XCTAssertEqual(response1, 422)
        XCTAssertEqual(file.store.document, original)
      }
      let response2 = try await helper.edit(service, file, "pixels.fill", ["target":"quickMask", "color":[0,0,0,1]])
      XCTAssertEqual(response2, 422)
      let response3 = try await helper.edit(service, file, "pixels.stroke", ["target":"quickMask", "color":[0,0,0,1], "width":1])
      XCTAssertEqual(response3, 422)
      let response4 = try await helper.edit(service, file, "channel.edit", ["action":"fill", "target":"quickMask", "value":2])
      XCTAssertEqual(response4, 400)
      XCTAssertEqual(file.store.session.undoStack.count, history)
      let state = file.store.pixelPaintState
      XCTAssertEqual(state["canCommitFill"] as? Bool, false)
      XCTAssertEqual(state["canCommitStroke"] as? Bool, false)
      let json = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: state))
      XCTAssertNoThrow(try BrushAPI.merge(json, schema: PixelPaintAPI.stateSchema))
      let filter = RasterFilter(.gaussianBlur)
      let raw: [String: Any] = ["kind":"gaussianBlur", "radius":filter.radius]
      let status = try await helper.edit(service, file, "channel.edit", ["action":"filter", "target":"quickMask", "filter":raw])
      XCTAssertEqual(status, 200)
      guard status == 200 else { return }
      var expected = original
      try Command.channel(.filter(.quickMask, filter)).apply(to: &expected)
      XCTAssertEqual(file.store.document, expected)
      XCTAssertFalse(file.store.isQuickMaskVisible)
      XCTAssertEqual(file.store.session.undoStack.count, history + 1)
      await file.store.undo()
      XCTAssertEqual(file.store.document, original)
      try file.store.setQuickMaskVisibility(true)
      let response5 = try await helper.edit(service, file, "channel.edit", ["action":"invert", "target":"quickMask"])
      XCTAssertEqual(response5, 200)
    }
  }

  @MainActor func testHTTPPixelInvertUsesExistingApplySchemaAndMatchesDesktop() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      file.store.session = EditorSession(document: try self.fixture())
      try service.share(file)
      let original = file.store.document
      let id = original.layers[0].id.uuidString
      let status = try await helper.edit(service, file, "adjustment.apply", ["layerID":id, "adjustment":["kind":"invert"]])
      XCTAssertEqual(status, 200)
      let desktop = EditorStore(document: original)
      defer { desktop.renderTask?.cancel(); desktop.geometryTask?.cancel() }
      desktop.invertPixels()
      await desktop.geometryTask?.value
      XCTAssertEqual(file.store.document, desktop.document)
      XCTAssertEqual(file.store.document.layers.count, original.layers.count)
      await file.store.undo()
      XCTAssertEqual(file.store.document, original)
      let bad = try await helper.edit(service, file, "adjustment.apply", ["layerID":id, "adjustment":["kind":"invert", "amount":1]])
      XCTAssertEqual(bad, 400)
      let create = try await helper.edit(service, file, "adjustment.create", ["adjustment":["kind":"invert"]])
      XCTAssertEqual(create, 400)
      XCTAssertEqual(file.store.document, original)
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }

  @MainActor func testMissingQuickMaskKeepsMissingTargetErrorAndMenuUsesFactoryCommandI() throws {
    let store = EditorStore(document: try fixture())
    defer { store.renderTask?.cancel() }
    XCTAssertThrowsError(try store.executeEditorCommand(.channel(.stroke(.quickMask, [], .init())))) { error in
      XCTAssertNotEqual(error.localizedDescription, EditorStore.hiddenQuickMaskBrushMessage)
    }
    try PhotoshopMenuTests().withMenus { _, menu in
      let item = try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first { $0.identifier?.rawValue == "Image > Adjustments > Invert" })
      XCTAssertEqual(item.action, #selector(AppDelegate.invertPixels))
      XCTAssertEqual(item.keyEquivalent, "i")
      XCTAssertEqual(item.keyEquivalentModifierMask, [.command])
    }
  }

  @MainActor func testModernPaintingAPIAndPreparedRequestRespectHiddenNativeBrushTarget() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      let store = file.store
      store.session = EditorSession(document: try self.fixture())
      store.toggleQuickMask()
      let original = store.document
      var brush = Brush(); brush.size = 4; brush.color = .black
      let request = PaintToolRequest(tool: .brush, target: .channel(.quickMask), points: [.init(x: 8, y: 8)], brush: brush)
      let prepared = try PreparedEdit(command: .painting(PaintingPreparation.prepare(request, in: original)), document: original)
      XCTAssertEqual(prepared.paintingRequest?.target, .channel(.quickMask))
      try store.setQuickMaskVisibility(false)
      try service.share(file)
      let history = store.session.undoStack.count
      XCTAssertThrowsError(try store.executeCompositePreparedEdit(prepared, allowAuxiliary: true))
      for tool in ["brush", "pencil", "mixerBrush"] {
        let status = try await helper.edit(service, file, "paint.tool", ["tool":tool, "target":"quickMask", "points":[["x":8,"y":8]], "brush":["size":4]])
        XCTAssertEqual(status, 422, tool)
        XCTAssertEqual(store.document, original)
        XCTAssertEqual(store.session.undoStack.count, history)
      }
      store.tool = .brush
      store.beginBrush(.init(x: 8, y: 8), zoom: 1)
      XCTAssertNil(store.brushGesture)
      XCTAssertEqual(store.error, EditorStore.hiddenQuickMaskBrushMessage)
      store.error = nil
      try store.setQuickMaskVisibility(true)
      let shown = try await helper.edit(service, file, "paint.tool", ["tool":"brush", "target":"quickMask", "points":[["x":8,"y":8]], "brush":["size":4]])
      XCTAssertEqual(shown, 200)
      XCTAssertEqual(store.document.layers, original.layers)
      XCTAssertNotEqual(store.document.quickMask, original.quickMask)
      await store.undo()
      XCTAssertEqual(store.document, original)
    }
  }

  @MainActor func testNativeAndHTTPRGB8InvertMatchEveryIndependentPhotoshopSample() async throws {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/quick-mask-selection")
    let input = try Data(contentsOf: folder.appendingPathComponent("pixel-invert-rgb8-input.psd"))
    let reference = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("pixel-invert-rgb8-reference.json"))) as? [String: Any])
    let planes = try XCTUnwrap(reference["planes"] as? [[Int]])
    let original = try PSDCodec.read(input)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      file.store.session = EditorSession(document: original)
      try service.share(file)
      let desktop = EditorStore(document: original)
      defer { desktop.renderTask?.cancel(); desktop.geometryTask?.cancel() }
      desktop.invertPixels()
      await desktop.geometryTask?.value
      XCTAssertNil(desktop.error)
      let status = try await helper.edit(service, file, "adjustment.apply", ["layerID":try XCTUnwrap(original.activeLayerID).uuidString, "adjustment":["kind":"invert"]])
      XCTAssertEqual(status, 200)
      guard status == 200 else { return }
      XCTAssertEqual(file.store.document, desktop.document)
      XCTAssertEqual(file.store.document.layers.count, original.layers.count)
      XCTAssertEqual(file.store.document.alphaChannels, original.alphaChannels)
      let output = try Renderer.composite(desktop.document)
      XCTAssertEqual(output.width, 16)
      XCTAssertEqual(output.height, 4)
      for y in 0..<4 { for x in 0..<16 {
        let pixel = output.pixel(x: x, y: y), i = y * 16 + x
        for (component, value) in [pixel.r, pixel.g, pixel.b].enumerated() {
          XCTAssertEqual(Int((Double(value) * 255).rounded()), planes[component][i], "RGB component\(component),sample\(i)")
        }
      } }
      if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try DocumentIO.encode(file.store.document, format: .psd).write(to: directory.appendingPathComponent("pixel-invert-native.psd"))
      }
      await file.store.undo()
      XCTAssertEqual(file.store.document, original)
    }
  }
}
