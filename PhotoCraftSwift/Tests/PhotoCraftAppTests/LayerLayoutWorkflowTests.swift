import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class LayerLayoutWorkflowTests: XCTestCase {
  @MainActor func testAll512LayersResolveAndMoveOnce() throws {
    var document = try CraftDocument(width: 400, height: 300)
    document.layers = try (0..<512).map { i in
      var layer = Layer(
        name: "Layer \(i)", content: .raster(try Surface(width: 1, height: 1, fill: .white)))
      layer.x = i * 17 % 300
      layer.y = i * 31 % 200
      return layer
    }
    document.activeLayerID = document.layers.last?.id
    let s = EditorStore(document: document)
    s.renderTask?.cancel()
    s.selectAllLayers()
    let start = Date.timeIntervalSinceReferenceDate
    for _ in 0..<10 {
      for edge in LayerAlignment.allCases { XCTAssertTrue(s.canLayout(.align(edge))) }
      for kind in LayerDistribution.allCases { XCTAssertTrue(s.canLayout(.distribute(kind))) }
    }
    let availabilitySeconds = Date.timeIntervalSinceReferenceDate - start
    let command = try Renderer.layoutCommand(
      in: document, selected: s.layoutSelection, operation: .align(.left))
    var result = document
    try command.apply(to: &result)
    for i in result.layers.indices {
      XCTAssertEqual(result.layers[i].x, 0)
      XCTAssertEqual(result.layers[i].y, document.layers[i].y)
      XCTAssertEqual(result.layers[i].content, document.layers[i].content)
    }
    let report: [String: Any] = [
      "layers": 512, "availability_checks": 140, "availability_seconds": availabilitySeconds,
      "availability_and_edit_seconds": Date.timeIntervalSinceReferenceDate - start,
      "all_layers_moved_once": true,
    ]
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: root.appendingPathComponent("artifacts/layer-layout-512-layers.json"))
  }
  @MainActor func store(count: Int = 3) throws -> EditorStore {
    var d = try CraftDocument(width: 100, height: 80)
    d.layers = try (0..<count).map { i in
      var layer = Layer(
        name: "Item \(i)", content: .raster(try Surface(width: 7 + i, height: 9 + i, fill: .white)))
      layer.x = 5 + i * i * 13
      layer.y = 3 + i * 19
      return layer
    }
    d.activeLayerID = d.layers.last?.id
    let store = EditorStore(document: d)
    store.renderTask?.cancel()
    store.selectAllLayers()
    return store
  }
  @MainActor func testLayoutCreatesOneUndoStepAndPreservesSelection() async throws {
    let s = try store()
    s.perform(.selection(IntRect(x: 10, y: 10, width: 60, height: 50)))
    s.renderTask?.cancel()
    s.selectAllLayers()
    let before = s.document
    let selected = s.selectedLayerIDs
    let history = s.session.undoStack.count
    s.arrangeLayers(.align(.right))
    await s.geometryTask?.value
    s.renderTask?.cancel()
    XCTAssertNil(s.error)
    XCTAssertEqual(s.session.undoStack.count, history + 1)
    XCTAssertEqual(s.selectedLayerIDs, selected)
    XCTAssertEqual(s.document.selection, before.selection)
    for layer in s.document.layers {
      let bounds = try XCTUnwrap(Renderer.layoutBounds(layer, in: s.document, stored: true))
      XCTAssertEqual(bounds.x + bounds.width, 70)
    }
    let changed = s.document
    await s.undo()
    s.renderTask?.cancel()
    XCTAssertEqual(s.document, before)
    await s.redo()
    s.renderTask?.cancel()
    XCTAssertEqual(s.document, changed)
  }
  @MainActor func testSelectionCanvasEnablementAndTwoLayerDistribution() throws {
    let one = try store(count: 1)
    XCTAssertFalse(one.canLayout(.align(.left)))
    one.layoutTarget = .canvas
    XCTAssertTrue(one.canLayout(.align(.left)))
    one.layoutTarget = .selection
    one.perform(.selection(IntRect(x: 1, y: 1, width: 20, height: 20)))
    one.renderTask?.cancel()
    XCTAssertTrue(one.canLayout(.align(.left)))
    let two = try store(count: 2)
    XCTAssertTrue(two.canLayout(.align(.left)))
    for kind in LayerDistribution.allCases { XCTAssertFalse(two.canLayout(.distribute(kind))) }
    let three = try store()
    for kind in LayerDistribution.allCases { XCTAssertTrue(three.canLayout(.distribute(kind))) }
    three.perform(.lock(three.document.layers[0].id, true))
    three.renderTask?.cancel()
    XCTAssertFalse(three.canLayout(.align(.left)))
    XCTAssertFalse(three.canLayout(.distribute(.horizontally)))
  }
  @MainActor func testCancellationAndStalePreparationDoNotApply() async throws {
    let s = try store()
    let before = s.document
    s.arrangeLayers(.distribute(.horizontally))
    s.geometryTask?.cancel()
    await s.geometryTask?.value
    s.renderTask?.cancel()
    XCTAssertEqual(s.document, before)
    XCTAssertTrue(s.session.undoStack.isEmpty)
    XCTAssertFalse(s.geometryBusy)
    let prepared = try PreparedEdit(
      command: Renderer.layoutCommand(
        in: before, selected: s.layoutSelection, operation: .align(.left)), document: before)
    s.perform(.renameLayer(before.layers[0].id, "Changed while preparing"))
    s.renderTask?.cancel()
    let changed = s.document
    XCTAssertThrowsError(try s.session.executePrepared(prepared))
    XCTAssertEqual(s.document, changed)
  }
  @MainActor func testMenusExposeFourteenCommandsAndSelectAllLayersShortcut() throws {
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
    let layer = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "Layer")?.submenu)
    for (title, names, action) in [
      ("Align", LayerAlignment.allCases.map(\.rawValue), #selector(AppDelegate.alignLayers(_:))),
      (
        "Distribute", LayerDistribution.allCases.map(\.rawValue),
        #selector(AppDelegate.distributeLayers(_:))
      ),
    ] {
      let menu = try XCTUnwrap(layer.item(withTitle: title)?.submenu)
      XCTAssertEqual(menu.items.map(\.title), names)
      XCTAssertTrue(
        menu.items.allSatisfy {
          $0.action == action && $0.keyEquivalent.isEmpty
            && $0.representedObject as? String == $0.title
        })
    }
    let all = try XCTUnwrap(
      NSApp.mainMenu?.item(withTitle: "Select")?.submenu?.item(withTitle: "All Layers"))
    XCTAssertEqual(all.keyEquivalent, "a")
    XCTAssertEqual(all.keyEquivalentModifierMask, [.command, .option])
    XCTAssertEqual(all.action, #selector(AppDelegate.selectAllLayers))
  }
}
