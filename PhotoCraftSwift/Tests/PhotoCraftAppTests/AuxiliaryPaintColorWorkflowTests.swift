import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class AuxiliaryPaintColorWorkflowTests: XCTestCase {
  let imageColor = Pixel(210.0 / 255, 74.0 / 255, 126.0 / 255)
  let imageBackground = Pixel(0.1, 0.3, 0.8)
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try CraftDocument(width: 24, height: 16, depth: depth)
    document.selection = .init(x: 4, y: 4, width: 12, height: 8)
    document.alphaChannels = [.init(name: "Saved", pixels: try Surface(width: 24, height: 16, depth: depth, fill: .white))]
    return document
  }
  @MainActor func setImageColors(_ store: EditorStore) {
    store.brush.color = imageColor; store.backgroundColor = imageBackground
  }
  @MainActor func assertPair(_ store: EditorStore, _ foreground: Pixel, _ background: Pixel, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(store.brush.color, foreground, file: file, line: line)
    XCTAssertEqual(store.backgroundColor, background, file: file, line: line)
    XCTAssertEqual(store.brush.backgroundColor, background, file: file, line: line)
  }

  @MainActor func testImageAndMaskPairsFollowPhotoshopSwitchesAndRememberXAcrossReentry() throws {
    let store = EditorStore(document: try fixture())
    defer { store.renderTask?.cancel() }
    setImageColors(store)
    let original = store.document
    store.toggleQuickMask()
    assertPair(store, .black, .white)
    XCTAssertTrue(store.auxiliaryPaintColorsActive)
    store.swapColors()
    assertPair(store, .white, .black)
    let entered = store.document, history = store.session.undoStack.count
    try store.selectEditingChannel(.composite)
    assertPair(store, imageColor, imageBackground)
    try store.selectQuickMaskChannel()
    assertPair(store, .white, .black)
    XCTAssertEqual(store.document, entered)
    XCTAssertEqual(store.session.undoStack.count, history)
    store.toggleQuickMask()
    assertPair(store, imageColor, imageBackground)
    store.toggleQuickMask()
    assertPair(store, .white, .black)
    XCTAssertEqual(store.document.layers, original.layers)
    XCTAssertEqual(store.document.alphaChannels, original.alphaChannels)
  }

  @MainActor func testDefaultQuickMaskBrushUsesBlackEvenWhenImageForegroundWasColored() throws {
    for depth in PixelDepth.allCases {
      let store = EditorStore(document: try fixture(depth))
      defer { store.renderTask?.cancel() }
      setImageColors(store)
      store.brush.size = 4; store.brush.hardness = 1; store.tool = .brush
      store.toggleQuickMask()
      let original = store.document, history = store.session.undoStack.count
      store.stroke([.init(x: 8, y: 8)], brush: store.brush)
      XCTAssertNil(store.error)
      XCTAssertEqual(store.document.quickMask?.pixels.pixel(x: 8, y: 8).r, 0)
      XCTAssertEqual(store.document.layers, original.layers)
      XCTAssertEqual(store.document.alphaChannels, original.alphaChannels)
      XCTAssertEqual(store.session.undoStack.count, history + 1)
    }
  }

  @MainActor func testHiddenEyeOptionsCancelAndHistoryKeepTheCorrectColorPair() async throws {
    let store = EditorStore(document: try fixture())
    defer { store.cancelChannelDialog(); store.renderTask?.cancel() }
    setImageColors(store)
    store.toggleQuickMask(); store.swapColors()
    let original = store.document
    try store.setQuickMaskVisibility(false)
    assertPair(store, .white, .black)
    store.beginChannelDialog(.quickOptions)
    let draft = try XCTUnwrap(store.channelDialog)
    draft.options.opacity = 0.37; store.cancelChannelDialog()
    assertPair(store, .white, .black)
    XCTAssertEqual(store.document, original)
    await store.undo()
    XCTAssertNil(store.document.quickMask)
    assertPair(store, imageColor, imageBackground)
    await store.redo()
    XCTAssertEqual(store.document, original)
    assertPair(store, .white, .black)
    XCTAssertFalse(store.isQuickMaskVisible)
  }

  @MainActor func testSavedAlphaAndCompositeSwitchColorsWithoutChangingAnyNativeDepth() throws {
    for depth in PixelDepth.allCases {
      let store = EditorStore(document: try fixture(depth))
      defer { store.renderTask?.cancel() }
      setImageColors(store)
      let original = store.document
      try store.selectAlphaChannel(try XCTUnwrap(original.alphaChannels?.first?.id))
      assertPair(store, .black, .white)
      store.swapColors()
      try store.selectEditingChannel(.composite)
      assertPair(store, imageColor, imageBackground)
      try store.selectAlphaChannel(try XCTUnwrap(original.alphaChannels?.first?.id))
      assertPair(store, .white, .black)
      XCTAssertEqual(store.document, original)
      XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }

  @MainActor func testResetAffectsOnlyActivePairAndIncludedPresetUpdatesRealBackground() throws {
    let library = BrushLibrary(), store = EditorStore(document: try fixture(), brushes: library)
    defer { store.renderTask?.cancel() }
    setImageColors(store); store.tool = .brush; store.toggleQuickMask()
    var brush = Brush(); brush.color = Pixel(0.25, 0.25, 0.25); brush.backgroundColor = Pixel(0.75, 0.75, 0.75)
    var preset = BrushPreset(name: "Owned gray pair", brush: brush); preset.includeColor = true
    try library.save(preset); try store.selectBrush(preset.id)
    assertPair(store, brush.color, try XCTUnwrap(brush.backgroundColor))
    store.resetColors(); assertPair(store, .black, .white)
    try store.selectEditingChannel(.composite)
    assertPair(store, imageColor, imageBackground)
    store.resetColors(); assertPair(store, .black, .white)
    try store.selectQuickMaskChannel(); assertPair(store, .black, .white)
  }

  @MainActor func testNativeReopenAndSessionReplacementNeverSerializeSessionPaintColors() throws {
    let file = CraftNSDocument(model: try fixture())
    defer { file.close() }
    let store = file.store
    setImageColors(store)
    let original = store.document, plain = try file.data(ofType: CraftNSDocument.nativeType)
    store.toggleQuickMask(); store.swapColors()
    try file.read(from: plain, ofType: CraftNSDocument.nativeType)
    XCTAssertEqual(store.document, original)
    assertPair(store, imageColor, imageBackground)
    XCTAssertEqual(try file.data(ofType: CraftNSDocument.nativeType), plain)
    var other = original; other.id = UUID()
    try Command.channel(.quickMask(true, .init())).apply(to: &other)
    store.session = EditorSession(document: other)
    assertPair(store, .white, .black)
    store.session = EditorSession(document: original)
    assertPair(store, imageColor, imageBackground)
  }

  @MainActor func testHTTPConfigurationTracksBothNativePairsAndRejectsInvalidStaleBusyPatches() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      let store = file.store
      store.session = EditorSession(document: try self.fixture()); try service.share(file)
      let original = store.document
      let configured = try await helper.edit(service, file, "brush.configure", ["brush":["color":BrushAPI.json(self.imageColor), "backgroundColor":BrushAPI.json(self.imageBackground)]])
      XCTAssertEqual(configured, 200)
      self.assertPair(store, self.imageColor, self.imageBackground)
      let staleRevision = service.revision(store)
      let entered = try await helper.edit(service, file, "channel.edit", ["action":"quickMask", "enabled":true])
      XCTAssertEqual(entered, 200); self.assertPair(store, .black, .white)
      let mask = store.document, history = store.session.undoStack.count
      let gray = Pixel(0.25, 0.25, 0.25)
      let changed = try await helper.edit(service, file, "brush.configure", ["brush":["color":BrushAPI.json(gray), "backgroundColor":BrushAPI.json(Pixel.black)]])
      XCTAssertEqual(changed, 200); self.assertPair(store, gray, .black)
      let returned = try await helper.edit(service, file, "channel.view", ["target":"RGB"])
      XCTAssertEqual(returned, 200); self.assertPair(store, self.imageColor, self.imageBackground)
      let back = try await helper.edit(service, file, "channel.view", ["target":"quickMask"])
      XCTAssertEqual(back, 200); self.assertPair(store, gray, .black)
      let state = store.paintColorState
      XCTAssertEqual(state["context"] as? String, "auxiliary")
      let raw = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: state))
      XCTAssertNoThrow(try BrushAPI.merge(raw, schema: PaintColorPair.stateSchema))
      let stale = try await helper.edit(service, file, "brush.configure", ["brush":["size":5]], revision: staleRevision)
      XCTAssertEqual(stale, 409)
      let invalid = try await helper.edit(service, file, "brush.configure", ["brush":["color":BrushAPI.json(Pixel.white), "backgroundColor":["r":2,"g":0,"b":0,"a":1]]])
      XCTAssertEqual(invalid, 400); self.assertPair(store, gray, .black)
      store.geometryBusy = true
      let busy = try await helper.edit(service, file, "brush.configure", ["brush":["size":5]])
      XCTAssertEqual(busy, 409); store.geometryBusy = false
      XCTAssertEqual(store.document, mask)
      XCTAssertEqual(store.document.layers, original.layers)
      XCTAssertEqual(store.session.undoStack.count, history)
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }

  @MainActor func testHTTPDefaultMaskPaintingMatchesNativeAndOneUndo() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      let store = file.store
      store.session = EditorSession(document: try self.fixture()); try service.share(file)
      let configured = try await helper.edit(service, file, "brush.configure", ["brush":["size":4,"hardness":1,"color":BrushAPI.json(self.imageColor),"backgroundColor":BrushAPI.json(self.imageBackground)]])
      XCTAssertEqual(configured, 200)
      let entered = try await helper.edit(service, file, "channel.edit", ["action":"quickMask", "enabled":true])
      XCTAssertEqual(entered, 200)
      let original = store.document, history = store.session.undoStack.count
      let native = EditorStore(document: original)
      defer { native.renderTask?.cancel() }
      native.brush = store.brush
      let points: [StrokePoint] = [.init(x: 8, y: 8)]
      native.stroke(points, brush: native.brush)
      let painted = try await helper.edit(service, file, "paint.stroke", ["target":"quickMask","points":BrushAPI.json(points)])
      XCTAssertEqual(painted, 200)
      XCTAssertEqual(store.document, native.document)
      XCTAssertEqual(store.document.quickMask?.pixels.pixel(x: 8, y: 8).r, 0)
      XCTAssertEqual(store.document.layers, original.layers)
      XCTAssertEqual(store.session.undoStack.count, history + 1)
      await store.undo(); XCTAssertEqual(store.document, original)
      self.assertPair(store, .black, .white)
    }
  }
}
