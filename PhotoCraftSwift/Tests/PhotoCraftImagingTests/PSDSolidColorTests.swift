import CoreGraphics
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSDSolidColorTests: XCTestCase {
  static var root: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
  }
  func fixture(_ depth: PixelDepth) throws -> CraftDocument {
    var d = try CraftDocument(width: 64, height: 48, depth: depth)
    var fill = Layer(name: "Editable blue", content: .fill(Pixel(0.2, 0.4, 0.8)))
    fill.vectorMask = VectorMask(
      path: VectorPath(components: [
        PathComponent(
          knots: [
            PathPoint(8, 8), PathPoint(48, 8), PathPoint(48, 36), PathPoint(8, 36),
          ].map { PathKnot($0) }, closed: true)
      ]))
    var top = Layer(name: "Editable red", content: .fill(Pixel(0.8, 0.2, 0.1)))
    top.mask = try Surface(width: 12, height: 16, depth: depth, fill: .white)
    top.maskProperties = MaskProperties()
    top.maskProperties?.transform = .translation(50, 10)
    top.maskProperties?.outside = 0
    d.layers = [
      Layer(
        name: "White",
        content: .raster(try Surface(width: 64, height: 48, depth: depth, fill: .white))), fill,
      top,
    ]
    d.activeLayerID = top.id
    return d
  }
  func testSolidFillPSDAtAllDepthsRetainsEditableColorAndMasks() throws {
    for depth in PixelDepth.allCases {
      let d = try fixture(depth)
      let data = try PSDCodec.writeRasterLayers(d)
      let imported = try PSDCodec.read(data)
      for i in [1, 2] {
        guard case .fill(let color) = d.layers[i].content else { return XCTFail("Expected fill") }
        // Float PSD stores linear color; the native encoded representation rounds on transfer.
        let expectedColor = depth == .f32 ? SRGBTransfer.encoded(SRGBTransfer.linear(color)) : color
        XCTAssertEqual(imported.layers[i].content, .fill(expectedColor))
      }
      XCTAssertEqual(imported.layers[2].maskCoordinateTransform, .translation(50, 10))
      XCTAssertNotNil(imported.layers[1].vectorMask)
      let expected = try Renderer.composite(d)
      let actual = try Renderer.composite(imported)
      for y in 0..<d.height {
        for x in 0..<d.width {
          XCTAssertEqual(actual.pixel(x: x, y: y), expected.pixel(x: x, y: y))
        }
      }
      let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
      let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
      XCTAssertEqual(image.width, d.width)
      let independent = try RasterIO.surface(image, depth: depth)
      XCTAssertEqual(
        independent.pixel(x: 15, y: 15).b, expected.pixel(x: 15, y: 15).b, accuracy: 0.005)
      try data.write(
        to: Self.root.appendingPathComponent("artifacts/native-solid-\(depth.rawValue).psd"))
    }
  }
  func testDescriptorPreservedUntilColorChangesAndRasterizationRemovesIt() throws {
    var d = try PSDCodec.read(PSDCodec.writeRasterLayers(fixture(.u8)))
    let original = try XCTUnwrap(d.layers[1].sourceTags?["SoCo"])
    XCTAssertEqual(
      try PSDCodec.read(PSDCodec.writeRasterLayers(d)).layers[1].sourceTags?["SoCo"], original)
    d.layers[1].content = .fill(Pixel(0.9, 0.7, 0.3))
    let changed = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
    XCTAssertEqual(changed.layers[1].content, d.layers[1].content)
    XCTAssertNotEqual(changed.layers[1].sourceTags?["SoCo"], original)
    try Command.rasterize(d.layers[1].id, Renderer.layerSurface(d.layers[1], in: d)).apply(to: &d)
    let raster = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
    XCTAssertNil(raster.layers[1].sourceTags?["SoCo"])
    guard case .raster = raster.layers[1].content else { return XCTFail("Fill was not rasterized") }
  }
  func testSolidColorValidationAndFloatKeys() throws {
    let color = PSDDescriptor(
      "RGBC",
      items: [
        .init("redFloat", .number(0.25)), .init("greenFloat", .number(0.5)),
        .init("blueFloat", .number(0.75)),
      ])
    let d = PSDDescriptor("null", items: [.init("Clr ", .object(color))])
    XCTAssertEqual(try PSDSolidColor.read(d.encoded()), Pixel(0.25, 0.5, 0.75))
    var duplicate = d
    duplicate.items.append(duplicate.items[0])
    XCTAssertThrowsError(try PSDSolidColor.read(duplicate.encoded()))
    XCTAssertThrowsError(try PSDSolidColor.write(Pixel(1, 0, 0, 0.5)))
    XCTAssertThrowsError(try PSDSolidColor.write(Pixel(2, 0, 0)))
    var malformed = color
    malformed.items[0].value = .number(.nan)
    XCTAssertThrowsError(
      try PSDSolidColor.read(
        PSDDescriptor("null", items: [.init("Clr ", .object(malformed))]).encoded()))
  }
}

extension PSDSolidColorTests {
  func compare(_ bytes: Data) throws -> (maximum: Float, changed: Int, document: CraftDocument) {
    let d = try PSDCodec.read(bytes)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
    let reference = try RasterIO.surface(
      XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)), depth: d.depth)
    let actual = try Renderer.composite(d)
    var maximum: Float = 0
    var changed = 0
    for y in 0..<d.height {
      for x in 0..<d.width {
        let p = actual.pixel(x: x, y: y)
        let q = reference.pixel(x: x, y: y)
        maximum = max(maximum, abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a))
        if p.quantized(d.depth) != q.quantized(d.depth) { changed += 1 }
      }
    }
    return (maximum, changed, d)
  }
  func testPhotoshopSavedSolidFillsRetainTypesAndMeasureExactness() throws {
    var report: [[String: Any]] = []
    for depth in [8, 16, 32] {
      let url = try XCTUnwrap(
        Bundle.module.url(
          forResource: "photoshop-solid-\(depth)", withExtension: "psd", subdirectory: "Fixtures"))
      let result = try compare(Data(contentsOf: url))
      for i in [1, 2] {
        guard case .fill = result.document.layers[i].content else {
          return XCTFail("Editable fill lost")
        }
      }
      XCTAssertNotNil(result.document.layers[1].vectorMask)
      XCTAssertNotNil(result.document.layers[2].mask)
      // Regression bounds are not the user's exact-parity acceptance gate.
      if depth != 32 {
        XCTAssertEqual(result.changed, 0)
        XCTAssertEqual(result.maximum, 0)
      } else {
        XCTAssertLessThanOrEqual(result.maximum, 0.0000002)
      }
      report.append([
        "depth": depth, "maximum_encoded_error": result.maximum,
        "differing_pixels": result.changed, "exact_at_document_depth": result.changed == 0,
      ])
    }
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: Self.root.appendingPathComponent("artifacts/solid-photoshop-comparison.json"))
  }
  func testPinnedOriginalCorpusReportsUnsupportedAndNonExactResults() throws {
    let cases: [(String, Float?, Bool)] = [
      ("mask", 0.002, true), ("mask-disabled", 0, true),
      ("clipping-mask", 0.069, false), ("layer_mask_data", 0.080, false),
      ("mask-parameters-no-real-channel", 0.0085, false),
      ("mask-density-layermask", nil, false), ("masks2", nil, false),
    ]
    var report: [[String: Any]] = []
    for (name, bound, exact) in cases {
      let url = try XCTUnwrap(
        Bundle.module.url(
          forResource: "psdtools-" + name, withExtension: "psd", subdirectory: "Fixtures"))
      let bytes = try Data(contentsOf: url)
      if let bound {
        let result = try compare(bytes)
        XCTAssertLessThanOrEqual(result.maximum, bound, name)
        if exact { XCTAssertEqual(result.changed, 0, name) }
        report.append([
          "file": name + ".psd", "imported": true,
          "maximum_encoded_error": result.maximum, "differing_pixels": result.changed,
          "exact_at_document_depth": result.changed == 0,
        ])
      } else {
        do {
          _ = try PSDCodec.read(bytes)
          XCTFail("Update the corpus qualification for \(name)")
        } catch CraftError.unsupported(let reason) {
          XCTAssertTrue(reason.contains(name == "masks2" ? "Txt2" : "vowv"))
          report.append([
            "file": name + ".psd", "imported": false, "reason": reason,
            "exact_at_document_depth": false,
          ])
        }
      }
    }
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: Self.root.appendingPathComponent("artifacts/solid-corpus-comparison.json"))
  }
  func testFeatheredCanvasMaskMatchesReferenceEdgeWithoutMutatingEditableData() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "psdtools-mask-parameters-no-real-channel", withExtension: "psd",
        subdirectory: "Fixtures"))
    let bytes = try Data(contentsOf: url)
    let document = try PSDCodec.read(bytes)
    let before = try NativeArchive.encode(document)
    let actual = try Renderer.composite(document)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
    let reference = try RasterIO.surface(
      XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)), depth: document.depth)
    // The previous outside-color padding produced a 0.01432 green error at this corner.
    XCTAssertEqual(actual.pixel(x: 255, y: 0).g, reference.pixel(x: 255, y: 0).g, accuracy: 0.001)
    XCTAssertEqual(try NativeArchive.encode(document), before)
    XCTAssertEqual(try NativeArchive.decode(before), document)
    let saved = try PSDCodec.read(PSDCodec.writeRasterLayers(document))
    XCTAssertEqual(saved.layers.count, document.layers.count)
    for (original, reloaded) in zip(document.layers, saved.layers) where original.mask != nil {
      XCTAssertEqual(reloaded.mask, original.mask)
      // Fill-layer export normalizes its layer origin; the mask must stay in document space.
      XCTAssertEqual(reloaded.maskCoordinateTransform, original.maskCoordinateTransform)
      var originalProperties = original.effectiveMaskProperties
      var reloadedProperties = reloaded.effectiveMaskProperties
      originalProperties.transform = .identity
      reloadedProperties.transform = .identity
      XCTAssertEqual(reloadedProperties, originalProperties)
      XCTAssertEqual(reloaded.vectorMask, original.vectorMask)
    }
    let savedComposite = try Renderer.composite(saved)
    for y in 0..<document.height {
      for x in 0..<document.width {
        XCTAssertEqual(savedComposite.pixel(x: x, y: y), actual.pixel(x: x, y: y))
      }
    }
  }
}

extension PSDSolidColorTests {
  func testExportFillQuantizationMatrix() throws {
    var d = try CraftDocument(width: 256, height: 24, depth: .u16)
    d.layers = []
    let boundaries: [Float] = [
      0, 1, 0.5, Float(0.5).nextDown, Float(0.5).nextUp,
      0.5 / 32768, 1.5 / 32768, 2.5 / 32768, 32767.5 / 32768,
    ]
    for i in 0..<64 {
      let red = i < boundaries.count ? boundaries[i] : Float(i) / 63
      let color = Pixel(red, Float((i * 17) % 64) / 63, Float((i * 31) % 64) / 63)
      var fill = Layer(name: "Sample \(i)", content: .fill(color))
      fill.mask = try Surface(width: 4, height: 24, depth: .u16, fill: .white)
      fill.maskProperties = MaskProperties()
      fill.maskProperties?.transform = .translation(Double(i * 4), 0)
      fill.maskProperties?.outside = 0
      d.layers.append(fill)
    }
    d.activeLayerID = d.layers.last?.id
    let bytes = try PSDCodec.writeRasterLayers(d)
    XCTAssertEqual(try PSDCodec.read(bytes).layers.count, 64)
    try bytes.write(to: Self.root.appendingPathComponent("artifacts/native-solid-matrix16.psd"))
  }
}

extension PSDSolidColorTests {
  func testPhotoshop16BitFillQuantizationMatrixIsExact() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "photoshop-solid-matrix16", withExtension: "psd", subdirectory: "Fixtures"))
    let result = try compare(Data(contentsOf: url))
    XCTAssertEqual(result.document.layers.count, 64)
    XCTAssertEqual(result.maximum, 0)
    XCTAssertEqual(result.changed, 0)
  }
}
