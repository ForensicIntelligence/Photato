import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class CurvesWorkflowTests: XCTestCase {
  @MainActor func testPreviewCancelBackgroundCommitUndoAndMutationGuards() async throws {
    var d = try CraftDocument(width: 8, height: 4)
    d.layers[0].content = .raster(try Surface(width: 8, height: 4, fill: Pixel(0.3, 0.4, 0.5)))
    let store = EditorStore(document: d)
    defer { store.renderTask?.cancel() }
    store.beginCurves()
    XCTAssertNotNil(store.curvesDraft)
    XCTAssertFalse(store.canBeginLevels)
    XCTAssertFalse(store.clipboardTargetAvailable)
    store.beginLevels()
    store.beginTransform()
    store.perform(.deleteLayer(d.layers[0].id))
    XCTAssertNil(store.levelsDraft)
    XCTAssertNil(store.transformDraft)
    XCTAssertEqual(store.document, d)
    store.curvesDraft?.curves = BuiltInCurvesPreset.negative.curves
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(store.document, d)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertGreaterThan(try XCTUnwrap(store.surface).pixel(x: 0, y: 0).r, 0.6)
    store.curvesDraft?.preview = false
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(store.surface, try Renderer.composite(d))
    store.cancelCurves()
    XCTAssertNil(store.curvesDraft)
    store.beginCurves()
    store.curvesDraft?.curves = BuiltInCurvesPreset.negative.curves
    store.commitCurves()
    await store.geometryTask?.value
    XCTAssertNotEqual(store.document, d)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.session.undoStack.last?.label, "Curves")
    store.undo()
    XCTAssertEqual(store.document, d)
    store.beginCurves()
    store.curvesDraft?.curves = BuiltInCurvesPreset.negative.curves
    store.commitCurves()
    store.geometryTask?.cancel()
    await store.geometryTask?.value
    XCTAssertEqual(store.document, d)
    XCTAssertFalse(store.geometryBusy)
    store.beginLevels()
    store.beginCurves()
    XCTAssertNil(store.curvesDraft)
    store.cancelLevels()
  }
  @MainActor func testAdjustmentLayerSelectionMaskCoalescingAndLocks() throws {
    let store = EditorStore(document: try CraftDocument(width: 4, height: 2))
    defer { store.renderTask?.cancel() }
    store.perform(.selection(IntRect(x: 1, y: 0, width: 2, height: 2)))
    let before = store.document
    store.addCurvesLayer()
    let layer = try XCTUnwrap(store.activeLayer)
    XCTAssertEqual(layer.content, .adjustment(.curves(.init())))
    XCTAssertEqual(layer.mask?.pixel(x: 1, y: 0), .white)
    XCTAssertEqual(layer.mask?.pixel(x: 0, y: 0), .black)
    XCTAssertFalse(store.canBeginCurves)
    let request = LevelsAnalysisRequest(
      document: store.document, layerID: layer.id, pixelLayer: false)
    store.coalesce(true)
    for preset in [BuiltInCurvesPreset.darker, .lighter, .negative] {
      store.setCurves(layer.id, preset.curves)
    }
    store.coalesce(false)
    XCTAssertEqual(
      store.activeLayer?.content, .adjustment(.curves(BuiltInCurvesPreset.negative.curves)))
    XCTAssertEqual(
      LevelsAnalysisRequest(document: store.document, layerID: layer.id, pixelLayer: false), request
    )
    store.undo()
    XCTAssertEqual(store.activeLayer?.content, layer.content)
    store.perform(.lock(layer.id, true))
    let locked = store.document
    store.setCurves(layer.id, BuiltInCurvesPreset.negative.curves)
    XCTAssertEqual(store.document, locked)
    store.undo()
    store.undo()
    XCTAssertEqual(store.document, before)
  }
  @MainActor func testMenusUseCommandMAndLayerEntry() {
    _ = NSApplication.shared
    let old = NSApp.mainMenu
    let windows = NSApp.windowsMenu
    let help = NSApp.helpMenu
    defer {
      NSApp.mainMenu = old
      NSApp.windowsMenu = windows
      NSApp.helpMenu = help
    }
    let app = AppDelegate()
    app.buildMenus()
    let image = NSApp.mainMenu?.item(withTitle: "Image")?.submenu?.item(withTitle: "Adjustments")?
      .submenu
    XCTAssertEqual(image?.item(withTitle: "Curves…")?.keyEquivalent, "m")
    XCTAssertEqual(image?.item(withTitle: "Curves…")?.keyEquivalentModifierMask, .command)
    XCTAssertEqual(image?.item(withTitle: "Curves…")?.action, #selector(AppDelegate.curves))
    let layer = NSApp.mainMenu?.item(withTitle: "Layer")?.submenu?.item(
      withTitle: "New Adjustment Layer")?.submenu
    XCTAssertEqual(layer?.item(withTitle: "Curves…")?.action, #selector(AppDelegate.newCurves))
  }
  func testPresetFileLoadPreservesOriginalAndBoundsInput() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("curves.acv")
    let curves = BuiltInCurvesPreset.crossProcess.curves
    let data = try CurvesPresetCodec.write(curves)
    try data.write(to: url)
    let loaded = try CurvesPresetFile.load(url)
    XCTAssertEqual(loaded.curves, curves)
    XCTAssertEqual(loaded.original, data)
    try Data(repeating: 0, count: 32769).write(to: url)
    XCTAssertThrowsError(try CurvesPresetFile.load(url))
    try Data([0, 4, 0, 1]).write(to: url)
    XCTAssertThrowsError(try CurvesPresetFile.load(url))
  }
}
