import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ColorChannelActionTests: XCTestCase {
  @MainActor func testNativeComponentBrushRoundTripsAcrossModesAndDepths() async throws {
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      var original = try ModePaintingWorkflowTests().document(mode, depth: depth)
      original.selection = .init(x: 2, y: 2, width: 6, height: 5)
      let components: Set<Int> = mode.componentCount == 1 ? [0] : [0, mode.componentCount - 1]
      let store = EditorStore(document: original, actions: ActionLibrary())
      defer { store.renderTask?.cancel() }
      try store.selectModeComponents(components)
      try store.setAllowToolRecording(true)
      try store.startRecordingAction(name: "Paint channels", set: "Tests")
      store.tool = .brush; store.brush.color = .black; store.brush.size = 3
      store.beginBrush(.init(x: 4.5, y: 4.5), zoom: 1)
      store.extendBrush(.init(x: 9.5, y: 4.5))
      let stroke = try XCTUnwrap(store.brushGesture)
      store.finishBrush()
      await store.geometryTask?.value
      XCTAssertNil(store.error, "\(mode)/\(depth)")
      let action = try store.stopRecordingAction()
      XCTAssertEqual(action.steps.count, 1)
      guard case .colorChannelBrushStroke = action.steps.first?.operation else {
        return XCTFail("Expected a process channel Brush step for \(mode)/\(depth)")
      }
      let bytes = try store.actions.exportFile(action.id)
      XCTAssertEqual(try ActionLibraryFile.decode(bytes).version, 70)
      let recordedID = try XCTUnwrap(original.activeLayerID)
      XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(recordedID.uuidString))
      let replayAction = try XCTUnwrap(ActionLibraryFile.decode(bytes).actions.first)

      var destination = try ModePaintingWorkflowTests().document(mode, depth: depth)
      destination.selection = .init(x: 5, y: 3, width: 5, height: 4)
      let destinationID = try XCTUnwrap(destination.activeLayerID)
      XCTAssertNotEqual(recordedID, destinationID)
      var expected = destination
      try ModeComponentEdit(layerID: destinationID, components: components, operation: .stroke(stroke.points, stroke.brush))
        .apply(to: &expected)
      XCTAssertNotEqual(expected, destination)
      let replay = EditorStore(document: destination, actions: ActionLibrary())
      defer { replay.renderTask?.cancel() }
      try replay.selectModeComponents(components)
      XCTAssertTrue(replay.canPlayAction(replayAction))
      replay.playAction(replayAction)
      await replay.geometryTask?.value
      XCTAssertNil(replay.error, "\(mode)/\(depth)")
      XCTAssertEqual(replay.document, expected)
      XCTAssertEqual(replay.effectiveComponentTargets, components)
      XCTAssertEqual(replay.session.undoStack.count, 1)
      await replay.undo()
      XCTAssertEqual(replay.document, destination)
      await replay.redo()
      XCTAssertEqual(replay.document, expected)
    } }
  }

  @MainActor func testColorChannelPlayRejectsChangedTargetAndOlderFileVersion() async throws {
    let original = try ModePaintingWorkflowTests().document(.rgb, depth: .u16)
    let store = EditorStore(document: original, actions: ActionLibrary())
    defer { store.renderTask?.cancel() }
    let layer = try XCTUnwrap(original.activeLayerID)
    let edit = Command.modeComponents(.init(layerID: layer, components: [0],
      operation: .stroke([.init(x: 5.5, y: 4.5)], Brush())))
    let action = RecordedAction(name: "Red", steps: [.init(name: "Brush",
      operation: ActionOperation(recording: edit, in: original))])
    try store.actions.save(action)
    let bytes = try store.actions.exportFile(action.id)
    var old = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    old["version"] = 69
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject: old)))
    let legacy = RecordedAction(name: "Quick Mask", steps: [.init(name: "Enter",
      operation: .quickMaskEdit(.transition(true, .init())))])
    let legacyFile = try ActionLibraryFile(actions: [legacy]).encoded()
    XCTAssertEqual(try ActionLibraryFile.decode(legacyFile).version, 69)

    try store.selectModeComponents([0])
    var validations = 0
    store.playPreparedAction(action, validate: {
      validations += 1
      if validations == 2 { store.modeComponentTargets = [1] }
    })
    await store.geometryTask?.value
    XCTAssertEqual(validations, 2)
    XCTAssertTrue(store.error?.contains("target changed") == true)
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertFalse(store.canPlayAction(action))
  }

  private let strokeParameters: [String: Any] = [
    "points": [["x": 4.5, "y": 4.5, "pressure": 0.7], ["x": 7.5, "y": 4.5, "pressure": 0.9]],
    "brush": ["size": 3, "hardness": 1, "color": ["r": 0, "g": 0, "b": 0, "a": 1]]
  ]

  @MainActor func testHTTPRecordsBothProcessStrokeRoutesAndRejectsMismatchedPlayback() async throws {
    let helper = AutomationTests(), library = ActionLibrary()
    let original = try ModePaintingWorkflowTests().document(.cmyk, depth: .u16)
    try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, file in
      let store = file.store, selection = ["components": [0, 2]]
      store.session = EditorSession(document: original)
      try service.share(file)
      let target = try await helper.edit(service, file, "mode.channel.select", selection)
      try store.setAllowToolRecording(true)
      let start = try await helper.edit(service, file, "actions.manage", ["operation": "record", "name": "Process strokes"])
      var fields = self.strokeParameters
      fields["components"] = [0, 2]; fields["action"] = "stroke"
      fields["layerID"] = try XCTUnwrap(original.activeLayerID).uuidString
      let typedStroke = try await helper.edit(service, file, "mode.channel.edit", fields)
      let paintStroke = try await helper.edit(service, file, "paint.stroke", self.strokeParameters)
      let stop = try await helper.edit(service, file, "actions.manage", ["operation": "stop"])
      XCTAssertEqual([target, start, typedStroke, paintStroke, stop], Array(repeating: 200, count: 5))
      let action = try XCTUnwrap(library.file.actions.first)
      XCTAssertEqual(action.steps.count, 2)
      XCTAssertTrue(action.steps.allSatisfy { if case .colorChannelBrushStroke = $0.operation { return true }; return false })
      let result = store.document
      XCTAssertNotEqual(result, original)
      store.session = EditorSession(document: original)
      try store.selectModeComponents([1])
      let play = ["actionID": action.id.uuidString]
      let rejected = try await helper.edit(service, file, "actions.play", play)
      XCTAssertEqual(rejected, 422)
      XCTAssertEqual(store.document, original)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      try store.selectModeComponents([0, 2])
      let accepted = try await helper.edit(service, file, "actions.play", play)
      XCTAssertEqual(accepted, 200)
      XCTAssertEqual(store.document, result)
      XCTAssertEqual(store.effectiveComponentTargets, [0, 2])
      XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo()
      XCTAssertEqual(store.document, original)
      let incompatible = try ModePaintingWorkflowTests().document(.lab, depth: .u16)
      store.session = EditorSession(document: incompatible)
      try store.selectModeComponents([])
      let wrongMode = try await helper.edit(service, file, "actions.play", play)
      XCTAssertEqual(wrongMode, 422)
      XCTAssertEqual(store.document, incompatible)
      XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }

  func inkDocument(duotone: Bool) throws -> CraftDocument {
    var document = try InkChannelWorkflowTests().source(duotone: duotone)
    if !duotone {
      var raster = try document.multichannelRaster()
      raster.plates[0].name = "Blue ink"
      raster.plates[1].name = "Blue ink"
      document = try document.replacingInkMode(.multichannel(raster))
    }
    return document
  }

  @MainActor func testHTTPInkActionResolvesDuplicatePlatesAndReplaysDuotone() async throws {
    for duotone in [false, true] {
      let helper = AutomationTests(), library = ActionLibrary()
      let original = try inkDocument(duotone: duotone)
      try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, file in
        let store = file.store
        let targets = duotone ? original.inkChannelTargets : [original.inkChannelTargets[1], original.inkChannelTargets[2]]
        store.session = EditorSession(document: original)
        try service.share(file)
        let select = try await helper.edit(service, file, "ink.channel.select", ["targets": targets.map(\.key)])
        try store.setAllowToolRecording(true)
        let start = try await helper.edit(service, file, "actions.manage", ["operation": "record", "name": "Ink strokes"])
        var fields = self.strokeParameters
        fields["targets"] = targets.map(\.key); fields["action"] = "stroke"
        let stroke = try await helper.edit(service, file, "ink.channel.edit", fields)
        let stop = try await helper.edit(service, file, "actions.manage", ["operation": "stop"])
        XCTAssertEqual([select, start, stroke, stop], [200, 200, 200, 200])
        let action = try XCTUnwrap(library.file.actions.first)
        guard case .colorChannelBrushStroke = action.steps.first?.operation else { return XCTFail("Missing ink stroke") }
        let bytes = try library.exportFile(action.id)
        XCTAssertEqual(try ActionLibraryFile.decode(bytes).version, 70)
        if !duotone {
          for target in targets { XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(target.key)) }
        }

        var destination = try self.inkDocument(duotone: duotone)
        destination.selection = .init(x: 4, y: 3, width: 4, height: 4)
        let next = duotone ? destination.inkChannelTargets : [destination.inkChannelTargets[1], destination.inkChannelTargets[2]]
        fields["targets"] = next.map(\.key)
        var expected = destination
        try InkChannelWorkflowTests().request("ink.channel.edit", fields).inkChannelCommand(in: destination).apply(to: &expected)
        XCTAssertNotEqual(expected, destination)
        store.session = EditorSession(document: destination)
        try store.selectInkChannels(Set(next))
        let played = try await helper.edit(service, file, "actions.play", ["actionID": action.id.uuidString])
        XCTAssertEqual(played, 200)
        XCTAssertEqual(store.document, expected)
        XCTAssertEqual(store.effectiveInkTargets, next)
        XCTAssertEqual(store.session.undoStack.count, 1)
        await store.undo()
        XCTAssertEqual(store.document, destination)
        if !duotone {
          XCTAssertEqual(try expected.inkChannel(destination.inkChannelTargets[0]),
            try destination.inkChannel(destination.inkChannelTargets[0]))
          var raster = try destination.multichannelRaster()
          raster.plates[1].name = "Different plate"
          destination = try destination.replacingInkMode(.multichannel(raster))
          store.session = EditorSession(document: destination)
          try store.selectInkChannels([])
          let missing = try await helper.edit(service, file, "actions.play", ["actionID": action.id.uuidString])
          XCTAssertEqual(missing, 422)
          XCTAssertEqual(store.document, destination)
          XCTAssertTrue(store.session.undoStack.isEmpty)
        }
      }
    }
  }
}
