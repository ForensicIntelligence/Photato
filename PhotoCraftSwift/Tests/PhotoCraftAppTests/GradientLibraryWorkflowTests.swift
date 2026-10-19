import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class GradientLibraryWorkflowTests: XCTestCase {
  @MainActor func testActivationAndCanvasDropValidationCreateEditableFillWithUndo() async throws {
    let library = GradientLibrary()
    var doc = try CraftDocument(width: 40, height: 30)
    doc.selection = .init(x: 4, y: 5, width: 20, height: 15)
    let store = EditorStore(document: doc, gradients: library)
    defer { store.renderTask?.cancel() }
    let id = library.state.presetIDs[1]
    XCTAssertEqual(store.gradientCanvasDrop("photato-gradients:\(id.uuidString)"), id)
    XCTAssertNil(store.gradientCanvasDrop("photato-gradients:\(UUID())"))
    XCTAssertNil(store.gradientCanvasDrop("https://example.com/gradient"))
    XCTAssertNil(store.gradientCanvasDrop("photato-gradients:\(id),\(id)"))
    store.activateGradientPreset(id)
    await store.geometryTask?.value
    await store.gradientLibraryTask?.value
    XCTAssertNil(store.error)
    guard case .gradientFill(let fill) = store.activeLayer?.content else { return XCTFail() }
    XCTAssertEqual(fill.gradient.opacity.last?.opacity, 0)
    XCTAssertNotNil(store.activeLayer?.mask)
    XCTAssertEqual(store.session.undoStack.count, 1)
    let result = store.document
    try await library.edit { try $0.remove([id]) }
    XCTAssertEqual(store.document, result)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(store.document)), result)
    store.undo()
    XCTAssertEqual(store.document, doc)
    store.redo()
    XCTAssertEqual(store.document, result)
  }
  @MainActor func testSavePresetFromFillDraftCapturesExactControlsWithoutDocumentEdit() async throws
  {
    let library = GradientLibrary()
    let store = EditorStore(document: try CraftDocument(width: 40, height: 30), gradients: library)
    defer { store.renderTask?.cancel() }
    store.beginGradientFill()
    store.gradientFillDraft?.fill.gradient = GradientLibraryTests.custom()
    let original = store.document
    store.beginSaveGradientPreset()
    let draft = try XCTUnwrap(store.gradientNameDraft)
    store.gradientFillDraft?.fill.gradient.colors[0].position = 0.5
    store.finishGradientName(draft, name: "Captured")
    await store.gradientLibraryTask?.value
    XCTAssertNil(store.error)
    var expected = GradientLibraryTests.custom()
    expected.name = "Captured"
    XCTAssertEqual(library.selectedPreset?.gradient, expected)
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertEqual(store.colorTab, .gradients)
    XCTAssertNotNil(store.gradientFillDraft)
    store.cancelGradientFill()
  }
  @MainActor func testPresetSelectionAppliesToLiveFillAndDraftWithOneUndo() async throws {
    let library = GradientLibrary()
    let store = EditorStore(document: try CraftDocument(width: 40, height: 30), gradients: library)
    defer { store.renderTask?.cancel() }
    let transparent = library.state.presetIDs[1]
    store.beginGradientFill()
    let doc = store.document
    store.brush.color = Pixel(0.7, 0.2, 0.8)
    store.chooseGradientPreset(transparent)
    store.brush.color = .black
    await store.gradientLibraryTask?.value
    XCTAssertEqual(store.document, doc)
    XCTAssertEqual(
      store.gradientFillDraft?.fill.gradient.colors[0].color, .rgb(Pixel(0.7, 0.2, 0.8)))
    XCTAssertEqual(store.gradientFillDraft?.fill.gradient.opacity.last?.opacity, 0)
    store.commitGradientFill()
    await store.geometryTask?.value
    store.chooseTool(WorkspaceCatalog.tool("move"))
    let before = store.document
    store.chooseGradientPreset(library.state.presetIDs[2])
    await store.gradientLibraryTask?.value
    await store.geometryTask?.value
    guard case .gradientFill(let fill) = store.activeLayer?.content else { return XCTFail() }
    XCTAssertEqual(fill.gradient, .blackToWhite)
    XCTAssertEqual(store.session.undoStack.count, 2)
    store.undo()
    XCTAssertEqual(store.document, before)
  }
  @MainActor func testClassicPresetSelectionAndLaterTargetChangeDoNotApplyToWrongLayer()
    async throws
  {
    let library = GradientLibrary()
    let store = EditorStore(document: try CraftDocument(width: 40, height: 30), gradients: library)
    defer { store.renderTask?.cancel() }
    store.chooseTool(WorkspaceCatalog.tool("gradient"))
    store.gradientOptions.mode = .classic
    let original = store.document
    store.chooseGradientPreset(library.state.presetIDs[1])
    await store.gradientLibraryTask?.value
    XCTAssertEqual(store.gradientOptions.gradient, .foregroundToTransparent)
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    store.gradientOptions.mode = .live
    store.beginGradientFill()
    XCTAssertEqual(store.gradientFillDraft?.fill.gradient.opacity.last?.opacity, 0)
    store.commitGradientFill()
    await store.geometryTask?.value
    store.chooseGradientPreset(library.state.presetIDs[2])
    store.select(original.layers[0].id)
    let before = store.document
    await store.gradientLibraryTask?.value
    await store.geometryTask?.value
    XCTAssertEqual(store.document, before)
    XCTAssertEqual(store.gradientOptions.gradient, .blackToWhite)
  }
  @MainActor func testGroupMultiSelectionUnavailablePresetsAndLibraryDeletionLeaveDocumentAlone()
    async throws
  {
    let library = GradientLibrary()
    let fixture = try GradientLibraryTests.fixture()
    try await library.edit { try $0.install(fixture, name: "External", into: nil) }
    let store = EditorStore(document: try CraftDocument(width: 40, height: 30), gradients: library)
    defer { store.renderTask?.cancel() }
    store.chooseTool(WorkspaceCatalog.tool("gradient"))
    let original = store.document
    let unavailable = try XCTUnwrap(
      library.state.presetIDs.first { library.state.presets[$0]?.gradient == nil })
    let previous = store.gradientOptions.gradient
    store.chooseGradientPreset(unavailable)
    await store.gradientLibraryTask?.value
    XCTAssertEqual(store.gradientOptions.gradient, previous)
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.status.contains("Noise"))
    let first = library.state.presetIDs[0]
    let second = library.state.presetIDs[1]
    store.chooseGradientPreset(first)
    await store.gradientLibraryTask?.value
    store.chooseGradientPreset(second, modifiers: .command)
    await store.gradientLibraryTask?.value
    XCTAssertEqual(library.state.selected, [first, second])
    XCTAssertEqual(
      try GRDCodec.read(library.state.exported(library.state.selected)).presets.count, 2)
    store.removeGradientPresets()
    await store.gradientLibraryTask?.value
    XCTAssertNil(library.state.presets[first])
    XCTAssertNil(library.state.presets[second])
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }
}
