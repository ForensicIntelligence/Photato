import SwiftUI
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class BrushSectionToggleTests: XCTestCase {
  @MainActor func testSidebarAndHTTPShareSettingsGuardsAndSubsequentStroke() async throws {
    // Independent request paths catch a sidebar checkbox bound to the wrong flag.
    let paths: [(String, [String])] = [
      ("shape", ["shape", "enabled"]), ("scattering", ["scattering", "enabled"]),
      ("texture", ["texture", "enabled"]), ("dual", ["dual", "enabled"]),
      ("colorDynamics", ["colorDynamics", "enabled"]), ("transfer", ["transfer", "enabled"]),
      ("pose", ["pose", "enabled"]), ("noise", ["noise"]), ("wetEdges", ["wetEdges"]),
      ("buildUp", ["buildUp"]), ("protectTexture", ["protectTexture"])
    ]
    let helper = AutomationTests()
    try await helper.withService(brushes: BrushLibrary(), pressedMouseButtons: { 0 }) { service, document in
      let original = try CraftDocument(width: 40, height: 32)
      document.store.session = EditorSession(document: original)
      document.store.selectedLayerIDs = [original.layers[0].id]
      let native = EditorStore(document: original, actions: ActionLibrary(), brushes: BrushLibrary())
      defer { native.cancelBrush(); native.renderTask?.cancel() }
      let panel = BrushSettingsPanel(store: native)
      var base = Brush(); base.size = 8; base.opacity = 0.7
      base.color = Pixel(0.2, 0.4, 0.8); base.backgroundColor = .white; base.settings = .init()
      base.settings!.shape.size.jitter = 0.25; base.settings!.scattering.amount.jitter = 0.2
      base.settings!.scattering.count = 2; base.settings!.dual.size = 6
      base.settings!.texture.scale = 0.7; base.settings!.smoothing.amount = 0.1
      base.settings!.lockedSections = ["shape", "texture", "noise"]
      native.brush = base
      try service.share(document)
      var status = try await helper.edit(service, document, "brush.configure", ["brush": BrushAPI.json(base)])
      XCTAssertEqual(status, 200); XCTAssertEqual(document.store.brush, native.brush)
      let revision = service.revision(document.store)
      for key in ["tip", "smoothing", "symmetry", "unknown"] { XCTAssertNil(panel.sectionEnabled(key)) }
      func patch(_ path: [String], _ enabled: Bool) -> [String: Any] {
        var value: Any = enabled
        for key in path.reversed() { value = [key: value] }
        return ["settings": value]
      }
      for (key, path) in paths {
        let binding = try XCTUnwrap(panel.sectionEnabled(key))
        for enabled in [true, false] {
          binding.wrappedValue = enabled
          status = try await helper.edit(service, document, "brush.configure", ["brush": patch(path, enabled)])
          XCTAssertEqual(status, 200, key); XCTAssertEqual(native.brush, document.store.brush, key)
          XCTAssertEqual(binding.wrappedValue, enabled, key)
          XCTAssertEqual(native.brushOptions.lockedSections, base.settings!.lockedSections)
          XCTAssertEqual(native.document, original); XCTAssertEqual(document.store.document, original)
          XCTAssertTrue(native.session.undoStack.isEmpty); XCTAssertTrue(document.store.session.undoStack.isEmpty)
          let unchanged = service.revision(document.store)
          binding.wrappedValue = enabled
          status = try await helper.edit(service, document, "brush.configure", ["brush": patch(path, enabled)])
          XCTAssertEqual(status, 200); XCTAssertEqual(service.revision(document.store), unchanged)
        }
      }
      XCTAssertNotEqual(service.revision(document.store), revision)
      let metadata = try XCTUnwrap(BrushAPI.capabilities["sectionToggles"] as? [String: Any])
      let mapping = try XCTUnwrap(metadata["sections"] as? [[String: String]])
      XCTAssertEqual(Dictionary(uniqueKeysWithValues: mapping.map { ($0["section"]!, $0["brushPath"]!) }),
        Dictionary(uniqueKeysWithValues: paths.map { ($0.0, "settings." + $0.1.joined(separator: ".")) }))
      XCTAssertEqual(metadata["command"] as? String, "brush.configure")
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: BrushAPI.capabilities))

      let unchanged = native.brush
      native.tool = .brush; native.beginBrush(.init(x: 8, y: 12), zoom: 1)
      try XCTUnwrap(panel.sectionEnabled("shape")).wrappedValue = true
      XCTAssertEqual(native.brush, unchanged); native.cancelBrush()
      native.geometryBusy = true
      try XCTUnwrap(panel.sectionEnabled("texture")).wrappedValue = true
      XCTAssertEqual(native.brush, unchanged); native.geometryBusy = false
      document.store.geometryBusy = true
      status = try await helper.edit(service, document, "brush.configure", ["brush": patch(["shape", "enabled"], true)])
      XCTAssertEqual(status, 409); document.store.geometryBusy = false
      status = try await helper.edit(service, document, "brush.configure", ["brush": patch(["shape", "enabled"], true)], revision: "stale")
      XCTAssertEqual(status, 409)
      status = try await helper.edit(service, document, "brush.configure", ["brush": ["settings": ["shape": ["enabled": "true"]]]])
      XCTAssertEqual(status, 400); XCTAssertEqual(document.store.brush, unchanged)

      // Use the actual native gesture's captured seed/settings for deterministic API replay.
      try XCTUnwrap(panel.sectionEnabled("shape")).wrappedValue = true
      native.beginBrush(.init(x: 8, y: 12, pressure: 0.6, time: 0), zoom: 1)
      native.extendBrush(.init(x: 26, y: 18, time: 100))
      let gesture = try XCTUnwrap(native.brushGesture)
      let captured = gesture.brush, points = gesture.points
      native.finishBrush(); await native.geometryTask?.value
      XCTAssertNil(native.error); XCTAssertEqual(native.session.undoStack.count, 1)
      status = try await helper.edit(service, document, "brush.configure", ["brush": BrushAPI.json(captured)])
      XCTAssertEqual(status, 200)
      status = try await helper.edit(service, document, "paint.stroke", ["target": "pixels", "points": BrushAPI.json(points)])
      XCTAssertEqual(status, 200); XCTAssertEqual(document.store.document, native.document)
      XCTAssertEqual(try NativeArchive.encodeChunked(document.store.document), try NativeArchive.encodeChunked(native.document))
      XCTAssertEqual(document.store.session.undoStack.count, 1)
      _ = await native.requestHistory(redo: false).value
      status = try await helper.edit(service, document, "history.undo")
      XCTAssertEqual(status, 200); XCTAssertEqual(native.document, original); XCTAssertEqual(document.store.document, original)
    }
  }
}
