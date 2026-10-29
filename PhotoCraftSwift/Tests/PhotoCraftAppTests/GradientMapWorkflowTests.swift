import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class GradientMapWorkflowTests: XCTestCase {
  @MainActor func store() throws -> EditorStore {
    var doc = try CraftDocument(width: 12, height: 8)
    doc.layers[0].content = .raster(try Surface(width: 12, height: 8, fill: Pixel(0.8, 0.25, 0.1)))
    return EditorStore(document: doc, gradients: GradientLibrary())
  }
  @MainActor func testPixelPreviewCancelCommitUndoAndMutualExclusion() async throws {
    let store = try store()
    defer { store.renderTask?.cancel() }
    let before = store.document
    store.beginGradientMap()
    XCTAssertNotNil(store.gradientMapDraft)
    XCTAssertFalse(store.canBeginLevels)
    XCTAssertNil(
      store.gradientCanvasDrop("photato-gradients:\(store.gradients.state.presetIDs[0])"))
    store.beginGradientFill()
    XCTAssertNil(store.gradientFillDraft)
    store.gradientMapDraft?.adjustment.reverse = true
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(store.document, before)
    XCTAssertNotEqual(store.surface, try Renderer.composite(before))
    store.gradientMapDraft?.preview = false
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(store.surface, try Renderer.composite(before))
    store.cancelGradientMap()
    XCTAssertEqual(store.document, before)
    store.beginGradientMap()
    store.commitGradientMap()
    await store.geometryTask?.value
    XCTAssertNotEqual(store.document, before)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.session.undoStack.last?.label, "Gradient Map")
    await store.undo()
    XCTAssertEqual(store.document, before)
  }
  @MainActor func testLayerMaskPresetApplicationAndGroupedUndo() async throws {
    let store = try store()
    defer { store.renderTask?.cancel() }
    store.perform(.selection(.init(x: 2, y: 1, width: 5, height: 3)))
    let before = store.document
    store.addGradientMapLayer()
    let id = try XCTUnwrap(store.activeLayer?.id)
    XCTAssertEqual(store.activeLayer?.mask?.pixel(x: 0, y: 0).r, 0)
    XCTAssertEqual(store.activeLayer?.mask?.pixel(x: 3, y: 2).r, 1)
    guard case .adjustment(.gradientMap(var value)) = store.activeLayer?.content else {
      return XCTFail()
    }
    value.reverse = true
    store.setGradientMap(id, value)
    let prior = store.session.undoStack.count
    store.brush.color = Pixel(0.2, 0.8, 0.4)
    store.chooseGradientPreset(store.gradients.state.presetIDs[1])
    await store.gradientLibraryTask?.value
    XCTAssertEqual(store.session.undoStack.count, prior + 1)
    guard case .adjustment(.gradientMap(let selected)) = store.activeLayer?.content else {
      return XCTFail()
    }
    XCTAssertTrue(selected.reverse)
    XCTAssertEqual(selected.gradient.colors[0].color, .rgb(Pixel(0.2, 0.8, 0.4)))
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(store.document)), store.document)
    await store.undo()
    await store.undo()
    await store.undo()
    XCTAssertEqual(store.document, before)
  }
  @MainActor func testDelayedPresetDoesNotOverwriteReopenedDraftOnSameLayer() async throws {
    let store = try store()
    defer { store.renderTask?.cancel() }
    store.beginGradientMap()
    store.chooseGradientPreset(store.gradients.state.presetIDs[1])
    store.cancelGradientMap()
    store.beginGradientMap()
    let newDraft = try XCTUnwrap(store.gradientMapDraft)
    await store.gradientLibraryTask?.value
    XCTAssertEqual(store.gradientMapDraft?.adjustment, newDraft.adjustment)
    store.cancelGradientMap()
    store.beginGradientFill()
    store.chooseGradientPreset(store.gradients.state.presetIDs[0])
    store.cancelGradientFill()
    store.beginGradientFill()
    let newFill = try XCTUnwrap(store.gradientFillDraft)
    await store.gradientLibraryTask?.value
    XCTAssertEqual(store.gradientFillDraft?.fill, newFill.fill)
  }
  @MainActor func testDraftPresetCaptureDoesNotEditDocumentAndCancelledCommitIsAtomic() async throws
  {
    let store = try store()
    defer { store.renderTask?.cancel() }
    let before = store.document
    store.beginGradientMap()
    store.brush.color = Pixel(0.25, 0.5, 0.75)
    store.chooseGradientPreset(store.gradients.state.presetIDs[1])
    store.brush.color = .black
    await store.gradientLibraryTask?.value
    XCTAssertEqual(
      store.gradientMapDraft?.adjustment.gradient.colors[0].color, .rgb(Pixel(0.25, 0.5, 0.75)))
    store.beginSaveGradientPreset()
    let name = try XCTUnwrap(store.gradientNameDraft)
    store.finishGradientName(name, name: "Captured map")
    await store.gradientLibraryTask?.value
    XCTAssertEqual(store.gradients.selectedPreset?.name, "Captured map")
    XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    store.commitGradientMap()
    store.geometryTask?.cancel()
    await store.geometryTask?.value
    XCTAssertEqual(store.document, before)
  }
}
