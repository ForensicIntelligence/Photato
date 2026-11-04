import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ModeChannelWorkflowTests: XCTestCase {
  @MainActor func testHostedModePanelsKeepRowsWithinPanelBounds() async throws {
    let helper = LayerRevealTests()
    for mode in DocumentColorMode.componentModes {
      let before = try fixture(mode), store = EditorStore(document: before)
      defer { store.renderTask?.cancel() }
      store.surface = try Renderer.composite(before)
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 275, height: 420),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      defer { window.close() }
      window.appearance = NSAppearance(named: .darkAqua)
      let host = NSHostingView(rootView: ChannelsPanel(store: store).background(StudioTheme.panel)
        .foregroundStyle(Color(white: 0.88)).preferredColorScheme(.dark))
      window.contentView = host
      try await helper.settle(window)
      XCTAssertEqual(host.bounds.width, 275, accuracy: 0.5)
      XCTAssertEqual(host.bounds.height, 420, accuracy: 0.5)
      try helper.capture(window, named: "mode-channels-" + mode.rawValue)
      XCTAssertEqual(store.document, before); XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }
  func fixture(_ mode: DocumentColorMode = .cmyk, _ depth: PixelDepth = .u16) throws -> CraftDocument {
    var document = try CraftDocument(width: 4, height: 3, depth: depth)
    document = try document.convertingMode(.init(mode: mode, depth: depth))
    var native = try XCTUnwrap(document.layers[0].nativeMode)
    for c in try native.planes.indices { for i in 0..<12 {
      try native.set(c == mode.componentCount ? 1 : Float((i + c) % 4) / 4, component: c, index: i)
    } }
    document.layers[0].nativeMode = native; document.layers[0].content = .raster(try native.surface())
    return document
  }
  func testComponentPreviewsReadRetainedInkAndGrayWithoutChangingSource() throws {
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      let document = try fixture(mode, depth), native = try XCTUnwrap(document.layers[0].nativeMode)
      for c in 0..<mode.componentCount {
        let view = try ModeChannelPresentation.singleComponent(document, component: c)
        for y in 0..<3 { for x in 0..<4 {
          let raw = native.value(component: c, index: y * 4 + x)
          XCTAssertEqual(view.pixel(x: x, y: y).r, mode == .cmyk ? 1 - raw : raw, accuracy: depth == .u8 ? 1 / 255 : 0.00005)
        } }
      }
      XCTAssertEqual(try ModeChannelPresentation.thumbnails(document, maximumSize: 16).count, mode.componentCount + 1)
      XCTAssertEqual(document.layers[0].nativeMode, native)
    } }
  }
  @MainActor func testSelectionVisibilityFillAndTargetSwitchingShareHistory() async throws {
    let before = try fixture(), store = EditorStore(document: before), id = try XCTUnwrap(before.activeLayerID)
    defer { store.renderTask?.cancel() }
    try store.selectModeComponents([0, 3]); XCTAssertTrue(store.editingComponent)
    XCTAssertFalse(store.canDrawShapes); XCTAssertFalse(store.isCompositeColorTarget)
    try store.setModeComponentVisibility([3]); XCTAssertEqual(store.modeComponentTargets, [0, 3])
    XCTAssertEqual(store.document, before); XCTAssertTrue(store.session.undoStack.isEmpty)
    store.fill(color: .black, opacity: 0.5)
    var expected = before
    try Command.modeComponents(.init(layerID: id, components: [0, 3], operation: .fill(0, 0.5))).apply(to: &expected)
    XCTAssertEqual(store.document, expected); XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertThrowsError(try store.executeEditorCommand(.clear(UUID())))
    await store.undo(); XCTAssertEqual(store.document, before)
    try store.selectModeComponents([]); XCTAssertFalse(store.editingComponent)
    XCTAssertNil(store.modeComponentVisibility)
    try store.selectModeComponents([3]); store.selectMask(id)
    // A layer without a mask cannot acquire a mask editing target.
    try store.selectAlphaChannel(nil); XCTAssertTrue(store.modeComponentTargets.isEmpty)
    store.session = EditorSession(document: try fixture(.lab))
    XCTAssertTrue(store.modeComponentTargets.isEmpty); XCTAssertNil(store.modeComponentVisibility)
  }
  @MainActor func testBrushPreviewCommitAndFilterCancelRetainUnselectedPlanes() async throws {
    let before = try fixture(), store = EditorStore(document: before)
    defer { store.cancelBrush(); store.cancelFilter(); store.renderTask?.cancel() }
    try store.selectModeComponents([3]); store.tool = .brush
    store.brush.size = 1; store.brush.hardness = 1; store.brush.color = .black
    store.beginBrush(.init(x: 1.5, y: 1.5), zoom: 1)
    XCTAssertNotNil(store.brushGesture); await store.renderTask?.value
    XCTAssertThrowsError(try store.selectModeComponents([0]))
    XCTAssertEqual(store.modeComponentTargets, [3])
    XCTAssertEqual(store.document, before)
    store.finishBrush(); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertNotEqual(store.document, before)
    for c in [0, 1, 2, 4] { XCTAssertEqual(try store.document.layers[0].nativeMode?.planes[c], try before.layers[0].nativeMode?.planes[c]) }
    await store.undo(); XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.canBeginFilterKind(.average)); XCTAssertFalse(store.canBeginFilterKind(.cameraRaw))
    store.beginFilter(.average); await store.renderTask?.value
    XCTAssertNotNil(store.filterDraft); XCTAssertEqual(store.document, before)
    store.cancelFilter(); XCTAssertEqual(store.document, before)
    store.beginFilter(.average); store.commitFilter(); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertNotEqual(store.document, before)
    await store.undo(); XCTAssertEqual(store.document, before)
  }
  @MainActor func testHTTPSelectionEditVisibilityPreviewAndUndoEqualDesktop() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document)
      let before = try self.fixture(), desktop = EditorStore(document: before)
      defer { desktop.renderTask?.cancel() }
      document.store.session = EditorSession(document: before)
      let id = try XCTUnwrap(before.activeLayerID)
      let selected = try await helper.edit(service, document, "mode.channel.select", ["components": [3]])
      XCTAssertEqual(selected, 200); XCTAssertEqual(document.store.modeComponentTargets, [3])
      let share = try XCTUnwrap(service.shares.first)
      let stateResponse = try await helper.request(service, path: "/v1/documents/\(share.id)")
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: stateResponse.1) as? [String: Any])
      XCTAssertEqual(state["channelTarget"] as? String, "Black")
      XCTAssertEqual((state["channelView"] as? [String: Any])?["visible"] as? [String], ["Black"])
      try desktop.selectModeComponents([3]); desktop.fill(color: .black, opacity: 0.4)
      let edited = try await helper.edit(service, document, "mode.channel.edit", ["layerID": id.uuidString, "components": [3], "action": "fill", "value": 0, "opacity": 0.4])
      XCTAssertEqual(edited, 200); XCTAssertEqual(document.store.document, desktop.document)
      let visibility = try await helper.edit(service, document, "mode.channel.visibility", ["components": [3]])
      XCTAssertEqual(visibility, 200)
      let preview = try await helper.request(service, path: "/v1/documents/\(share.id)/channel-preview.png")
      XCTAssertEqual(preview.0.statusCode, 200)
      XCTAssertEqual(preview.1, try AutomationService.png(desktop.document, modeVisibility: [3]))
      let undone = try await helper.edit(service, document, "history.undo")
      XCTAssertEqual(undone, 200); XCTAssertEqual(document.store.document, before)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: document.store.documentModeState))
    }
  }
  @MainActor func testHTTPInvalidBusyStaleAndWrongTargetAreAtomic() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); document.store.session = EditorSession(document: try self.fixture())
      let before = document.store.document, id = try XCTUnwrap(before.activeLayerID)
      for components in [[-1], [4], [1, 1], []] {
        let status = try await helper.edit(service, document, "mode.channel.edit", ["layerID": id.uuidString, "components": components, "action": "invert"])
        XCTAssertEqual(status, 400); XCTAssertEqual(document.store.document, before)
      }
      try document.store.selectModeComponents([0])
      let mismatch = try await helper.edit(service, document, "mode.channel.edit", ["layerID": id.uuidString, "components": [3], "action": "invert"])
      XCTAssertEqual(mismatch, 422); XCTAssertEqual(document.store.document, before)
      let stale = try await helper.edit(service, document, "mode.channel.select", ["components": [3]], revision: "old")
      XCTAssertEqual(stale, 409)
      document.store.geometryBusy = true
      let busy = try await helper.edit(service, document, "mode.channel.select", ["components": [3]])
      XCTAssertEqual(busy, 409); document.store.geometryBusy = false
      XCTAssertEqual(document.store.document, before); XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
  func testHighDepthRGBRichPreviewAndSelectedPlaneValuesOutsideSelection() throws {
    for depth in [PixelDepth.u16, .f32] {
      var document = try CraftDocument(width: 4, height: 3, depth: depth)
      var pixels = try Surface(width: 4, height: 3, depth: depth, colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
      for y in 0..<3 { for x in 0..<4 { pixels.setPixel(x: x, y: y, Pixel(0.173, 0.367, 0.891, 0.54)) } }
      document.layers[0].content = .raster(pixels)
      document.selection = IntRect(x: 1, y: 1, width: 1, height: 1)
      let before = document, id = try XCTUnwrap(document.activeLayerID)
      try Command.modeComponents(.init(layerID: id, components: [0], operation: .fill(1, 1))).apply(to: &document)
      guard case .raster(let actual) = document.layers[0].content else { return XCTFail() }
      for y in 0..<3 { for x in 0..<4 where x != 1 || y != 1 {
        XCTAssertEqual(actual.linearPixel(x: x, y: y), pixels.linearPixel(x: x, y: y))
      } }
      var rich = before
      rich.layers.append(Layer(name: "Live fill", content: .fill(Pixel(0.9, 0.2, 0.1))))
      XCTAssertNoThrow(try ModeChannelPresentation.surface(rich, visible: [0]))
      XCTAssertEqual(rich.layers.count, 2)
    }
  }
  @MainActor func testHTTPStrokeFilterAndInvertShareNativeComponentEngine() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document)
      let before = try self.fixture(.lab), id = try XCTUnwrap(before.activeLayerID)
      let cases: [[String: Any]] = [
        ["action": "stroke", "points": [["x": 1.5, "y": 1.5]], "brush": ["size": 1, "hardness": 1, "color": ["r": 0, "g": 0, "b": 0, "a": 1]]],
        ["action": "filter", "filter": ["kind": "average"]], ["action": "invert"]]
      for fields in cases {
        document.store.session = EditorSession(document: before)
        var fields = fields; fields["layerID"] = id.uuidString; fields["components"] = [1]
        let request = try AutomationCommand(data: JSONSerialization.data(withJSONObject: ["command": "mode.channel.edit", "revision": "test", "parameters": fields]))
        var expected = before; try request.modeComponentEdit(in: before).apply(to: &expected)
        let status = try await helper.edit(service, document, "mode.channel.edit", fields)
        XCTAssertEqual(status, 200); XCTAssertEqual(document.store.document, expected)
        XCTAssertEqual(document.store.session.undoStack.count, 1)
        let undone = try await helper.edit(service, document, "history.undo")
        XCTAssertEqual(undone, 200); XCTAssertEqual(document.store.document, before)
      }
    }
  }
}
