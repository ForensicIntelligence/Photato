import XCTest

@testable import PhotoCraftCore

final class PatternTests: XCTestCase {
  func tile(depth: PixelDepth = .f32) throws -> RasterPattern {
    var s = try Surface(width: 2, height: 2, depth: depth, fill: Pixel(1, 0, 0))
    s.setPixel(x: 1, y: 0, Pixel(0, 0, 1, 0))
    s.setPixel(x: 0, y: 1, Pixel(0, 1, 0, 0.5))
    s.setPixel(x: 1, y: 1, Pixel(0, 0, 1))
    return try .init(name: "Tile", surface: s)
  }
  func testIdentityNegativeWrapAndPremultipliedTransparentEdge() throws {
    let pattern = try tile()
    let sampler = try PatternSampler(pattern)
    XCTAssertEqual(sampler.sample(x: 0.5, y: 0.5), Pixel(1, 0, 0))
    XCTAssertEqual(sampler.sample(x: -1.5, y: -1.5), Pixel(1, 0, 0))
    XCTAssertEqual(sampler.sample(x: 1.5, y: 0.5), .clear)
    XCTAssertEqual(sampler.sample(x: 1, y: 0.5), Pixel(1, 0, 0, 0.5))
    for y in -5...5 {
      for x in -5...5 {
        XCTAssertEqual(
          sampler.sample(x: Double(x) + 0.25, y: Double(y) + 0.75),
          sampler.sample(x: Double(x + 4) + 0.25, y: Double(y - 6) + 0.75))
      }
    }
  }
  func testScaleRotationAndPhase() throws {
    var placement = PatternPlacement()
    placement.scale = 200
    placement.phaseX = 5
    placement.phaseY = -3
    let sampler = try PatternSampler(tile(), placement: placement)
    XCTAssertEqual(sampler.sample(x: 6, y: -2), Pixel(1, 0, 0))
    placement.angle = 90
    let rotated = try PatternSampler(tile(), placement: placement)
    let p = rotated.sample(x: 6, y: -4)
    XCTAssertEqual(p.r, 1, accuracy: 0.000001)
    XCTAssertEqual(p.a, 1, accuracy: 0.000001)
    placement.scale = 0
    XCTAssertThrowsError(try PatternSampler(tile(), placement: placement))
  }
  func testDeterministicIdentityNamesAndLosslessLibraryArchive() throws {
    for depth in PixelDepth.allCases {
      let p = try tile(depth: depth)
      XCTAssertEqual(p, try tile(depth: depth))
      XCTAssertNotEqual(p.id, try RasterPattern(name: "Other", surface: p.surface).id)
      let data = try PatternArchive.encode([p], selectedID: p.id)
      let restored = try PatternArchive.decodeState(data)
      XCTAssertEqual(restored.patterns, [p])
      XCTAssertEqual(restored.selectedID, p.id)
      var renamed = p
      renamed.name = "$$$/Patterns/Native/Tile=Localized Tile\0"
      XCTAssertEqual(renamed.displayName, "Localized Tile")
      XCTAssertEqual(renamed.id, p.id)
      XCTAssertThrowsError(try PatternArchive.encode([p, p]))
    }
  }
  func testBuiltinsAndInvalidDataAreExplicit() throws {
    let patterns = try PatternPresets.make()
    XCTAssertEqual(
      patterns.map(\.name),
      ["Checkerboard", "Diagonal Lines", "Dots", "Grid", "Bricks", "Weave", "Paper Noise"])
    XCTAssertEqual(Set(patterns.map(\.id)).count, 7)
    XCTAssertEqual(patterns[1].surface.pixel(x: 0, y: 0), Pixel(0.2, 0.2, 0.2))
    XCTAssertEqual(patterns[1].surface.pixel(x: 3, y: 0), .white)
    XCTAssertThrowsError(try RasterPattern(name: "", surface: patterns[0].surface))
    XCTAssertThrowsError(try PatternArchive.decode(Data([1, 2, 3])))
    let sampler = try PatternSampler(patterns[0])
    XCTAssertEqual(sampler.tile(u: .infinity, v: 0), .clear)
  }
  func testPatternBucketRespectsAlphaSelectionTransformAndNativeDepth() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 8, height: 6, depth: depth)
      let source = try Surface(width: 8, height: 6, depth: depth, fill: .white)
      let original = try Surface(width: 2, height: 2, depth: depth)
      d.layers[0].content = .raster(original)
      d.layers[0].x = 2
      d.layers[0].y = 2
      d.selection = IntRect(x: 1, y: 1, width: 6, height: 4)
      var options = BucketOptions()
      options.match.antiAlias = false
      let p = try tile(depth: depth)
      let fill = BucketFill(
        source: .init(surface: source), seed: .init(0, 0), color: .clear,
        options: options, pattern: p)
      let before = d
      var session = EditorSession(document: d)
      try session.execute(.paintBucket(d.layers[0].id, fill))
      guard case .raster(let output) = session.document.layers[0].content else {
        return XCTFail("Expected raster")
      }
      let sampler = try PatternSampler(p)
      let transform = session.document.layers[0].coordinateTransform
      for y in 0..<output.height {
        for x in 0..<output.width {
          let q = transform.point(Double(x) + 0.5, Double(y) + 0.5)
          let expected = sampler.sample(x: q.x, y: q.y).quantized(depth)
          XCTAssertEqual(output.pixel(x: x, y: y).r, expected.r, accuracy: 0.000001)
          XCTAssertEqual(output.pixel(x: x, y: y).a, expected.a, accuracy: 0.000001)
        }
      }
      let after = session.document
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(after)), after)
      XCTAssertEqual(session.undoStack.count, 1)
      session.undo()
      XCTAssertEqual(session.document, before)
    }
  }
  func testPatternMaskUsesLuminanceAndPatternAlpha() throws {
    var layer = Layer(
      name: "Mask", content: .raster(try Surface(width: 2, height: 1, fill: .white)))
    layer.mask = try Surface(width: 2, height: 1, depth: .f32, fill: .white)
    var pixels = try Surface(width: 2, height: 1, depth: .f32, fill: Pixel(1, 0, 0, 0.5))
    pixels.setPixel(x: 1, y: 0, .clear)
    let pattern = try RasterPattern(name: "Mask pattern", surface: pixels)
    let sample = CloneSample(surface: try XCTUnwrap(layer.mask))
    var options = BucketOptions()
    options.match.antiAlias = false
    options.opacity = 0.5
    let fill = BucketFill(
      source: sample, seed: .init(0, 0), color: .black,
      options: options, mask: true, pattern: pattern)
    let original = layer.content
    try BucketPainter.paint(fill, on: &layer, canvasWidth: 2, canvasHeight: 1)
    let mask = try XCTUnwrap(layer.mask)
    XCTAssertEqual(mask.pixel(x: 0, y: 0).r, 0.75 + 0.2126 * 0.25, accuracy: 0.000001)
    XCTAssertEqual(mask.pixel(x: 1, y: 0), .white)
    XCTAssertEqual(layer.content, original)
  }
}
