import AppKit
import Foundation
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private final class PaletteObservationSignal: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  func hit() { lock.lock(); count += 1; lock.unlock() }
  var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

final class SharedPaintPaletteWorkflowTests: XCTestCase {
  let pink = Pixel(210.0/255,74.0/255,126.0/255), blue = Pixel(0.1,0.3,0.8)
  func model(_ depth: PixelDepth = .u8) throws -> CraftDocument { try AuxiliaryPaintColorWorkflowTests().fixture(depth) }
  @MainActor func pair(_ store: EditorStore, _ fg: Pixel, _ bg: Pixel, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(store.brush.color, fg, file: file, line: line)
    XCTAssertEqual(store.backgroundColor, bg, file: file, line: line)
    XCTAssertEqual(store.brush.backgroundColor, bg, file: file, line: line)
  }
  @MainActor func controller() throws -> CraftDocumentController {
    let folder = try DocumentPersistenceTests().directory()
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    return RecoveryIndexTests().controller(RecoveryIndexStore(directoryURL: folder))
  }
  @MainActor func request(_ service: AutomationService, _ file: CraftNSDocument, _ name: String,
    _ parameters: [String:Any], revision: String? = nil) async throws -> Int {
    let id = try XCTUnwrap(service.shares.first(where: { $0.document === file })?.id)
    let response = try await AutomationTests().request(service, path: "/v1/documents/\(id.uuidString)/commands",
      body: ["command":name, "revision":revision ?? service.revision(file.store), "parameters":parameters])
    return response.0.statusCode
  }

  @MainActor func captureHTTPColors(_ service: AutomationService, _ a: CraftNSDocument, _ b: CraftNSDocument, _ label: String) async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] else { return }
    var values: [Any] = []
    for file in [a,b] {
      let id = try XCTUnwrap(service.shares.first(where: { $0.document === file })?.id)
      let response = try await AutomationTests().request(service, path: "/v1/documents/\(id.uuidString)")
      XCTAssertEqual(response.0.statusCode, 200)
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String:Any])
      let brush = try XCTUnwrap(state["brush"] as? [String:Any])
      values.append(try XCTUnwrap(brush["colors"]))
    }
    let directory = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: ["interface":"actual HTTP document state", "documents":values], options: [.sortedKeys]).write(to: directory.appendingPathComponent("shared-palette-" + label + ".json"))
  }

  @MainActor func testControllerDocumentsShareImagePairButBrushSettingsPixelsAndHistoryStayLocal() throws {
    let c = try controller(), a = CraftNSDocument(model: try model()), b = CraftNSDocument(model: try model())
    c.addDocument(a); c.addDocument(b)
    defer { a.close(); b.close() }
    let da = a.store.document, db = b.store.document, bytes = try a.data(ofType: CraftNSDocument.nativeType)
    a.store.brush.size = 7; b.store.brush.size = 29
    a.store.brush.color = pink; a.store.backgroundColor = blue
    pair(b.store, pink, blue)
    XCTAssertEqual(a.store.brush.size, 7); XCTAssertEqual(b.store.brush.size, 29)
    XCTAssertTrue(a.store.paintPalette === b.store.paintPalette)
    XCTAssertEqual(a.store.document, da); XCTAssertEqual(b.store.document, db)
    XCTAssertTrue(a.store.session.undoStack.isEmpty); XCTAssertTrue(b.store.session.undoStack.isEmpty)
    XCTAssertFalse(a.isDocumentEdited); XCTAssertFalse(b.isDocumentEdited)
    XCTAssertEqual(try a.data(ofType: CraftNSDocument.nativeType), bytes)
  }

  @MainActor func testQuickMaskAndSavedAlphaShareAuxiliaryColorsAcrossAllNativeDepths() throws {
    for depth in PixelDepth.allCases {
      let palette = PaintPalette(), a = EditorStore(document: try model(depth), paintPalette: palette), b = EditorStore(document: try model(depth), paintPalette: palette)
      defer { a.renderTask?.cancel(); b.renderTask?.cancel() }
      let originalA = a.document, originalB = b.document
      a.brush.color = pink; a.backgroundColor = blue
      a.toggleQuickMask(); pair(a, .black, .white); a.swapColors(); a.toggleQuickMask()
      pair(a, pink, blue)
      b.toggleQuickMask(); pair(b, .white, .black)
      b.resetColors(); a.toggleQuickMask(); pair(a, .black, .white)
      try b.selectEditingChannel(.composite); pair(b, pink, blue)
      try b.selectAlphaChannel(try XCTUnwrap(b.document.alphaChannels?.first?.id))
      let gray = Pixel(0.25,0.25,0.25); b.brush.color = gray
      pair(a, gray, .white)
      XCTAssertEqual(a.document.layers, originalA.layers)
      XCTAssertEqual(b.document.layers, originalB.layers)
      XCTAssertEqual(a.document.alphaChannels, originalA.alphaChannels)
      XCTAssertEqual(b.document.alphaChannels, originalB.alphaChannels)
    }
  }

  @MainActor func testObservationAndBrushRevisionFollowPeerColorChangesWithoutHistory() throws {
    let palette = PaintPalette(), a = EditorStore(document: try model(), paintPalette: palette), b = EditorStore(document: try model(), paintPalette: palette)
    defer { a.renderTask?.cancel(); b.renderTask?.cancel() }
    let signal = PaletteObservationSignal(), before = b.brushRevision, document = b.document
    withObservationTracking { _ = b.brush.color; _ = b.backgroundColor } onChange: { signal.hit() }
    a.brush.color = pink
    XCTAssertGreaterThan(signal.value, 0); XCTAssertGreaterThan(b.brushRevision, before)
    pair(b, pink, .white)
    let revision = b.brushRevision; a.brush.color = pink; XCTAssertEqual(b.brushRevision, revision)
    XCTAssertEqual(b.document, document); XCTAssertTrue(b.session.undoStack.isEmpty)
  }

  @MainActor func testClosedEditorDetachesAndNewDocumentInheritsControllerPalette() throws {
    let c = try controller(), a = CraftNSDocument(model: try model()), b = CraftNSDocument(model: try model())
    c.addDocument(a); c.addDocument(b)
    defer { a.close(); b.close() }
    a.store.brush.color = pink; a.store.backgroundColor = blue
    c.removeDocument(a)
    XCTAssertFalse(a.store.paintPalette === b.store.paintPalette)
    a.store.brush.color = .white; pair(b.store, pink, blue)
    c.removeDocument(b)
    let fresh = CraftNSDocument(model: try model()); c.addDocument(fresh)
    defer { fresh.close() }
    pair(fresh.store, pink, blue)
    b.store.resetColors(); pair(fresh.store, pink, blue)
  }

  @MainActor func testAdoptionAndDetachKeepRevisionsMonotonicAndStandaloneEditorsIndependent() throws {
    let a = EditorStore(document: try model()), b = EditorStore(document: try model()), shared = PaintPalette()
    defer { a.renderTask?.cancel(); b.renderTask?.cancel() }
    for i in 0..<8 { shared.set(PaintColorPair(foreground: i%2 == 0 ? pink:.white, background: blue), auxiliary: false) }
    let before = a.brushRevision; a.adoptPaintPalette(shared); XCTAssertGreaterThan(a.brushRevision, before)
    pair(b, .black, .white)
    let attached = a.brushRevision; a.detachPaintPalette(); XCTAssertGreaterThan(a.brushRevision, attached)
    let detachedPair = a.activePaintColorPair
    shared.set(PaintColorPair(), auxiliary: false)
    XCTAssertEqual(a.activePaintColorPair, detachedPair)
  }

  @MainActor func testPersistenceRestoresPairsAndRejectsInvalidVersionsValuesAndOversizedRecords() throws {
    let suite = "Photato.palette-tests." + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let p = PaintPalette(defaults: defaults), image = PaintColorPair(foreground: pink, background: blue), auxiliary = PaintColorPair(foreground: Pixel(0.25,0.25,0.25), background: .white)
    p.set(image, auxiliary: false); p.set(auxiliary, auxiliary: true)
    let restored = PaintPalette(defaults: defaults)
    XCTAssertEqual(restored.colors(auxiliary: false), image); XCTAssertEqual(restored.colors(auxiliary: true), auxiliary)
    let data = try XCTUnwrap(defaults.data(forKey: PaintPalette.key))
    var record = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String:Any]); record["version"] = 999
    defaults.set(try JSONSerialization.data(withJSONObject: record), forKey: PaintPalette.key)
    XCTAssertEqual(PaintPalette(defaults: defaults).colors(auxiliary: false), PaintColorPair())
    record["version"] = 2
    var invalidImage = try XCTUnwrap(record["image"] as? [String:Any]), invalidFG = try XCTUnwrap(invalidImage["foreground"] as? [String:Any]); invalidFG["r"] = 2; invalidImage["foreground"] = invalidFG; record["image"] = invalidImage
    defaults.set(try JSONSerialization.data(withJSONObject: record), forKey: PaintPalette.key)
    XCTAssertEqual(PaintPalette(defaults: defaults).colors(auxiliary: false), PaintColorPair())
    defaults.set(Data(repeating: 0, count: 4097), forKey: PaintPalette.key)
    XCTAssertEqual(PaintPalette(defaults: defaults).colors(auxiliary: true), PaintColorPair())
    let app = AppDelegate(workspaces: WorkspaceLibrary(), paintPalette: restored)
    XCTAssertTrue(app.controller.paintPalette === restored)
  }

  @MainActor func testIncludedColorPresetAndXDUpdateOnlyActiveSharedPairAtomically() throws {
    let p = PaintPalette(), library = BrushLibrary(), a = EditorStore(document: try model(), brushes: library, paintPalette: p), b = EditorStore(document: try model(), paintPalette: p)
    defer { a.renderTask?.cancel(); b.renderTask?.cancel() }
    a.brush.color = pink; a.backgroundColor = blue
    a.toggleQuickMask(); b.toggleQuickMask(); a.tool = .brush
    var brush = Brush(); brush.size = 11; brush.color = Pixel(0.25,0.25,0.25); brush.backgroundColor = Pixel(0.75,0.75,0.75)
    var preset = BrushPreset(name: "Owned shared mask colors", brush: brush); preset.includeColor = true
    try library.save(preset); try a.selectBrush(preset.id)
    pair(b, brush.color, try XCTUnwrap(brush.backgroundColor))
    XCTAssertNotEqual(b.brush.size, 11)
    let revision = p.revision; a.swapColors(); XCTAssertEqual(p.revision, revision + 1)
    pair(b, try XCTUnwrap(brush.backgroundColor), brush.color)
    a.resetColors(); pair(b, .black, .white)
    try b.selectEditingChannel(.composite); pair(b, pink, blue)
  }

  @MainActor func testStartedNativeStrokeRetainsItsCapturedColorsWhenPeerChangesPalette() async throws {
    let p = PaintPalette(), a = EditorStore(document: try model(), paintPalette: p), b = EditorStore(document: try model(), paintPalette: p)
    defer { a.cancelBrush(); a.renderTask?.cancel(); b.renderTask?.cancel() }
    a.tool = .brush; a.brush.size = 4; a.brush.hardness = 1; a.brush.color = Pixel(1,0,0)
    let original = a.document
    a.beginBrush(.init(x: 8, y: 8), zoom: 1)
    let captured = try XCTUnwrap(a.brushGesture)
    b.brush.color = blue
    XCTAssertEqual(a.brush.color, blue); XCTAssertEqual(captured.brush.color, Pixel(1,0,0))
    a.finishBrush()
    for _ in 0..<500 where a.geometryBusy { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertFalse(a.geometryBusy); XCTAssertNil(a.error)
    guard case .raster(let pixels) = a.document.layers[0].content else { return XCTFail("Missing raster") }
    XCTAssertEqual(pixels.pixel(x: 8, y: 8), Pixel(1,0,0))
    XCTAssertEqual(a.session.undoStack.count, 1)
    await a.undo(); XCTAssertEqual(a.document, original); pair(a, blue, .white)
  }

  @MainActor func testRealHTTPColorsShareAndPeerOldRevisionsInvalidBusyPatchesStayAtomic() async throws {
    try await AutomationTests().withService(pressedMouseButtons: {0}) { service, a in
      a.store.session = EditorSession(document: try self.model()); try service.share(a)
      let b = CraftNSDocument(model: try self.model()); service.controller.addDocument(b); try service.share(b)
      defer { b.close() }
      let oldB = service.revision(b.store), originalA = a.store.document, originalB = b.store.document
      let changed = try await self.request(service, a, "brush.configure", ["brush":["color":BrushAPI.json(self.pink),"backgroundColor":BrushAPI.json(self.blue)]])
      XCTAssertEqual(changed, 200); self.pair(b.store, self.pink, self.blue)
      XCTAssertNotEqual(service.revision(b.store), oldB)
      let stale = try await self.request(service, b, "brush.configure", ["brush":["size":5]], revision: oldB)
      XCTAssertEqual(stale, 409)
      let invalid = try await self.request(service, a, "brush.configure", ["brush":["color":BrushAPI.json(Pixel.white),"backgroundColor":["r":2,"g":0,"b":0,"a":1]]])
      XCTAssertEqual(invalid, 400); self.pair(b.store, self.pink, self.blue)
      a.store.geometryBusy = true
      let busy = try await self.request(service, a, "brush.configure", ["brush":["color":BrushAPI.json(Pixel.white)]])
      a.store.geometryBusy = false; XCTAssertEqual(busy, 409); self.pair(b.store, self.pink, self.blue)
      XCTAssertEqual(a.store.document, originalA); XCTAssertEqual(b.store.document, originalB)
      XCTAssertTrue(a.store.session.undoStack.isEmpty); XCTAssertTrue(b.store.session.undoStack.isEmpty)
      let state = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: b.store.paintColorState))
      XCTAssertNoThrow(try BrushAPI.merge(state, schema: PaintColorPair.stateSchema))
      XCTAssertNotNil(BrushAPI.capabilities["sharedPaintColors"])
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
      try await self.captureHTTPColors(service, a, b, "image")
      a.store.toggleQuickMask(); b.store.toggleQuickMask(); a.store.swapColors()
      self.pair(b.store, .white, .black)
      try await self.captureHTTPColors(service, a, b, "auxiliary")
    }
  }

  @MainActor func testHTTPPaintUsesSharedImageAndMaskColorsWithNativeResultsAndOneUndo() async throws {
    try await AutomationTests().withService(pressedMouseButtons: {0}) { service, a in
      var first=try self.model(),second=try self.model()
      first.layers[0].content = .raster(try Surface(width:first.width,height:first.height,fill:.black))
      second.layers[0].content = .raster(try Surface(width:second.width,height:second.height,fill:.black))
      a.store.session = EditorSession(document:first);try service.share(a)
      let b = CraftNSDocument(model:second);service.controller.addDocument(b);try service.share(b)
      defer { b.close() }
      b.store.brush.size = 4; b.store.brush.hardness = 1
      let configured = try await self.request(service, a, "brush.configure", ["brush":["color":BrushAPI.json(Pixel.white)]])
      XCTAssertEqual(configured, 200)
      for mask in [false,true] {
        if mask {
          a.store.toggleQuickMask(); b.store.toggleQuickMask()
          // Establish the shared auxiliary color rather than inherit another test's remembered white ink.
          let configured = try await self.request(service, a, "brush.configure", ["brush":["color":BrushAPI.json(Pixel.black)]])
          XCTAssertEqual(configured, 200);XCTAssertEqual(b.store.brush.color,.black)
        }
        let original = b.store.document, history = b.store.session.undoStack.count
        let native = EditorStore(document: original)
        defer { native.renderTask?.cancel() }
        native.brush = b.store.brush
        let points: [StrokePoint] = [.init(x: 8, y: 8)]
        native.stroke(points, brush: native.brush)
        let painted = try await self.request(service, b, "paint.stroke", ["target":mask ? "quickMask":"pixels","points":BrushAPI.json(points)])
        XCTAssertEqual(painted, 200); XCTAssertEqual(b.store.document, native.document)
        XCTAssertEqual(b.store.session.undoStack.count, history + 1)
        await b.store.undo(); XCTAssertEqual(b.store.document, original)
      }
    }
  }

  @MainActor func testSessionReopenRetainsSharedColorsWithoutSerializingPaletteOrTargetHistory() throws {
    let c = try controller(), a = CraftNSDocument(model: try model()), b = CraftNSDocument(model: try model())
    c.addDocument(a); c.addDocument(b)
    defer { a.close(); b.close() }
    let original = a.store.document, bytes = try a.data(ofType: CraftNSDocument.nativeType)
    b.store.brush.color = pink; b.store.backgroundColor = blue
    a.store.toggleQuickMask(); a.store.swapColors()
    try a.read(from: bytes, ofType: CraftNSDocument.nativeType)
    XCTAssertEqual(a.store.document, original); pair(a.store, pink, blue)
    XCTAssertEqual(try a.data(ofType: CraftNSDocument.nativeType), bytes)
    b.store.toggleQuickMask(); pair(b.store, .white, .black)
  }
}
