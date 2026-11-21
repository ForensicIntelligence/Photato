import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class GenerativeExpandTests: XCTestCase {
  private func fixture(depth: PixelDepth = .u8, background: Bool = false) throws -> CraftDocument {
    var doc = try CraftDocument(width: 96, height: 80, depth: depth)
    var pixels = try Surface(width: 96, height: 80, depth: depth,
      colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
    for y in 0..<80 {
      for x in 0..<96 {
        let r = (x < 48 ? Float(0.25) : 0.65) + Float(y) / 500
        let color = Pixel(depth == .f32 && y < 40 ? 2 * r : r, 0.55, 0.3, 1)
        if depth == .f32 { pixels.setLinearPixel(x: x, y: y, color) }
        else { pixels.setPixel(x: x, y: y, color) }
      }
    }
    if !background { pixels.setPixel(x: 20, y: 16, .clear) }
    doc.layers[0].content = .raster(pixels)
    if background { try Command.backgroundLayer(.fromLayer(doc.layers[0].id, .white)).apply(to: &doc) }
    doc.selection = IntRect(x: 18, y: 15, width: 6, height: 6)
    return doc
  }

  func testFourSidedExpansionPreservesPixelsDepthLayersAndHistory() throws {
    let request = CropRequest(x: -14, y: -11, width: 127, height: 106)
    for depth in PixelDepth.allCases {
      let source = try fixture(depth: depth)
      let command = try GenerativeExpand.prepare(request, in: source, prompt: "", seed: 1, count: 1) { _, mask in
        XCTAssertTrue(mask.contains(0))
        XCTAssertTrue(mask.contains(1))
        return [try Surface(width: 512, height: 512, fill: Pixel(0.05, 0.2, 0.9))]
      }
      XCTAssertEqual(command.label, "Generative Expand")
      var session = EditorSession(document: source)
      try session.executePrepared(PreparedEdit(command: command, document: source))
      let edited = session.document
      XCTAssertNil(edited.selection)
      XCTAssertEqual(edited.layers.count, 2)
      XCTAssertEqual(edited.layers[0].id, source.layers[0].id)
      XCTAssertEqual(edited.layers[0].content, source.layers[0].content)
      XCTAssertEqual(edited.layers[0].x, 14)
      XCTAssertEqual(edited.layers[0].y, 11)
      XCTAssertEqual(edited.layers[1].name, "Generative Expand")
      let before = try Renderer.composite(source), after = try Renderer.composite(edited)
      let retained = try after.cropped(to: IntRect(x: 14, y: 11, width: 96, height: 80))
      XCTAssertEqual(try retained.rgbaData(depth: depth), try before.rgbaData(depth: depth))
      let mask = try XCTUnwrap(edited.layers[1].mask)
      for y in 0..<106 { for x in 0..<127 {
        XCTAssertEqual(mask.pixel(x: x, y: y).r, x >= 14 && x < 110 && y >= 11 && y < 91 ? 0 : 1)
      } }
      for (x, y, a, b) in [(13, 25, 14, 25), (110, 26, 109, 26), (29, 10, 29, 11), (33, 91, 33, 90)] {
        XCTAssertTrue(after.pixel(x: x, y: y).hasSameBits(as: after.pixel(x: a, y: b)))
      }
      XCTAssertGreaterThan(after.pixel(x: 1, y: 2).b, 0.8)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(edited)), edited)
      XCTAssertEqual(session.undoStack.count, 1)
      try session.undo()
      XCTAssertEqual(session.document, source)
      try session.redo()
      XCTAssertEqual(session.document, edited)
    }
  }

  func testOneSidedExpandKeepsBackgroundAndReopensEditablePSBVariations() throws {
    let source = try fixture(background: true)
    let request = CropRequest(x: 0, y: 0, width: 120, height: 80)
    var edited = source
    let command = try GenerativeExpand.prepare(request, in: source, prompt: "extend the background", seed: 29, count: 2) { _, _ in
      try [Pixel(0.2, 0.8, 0.5), Pixel(0.8, 0.2, 0.5)].map { try Surface(width: 512, height: 512, fill: $0) }
    }
    try command.apply(to: &edited)
    XCTAssertTrue(edited.layers[0].isBackground)
    XCTAssertEqual(edited.layers.last?.x, 96)
    XCTAssertEqual(edited.layers.last?.mask?.width, 24)
    let before = try Renderer.composite(source)
    for psb in [false, true] {
      var reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(edited, format: psb ? .psb : .psd))
      let layer = try XCTUnwrap(reopened.layers.last)
      let choices = try XCTUnwrap(GenerativeFillVariations.read(layer))
      XCTAssertEqual(choices.entries.map(\.seed), [29, 30])
      XCTAssertEqual(layer.mask, edited.layers.last?.mask)
      let first = try Renderer.composite(reopened)
      try SmartObjectLayerCompIO.selection(in: reopened, layerID: layer.id, compID: choices.entries[1].id).apply(to: &reopened)
      let second = try Renderer.composite(reopened)
      XCTAssertNotEqual(first.pixel(x: 113, y: 39), second.pixel(x: 113, y: 39))
      for pixels in [first, second] {
        let inside = try pixels.cropped(to: IntRect(x: 0, y: 0, width: 96, height: 80))
        XCTAssertEqual(try inside.rgbaData(depth: .u8), try before.rgbaData(depth: .u8))
        XCTAssertEqual(pixels.pixel(x: 96, y: 39), pixels.pixel(x: 95, y: 39))
      }
    }
  }

  func testInvalidFramesAndOversizedBorderFailBeforeInference() throws {
    let source = try fixture()
    var rotated = CropRequest(x: -4, y: -4, width: 104, height: 88)
    rotated.angle = 5
    for request in [
      CropRequest(x: 0, y: 0, width: 96, height: 80),
      CropRequest(x: 1, y: 0, width: 104, height: 80),
      CropRequest(x: -5, y: 0, width: 98, height: 80),
      CropRequest(x: -1, y: 0, width: Surface.maxDimension + 1, height: 80),
      rotated,
    ] {
      XCTAssertThrowsError(try GenerativeExpand.prepare(request, in: source, prompt: "", seed: 1, count: 1) { _, _ in
        XCTFail("Invalid geometry reached the model")
        return []
      })
    }
  }

  func testDeepMultiEdgeWindowsRetainOriginalAndSwitchEditableVariations() throws {
    let original = try fixture()
    let request = CropRequest(x: -17, y: -12, width: 4_350, height: 108)
    let retained = try GenerativeExpand.protectedCanvas(for: request, in: original)
    var calls = 0
    let command = try GenerativeExpand.prepare(request, in: original, prompt: "new background", seed: 17, count: 2) { _, mask in
      XCTAssertTrue(mask.contains(0), "Every window needs source or previously synthesized context.")
      XCTAssertTrue(mask.contains(1))
      let alternating: Float = calls.isMultiple(of: 2) ? 0.15 : 0.65
      calls += 1
      return try [Pixel(alternating, 0.55, 0.3), Pixel(alternating, 0.25, 0.45)].map {
        try Surface(width: 512, height: 512, fill: $0)
      }
    }
    XCTAssertGreaterThan(calls, 20)
    var session = EditorSession(document: original)
    try session.executePrepared(PreparedEdit(command: command, document: original))
    let edited = session.document
    let above = try XCTUnwrap(edited.layers.last)
    XCTAssertTrue(above.smartObject?.sourceBytes.isFileBacked == true)
    let record = try XCTUnwrap(GenerativeFillVariations.read(above))
    XCTAssertEqual(record.entries.map(\.seed), [17, 18])
    let before = try Renderer.composite(original)
    let rendered = try Renderer.composite(edited)
    XCTAssertEqual(try rendered.cropped(to: retained).rgbaData(depth: .u8), try before.rgbaData(depth: .u8))
    for (x, y) in [(0, 0), (4_349, 0), (0, 107), (4_349, 107), (2_598, 60), (214, 45)] {
      XCTAssertEqual(rendered.pixel(x: x, y: y).a, 1, "Generated border at \(x), \(y)")
      XCTAssertEqual(above.mask?.pixel(x: x, y: y).r, 1)
    }
    XCTAssertEqual(above.mask?.pixel(x: retained.x + 20, y: retained.y + 16).r, 0)
    for x in stride(from: 384, to: 4_300, by: 384) {
      XCTAssertLessThan(abs(rendered.pixel(x: x - 1, y: 54).r - rendered.pixel(x: x, y: 54).r), 0.08)
    }
    for format in [PSDFileFormat.psd, .psb] {
      var reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(edited, format: format))
      let layer = try XCTUnwrap(reopened.layers.last)
      let alternatives = try XCTUnwrap(GenerativeFillVariations.read(layer))
      XCTAssertEqual(alternatives.entries, record.entries)
      XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .u8), try rendered.rgbaData(depth: .u8))
      try SmartObjectLayerCompIO.selection(in: reopened, layerID: layer.id, compID: alternatives.entries[1].id).apply(to: &reopened)
      let different = try Renderer.composite(reopened)
      XCTAssertNotEqual(different.pixel(x: 3_620, y: 55), rendered.pixel(x: 3_620, y: 55))
      XCTAssertEqual(try different.cropped(to: retained).rgbaData(depth: .u8), try before.rgbaData(depth: .u8))
    }
    XCTAssertEqual(session.undoStack.count, 1)
    try session.undo()
    XCTAssertEqual(session.document, original)
  }

  @MainActor func testRealWideCanvasMatchesNativeAndHTTPWithOneUndo() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_LAMA_MODEL"], LocalGenerativeFill.supported else {
      throw XCTSkip("Requires the optional LaMa model.")
    }
    let key = GenerativeFillModelPreference.key
    let previous = UserDefaults.standard.data(forKey: key)
    UserDefaults.standard.set(try GenerativeFillModelPreference.bookmark(for: URL(fileURLWithPath: path, isDirectory: true)), forKey: key)
    defer { UserDefaults.standard.set(previous, forKey: key) }
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      var original = try CraftDocument(width: 4_160, height: 48)
      var image = try Surface(width: 4_160, height: 48, fill: Pixel(0.42, 0.66, 0.79))
      try image.mapPixels(in: IntRect(x: 0, y: 24, width: 4_160, height: 24)) { x, _, _ in
        Pixel(0.35 + Float(x) / 10_000, 0.54, 0.31)
      }
      original.layers[0].content = .raster(image)
      let store = shared.store
      store.session = EditorSession(document: original)
      try service.share(shared)
      store.chooseTool(WorkspaceCatalog.tool("crop"))
      var crop = try XCTUnwrap(store.cropDraft)
      crop.frame.scaleY = 137.5
      crop.frame.centerY = 33
      store.updateCrop(crop)
      store.beginGenerativeExpand()
      let draft = try XCTUnwrap(store.generativeFillDraft)
      store.generateFill(draft)
      await store.geometryTask?.value
      XCTAssertNil(draft.error)
      XCTAssertNil(store.cropDraft)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let native = try Renderer.composite(store.document)
      XCTAssertEqual(native.height, 66)
      XCTAssertEqual(try native.cropped(to: IntRect(x: 0, y: 0, width: 4_160, height: 48)).rgbaData(depth: .u8),
        try image.rgbaData(depth: .u8))
      XCTAssertEqual(native.pixel(x: 4_159, y: 65).a, 1)
      let mask = try XCTUnwrap(store.activeLayer?.mask)
      XCTAssertEqual(mask.width, 4_160)
      XCTAssertEqual(mask.height, 18)
      await store.undo()
      XCTAssertEqual(store.document, original)
      let code = try await helper.edit(service, shared, GenerativeFillAPI.expand,
        ["x": 0, "y": 0, "width": 4_160, "height": 66], timeout: 240)
      XCTAssertEqual(code, 200)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), try native.rgbaData(depth: .u8))
      XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo()
      XCTAssertEqual(store.document, original)
    }
  }

  @MainActor func testRealModelsCropHandlesNativeAPIAndUndo() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard LocalGenerativeFill.supported,
      let contextURL = environment["PHOTATO_TEST_LAMA_MODEL"],
      let promptURL = environment["PHOTATO_TEST_PROMPT_FILL_MODEL"] else {
      throw XCTSkip("Requires the two optional local models.")
    }
    let keys = [GenerativeFillModelPreference.key, GenerativeFillModelPreference.promptKey]
    let previous = keys.map { UserDefaults.standard.data(forKey: $0) }
    defer { for (key, saved) in zip(keys, previous) { UserDefaults.standard.set(saved, forKey: key) } }
    for (key, path) in zip(keys, [contextURL, promptURL]) {
      let url = URL(fileURLWithPath: path, isDirectory: true)
      UserDefaults.standard.set(try GenerativeFillModelPreference.bookmark(for: url), forKey: key)
    }
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      var source = try self.fixture(background: true)
      source.setCoverageSelection(nil)
      let store = shared.store
      store.session = EditorSession(document: source)
      try service.share(shared)
      let before = try Renderer.composite(source)
      for prompt in ["", "extend the warm studio backdrop with a soft shadow"] {
        store.chooseTool(WorkspaceCatalog.tool("crop"))
        XCTAssertFalse(store.canBeginGenerativeExpand)
        let canvas = CraftCanvas(store: store)
        canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
        store.zoom = 2
        let crop = try XCTUnwrap(store.cropDraft)
        let start = canvas.viewPoint(crop.frame.handles[4])
        let end = CGPoint(x: start.x + 45, y: start.y + 32)
        @MainActor func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
          try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, at: start))
        canvas.mouseDragged(with: try event(.leftMouseDragged, at: end))
        canvas.mouseUp(with: try event(.leftMouseUp, at: end))
        let actualDraft = try XCTUnwrap(store.cropDraft)
        let actualRequest = try actualDraft.request(background: store.backgroundColor)
        XCTAssertEqual(actualRequest.x, 0)
        XCTAssertEqual(actualRequest.y, 0)
        XCTAssertTrue(store.canBeginGenerativeExpand)
        store.beginGenerativeExpand()
        let draft = try XCTUnwrap(store.generativeFillDraft)
        let frame = try XCTUnwrap(draft.expandRequest)
        store.cancelGenerativeFill()
        XCTAssertNotNil(store.cropDraft)
        XCTAssertEqual(store.document, source)
        store.beginGenerativeExpand()
        let generation = try XCTUnwrap(store.generativeFillDraft)
        generation.prompt = prompt
        generation.seed = 472130
        generation.variationCount = 1
        store.generateFill(generation)
        await store.geometryTask?.value
        XCTAssertNil(generation.error)
        XCTAssertNil(store.cropDraft)
        XCTAssertEqual(store.session.undoStack.count, 1)
        let native = try Renderer.composite(store.document)
        let kept = try GenerativeExpand.protectedCanvas(for: frame, in: source)
        XCTAssertEqual(try native.cropped(to: kept).rgbaData(depth: .u8), try before.rgbaData(depth: .u8))
        XCTAssertGreaterThan(native.width, before.width)
        XCTAssertGreaterThan(native.height, before.height)
        if !prompt.isEmpty { XCTAssertEqual(store.activeLayer.flatMap(GenerativeFillVariations.read)?.entries.count, 1) }
        await store.undo()
        XCTAssertEqual(store.document, source)

        var parameters: [String: Any] = ["x": frame.x, "y": frame.y, "width": frame.width, "height": frame.height]
        if !prompt.isEmpty { parameters["prompt"] = prompt; parameters["seed"] = 472130 }
        let code = try await helper.edit(service, shared, GenerativeFillAPI.expand, parameters, timeout: 240)
        XCTAssertEqual(code, 200)
        XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), try native.rgbaData(depth: .u8))
        XCTAssertEqual(store.session.undoStack.count, 1)
        await store.undo()
        XCTAssertEqual(store.document, source)
      }
    }
  }
}
