import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class EditableGradientProfileTests: XCTestCase {
  func profile(_ name: CFString, _ depth: PixelDepth) throws -> Data {
    try NativeModeProfile.atDepth(XCTUnwrap(CGColorSpace(name: name)?.copyICCData() as Data?), mode: .rgb, depth: depth)
  }
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 48, height: 32, depth: depth)
    d.name = "Owned editable gradient profile"
    d.workingICC = try profile(CGColorSpace.sRGB, depth)
    let gradient = GradientDefinition(name: "Owned RGB HSB gray", colors: [
      .init(0, .rgb(Pixel(0.2, 0.6, 0.8))), .init(0.45, .hsb(hue: 25, saturation: 0.7, brightness: 0.8), midpoint: 0.3),
      .init(1, .gray(ink: 0.25), midpoint: 0.7)],
      opacity: [.init(0, 0.8), .init(1, 0.4, midpoint: 0.6)], smoothness: 0.5, method: .classic)
    var fill = GradientFill(gradient: gradient, aligned: false, dither: false)
    fill.placement.angle = 25
    var layer = Layer(name: "Editable gradient", content: .gradientFill(fill)); layer.opacity = 0.8
    layer.mask = try Surface(width: 48, height: 32, depth: depth, fill: .white)
    d.layers.append(layer)
    var paint = ShapePaint(color: Pixel(0.3, 0.4, 0.5)); paint.kind = .gradient; paint.gradient = fill
    var stroke = ShapeStroke(); stroke.paint = paint; stroke.width = 2; stroke.alignment = .inside
    let definition = ShapeDefinition(geometry: .init(kind: .ellipse, width: 24, height: 18), fill: paint, stroke: stroke)
    var shape = Layer(name: "Editable gradient vector", content: .shape(try ShapeContent(definition: definition)))
    shape.x = 8; shape.y = 6
    d.layers.append(shape); d.activeLayerID = shape.id
    d.selection = IntRect(x: 3, y: 2, width: 12, height: 10)
    try d.validate(); return d
  }
  func testOwnedLayeredRGBFixtureKeepsEditableControlsBeforeConversion() throws {
    for depth in PixelDepth.allCases {
      let source = try fixture(depth)
      XCTAssertEqual(source.layers.count, 3)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(source)), source)
      if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let root = URL(fileURLWithPath: path)
        try NativeArchive.encode(source).write(to: root.appendingPathComponent("editable-gradient-\(depth)-source.photato"))
        if depth == .u8 {
          // Vector-gradient PSD export has a separate known unsupported gate.
          // Keep the complete native fixture; use only the supported fill layers for the Photoshop reference.
          var reference = source; reference.layers.removeLast(); reference.activeLayerID = reference.layers.last?.id
          try DocumentIO.encode(reference, format: .psd).write(to: root.appendingPathComponent("editable-gradient-fill-source.psd"))
        }
      }
    }
  }
  func testRGBProfileConversionRetainsGradientLayersAndVectorControlsAndUndo() throws {
    for depth in PixelDepth.allCases {
      let source = try fixture(depth), p3 = try profile(CGColorSpace.displayP3, depth)
      XCTAssertFalse(ColorProfileInput.needsMerge(source, destination: .rgb))
      var session = EditorSession(document: source)
      try session.execute(ColorProfileInput.command(.init(.convert, profile: p3), in: source))
      let result = session.document
      XCTAssertEqual(result.layers.map(\.id), source.layers.map(\.id)); XCTAssertEqual(result.workingICC, p3)
      XCTAssertEqual(result.selection, source.selection)
      guard case .gradientFill(let before) = source.layers[1].content,
        case .gradientFill(let after) = result.layers[1].content,
        case .shape(let oldShape) = source.layers[2].content,
        case .shape(let newShape) = result.layers[2].content else { return XCTFail("Editable layers were flattened") }
      var controls = after; controls.gradient.colors = before.gradient.colors
      XCTAssertEqual(controls, before); XCTAssertNotEqual(after.gradient.colors, before.gradient.colors)
      XCTAssertEqual(newShape.definition?.components, oldShape.definition?.components)
      XCTAssertEqual(newShape.width, oldShape.width); XCTAssertEqual(newShape.height, oldShape.height)
      XCTAssertEqual(result.layers[1].mask, source.layers[1].mask)
      XCTAssertEqual(result.layers[2].x, source.layers[2].x); XCTAssertEqual(result.layers[2].y, source.layers[2].y)
      XCTAssertEqual(session.undoStack.count, 1)
      try session.undo(); XCTAssertEqual(session.document, source)
      try session.redo(); XCTAssertEqual(session.document, result)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(result)), result)
    }
  }

  func converted(_ source: CraftDocument) throws -> CraftDocument {
    var result = source
    try ColorProfileInput.command(.init(.convert, profile: profile(CGColorSpace.displayP3, source.depth)), in: source).apply(to: &result)
    return result
  }
  func testEveryGradientMethodAndBlackWhiteStopsRetainAllNonColorControls() throws {
    for depth in PixelDepth.allCases { for method in GradientMethod.allCases {
      var source = try fixture(depth)
      guard case .gradientFill(var fill) = source.layers[1].content else { return XCTFail("fill") }
      fill.gradient = .blackToWhite; fill.gradient.method = method
      fill.gradient.opacity = [.init(0, 0.25), .init(1, 0.75, midpoint: 0.3)]
      source.layers[1].content = .gradientFill(fill)
      let result = try converted(source)
      guard case .gradientFill(var output) = result.layers[1].content else { return XCTFail("flattened") }
      output.gradient.colors = fill.gradient.colors
      XCTAssertEqual(output, fill)
    } }
  }
  func testSameProfileConversionRetainsHSBGrayEncoding() throws {
    for depth in PixelDepth.allCases {
      let source = try fixture(depth), request = ColorProfileRequest(.convert, profile: try XCTUnwrap(source.workingICC))
      var result = source; try ColorProfileInput.command(request, in: source).apply(to: &result)
      XCTAssertEqual(result.layers[1].content, source.layers[1].content)
      guard case .shape(let a) = source.layers[2].content, case .shape(let b) = result.layers[2].content else { return XCTFail("shape") }
      XCTAssertEqual(a.definition?.fill.gradient, b.definition?.fill.gradient)
      XCTAssertEqual(a.definition?.stroke.paint.gradient, b.definition?.stroke.paint.gradient)
    }
  }
  func cachedFixture(_ depth: PixelDepth, stale: Bool = false) throws -> CraftDocument {
    var source = try fixture(depth)
    guard case .shape(var shape) = source.layers[2].content, let definition = shape.definition else { throw CraftError.invalid("Missing owned vector") }
    var captured = definition
    if stale { captured.fill.color = Pixel(0.1, 0.2, 0.3) }
    let pixels = try Surface(width: 10, height: 7, depth: depth, fill: Pixel(0.25, 0.45, 0.7, 0.5))
    shape.importedAppearance = .init(definition: captured, pixels: pixels, x: -3, y: -2, vectorRecord: Data("owned opaque vector source".utf8))
    let bounds = try shape.renderBounds(); shape.width = bounds.width; shape.height = bounds.height
    source.layers[2].content = .shape(shape); try source.validate(); return source
  }
  func testPristineImportedCacheKeepsBoundsAndPreservesOriginalRecordAsProvenance() throws {
    for depth in PixelDepth.allCases {
      let source = try cachedFixture(depth), result = try converted(source)
      guard case .shape(let before) = source.layers[2].content, case .shape(let after) = result.layers[2].content else { return XCTFail("shape") }
      let old = try XCTUnwrap(before.importedAppearance), cache = try XCTUnwrap(after.importedAppearance)
      XCTAssertEqual(cache.definition, after.definition); XCTAssertNil(cache.vectorRecord)
      XCTAssertEqual(try after.renderBounds(), try before.renderBounds())
      XCTAssertEqual(after.width, before.width); XCTAssertEqual(after.height, before.height)
      XCTAssertEqual(cache.x, old.x); XCTAssertEqual(cache.y, old.y)
      let input = try XCTUnwrap(old.pixels), actual = try XCTUnwrap(cache.pixels)
      var raster = source; let layer = Layer(name: "Owned cache", content: .raster(input))
      raster.layers = [layer]; raster.activeLayerID = layer.id
      guard case .raster(let expected) = try converted(raster).layers[0].content else { return XCTFail("raster") }
      XCTAssertEqual(actual, expected)
      for y in 0..<7 { for x in 0..<10 { XCTAssertEqual(actual.pixel(x: x, y: y).a, input.pixel(x: x, y: y).a) } }
      let data = try XCTUnwrap(result.layers[2].sourceTags?["PtVP"])
      let provenance = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
      XCTAssertEqual(provenance["version"] as? Int, 1)
      XCTAssertEqual(provenance["profileBase64"] as? String, source.workingICC?.base64EncodedString())
      XCTAssertEqual(provenance["recordBase64"] as? String, old.vectorRecord?.base64EncodedString())
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(result)), result)
      var session = EditorSession(document: source)
      try session.execute(ColorProfileInput.command(.init(.convert, profile: profile(CGColorSpace.displayP3, depth)), in: source))
      try session.undo(); XCTAssertEqual(session.document, source)
    }
  }
  func testStaleAppearanceCannotReactivateInTheDestinationProfile() throws {
    let source = try cachedFixture(.u16, stale: true), result = try converted(source)
    guard case .shape(let before) = source.layers[2].content, case .shape(let after) = result.layers[2].content else { return XCTFail("shape") }
    XCTAssertNil(after.importedAppearance)
    XCTAssertEqual(try before.renderBounds(), try after.renderBounds())
    XCTAssertNotNil(result.layers[2].sourceTags?["PtVP"])
    XCTAssertEqual(result.layers.map(\.id), source.layers.map(\.id))
  }
  func testProvenanceCollisionAndNonRGBDestinationRejectAtomically() throws {
    var source = try cachedFixture(.u8)
    source.layers[2].sourceTags = ["PtVP": Data("existing unrelated metadata".utf8)]
    var session = EditorSession(document: source)
    XCTAssertThrowsError(try session.execute(ColorProfileInput.command(.init(.convert, profile: profile(CGColorSpace.displayP3, .u8)), in: source)))
    XCTAssertEqual(session.document, source); XCTAssertTrue(session.undoStack.isEmpty)
    let plain = try fixture()
    XCTAssertTrue(ColorProfileInput.needsMerge(plain, destination: .cmyk))
    XCTAssertThrowsError(try ColorProfileInput.command(.init(.convert, profile: NativeModeProfile.standard(.cmyk, depth: .u8)), in: plain))
  }
  @MainActor func testNativePreviewCancelCommitAndHTTPShareEditableConversion() async throws {
    let source = try fixture(), expected = try converted(source), p3 = try profile(CGColorSpace.displayP3, .u8)
    let s = EditorStore(document: source); s.renderTask?.cancel()
    defer { s.cancelColorProfile(); s.renderTask?.cancel() }
    s.beginColorProfile(.convert)
    let cancelled = try XCTUnwrap(s.colorProfileWorkspace)
    try cancelled.loadProfile(p3); await cancelled.task?.value
    XCTAssertTrue(cancelled.ready, cancelled.error ?? "no preview")
    XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
    XCTAssertFalse(cancelled.request.mergeVisible)
    s.cancelColorProfile(); XCTAssertEqual(s.document, source)
    s.beginColorProfile(.convert)
    let commit = try XCTUnwrap(s.colorProfileWorkspace)
    try commit.loadProfile(p3); await commit.task?.value
    s.commitColorProfile(); await commit.commitTask?.value
    XCTAssertNil(s.colorProfileWorkspace, commit.error ?? "commit did not finish")
    XCTAssertEqual(s.document, expected); XCTAssertEqual(s.session.undoStack.count, 1)
    await s.undo(); XCTAssertEqual(s.document, source)
    await s.redo(); XCTAssertEqual(s.document, expected)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, doc in
      doc.store.renderTask?.cancel(); doc.store.session = EditorSession(document: source)
      defer { doc.store.cancelColorProfile(); doc.store.renderTask?.cancel() }
      try service.share(doc)
      let share = try XCTUnwrap(service.shares.first?.id)
      let denied = try await helper.request(service, path: "/v1/documents/\(share)/commands", body: [
        "command": "document.convertProfile", "revision": service.revision(doc.store),
        "parameters": ["profileBase64": p3.base64EncodedString()]], authenticate: false)
      XCTAssertEqual(denied.0.statusCode, 401); XCTAssertEqual(doc.store.document, source)
      // ICC edits need explicit document sharing, not the separate file-transfer permission.
      XCTAssertFalse(service.documentTransfersEnabled)
      let stale = try await helper.edit(service, doc, "document.convertProfile", ["profileBase64": p3.base64EncodedString()], revision: "stale")
      XCTAssertEqual(stale, 409); XCTAssertEqual(doc.store.document, source)
      doc.store.beginColorProfile(.convert)
      let busy = try await helper.edit(service, doc, "document.convertProfile", ["profileBase64": p3.base64EncodedString()])
      XCTAssertEqual(busy, 409); XCTAssertEqual(doc.store.document, source)
      doc.store.cancelColorProfile()
      let status = try await helper.edit(service, doc, "document.convertProfile", ["profileBase64": p3.base64EncodedString()])
      XCTAssertEqual(status, 200); XCTAssertEqual(doc.store.document, expected)
      XCTAssertEqual(doc.store.session.undoStack.count, 1)
    }
  }
  func testAdobeOutputProfileAndSupportedPSDGradientFillsUseSameConversion() throws {
    let original = try fixture(.u8), expected = try converted(original), p3 = try profile(CGColorSpace.displayP3, .u8)
    let url = URL(string: "https://example.test/owned-gradient.icc")!
    let output = try AdobeOutputProfile(["type": "custom", "name": "Owned Display P3", "imageMode": "rgb", "source": ["url": url.absoluteString]])
    XCTAssertEqual(try output.convert(original, resources: [url: p3], rasterOutput: false), expected)
    var source = original; source.layers.removeLast(); source.activeLayerID = source.layers.last?.id
    let request = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: [
      "image": ["width": 48, "height": 32, "mode": "rgb", "depth": 8], "edits": ["layers": []],
      "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60],
        "iccProfile": ["type": "custom", "name": "Owned Display P3", "imageMode": "rgb", "source": ["url": url.absoluteString]]]]
    ]), createComposite: true)
    let encoded = try AdobeActionAssets.execute(request, document: source, resources: [url: p3])
    XCTAssertEqual(encoded.count, 1)
    let reopened = try PSDCodec.read(try XCTUnwrap(encoded.first).data)
    XCTAssertEqual(reopened.workingICC, p3); XCTAssertEqual(reopened.layers.count, 2)
    guard case .gradientFill(let gradient) = reopened.layers[1].content else { return XCTFail("Adobe output flattened the gradient") }
    XCTAssertEqual(gradient.gradient.colors.count, 3)
    if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let root = URL(fileURLWithPath: path)
      try XCTUnwrap(encoded.first).data.write(to: root.appendingPathComponent("editable-gradient-fill-p3-output.psd"))
      try NativeArchive.encode(expected).write(to: root.appendingPathComponent("editable-gradient-u8-result.photato"))
    }
  }
  func testRasterOutputConvertsTheOriginalCompositeBeforeGradientInterpolationChanges() throws {
    for depth in PixelDepth.allCases {
      let source = try fixture(depth), p3 = try profile(CGColorSpace.displayP3, depth)
      let url = URL(string: "https://example.test/owned-raster-output.icc")!
      let output = try AdobeOutputProfile(["type": "custom", "name": "Owned P3", "imageMode": "rgb", "source": ["url": url.absoluteString]])
      XCTAssertFalse(ColorProfileInput.needsMerge(source, destination: .rgb))
      XCTAssertTrue(ColorProfileInput.needsRasterMerge(source, destination: .rgb))
      var request = ColorProfileRequest(.convert, profile: p3); request.mergeVisible = true
      var expected = source; try ColorProfileInput.command(request, in: source).apply(to: &expected)
      let actual = try output.convert(source, resources: [url: p3], rasterOutput: true)
      XCTAssertEqual(actual, expected); XCTAssertEqual(actual.layers.count, 1)
      let editable = try output.convert(source, resources: [url: p3], rasterOutput: false)
      XCTAssertEqual(editable.layers.count, 3)
      XCTAssertNotEqual(try Renderer.composite(actual), try Renderer.composite(editable))
    }
  }
  func testBoundedStopsClipOutOfGamutWhileFloatRasterKeepsExtendedSamples() throws {
    for depth in PixelDepth.allCases {
      var source = try CraftDocument(width: 2, height: 2, depth: depth)
      source.workingICC = try profile(CGColorSpace.displayP3, depth)
      let gradient = GradientDefinition(colors: [.init(0, .rgb(Pixel(1, 0, 0))), .init(1, .rgb(.white))])
      source.layers.append(Layer(name: "Bounded red", content: .gradientFill(.init(gradient: gradient))))
      source.layers.append(Layer(name: "Extended solid reference", content: .fill(Pixel(1, 0, 0))))
      source.activeLayerID = source.layers.last?.id
      var result = source
      try ColorProfileInput.command(.init(.convert, profile: profile(CGColorSpace.sRGB, depth)), in: source).apply(to: &result)
      guard case .gradientFill(let fill) = result.layers[1].content,
        case .rgb(let stop) = fill.gradient.colors[0].color,
        case .fill(let reference) = result.layers[2].content else { return XCTFail("editable content") }
      XCTAssertEqual(stop, Pixel(unit(reference.r), unit(reference.g), unit(reference.b)))
      XCTAssertEqual(stop.r, 1); XCTAssertEqual(stop.g, 0); XCTAssertEqual(stop.b, 0)
      XCTAssertTrue(reference.r > 1 || reference.g < 0 || reference.b < 0)
      XCTAssertEqual(fill.gradient.opacity, gradient.opacity)
    }
  }
  func testNonSRGBPSDGradientAdmissionDoesNotRelaxToneOrGrayStopGuards() throws {
    for depth in [PixelDepth.u8, .u16] {
      var source = try fixture(depth); source.layers.removeLast(); source.activeLayerID = source.layers.last?.id
      let result = try converted(source)
      for format in [DocumentIO.Format.psd, .psb] {
        let bytes = try DocumentIO.encode(result, format: format)
        let reopened = try PSDCodec.read(bytes)
        XCTAssertEqual(reopened.workingICC, result.workingICC)
        guard case .gradientFill(let actual) = reopened.layers[1].content,
          case .gradientFill(let expected) = result.layers[1].content else { return XCTFail("gradient") }
        XCTAssertEqual(actual.gradient.colors.map(\.color), expected.gradient.colors.map(\.color))
      }
      var gray = result
      guard case .gradientFill(var fill) = gray.layers[1].content else { return XCTFail("gradient") }
      fill.gradient.colors[0].color = .gray(ink: 0.25); gray.layers[1].content = .gradientFill(fill)
      XCTAssertThrowsError(try PSDCodec.read(DocumentIO.encode(gray, format: .psd)))
      var tone = result; tone.layers[1].content = .adjustment(.levels(.init()))
      XCTAssertThrowsError(try PSDCodec.read(DocumentIO.encode(tone, format: .psd)))
    }
  }
  func testOwnedPhotoshopDisplayP3ReferenceKeepsEditableGradientAndProfile() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "photoshop-owned-gradient-fill-p3-applecmm", withExtension: "psd", subdirectory: "Fixtures/ColorProfiles"))
    let document = try PSDCodec.read(Data(contentsOf: url))
    XCTAssertEqual(document.depth, .u8); XCTAssertEqual(document.width, 48); XCTAssertEqual(document.height, 32)
    XCTAssertEqual(document.layers.count, 2); XCTAssertNotNil(document.workingICC)
    XCTAssertEqual(CGColorSpace(iccData: try XCTUnwrap(document.workingICC) as CFData), CGColorSpace(name: CGColorSpace.displayP3))
    guard case .gradientFill(let fill) = document.layers[1].content else { return XCTFail("Photoshop gradient was flattened") }
    XCTAssertEqual(fill.gradient.name, "Owned RGB HSB gray"); XCTAssertEqual(fill.gradient.method, .classic)
    XCTAssertEqual(fill.placement.angle, 25); XCTAssertFalse(fill.aligned); XCTAssertFalse(fill.dither)
    XCTAssertEqual(fill.gradient.colors.map(\.position), [0, Float(1843) / 4096, 1])
    XCTAssertEqual(fill.gradient.colors.map(\.midpoint), [0.5, 0.3, 0.7])
    let components: [[Double]] = [[81.72637939453125, 150.908203125, 199.35104370117188],
      [192.5262451171875, 124.67514038085938, 73.1195068359375],
      [204.43267822265625, 204.43267822265625, 204.43267822265625]]
    for (stop, values) in zip(fill.gradient.colors, components) {
      XCTAssertEqual(stop.color, .rgb(Pixel(Float(values[0] / 255), Float(values[1] / 255), Float(values[2] / 255))))
    }
    XCTAssertEqual(fill.gradient.opacity.map(\.opacity), [0.8, 0.4])
    let reopened = try PSDCodec.read(DocumentIO.encode(document, format: .psd))
    XCTAssertEqual(reopened.layers[1].content, document.layers[1].content)
    XCTAssertEqual(reopened.workingICC, document.workingICC)
  }
  func testMaximumGeometryGradientConversionDoesNotAllocateDenseCanvas() throws {
    var source = try CraftDocument(width: Surface.maxDimension, height: Surface.maxDimension, depth: .u16)
    source.workingICC = try profile(CGColorSpace.sRGB, .u16)
    source.layers.append(Layer(name: "Sparse gradient", content: .gradientFill(.init(gradient: .blackToWhite))))
    source.activeLayerID = source.layers.last?.id
    let result = try converted(source)
    XCTAssertEqual(result.width, 300_000); XCTAssertEqual(result.height, 300_000)
    XCTAssertEqual(result.layers.count, 2)
    guard case .gradientFill = result.layers[1].content else { return XCTFail("flattened") }
    guard case .raster(let surface) = result.layers[0].content else { return XCTFail("raster") }
    XCTAssertLessThan(surface.allocatedBytes, 1_000_000)
  }
}
