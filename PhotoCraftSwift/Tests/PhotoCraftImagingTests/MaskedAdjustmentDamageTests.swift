import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class MaskedAdjustmentDamageTests: XCTestCase {
  private func fixture(_ depth: PixelDepth) throws -> CraftDocument {
    var d = try CraftDocument(width: 193, height: 129, depth: depth)
    var pixels = try Surface(width: d.width, height: d.height, depth: depth)
    for y in 0..<d.height { for x in 0..<d.width {
      pixels.setPixel(x: x, y: y, Pixel(Float(8 + x % 220) / 255,
        Float(8 + y % 220) / 255, Float(20 + (x + y) % 200) / 255, Float(90 + (x * y) % 166) / 255))
    } }
    d.layers[0].content = .raster(pixels)
    return d
  }
  private func added(_ adjustment: Adjustment, to original: CraftDocument, painted: Bool = true) throws -> CraftDocument {
    var d = original, layer = Layer(name: "Painted adjustment", content: .adjustment(adjustment))
    var mask = try Surface(width: d.width, height: d.height, depth: d.depth, fill: .black)
    if painted {
      mask.setPixel(x: 25, y: 27, .white)
      mask.setPixel(x: 31, y: 30, Pixel(0.37, 0.37, 0.37))
    }
    layer.mask = mask; layer.opacity = 0.63
    d.layers.append(layer); d.activeLayerID = layer.id
    return d
  }
  private func exact(_ result: RenderSnapshot, _ document: CraftDocument, label: String) throws {
    let expected = try Renderer.composite(document)
    let a = try result.surface.rgbaData(depth: .f32), b = try expected.rgbaData(depth: .f32)
    if a != b, let directory = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let path = URL(fileURLWithPath: directory).appendingPathComponent(label)
      try a.write(to: path.appendingPathExtension("regional.rgba32"))
      try b.write(to: path.appendingPathExtension("full.rgba32"))
    }
    XCTAssertTrue(a == b, "\(label): all Float32 component words must match the complete renderer")
  }
  func testEveryBrushAdjustmentAddedOverRasterMatchesCompleteRenderAtAllDepthsAndBlends() throws {
    for depth in PixelDepth.allCases {
      let original = try fixture(depth), previous = try Renderer.render(original)
      for kind in AdjustmentBrushKind.allCases { for mode in [BlendMode.normal, .multiply, .screen, .color] {
        var d = try added(kind.initial, to: original)
        d.layers[d.layers.count - 1].blendMode = mode
        let result = try Renderer.render(d, reusing: previous)
        guard case .region(let region) = result.update else {
          XCTFail("Expected bounded added mask damage: \(depth)/\(kind)/\(mode)"); continue
        }
        XCTAssertTrue(region.contains(25, 27)); XCTAssertTrue(region.contains(31, 30))
        XCTAssertLessThan(region.width * region.height, d.width * d.height)
        try exact(result, d, label: "\(depth)-\(kind)-\(mode)")
        XCTAssertEqual(previous.document, original)
      } }
    }
  }
  func testBlackMasksAndFullyCoveredPixelsRetainExactBackdropAndUnmaskedResult() throws {
    for depth in PixelDepth.allCases {
      let original = try fixture(depth), previous = try Renderer.render(original)
      for (index, adjustment) in [AdjustmentBrushKind.colorVibrance.initial, .invert, .exposure(1.2)].enumerated() {
        let black = try added(adjustment, to: original, painted: false)
        let unchanged = try Renderer.render(black, reusing: previous)
        XCTAssertEqual(unchanged.update, .unchanged)
        try exact(unchanged, black, label: "black-\(depth)-\(index)")
        var masked = try added(adjustment, to: original)
        masked.layers[masked.layers.count - 1].opacity = 1
        let result = try Renderer.composite(masked)
        var unmasked = masked; unmasked.layers[unmasked.layers.count - 1].mask = nil
        let whole = try Renderer.composite(unmasked)
        XCTAssertTrue(result.pixel(x: 25, y: 27).hasSameBits(as: whole.pixel(x: 25, y: 27)))
        XCTAssertTrue(result.pixel(x: 100, y: 100).hasSameBits(as: previous.surface.pixel(x: 100, y: 100)))
      }
    }
  }
  func testAddedMaskOverNestedGroupsClippingAndExistingAdjustmentsMatchesCompleteWords() throws {
    for depth in PixelDepth.allCases { for passThrough in [false, true] {
      var original = try GroupRenderTests().fixture(depth: depth)
      original.layers[5].content = .group(GroupContent(passThrough: passThrough))
      var adjustment = Layer(name: "Existing adjustment", content: .adjustment(.invert))
      adjustment.opacity = 0.32
      original.layers.append(adjustment); original.activeLayerID = adjustment.id
      let before = try Renderer.render(original)
      let d = try added(AdjustmentBrushKind.colorVibrance.initial, to: original)
      let result = try Renderer.render(d, reusing: before)
      guard case .region = result.update else { return XCTFail("Expected local top-mask damage") }
      try exact(result, d, label: "groups-\(depth)-\(passThrough)")
    } }
  }
  func testStructuralNonlocalAndNonblackMaskChangesRetainFullFallbackAndExactPixels() throws {
    let original = try fixture(.u8), previous = try Renderer.render(original)
    for variant in 0..<9 {
      var d = try added(AdjustmentBrushKind.colorVibrance.initial, to: original)
      let i = d.layers.count - 1
      switch variant {
      case 0: d.layers[i].mask = try Surface(width: d.width, height: d.height, fill: .white)
      case 1: var p = MaskProperties(); p.density = 0.5; d.layers[i].maskProperties = p
      case 2: var p = MaskProperties(); p.feather = 2; d.layers[i].maskProperties = p
      case 3: d.layers[i].affine = .translation(2, 3)
      case 4: d.layers[i].clipped = true
      case 5:
        var value = ModernAdjustment(.clarityDehaze); value.values["clarity"] = 30
        d.layers[i].content = .adjustment(.modern(value))
      case 6: d.layers[0].content = .fill(Pixel(1, 0, 0))
      case 7: let layer = d.layers.removeLast(); d.layers.insert(layer, at: 0)
      default: d.layers[i].mask = nil
      }
      let result = try Renderer.render(d, reusing: previous)
      XCTAssertEqual(result.update, .full, "variant \(variant)")
      try exact(result, d, label: "fallback-\(variant)")
    }
  }
  func testInvalidDocumentsAndSignedZeroStackChangesCannotUseInsertionReuse() throws {
    var original = try fixture(.f32)
    original.layers[0].affine = .identity
    let previous = try Renderer.render(original)
    var d = try added(.invert, to: original)
    d.layers[0].affine?.tx = -0.0
    XCTAssertEqual(d.layers[0].affine, original.layers[0].affine)
    let result = try Renderer.render(d, reusing: previous)
    XCTAssertEqual(result.update, .full)
    try exact(result, d, label: "signed-zero")
    for variant in 0..<2 {
      var invalid = try added(.invert, to: original, painted: false)
      if variant == 0 { invalid.layers[1].opacity = .nan }
      else { invalid.layers[1].content = .adjustment(.colorLookup(.init(lut: .init(size: 2, values: [0])))) }
      XCTAssertThrowsError(try Renderer.render(invalid, reusing: previous))
      XCTAssertThrowsError(try Renderer.composite(invalid))
    }
  }
}
