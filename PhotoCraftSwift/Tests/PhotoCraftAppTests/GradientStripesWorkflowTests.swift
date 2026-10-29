import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class GradientStripesWorkflowTests: XCTestCase {
  @MainActor func testStripesPresetCaptureApplyAndUndo() async throws {
    let store = try GradientMapWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let original = store.document
    store.gradientOptions.gradient = .init(
      name: "Photato bands",
      colors: [.init(0, .rgb(.black)), .init(0.5, .rgb(.white))], method: .stripes)
    store.beginGradientMap()
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(store.gradientMapDraft?.adjustment.gradient.method, .stripes)
    XCTAssertEqual(store.surface?.pixel(x: 0, y: 0), .black)
    XCTAssertEqual(store.document, original)
    store.beginSaveGradientPreset()
    store.finishGradientName(try XCTUnwrap(store.gradientNameDraft), name: "Saved stripes")
    await store.gradientLibraryTask?.value
    let preset = try XCTUnwrap(store.gradients.selectedPreset)
    let presetID = try XCTUnwrap(store.gradients.state.activePreset)
    XCTAssertEqual(preset.gradient?.method, .stripes)
    let exported = try store.gradients.state.exported(store.gradients.state.selected)
    XCTAssertEqual(try GRDCodec.read(exported).presets.first?.gradient?.method, .stripes)
    store.cancelGradientMap()
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    store.gradientOptions.gradient = .blackToWhite
    store.addGradientMapLayer()
    let before = store.document
    store.chooseGradientPreset(presetID)
    await store.gradientLibraryTask?.value
    guard case .adjustment(.gradientMap(let map)) = store.activeLayer?.content else {
      return XCTFail("Expected an editable Gradient Map")
    }
    XCTAssertEqual(map.gradient.method, .stripes)
    XCTAssertEqual(store.session.undoStack.count, 2)
    await store.undo()
    XCTAssertEqual(store.document, before)
    await store.undo()
    XCTAssertEqual(store.document, original)
  }

  @MainActor func testRGB32MapCreationAndLegacyEditingAreUnavailable() throws {
    for depth in PixelDepth.allCases {
      let store = EditorStore(
        document: try CraftDocument(width: 4, height: 3, depth: depth),
        gradients: GradientLibrary())
      defer { store.renderTask?.cancel() }
      XCTAssertEqual(store.canBeginGradientMap, depth != .f32)
      XCTAssertEqual(store.canAddGradientMap, depth != .f32)
      store.beginGradientMap()
      XCTAssertEqual(store.gradientMapDraft != nil, depth != .f32)
      store.cancelGradientMap()
      store.addGradientMapLayer()
      XCTAssertEqual(store.document.layers.count, depth == .f32 ? 1 : 2)
      XCTAssertEqual(store.session.undoStack.count, depth == .f32 ? 0 : 1)
    }
    var legacy = try CraftDocument(width: 4, height: 3, depth: .f32)
    let map = GradientMapAdjustment()
    let layer = Layer(name: "Legacy map", content: .adjustment(.gradientMap(map)))
    legacy.layers.append(layer)
    legacy.activeLayerID = layer.id
    let store = EditorStore(document: legacy, gradients: GradientLibrary())
    defer { store.renderTask?.cancel() }
    var edited = map
    edited.reverse = true
    store.setGradientMap(layer.id, edited)
    XCTAssertEqual(store.document, legacy)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(store.document)), legacy)
  }
}
