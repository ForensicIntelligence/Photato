import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ActionsWorkflowTests: XCTestCase {
  @MainActor func testNativeSmartFilterMaskBrushActionSurvivesExportAndReplaysWithOneUndo() async throws {
    let filterID = UUID()
    func fixture() throws -> CraftDocument {
      var document = try CraftDocument(width: 22, height: 18, depth: .u16)
      let id = document.layers[0].id
      document.layers[0].content = .raster(try Surface(width: 22, height: 18, depth: .u16, fill: .white))
      try SmartObjectIO.convert(in: document, selected: [id]).apply(to: &document)
      var filters = SmartFilterStack()
      filters.filters = [SmartFilter(id: filterID, filter: RasterFilter(.gaussianBlur))]
      filters.mask = try Surface(width: 12, height: 10, depth: .u16, fill: .white)
      filters.maskProperties.transform = .translation(3, 2)
      document.layers[0].smartFilters = filters
      let coverage = (0..<(document.width * document.height)).map { index -> UInt8 in
        switch index % 22 { case 6: return 128; case 7...10: return 255; default: return 0 }
      }
      document.setCoverageSelection(try SelectionMask(width: 22, height: 18, bytes: coverage))
      return document
    }
    let original = try fixture(), library = ActionLibrary()
    let native = EditorStore(document: original, actions: library)
    defer { native.renderTask?.cancel() }
    let id = try XCTUnwrap(original.activeLayerID)
    try native.startRecordingAction(name: "Filter mask", set: "Tests")
    native.selectSmartFilterMask(id)
    XCTAssertTrue(native.smartFilterMaskEditing)
    native.tool = .brush
    native.brush.color = .black
    native.brush.size = 5
    native.brush.hardness = 1
    native.beginBrush(.init(x: 7.5, y: 6.5, pressure: 0.75), zoom: 1)
    native.extendBrush(.init(x: 9.5, y: 7.5, pressure: 0.9))
    native.finishBrush()
    await native.geometryTask?.value
    XCTAssertNil(native.error)
    XCTAssertEqual(native.session.undoStack.count, 1)
    XCTAssertNotEqual(native.document.layers[0].smartFilters?.mask, original.layers[0].smartFilters?.mask)
    XCTAssertEqual(native.document.layers[0].smartObject, original.layers[0].smartObject)
    let action = try native.stopRecordingAction()
    XCTAssertEqual(action.steps.count, 1)
    guard case .targetedBrushStroke = action.steps.first?.operation else { return XCTFail("Expected a targeted Brush step") }
    let bytes = try library.exportFile(action.id)
    XCTAssertEqual(try ActionLibraryFile.decode(bytes).version, 68)
    var older = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    older["version"] = 67
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject: older)))
    let destination = try fixture(), replayLibrary = ActionLibrary()
    let replay = EditorStore(document: destination, actions: replayLibrary)
    defer { replay.renderTask?.cancel() }
    XCTAssertNotEqual(destination.activeLayerID, original.activeLayerID)
    try replayLibrary.importFile(bytes)
    replay.playAction(try XCTUnwrap(replayLibrary.file.actions.first))
    await replay.geometryTask?.value
    XCTAssertNil(replay.error)
    XCTAssertEqual(replay.document.layers[0].smartFilters, native.document.layers[0].smartFilters)
    XCTAssertEqual(replay.document.layers[0].smartObject, destination.layers[0].smartObject)
    XCTAssertEqual(replay.document.selectionMask, destination.selectionMask)
    XCTAssertEqual(replay.session.undoStack.count, 1)
    _ = await replay.requestHistory(redo: false).value
    XCTAssertEqual(replay.document, destination)
  }

  @MainActor func testHTTPSavedBrushActionsReplayDuplicateNamesAndRejectWrongChannelTypeAtomically() async throws {
    func fixture(spot: Bool = true) throws -> CraftDocument {
      var document = try CraftDocument(width: 24, height: 16, depth: .u16)
      let gray = try Surface(width: 24, height: 16, depth: .u16, fill: .black)
      var options = ChannelDisplayOptions()
      options.indicates = .selectedAreas
      document.alphaChannels = [
        AlphaChannel(name: "Matte", pixels: gray, options: options),
        AlphaChannel(name: "Matte", pixels: gray, spot: spot ? SpotInk(color: Pixel(0.2, 0.4, 0.8)) : nil),
      ]
      return document
    }
    let source = try fixture(), library = ActionLibrary(), helper = AutomationTests()
    let channels = try XCTUnwrap(source.alphaChannels)
    try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, file in
      let store = file.store
      store.session = EditorSession(document: source)
      try service.share(file)
      let began = try await helper.edit(service, file, "actions.manage", ["operation": "record", "name": "Two Mattes"])
      XCTAssertEqual(began, 200)
      let points: [[String: Any]] = [["x": 6.5,"y": 6.5,"pressure": 0.75],["x": 10.5,"y": 7.5]]
      let brush: [String: Any] = ["size": 4, "hardness": 1, "color": ["r": 0.3,"g": 0.3,"b": 0.3,"a": 1]]
      let direct: [String: Any] = ["target": "alpha", "channelID": channels[0].id.uuidString, "points": points, "brush": brush]
      let prepared: [String: Any] = ["tool": "brush", "target": "alpha", "channelID": channels[1].id.uuidString, "points": points, "brush": brush]
      let directStatus = try await helper.edit(service, file, "paint.stroke", direct)
      let preparedStatus = try await helper.edit(service, file, "paint.tool", prepared)
      XCTAssertEqual(directStatus, 200)
      XCTAssertEqual(preparedStatus, 200)
      XCTAssertEqual(store.session.undoStack.count, 2)
      XCTAssertNotEqual(store.document.alphaChannels?[0].pixels, channels[0].pixels)
      XCTAssertNotEqual(store.document.alphaChannels?[1].pixels, channels[1].pixels)
      let stopped = try await helper.edit(service, file, "actions.manage", ["operation": "stop"])
      XCTAssertEqual(stopped, 200)
      let action = try XCTUnwrap(library.file.actions.first)
      XCTAssertEqual(action.steps.count, 2)
      for step in action.steps {
        guard case .targetedBrushStroke = step.operation else { return XCTFail("Expected a targeted Brush step") }
      }

      var destination = try fixture()
      destination.selection = .init(x: 8, y: 5, width: 7, height: 5)
      let next = try XCTUnwrap(destination.alphaChannels)
      XCTAssertNotEqual(next.map(\.id), channels.map(\.id))
      store.session = EditorSession(document: destination)
      func command(_ name: String, _ fields: [String: Any], _ id: UUID) throws -> AutomationCommand {
        var arguments = fields
        arguments["channelID"] = id.uuidString
        let data = try JSONSerialization.data(withJSONObject: ["command": name, "parameters": arguments, "revision": "fixture"])
        return try AutomationCommand(data: data)
      }
      let capturedBrush = store.brush
      let directRequest = try command("paint.stroke", direct, next[0].id)
      let preparedRequest = try command("paint.tool", prepared, next[1].id).paintingRequest(store: store)
      var expected = destination
      try directRequest.brushStroke(document: expected, current: capturedBrush, library: store.brushes.file).apply(to: &expected)
      try Command.painting(PaintingPreparation.prepare(preparedRequest, in: expected)).apply(to: &expected)
      let played = try await helper.edit(service, file, "actions.play", ["actionID": action.id.uuidString])
      XCTAssertEqual(played, 200)
      XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let undo = try await helper.edit(service, file, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(store.document, destination)
      let wrong = try fixture(spot: false)
      store.session = EditorSession(document: wrong)
      let rejected = try await helper.edit(service, file, "actions.play", ["actionID": action.id.uuidString])
      XCTAssertEqual(rejected, 422)
      XCTAssertEqual(store.document, wrong)
      XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }

  @MainActor func testNativePreparedBrushActionRecreatesPixelLayerAboveShape() async throws {
    func fixture() throws -> CraftDocument {
      var document = try CraftDocument(width: 20, height: 16)
      document.layers[0].content = .shape(.init(kind: .rectangle, width: 12, height: 10, color: .white))
      return document
    }
    let original = try fixture(), library = ActionLibrary()
    let store = EditorStore(document: original, actions: library)
    defer { store.renderTask?.cancel() }
    store.tool = .brush
    store.brush.color = Pixel(0.2, 0.5, 0.8)
    store.brush.size = 5
    try store.startRecordingAction(name: "Paint above Shape", set: "Tests")
    store.beginBrush(.init(x: 6.5, y: 5.5), zoom: 1)
    store.extendBrush(.init(x: 12.5, y: 6.5))
    store.finishBrush()
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertEqual(store.document.layers.count, 2)
    let added = try XCTUnwrap(store.document.layers.last)
    XCTAssertEqual(store.document.activeLayerID, added.id)
    XCTAssertEqual(store.document.layers.first, original.layers.first)
    let action = try store.stopRecordingAction()
    guard case .targetedBrushStroke = action.steps.first?.operation else { return XCTFail("Expected a prepared Brush step") }
    let destination = try fixture()
    let replay = EditorStore(document: destination, actions: library)
    defer { replay.renderTask?.cancel() }
    replay.playAction(action)
    await replay.geometryTask?.value
    XCTAssertNil(replay.error)
    XCTAssertEqual(replay.document.layers.count, 2)
    let result = try XCTUnwrap(replay.document.layers.last)
    XCTAssertNotEqual(result.id, added.id)
    XCTAssertEqual(replay.document.activeLayerID, result.id)
    XCTAssertEqual(result.content, added.content)
    XCTAssertEqual(replay.document.layers.first, destination.layers.first)
    XCTAssertEqual(replay.session.undoStack.count, 1)
    _ = await replay.requestHistory(redo: false).value
    XCTAssertEqual(replay.document, destination)
  }

  @MainActor func testNativeRecordSaveLoadEditReplayUndoAndPanel() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Actions.photatoactions"), library = ActionLibrary(persistenceURL: url)
    let d = try CraftDocument(width: 8, height: 6), store = EditorStore(document: d, actions: library)
    defer { store.renderTask?.cancel() }
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    try store.startRecordingAction(name: "Paint", set: "Tests")
    store.perform(.fill(d.activeLayerID!, .black)); store.perform(.opacity(d.activeLayerID!, 0.5))
    let action = try store.stopRecordingAction(); XCTAssertEqual(action.steps.count, 2)
    let restored = ActionLibrary(persistenceURL: url); XCTAssertNil(restored.loadError)
    XCTAssertEqual(restored.file.actions.first?.name, "Paint")
    let replay = EditorStore(document: d, actions: restored); defer { replay.renderTask?.cancel() }
    replay.playAction(action); await replay.geometryTask?.value
    XCTAssertNil(replay.error); XCTAssertEqual(replay.document, store.document); XCTAssertEqual(replay.session.undoStack.count, 1)
    _ = await replay.requestHistory(redo: false).value; XCTAssertEqual(replay.document, d)
    let view = NSHostingView(rootView: ActionsPanel(store: store)); view.frame = NSRect(x: 0, y: 0, width: 420, height: 520); view.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(view.fittingSize.width, 300)
    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
      view.cacheDisplay(in: view.bounds, to: bitmap)
      if let png = bitmap.representation(using: .png, properties: [:]) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try png.write(to: root.appendingPathComponent("artifacts/actions-offscreen.png"))
      }
    }
    try restored.importFile(library.exportFile()); XCTAssertEqual(restored.file.actions.count, 2)
    XCTAssertNotEqual(restored.file.actions[0].id, restored.file.actions[1].id)
    try restored.remove(action.id); XCTAssertEqual(restored.file.actions.count, 1)
  }
  @MainActor func testCorruptLibraryPreservedAndFailedSaveRetainsRecording() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("broken"), invalid = Data("broken".utf8); try invalid.write(to: url)
    let broken = ActionLibrary(persistenceURL: url); XCTAssertNotNil(broken.loadError)
    XCTAssertThrowsError(try broken.save(.init(name: "Replace"))); XCTAssertEqual(try Data(contentsOf: url), invalid)
    let blocked = ActionLibrary(persistenceURL: url.appendingPathComponent("library"))
    let store = EditorStore(document: try CraftDocument(width: 2, height: 2), actions: blocked); defer { store.renderTask?.cancel() }
    try store.startRecordingAction(name: "Retained", set: "Test"); store.perform(.opacity(store.document.activeLayerID!, 0.5))
    XCTAssertThrowsError(try store.stopRecordingAction()); XCTAssertNotNil(store.session.actionRecording)
    _ = try store.stopRecordingAction(save: false); XCTAssertNil(store.session.actionRecording)
  }
  @MainActor func testAPIRecordingPlaybackStateInvalidBusyAndStale() async throws {
    let library = ActionLibrary(), helper = AutomationTests()
    try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, document in
      try service.share(document)
      let initial = service.revision(document.store)
      let start = try await helper.edit(service, document, "actions.manage", ["operation": "record", "name": "API", "set": "Tests"]); XCTAssertEqual(start, 200)
      let stale = try await helper.edit(service, document, "actions.manage", ["operation": "list"], revision: initial); XCTAssertEqual(stale, 409)
      let fill = try await helper.edit(service, document, "layer.fill", ["layerID": document.store.document.activeLayerID!.uuidString, "r": 0.2, "g": 0.3, "b": 0.8, "a": 1]); XCTAssertEqual(fill, 200)
      let stop = try await helper.edit(service, document, "actions.manage", ["operation": "stop"]); XCTAssertEqual(stop, 200)
      let action = try XCTUnwrap(library.file.actions.first); XCTAssertEqual(action.steps.count, 1)
      let expected = document.store.document
      let undo = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo, 200)
      let play = try await helper.edit(service, document, "actions.play", ["actionID": action.id.uuidString]); XCTAssertEqual(play, 200); XCTAssertEqual(document.store.document, expected)
      let bad = try await helper.edit(service, document, "actions.manage", ["operation": "step.enable", "actionID": action.id.uuidString, "stepID": action.steps[0].id.uuidString, "enabled": "yes"]); XCTAssertEqual(bad, 400)
      let state = document.store.actionState; XCTAssertEqual((state["library"] as? [[String: Any]])?.count, 1)
      document.store.geometryBusy = true
      let busy = try await helper.edit(service, document, "actions.play", ["actionID": action.id.uuidString]); XCTAssertEqual(busy, 409); document.store.geometryBusy = false
      let disable = try await helper.edit(service, document, "actions.manage", ["operation": "step.enable", "actionID": action.id.uuidString, "stepID": action.steps[0].id.uuidString, "enabled": false]); XCTAssertEqual(disable, 200)
      XCTAssertFalse(library.file.actions[0].steps[0].enabled)
      let schema = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == "actions.manage" }); XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: schema.schema))
    }
  }
}
