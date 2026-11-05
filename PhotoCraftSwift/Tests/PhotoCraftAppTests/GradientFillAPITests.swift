import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class GradientFillAPITests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try CraftDocument(width: 64, height: 48, depth: depth)
    var fill = GradientFill(gradient: .blackToWhite, aligned: false, dither: false)
    fill.gradient.smoothness = 0.7
    var layer = Layer(name: "Owned gradient", content: .gradientFill(fill))
    layer.x = 3; layer.y = -2; layer.opacity = 0.7
    layer.mask = try Surface(width: 64, height: 48, depth: depth, fill: .white)
    try Command.addGradientFill(layer, false).apply(to: &document)
    return document
  }
  func fill(_ document: CraftDocument, _ id: UUID) throws -> GradientFill {
    guard case .gradientFill(let value) = document.layers.first(where: { $0.id == id })?.content
    else { throw CraftError.invalid("Missing owned gradient.") }
    return value
  }
  func request(_ id: UUID, _ patch: [String: Any]) throws -> AutomationCommand {
    try AutomationCommand(data: JSONSerialization.data(withJSONObject: [
      "command": GradientFillAPI.command, "revision": "owned-test",
      "parameters": ["layerID": id.uuidString, "fill": patch],
    ]))
  }
  @MainActor func close(_ store: EditorStore) {
    store.cancelGradientFill(); store.geometryTask?.cancel(); store.renderTask?.cancel()
  }

  func testPartialPatchPreservesUnrelatedFieldsMasksPlacementAndStopBits() throws {
    let original = try fixture(), id = try XCTUnwrap(original.activeLayerID)
    var expected = original, desired = try fill(original, id)
    desired.placement.angle = -45; desired.placement.scale = 0.75
    desired.placement.offsetX = 0.125; desired.placement.reverse = true
    try Command.setGradientFill(id, desired).apply(to: &expected)
    var actual = original
    try request(id, ["placement": ["angle": -45, "scale": 0.75, "offsetX": 0.125, "reverse": true]])
      .gradientFillCommand(original).apply(to: &actual)
    XCTAssertEqual(actual, expected)
    XCTAssertEqual(try NativeArchive.encode(actual), try NativeArchive.encode(expected))
    let before = try XCTUnwrap(original.layers.first { $0.id == id })
    var retained = try XCTUnwrap(actual.layers.first { $0.id == id })
    retained.content = before.content
    XCTAssertEqual(retained, before)
  }

  @MainActor func testHTTPPatchMatchesNativeEditorAndNativeBytesAtAllRGBDepths() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
      for depth in PixelDepth.allCases {
        let original = try self.fixture(depth), id = try XCTUnwrap(original.activeLayerID)
        document.store.session = EditorSession(document: original); try service.share(document)
        let native = EditorStore(document: original, gradients: GradientLibrary(), actions: ActionLibrary())
        defer { self.close(native) }
        native.beginGradientFill(editing: id)
        XCTAssertEqual(native.document, original)
        native.gradientFillDraft?.fill.placement.style = .radial
        native.gradientFillDraft?.fill.placement.scale = 1.25
        native.gradientFillDraft?.fill.placement.offsetY = -0.125
        native.gradientFillDraft?.fill.placement.reverse = true
        native.gradientFillDraft?.fill.aligned = true
        native.commitGradientFill(); await native.geometryTask?.value
        XCTAssertNil(native.error)
        let status = try await helper.edit(service, document, GradientFillAPI.command, [
          "layerID": id.uuidString, "fill": ["placement": ["style": "Radial", "scale": 1.25,
            "offsetY": -0.125, "reverse": true], "aligned": true],
        ])
        XCTAssertEqual(status, 200); XCTAssertEqual(document.store.document, native.document)
        XCTAssertEqual(try NativeArchive.encode(document.store.document), try NativeArchive.encode(native.document))
        XCTAssertEqual(document.store.session.undoStack.count, 1)
        let edited = document.store.document
        let undo = try await helper.edit(service, document, "history.undo")
        XCTAssertEqual(undo, 200); XCTAssertEqual(document.store.document, original)
        let redo = try await helper.edit(service, document, "history.redo")
        XCTAssertEqual(redo, 200); XCTAssertEqual(document.store.document, edited)
      }
    }
  }

  func testStopArraysReplaceWhileNestedGradientFieldsMerge() throws {
    let original = try fixture(), id = try XCTUnwrap(original.activeLayerID)
    let colors = [GradientColorStop(0, .rgb(Pixel(1, 0, 0)), midpoint: 0.3),
      .init(1, .rgb(Pixel(0, 0, 1)), midpoint: 0.6)]
    var desired = try fill(original, id)
    desired.gradient.colors = colors; desired.gradient.method = .stripes
    var actual = original, expected = original
    try request(id, ["gradient": ["colors": BrushAPI.json(colors), "method": "Stripes"]])
      .gradientFillCommand(original).apply(to: &actual)
    try Command.setGradientFill(id, desired).apply(to: &expected)
    XCTAssertEqual(actual, expected)
    XCTAssertEqual(try Renderer.composite(actual), try Renderer.composite(expected))
    XCTAssertEqual(try fill(actual, id).gradient.opacity, try fill(original, id).gradient.opacity)
    XCTAssertEqual(try fill(actual, id).gradient.smoothness, 0.7)
  }

  @MainActor func testInvalidBusyStaleWrongLockedAndUnknownRequestsAreAtomic() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
      let original = try self.fixture(), id = try XCTUnwrap(original.activeLayerID)
      document.store.session = EditorSession(document: original); try service.share(document)
      for bad: [String: Any] in [[:], ["typo": 1], ["placement": ["scale": 0]],
        ["placement": ["angle": true]], ["gradient": ["colors": []]],
        ["gradient": ["method": "Unknown"]], ["dither": 1], ["aligned": NSNull()]] {
        let status = try await helper.edit(service, document, GradientFillAPI.command,
          ["layerID": id.uuidString, "fill": bad])
        XCTAssertEqual(status, 400)
      }
      for target in [UUID(), original.layers[0].id] {
        let status = try await helper.edit(service, document, GradientFillAPI.command,
          ["layerID": target.uuidString, "fill": ["dither": true]])
        XCTAssertEqual(status, 404)
      }
      let stale = try await helper.edit(service, document, GradientFillAPI.command,
        ["layerID": id.uuidString, "fill": ["dither": true]], revision: "stale")
      XCTAssertEqual(stale, 409)
      document.store.beginGradientFill(editing: id)
      let busy = try await helper.edit(service, document, GradientFillAPI.command,
        ["layerID": id.uuidString, "fill": ["dither": true]])
      XCTAssertEqual(busy, 409); document.store.cancelGradientFill()
      XCTAssertEqual(document.store.document, original); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      try document.store.selectEditingChannel(.red)
      XCTAssertEqual(document.store.gradientFillState["canEditActive"] as? Bool, false)
      let component = try await helper.edit(service, document, GradientFillAPI.command,
        ["layerID": id.uuidString, "fill": ["dither": true]])
      XCTAssertEqual(component, 422)
      try document.store.selectEditingChannel(.composite)
      XCTAssertEqual(document.store.document, original)
      var locked = original; try Command.lock(id, true).apply(to: &locked)
      document.store.session = EditorSession(document: locked)
      let rejected = try await helper.edit(service, document, GradientFillAPI.command,
        ["layerID": id.uuidString, "fill": ["dither": true]])
      XCTAssertEqual(rejected, 422); XCTAssertEqual(document.store.document, locked)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }

  @MainActor func testDiscoveryStateAndWidgetReflectTheSameLiveFill() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: try self.fixture()); try service.share(document)
      document.store.tool = .gradient
      let id = try XCTUnwrap(document.store.document.activeLayerID)
      XCTAssertEqual(document.store.gradientFillState["activeLayerID"] as? String, id.uuidString)
      XCTAssertEqual(document.store.gradientFillState["canEditActive"] as? Bool, true)
      let before = try XCTUnwrap(document.store.activeGradientWidget)
      let status = try await helper.edit(service, document, GradientFillAPI.command,
        ["layerID": id.uuidString, "fill": ["placement": ["offsetX": 0.25]]])
      XCTAssertEqual(status, 200)
      let after = try XCTUnwrap(document.store.activeGradientWidget)
      XCTAssertNotEqual(before.start, after.start)
      XCTAssertEqual(after.fill, try self.fill(document.store.document, id))
      XCTAssertTrue(JSONSerialization.isValidJSONObject(GradientFillAPI.capabilities))
      let (response, body) = try await helper.request(service, path: "/v1/capabilities")
      XCTAssertEqual(response.statusCode, 200)
      let capabilities = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertNotNil(capabilities["gradientFills"])
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
      XCTAssertEqual(AutomationCommand.definitions.first { $0.name == GradientFillAPI.command }?.optionalParameters, Set<String>())
      document.store.beginGradientFill(editing: id)
      XCTAssertEqual(document.store.gradientFillState["canEditActive"] as? Bool, false)
      document.store.cancelGradientFill()
    }
  }

  @MainActor func testExplicitTargetDoesNotChangeSelectionOrOtherLayers() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
      var original = try self.fixture(); let id = try XCTUnwrap(original.activeLayerID)
      original.activeLayerID = original.layers[0].id
      document.store.session = EditorSession(document: original); try service.share(document)
      let status = try await helper.edit(service, document, GradientFillAPI.command,
        ["layerID": id.uuidString, "fill": ["dither": true]])
      XCTAssertEqual(status, 200); XCTAssertEqual(document.store.document.activeLayerID, original.activeLayerID)
      XCTAssertEqual(document.store.document.layers[0], original.layers[0])
      XCTAssertTrue(document.store.gradientFillState["activeFill"] is NSNull)
    }
  }

  @MainActor func testNativeArchiveAndRecordedCommandPlaybackRetainPatch() async throws {
    let original = try fixture(), id = try XCTUnwrap(original.activeLayerID)
    let library = ActionLibrary(), store = EditorStore(document: original, actions: library)
    defer { close(store) }
    try store.startRecordingAction(name: "Owned gradient patch", set: "Owned tests")
    try store.executeEditorCommand(request(id, ["placement": ["angle": 32], "dither": true])
      .gradientFillCommand(original))
    let action = try store.stopRecordingAction(), edited = store.document
    XCTAssertEqual(action.steps.count, 1)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(edited)), edited)
    let saved = try ActionLibraryFile.decode(library.exportFile(action.id))
    XCTAssertEqual(ActionLibraryFile.maximumVersion, 49)
    XCTAssertEqual(saved.version, 47)
    var wire = try XCTUnwrap(JSONSerialization.jsonObject(with: library.exportFile(action.id)) as? [String: Any])
    wire["version"] = 46
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject: wire)))
    wire["version"] = ActionLibraryFile.maximumVersion + 1
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject: wire)))
    var invalid = saved
    if case .gradientFill(let target, var captured) = invalid.actions[0].steps[0].operation {
      captured.placement.scale = 0
      invalid.actions[0].steps[0].operation = .gradientFill(target, captured)
    } else { XCTFail("Expected a self-contained recorded Gradient Fill") }
    XCTAssertThrowsError(try invalid.encoded())
    let legacy = RecordedAction(name: "Legacy")
    XCTAssertNoThrow(try ActionLibraryFile.decode(ActionLibraryFile(version: 46, actions: [legacy]).encoded()))

    await store.undo(); XCTAssertEqual(store.document, original)
    store.playAction(saved.actions[0]); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.document, edited)
    var other = try fixture(), otherExpected = other
    let otherID = try XCTUnwrap(other.activeLayerID), capturedFill = try fill(edited, id)
    try Command.setGradientFill(otherID, capturedFill).apply(to: &otherExpected)
    try saved.actions[0].apply(to: &other)
    XCTAssertEqual(other, otherExpected)

  }

  @MainActor func testClassicMaskGradientUsesMaskPaletteAndExplicitRampIndependently() async throws {
    for explicit in [false, true] {
      let store = EditorStore(document: try CraftDocument(width: 100, height: 40),
        gradients: GradientLibrary(), actions: ActionLibrary(), paintPalette: PaintPalette())
      defer { close(store) }
      let id = try XCTUnwrap(store.document.activeLayerID)
      store.perform(.createMask(id, .revealAll)); store.maskEditingLayerID = id
      XCTAssertEqual(store.brush.color, .white); XCTAssertEqual(store.backgroundColor, .black)
      store.tool = .gradient; store.gradientOptions.mode = .live; store.gradientOptions.dither = false
      store.gradientOptions.gradient = explicit ? .blackToWhite : .foregroundToBackground
      XCTAssertFalse(store.liveGradientMode)
      let pixels = store.activeLayer?.content
      store.beginGradient(at: .init(0, 0), zoom: 1); store.dragGradient(to: .init(100, 0))
      XCTAssertTrue(store.gradientGesture?.stroke?.mask == true)
      store.finishGradient(); await store.geometryTask?.value
      XCTAssertNil(store.error); XCTAssertEqual(store.activeLayer?.content, pixels)
      let nearStart = try XCTUnwrap(store.activeLayer?.mask?.pixel(x: 2, y: 0).r)
      if explicit { XCTAssertLessThan(nearStart, 0.1) } else { XCTAssertGreaterThan(nearStart, 0.9) }
    }
  }
}
