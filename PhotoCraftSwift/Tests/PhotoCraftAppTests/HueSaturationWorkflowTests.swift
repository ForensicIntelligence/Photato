import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class HueSaturationWorkflowTests: XCTestCase {
  @MainActor func testPreviewCancelBackgroundCommitUndoAndDraftExclusion() async throws {
    var d = try CraftDocument(width: 8, height: 4)
    d.layers[0].content = .raster(try Surface(width: 8, height: 4, fill: Pixel(0.8, 0.2, 0.4)))
    let store = EditorStore(document: d)
    defer { store.renderTask?.cancel() }
    store.beginHueSaturation()
    XCTAssertNotNil(store.hueSaturationDraft)
    XCTAssertFalse(store.canBeginLevels)
    XCTAssertFalse(store.canBeginCurves)
    XCTAssertFalse(store.clipboardTargetAvailable)
    store.beginLevels()
    store.beginCurves()
    store.beginTransform()
    XCTAssertNil(store.levelsDraft)
    XCTAssertNil(store.curvesDraft)
    XCTAssertNil(store.transformDraft)
    store.hueSaturationDraft?.adjustment.master.hue = 120
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(store.document, d)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertGreaterThan(try XCTUnwrap(store.surface).pixel(x: 0, y: 0).g, 0.7)
    store.hueSaturationDraft?.preview = false
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(store.surface, try Renderer.composite(d))
    store.cancelHueSaturation()
    XCTAssertEqual(store.document, d)
    store.beginHueSaturation()
    store.hueSaturationDraft?.adjustment = BuiltInHueSaturationPreset.sepia.adjustment
    store.commitHueSaturation()
    await store.geometryTask?.value
    XCTAssertNotEqual(store.document, d)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.session.undoStack.last?.label, "Hue/Saturation")
    await store.undo()
    XCTAssertEqual(store.document, d)
    store.beginHueSaturation()
    store.hueSaturationDraft?.adjustment.master.hue = 90
    store.commitHueSaturation()
    store.geometryTask?.cancel()
    await store.geometryTask?.value
    XCTAssertEqual(store.document, d)
    XCTAssertFalse(store.geometryBusy)
    store.beginCurves()
    store.beginHueSaturation()
    XCTAssertNil(store.hueSaturationDraft)
    store.cancelCurves()
  }
  @MainActor func testSelectionMaskRangeEditsCoalescingAndLocks() async throws {
    let store = EditorStore(document: try CraftDocument(width: 4, height: 2))
    defer { store.renderTask?.cancel() }
    store.perform(.selection(IntRect(x: 1, y: 0, width: 2, height: 2)))
    let before = store.document
    store.addHueSaturationLayer()
    let layer = try XCTUnwrap(store.activeLayer)
    XCTAssertEqual(layer.content, .adjustment(.hueSaturation(.init())))
    XCTAssertEqual(layer.mask?.pixel(x: 1, y: 0), .white)
    XCTAssertEqual(layer.mask?.pixel(x: 0, y: 0), .black)
    XCTAssertFalse(store.canBeginHueSaturation)
    store.coalesce(true)
    for amount in [10, 20, 30] {
      var a = HueSaturationAdjustment()
      a.ranges[0].values.hue = amount
      a.ranges[0].moveEdge(0, to: -20)
      store.setHueSaturation(layer.id, a)
    }
    store.coalesce(false)
    await store.undo()
    XCTAssertEqual(store.activeLayer?.content, layer.content)
    store.perform(.lock(layer.id, true))
    let locked = store.document
    store.setHueSaturation(layer.id, BuiltInHueSaturationPreset.sepia.adjustment)
    XCTAssertEqual(store.document, locked)
    await store.undo()
    await store.undo()
    XCTAssertEqual(store.document, before)
  }
  @MainActor func testCommandUAndLayerMenus() {
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
    let menu = NSApp.mainMenu?.item(withTitle: "Image")?.submenu?.item(withTitle: "Adjustments")?
      .submenu
    XCTAssertEqual(menu?.item(withTitle: "Hue/Saturation…")?.keyEquivalent, "u")
    XCTAssertEqual(menu?.item(withTitle: "Hue/Saturation…")?.keyEquivalentModifierMask, .command)
    XCTAssertEqual(
      menu?.item(withTitle: "Hue/Saturation…")?.action, #selector(AppDelegate.hueSaturation))
    XCTAssertEqual(menu?.item(withTitle: "Desaturate")?.keyEquivalent, "u")
    XCTAssertEqual(
      menu?.item(withTitle: "Desaturate")?.keyEquivalentModifierMask, [.command, .shift])
    let layer = NSApp.mainMenu?.item(withTitle: "Layer")?.submenu?.item(
      withTitle: "New Adjustment Layer")?.submenu
    XCTAssertEqual(
      layer?.item(withTitle: "Hue/Saturation…")?.action, #selector(AppDelegate.newHueSaturation))
  }
  func testPresetFileBoundedReadPreservesOriginal() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("preset.ahu")
    let preset = BuiltInHueSaturationPreset.cyanotype.adjustment
    let data = try HueSaturationPresetCodec.write(preset)
    try data.write(to: url)
    let actual = try HueSaturationPresetFile.load(url)
    XCTAssertEqual(actual.adjustment, preset)
    XCTAssertEqual(actual.original, data)
    var extended = data
    for hue in [0, 60, 120, 180, 240, 300] {
      for value in [hue, 100, 50] {
        extended.append(UInt8(value >> 8))
        extended.append(UInt8(value & 255))
      }
    }
    try extended.write(to: url)
    let modern = try HueSaturationPresetFile.load(url)
    XCTAssertEqual(modern.adjustment, preset)
    XCTAssertEqual(modern.original, extended)
    try (extended + Data([0])).write(to: url)
    XCTAssertThrowsError(try HueSaturationPresetFile.load(url))
    try Data(repeating: 0, count: 101).write(to: url)
    XCTAssertThrowsError(try HueSaturationPresetFile.load(url))
    try data.prefix(99).write(to: url)
    XCTAssertThrowsError(try HueSaturationPresetFile.load(url))
  }
  @MainActor func testDesaturateTargetsSelectedPixelsAndHasOneUndo() async throws {
    var d = try CraftDocument(width: 4, height: 1)
    d.layers[0].content = .raster(try Surface(width: 4, height: 1, fill: Pixel(0.8, 0.2, 0.4)))
    d.selection = .init(x: 1, y: 0, width: 2, height: 1)
    let store = EditorStore(document: d)
    defer { store.renderTask?.cancel() }
    store.desaturate()
    await store.geometryTask?.value
    guard case .raster(let pixels) = store.document.layers[0].content else { return XCTFail() }
    XCTAssertEqual(pixels.pixel(x: 0, y: 0), Pixel(0.8, 0.2, 0.4))
    let gray = pixels.pixel(x: 1, y: 0)
    XCTAssertEqual(gray.r, 0.5, accuracy: 1.0 / 255)
    XCTAssertEqual(gray.r, gray.g)
    XCTAssertEqual(gray.g, gray.b)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.session.undoStack.last?.label, "Desaturate")
    await store.undo()
    XCTAssertEqual(store.document, d)
    store.perform(.lock(d.layers[0].id, true))
    let locked = store.document
    store.desaturate()
    XCTAssertEqual(store.document, locked)
  }
}
