import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class FilterWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var document = try CraftDocument(width: 8, height: 8)
    var pixels = try Surface(width: 8, height: 8)
    for y in 0..<8 { for x in 0..<8 {
      pixels.setPixel(x: x, y: y, Pixel(0.25 + Float(x)/14, 0.25 + Float(y)/14, x == y ? 0.75 : 0.25))
    } }
    document.layers[0].content = .raster(pixels)
    return document
  }
  @MainActor func testPreviewCancelCommitUndoAndPSDForAllFilters() async throws {
    for kind in RasterFilter.Kind.allCases {
      var original = try fixture()
      if kind == .ntscColors,case .raster(var pixels)=original.layers[0].content {pixels.setPixel(x:0,y:0,Pixel(1,0,0));original.layers[0].content = .raster(pixels)}
      let store = EditorStore(document: original)
      defer { store.renderTask?.cancel() }
      store.beginFilter(kind)
      if kind.isImmediateClassicDetail || kind == .ntscColors || kind.isImmediatePixelate || kind.isImmediateRender || kind.isImmediateStylize {
        await store.geometryTask?.value;XCTAssertNil(store.filterDraft);XCTAssertNil(store.error)
        var expected=original
        if kind.isImmediateRender {expected=store.document;XCTAssertNotEqual(expected,original)} else {try Command.applyFilter(original.layers[0].id,RasterFilter(kind)).apply(to:&expected)}
        XCTAssertEqual(store.document,expected);XCTAssertEqual(store.session.undoStack.count,1)
        await store.undo();XCTAssertEqual(store.document,original);await store.redo();XCTAssertEqual(store.document,expected);continue
      }
      XCTAssertTrue(store.hasToneDraft)
      XCTAssertFalse(store.canBeginFilter)
      await store.renderTask?.value
      XCTAssertNil(store.error)
      XCTAssertEqual(store.document, original)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      store.cancelFilter()
      XCTAssertNil(store.filterDraft)
      XCTAssertEqual(store.document, original)
      store.beginFilter(kind)
      if kind == .tiles {store.filterDraft?.filter.stylize?.count=2;store.filterDraft?.filter.stylize?.maxOffset=80}
      if kind.isOtherVideo {store.filterDraft?.filter=OtherVideoWorkflowTests().filter(kind)}
      if kind.isDistortion { store.filterDraft?.filter=DistortionWorkflowTests().filter(kind) }
      if kind == .perspectiveWarp { store.filterDraft?.filter.perspective?.planes=[.init(source:[PathPoint(0,0),PathPoint(8,0),PathPoint(8,6),PathPoint(0,6)],destination:[PathPoint(0,0),PathPoint(9,0),PathPoint(10,6),PathPoint(1,6)])] }
      if kind == .puppetWarp { store.filterDraft?.filter.puppet?.pins = [.init(source:PathPoint(1,1)),.init(source:PathPoint(6,6),destination:PathPoint(7,4))] }
      if kind == .lensCorrection { store.filterDraft?.filter.lens?.distortion = 40 }
      if kind == .adaptiveWideAngle { store.filterDraft?.filter.wideAngle?.scale = 80 }
      if kind == .cameraRaw { store.filterDraft?.filter.cameraRaw?.exposure = 1 }
      if kind == .liquify { store.filterDraft?.filter.liquify?.strokes = [.init(size:6,points:[[4,4],[6,4]])] }
      let draft = try XCTUnwrap(store.filterDraft)
      var expected = original
      try Command.applyFilter(draft.id, draft.filter).apply(to: &expected)
      store.commitFilter()
      await store.geometryTask?.value
      XCTAssertNil(store.error)
      XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertEqual(store.session.undoStack.last?.label, kind.title)
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(expected))
      XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .u8), try Renderer.composite(expected).rgbaData(depth: .u8))
      await store.undo(); XCTAssertEqual(store.document, original)
      await store.redo(); XCTAssertEqual(store.document, expected)
    }
  }
  @MainActor func testCancellationAndInvalidDraftCannotCommit() async throws {
    let original = try fixture(), store = EditorStore(document: original)
    defer { store.renderTask?.cancel() }
    store.beginFilter(.boxBlur)
    store.filterDraft?.filter.radius = -1
    store.commitFilter()
    XCTAssertNotNil(store.filterDraft)
    XCTAssertEqual(store.document, original)
    store.cancelFilter(); store.error = nil
    store.beginFilter(.gaussianBlur); store.commitFilter()
    store.geometryTask?.cancel(); await store.geometryTask?.value
    XCTAssertEqual(store.document, original)
    XCTAssertFalse(store.geometryBusy)
  }
  @MainActor func testHTTPMatchesDesktopAndRejectsStaleBusyAndInvalidRequests() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      let original = try fixture()
      for kind in RasterFilter.Kind.allCases {
        shared.store.session = EditorSession(document: original)
        var expected = original
        let filter=kind.isDistortion ? DistortionWorkflowTests().filter(kind):RasterFilter(kind)
        try Command.applyFilter(original.layers[0].id, filter).apply(to: &expected)
        let parameters: [String: Any] = ["layerID": original.layers[0].id.uuidString, "filter": filter.apiState]
        let result = try await helper.edit(service, shared, "filter.apply", parameters)
        XCTAssertEqual(result, 200)
        XCTAssertEqual(shared.store.document, expected)
        let undo = try await helper.edit(service, shared, "history.undo")
        XCTAssertEqual(undo, 200); XCTAssertEqual(shared.store.document, original)
      }
      let parameters: [String: Any] = ["layerID": original.layers[0].id.uuidString, "filter": ["kind": "boxBlur"]]
      let stale = try await helper.edit(service, shared, "filter.apply", parameters, revision: "stale")
      XCTAssertEqual(stale, 409)
      shared.store.beginFilter(.boxBlur)
      let busy = try await helper.edit(service, shared, "filter.apply", parameters)
      XCTAssertEqual(busy, 409)
      shared.store.cancelFilter()
      let bad = try await helper.edit(service, shared, "filter.apply", ["layerID": original.layers[0].id.uuidString, "filter": ["kind": "mosaic", "radius": 1]])
      XCTAssertEqual(bad, 400)
      XCTAssertEqual(shared.store.document, original)
    }
  }
  @MainActor func testFactoryMenuBindingsAllEight() throws {
    try PhotoshopMenuTests().withMenus { _, menu in
      func find(_ menu: NSMenu, _ path: String) -> NSMenuItem? {
        for item in menu.items {
          if item.identifier?.rawValue == path { return item }
          if let child = item.submenu, let match = find(child, path) { return match }
        }
        return nil
      }
      for path in AppDelegate.filterMenus.keys {
        let item = try XCTUnwrap(find(menu, path), path)
        XCTAssertEqual(item.action, #selector(AppDelegate.rasterFilterDialog(_:)))
        if path == "Filter > Adaptive Wide Angle…" { XCTAssertEqual(item.keyEquivalent,"a");XCTAssertEqual(item.keyEquivalentModifierMask,[.option,.shift,.command]) }
      }
    }
  }
}
