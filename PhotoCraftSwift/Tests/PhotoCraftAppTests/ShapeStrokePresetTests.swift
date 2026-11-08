import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ShapeStrokePresetTests: XCTestCase {
  func definition() -> ShapeDefinition {
    var d = ShapeDefinition(geometry: .init(kind: .rectangle, width: 80, height: 50), fill: .none)
    d.stroke.paint = .init(color: .black); d.stroke.width = 6
    return d
  }
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 128, height: 96, depth: depth)
    d.layers[0].background = false
    d.layers[0].content = .raster(try Surface(width: d.width, height: d.height, depth: depth, fill: .clear))
    try Command.shape(.create("Owned rectangle", definition(), .translation(20,20))).apply(to: &d)
    return d
  }
  @MainActor func close(_ s: EditorStore) {
    s.cancelShapeProperties(); s.geometryTask?.cancel(); s.renderTask?.cancel()
  }
  @MainActor func testCanonicalFieldsCustomClassificationAndUnrelatedStrokeValues() throws {
    var original = definition().stroke
    original.dash = [8,4,2,4]; original.phase = 7; original.cap = .square
    original.alignment = .outside; original.join = .bevel; original.miterLimit = 9
    original.opacity = 0.6; original.pathContours = true
    XCTAssertEqual(ShapeStrokePreset.matching(original), .custom)
    XCTAssertEqual(ShapeStrokePreset.custom.applied(to: original), original)
    for preset in ShapeStrokePreset.selectable {
      let result = preset.applied(to: original)
      XCTAssertEqual(ShapeStrokePreset.matching(result), preset)
      XCTAssertEqual(result.width, original.width); XCTAssertEqual(result.paint, original.paint)
      XCTAssertEqual(result.alignment, original.alignment); XCTAssertEqual(result.join, original.join)
      XCTAssertEqual(result.miterLimit, original.miterLimit); XCTAssertEqual(result.opacity, original.opacity)
      XCTAssertEqual(result.pathContours, original.pathContours); XCTAssertEqual(result.phase, 0)
      if preset == .solid { XCTAssertTrue(result.dash.isEmpty); XCTAssertEqual(result.cap, .square) }
      if preset == .dashed { XCTAssertEqual(result.dash, [3,3]); XCTAssertEqual(result.cap, .butt); XCTAssertEqual(result.widthRelativeDashes, true) }
      if preset == .dotted { XCTAssertEqual(result.dash, [0,2]); XCTAssertEqual(result.cap, .round); XCTAssertEqual(result.widthRelativeDashes, true) }
      XCTAssertNoThrow(try result.validate())
    }
  }
  func testExistingRendererDrawsNonemptyDotsAndGapsAtEveryRGBDepth() throws {
    for depth in [PixelDepth.u8,.u16,.f32] {
      let original = try fixture(depth), id = try XCTUnwrap(original.activeLayerID)
      var coverages: [ShapeStrokePreset: Float] = [:], words: [ShapeStrokePreset: [UInt32]] = [:]
      for preset in ShapeStrokePreset.selectable {
        var d = original, value = definition(); value.stroke = preset.applied(to: value.stroke)
        try Command.shape(.configure(id,value)).apply(to: &d)
        let pixels = try Renderer.composite(d)
        var alpha: Float = 0, bits: [UInt32] = []
        for y in 0..<d.height { for x in 0..<d.width { let p = pixels.pixel(x:x,y:y); alpha += p.a; bits.append(p.a.bitPattern) } }
        XCTAssertGreaterThan(alpha, 0); coverages[preset] = alpha; words[preset] = bits
        XCTAssertEqual(d.layers[0], original.layers[0])
      }
      XCTAssertLessThan(try XCTUnwrap(coverages[.dashed]), try XCTUnwrap(coverages[.solid]))
      XCTAssertLessThan(try XCTUnwrap(coverages[.dotted]), try XCTUnwrap(coverages[.solid]))
      XCTAssertNotEqual(words[.dashed], words[.dotted])
    }
  }
  @MainActor func testNativeDraftPreviewCancelCommitUndoAndOriginPreservation() async throws {
    let original = try fixture(), s = EditorStore(document: original, actions: ActionLibrary()); defer { close(s) }
    let id = try XCTUnwrap(original.activeLayerID), origin = try XCTUnwrap(original.layers.first { $0.id == id }).shapeTransform()
    s.beginShapeProperties(editLayer: true); let draft = try XCTUnwrap(s.shapeDraft)
    draft.strokePreset = .dotted; s.refreshShapePreview()
    XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
    XCTAssertEqual(s.shapePreview?.layers.first { $0.id == id }?.shape?.definition?.stroke.dash, [0,2])
    s.cancelShapeProperties(); XCTAssertNil(s.shapePreview); XCTAssertEqual(s.document, original)
    s.beginShapeProperties(editLayer: true); let accepted = try XCTUnwrap(s.shapeDraft)
    accepted.strokePreset = .dotted; s.commitShapeProperties(accepted); await s.geometryTask?.value
    XCTAssertNil(s.error); XCTAssertEqual(s.session.undoStack.count, 1)
    let edited = s.document; XCTAssertEqual(try XCTUnwrap(edited.layers.first { $0.id == id }).shapeTransform(), origin)
    XCTAssertEqual(ShapeStrokePreset.matching(try XCTUnwrap(s.activeLayer?.shape?.definition).stroke), .dotted)
    await s.undo(); XCTAssertEqual(s.document, original); await s.redo(); XCTAssertEqual(s.document, edited)
  }
  @MainActor func testToolSettingsAndCapturedGestureRetainPresetWithoutPrematureHistory() async throws {
    let original = try fixture(), s = EditorStore(document: original, actions: ActionLibrary()); defer { close(s) }
    s.tool = .rectangle; s.shapeTemplate = definition(); s.beginShapeProperties(editLayer: false)
    let draft = try XCTUnwrap(s.shapeDraft); draft.strokePreset = .dotted
    s.commitShapeProperties(draft)
    XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
    XCTAssertEqual(s.shapeState["templateStrokePreset"] as? String, "dotted")
    let captured = try s.currentShape()
    s.shapeGesture = ShapeGesture(original: original, start: .init(x:10,y:10), definition: captured,
      mode: .shape, target: original.activeLayerID, operation: nil, end: .init(x:90,y:60))
    s.shapeTemplate.stroke = ShapeStrokePreset.solid.applied(to: s.shapeTemplate.stroke)
    s.finishShapeGesture(); await s.geometryTask?.value; XCTAssertNil(s.error)
    XCTAssertEqual(ShapeStrokePreset.matching(try XCTUnwrap(s.activeLayer?.shape?.definition).stroke), .dotted)
    XCTAssertEqual(s.session.undoStack.count, 1); await s.undo(); XCTAssertEqual(s.document, original)
  }
  @MainActor func testHTTPTemplateAndExistingLayerPresetEqualNativeDefinitionAndBytes() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), shapes: ShapeLibrary(), pressedMouseButtons: { 0 }) { service, document in
      let original = try self.fixture(); document.store.session = EditorSession(document: original); try service.share(document)
      let id = try XCTUnwrap(original.activeLayerID), native = EditorStore(document: original, actions: ActionLibrary())
      defer { self.close(native) }
      native.beginShapeProperties(editLayer:true); let draft = try XCTUnwrap(native.shapeDraft)
      draft.strokePreset = .dotted; native.commitShapeProperties(draft); await native.geometryTask?.value
      let changed = try await helper.edit(service, document, "shape.edit", ["operation":"configure", "layerID":id.uuidString, "strokePreset":"dotted"])
      XCTAssertEqual(changed, 200); XCTAssertEqual(document.store.document, native.document)
      XCTAssertEqual(try NativeArchive.encode(document.store.document), try NativeArchive.encode(native.document))
      XCTAssertEqual(document.store.shapeState["activeStrokePreset"] as? String, "dotted")
      let undo = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo, 200)
      XCTAssertEqual(document.store.document, original)
      let templateBefore = document.store.shapeTemplate
      let template = try await helper.edit(service, document, "shape.configure", ["strokePreset":"dashed"])
      XCTAssertEqual(template, 200); XCTAssertEqual(document.store.document, original)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertEqual(document.store.shapeTemplate.stroke, ShapeStrokePreset.dashed.applied(to: templateBefore.stroke))
      XCTAssertEqual(document.store.shapeState["templateStrokePreset"] as? String, "dashed")
      XCTAssertTrue(JSONSerialization.isValidJSONObject(ShapeAPI.strokePresetCapabilities))
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testAPIInvalidCustomBusyStaleAndWrongLayerAreAtomic() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), shapes: ShapeLibrary(), pressedMouseButtons: { 0 }) { service, document in
      let original = try self.fixture(); document.store.session = EditorSession(document: original); try service.share(document)
      let id = try XCTUnwrap(original.activeLayerID)
      for value: Any in ["custom","unknown",17] {
        let bad = try await helper.edit(service, document, "shape.edit", ["operation":"configure", "layerID":id.uuidString, "strokePreset":value])
        XCTAssertEqual(bad, 400)
      }
      let missing = try await helper.edit(service, document, "shape.edit", ["operation":"configure", "layerID":id.uuidString])
      XCTAssertEqual(missing, 400)
      let wrong = try await helper.edit(service, document, "shape.edit", ["operation":"configure", "layerID":original.layers[0].id.uuidString, "strokePreset":"dotted"])
      XCTAssertEqual(wrong, 404)
      let stale = try await helper.edit(service, document, "shape.edit", ["operation":"configure", "layerID":id.uuidString, "strokePreset":"dotted"], revision:"stale")
      XCTAssertEqual(stale, 409)
      document.store.beginShapeProperties(editLayer:true)
      let busy = try await helper.edit(service, document, "shape.configure", ["strokePreset":"dotted"])
      XCTAssertEqual(busy, 409); document.store.cancelShapeProperties()
      XCTAssertEqual(document.store.document, original); XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testNativeArchiveAndRecordedPlaybackRetainCanonicalStrokeValues() async throws {
    let original = try fixture(), library = ActionLibrary(), s = EditorStore(document: original, actions: library)
    defer { close(s) }
    let id = try XCTUnwrap(original.activeLayerID)
    try s.startRecordingAction(name:"Owned dots",set:"Owned tests")
    var modified = definition(); modified.stroke = ShapeStrokePreset.dotted.applied(to: modified.stroke)
    try s.executeEditorCommand(.shape(.configure(id,modified)))
    let action = try s.stopRecordingAction(); XCTAssertEqual(action.steps.count, 1)
    let expected = s.document
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(expected)), expected)
    let decoded = try ActionLibraryFile.decode(library.exportFile(action.id))
    XCTAssertGreaterThanOrEqual(decoded.version, 24); XCTAssertEqual(ActionLibraryFile.maximumVersion, 60)
    await s.undo(); XCTAssertEqual(s.document, original)
    s.playAction(decoded.actions[0]); await s.geometryTask?.value
    XCTAssertNil(s.error); XCTAssertEqual(s.document, expected)
  }
  @MainActor func testOpeningCustomStrokeAndGenericDefinitionClientsKeepTheirValues() async throws {
    var original = try fixture(), custom = definition()
    custom.stroke.dash = [8,4,2,4]; custom.stroke.phase = 5; custom.stroke.cap = .square
    let id = try XCTUnwrap(original.activeLayerID); try Command.shape(.configure(id,custom)).apply(to:&original)
    let s = EditorStore(document: original, actions: ActionLibrary()); defer { close(s) }
    s.beginShapeProperties(editLayer:true); let draft = try XCTUnwrap(s.shapeDraft)
    XCTAssertEqual(draft.strokePreset, .custom); XCTAssertEqual(draft.definition, custom)
    s.cancelShapeProperties(); XCTAssertEqual(s.document, original)
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), shapes: ShapeLibrary(), pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: try self.fixture()); try service.share(document)
      let target = try XCTUnwrap(document.store.document.activeLayerID)
      let changed = try await helper.edit(service, document, "shape.edit", ["operation":"configure", "layerID":target.uuidString, "definition":BrushAPI.json(custom)])
      XCTAssertEqual(changed, 200); XCTAssertEqual(document.store.activeLayer?.shape?.definition, custom)
      XCTAssertEqual(document.store.shapeState["activeStrokePreset"] as? String, "custom")
    }
  }
}
