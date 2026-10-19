import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class TonalStepsWorkflowTests: XCTestCase {
  @MainActor func testPreviewCancelBackgroundCommitUndoAndDraftExclusion() async throws {
    for kind in TonalStepsAdjustment.Kind.allCases {
      var d = try CraftDocument(width: 8, height: 4)
      d.layers[0].content = .raster(try Surface(width: 8, height: 4, fill: Pixel(0.8, 0.2, 0.4)))
      let store = EditorStore(document: d)
      defer { store.renderTask?.cancel() }
      store.beginTonalSteps(kind)
      XCTAssertNotNil(store.tonalStepsDraft)
      XCTAssertFalse(store.canBeginLevels)
      XCTAssertFalse(store.canBeginCurves)
      XCTAssertFalse(store.clipboardTargetAvailable)
      store.beginLevels()
      store.beginCurves()
      store.beginHueSaturation()
      store.beginColorBalance()
      store.beginTransform()
      XCTAssertNil(store.levelsDraft)
      XCTAssertNil(store.curvesDraft)
      XCTAssertNil(store.hueSaturationDraft)
      XCTAssertNil(store.colorBalanceDraft)
      XCTAssertNil(store.transformDraft)
      store.tonalStepsDraft?.adjustment.level = kind == .threshold ? 200 : 2
      store.render()
      await store.renderTask?.value
      XCTAssertEqual(store.document, d)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertNotEqual(try XCTUnwrap(store.surface), try Renderer.composite(d))
      store.tonalStepsDraft?.preview = false
      store.render()
      await store.renderTask?.value
      XCTAssertEqual(store.surface, try Renderer.composite(d))
      store.cancelTonalSteps()
      XCTAssertEqual(store.document, d)
      store.beginTonalSteps(kind)
      store.commitTonalSteps()
      await store.geometryTask?.value
      XCTAssertNotEqual(store.document, d)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertEqual(store.session.undoStack.last?.label, kind.rawValue)
      store.undo()
      XCTAssertEqual(store.document, d)
      store.beginTonalSteps(kind)
      store.commitTonalSteps()
      store.geometryTask?.cancel()
      await store.geometryTask?.value
      XCTAssertEqual(store.document, d)
      XCTAssertFalse(store.geometryBusy)
      store.beginCurves()
      store.beginTonalSteps(kind)
      XCTAssertNil(store.tonalStepsDraft)
      store.cancelCurves()
    }
  }

  @MainActor func testSelectionMaskLayerEditsCoalescingAndLocks() throws {
    for kind in TonalStepsAdjustment.Kind.allCases {
      let store = EditorStore(document: try CraftDocument(width: 4, height: 2))
      defer { store.renderTask?.cancel() }
      store.perform(.selection(IntRect(x: 1, y: 0, width: 2, height: 2)))
      let before = store.document
      store.addTonalStepsLayer(kind)
      let layer = try XCTUnwrap(store.activeLayer)
      XCTAssertEqual(layer.content, .adjustment(.tonalSteps(.init(kind: kind))))
      XCTAssertEqual(layer.mask?.pixel(x: 1, y: 0), .white)
      XCTAssertEqual(layer.mask?.pixel(x: 0, y: 0), .black)
      XCTAssertFalse(store.canBeginLevels)
      store.coalesce(true)
      for level in [10, 20, 30] { store.setTonalSteps(layer.id, .init(kind: kind, level: level)) }
      store.coalesce(false)
      store.undo()
      XCTAssertEqual(store.activeLayer?.content, layer.content)
      let other: TonalStepsAdjustment.Kind = kind == .threshold ? .posterize : .threshold
      store.setTonalSteps(layer.id, .init(kind: other))
      XCTAssertEqual(store.activeLayer?.content, layer.content)
      store.perform(.lock(layer.id, true))
      let locked = store.document
      store.setTonalSteps(layer.id, .init(kind: kind, level: 64))
      XCTAssertEqual(store.document, locked)
      store.undo()
      store.undo()
      XCTAssertEqual(store.document, before)
    }
  }

  @MainActor func testImageAndLayerMenus() {
    _ = NSApplication.shared
    let old = NSApp.mainMenu
    let windows = NSApp.windowsMenu
    let help = NSApp.helpMenu
    defer {
      NSApp.mainMenu = old
      NSApp.windowsMenu = windows
      NSApp.helpMenu = help
    }
    AppDelegate().buildMenus()
    let menu = NSApp.mainMenu?.item(withTitle: "Image")?.submenu?.item(withTitle: "Adjustments")?
      .submenu
    let layer = NSApp.mainMenu?.item(withTitle: "Layer")?.submenu?.item(
      withTitle: "New Adjustment Layer")?.submenu
    for (title, action, layerAction) in [
      ("Threshold…", #selector(AppDelegate.threshold), #selector(AppDelegate.newThreshold)),
      ("Posterize…", #selector(AppDelegate.posterize), #selector(AppDelegate.newPosterize)),
    ] {
      XCTAssertEqual(menu?.item(withTitle: title)?.action, action)
      XCTAssertEqual(menu?.item(withTitle: title)?.keyEquivalent, "")
      XCTAssertEqual(layer?.item(withTitle: title)?.action, layerAction)
      XCTAssertEqual(layer?.item(withTitle: title)?.keyEquivalent, "")
    }
  }

  @MainActor func testThresholdHistogramUsesSelectedInputAndRemainsStableWhileEditing() async throws
  {
    var d = try CraftDocument(width: 4, height: 1)
    var s = try Surface(width: 4, height: 1)
    s.setPixel(x: 0, y: 0, Pixel(1, 0, 0))
    s.setPixel(x: 1, y: 0, Pixel(0, 1, 0))
    s.setPixel(x: 2, y: 0, Pixel(0, 0, 1))
    d.layers[0].content = .raster(s)
    try Command.selection(IntRect(x: 0, y: 0, width: 2, height: 1)).apply(to: &d)
    let request = LevelsAnalysisRequest(
      document: d, layerID: d.layers[0].id, pixelLayer: true, luminance: true)
    let analysis = LevelsAnalysis()
    defer { analysis.cancel() }
    analysis.update(request)
    await analysis.task?.value
    let h = try XCTUnwrap(analysis.histogram)
    XCTAssertEqual(h.samples, 2)
    XCTAssertEqual(h.channels[0][76], 1)
    XCTAssertEqual(h.channels[0][150], 1)
    XCTAssertEqual(h.channels[0][28], 0)
    var layer = Layer(name: "Threshold", content: .adjustment(.tonalSteps(.init(kind: .threshold))))
    d.layers.append(layer)
    let original = LevelsAnalysisRequest(
      document: d, layerID: layer.id, pixelLayer: false, luminance: true)
    layer.content = .adjustment(.tonalSteps(.init(kind: .threshold, level: 200)))
    d.layers[1] = layer
    let edited = LevelsAnalysisRequest(
      document: d, layerID: layer.id, pixelLayer: false, luminance: true)
    XCTAssertEqual(original, edited)
    XCTAssertEqual(try original.analyze(), try edited.analyze())
    XCTAssertNotEqual(
      edited, LevelsAnalysisRequest(document: d, layerID: layer.id, pixelLayer: false))
  }
}
