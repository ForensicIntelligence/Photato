import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class ColorLookupExportTests: XCTestCase {
  private func fixture(_ depth: PixelDepth = .u8, width: Int = 8, height: Int = 6) throws -> CraftDocument {
    var d = try CraftDocument(width: width, height: height, depth: depth)
    d.layers[0].background = true
    d.layers.append(Layer(name: "Invert", content: .adjustment(.invert)))
    return d
  }
  func testIndependentCubeCornersAndRedFastestOrdering() throws {
    let d = try fixture(), data = try ColorLookupExport.cube(d, size: 2, title: "Owned test")
    let text = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertTrue(text.contains("LUT_3D_SIZE 2")); XCTAssertTrue(text.contains("Owned test"))
    let rows = text.split(whereSeparator: \.isNewline).compactMap { line -> [Float]? in
      let tokens = line.split(whereSeparator: \.isWhitespace)
      guard tokens.count == 3, Float(tokens[0]) != nil else { return nil }
      let values = tokens.compactMap { Float($0) }
      return values.count == 3 ? values : nil
    }
    XCTAssertEqual(rows.count, 8)
    for b in 0..<2 { for g in 0..<2 { for r in 0..<2 {
      XCTAssertEqual(rows[(b * 2 + g) * 2 + r], [Float(1-r), Float(1-g), Float(1-b)])
    } } }
    let decoded = try ColorLUTFile.read(data, name: "test.cube")
    XCTAssertEqual(decoded.size, 2)
  }
  func testSamplingMatchesNativeCompositorForEveryGridNodeAndDepth() throws {
    for depth in PixelDepth.allCases {
      var d = try fixture(depth)
      d.layers[1].opacity = 0.35
      d.layers.append(Layer(name: "Exposure", content: .adjustment(.exposure(0.25))))
      let lut = try ColorLookupExport.bake(d, size: 3)
      for b in 0..<3 { for g in 0..<3 { for r in 0..<3 {
        var reference = d
        reference.width = 1; reference.height = 1
        reference.layers[0].content = .raster(try Surface(width: 1, height: 1, depth: depth,
          fill: Pixel(Float(r)/2, Float(g)/2, Float(b)/2)))
        let p = try Renderer.composite(reference).pixel(x: 0, y: 0), offset = ((b*3+g)*3+r)*3
        XCTAssertEqual(Array(lut.values[offset..<offset+3]), [p.r, p.g, p.b], "\(depth) \(r),\(g),\(b)")
      } } }
    }
  }
  func testUniformMasksHiddenAdjustmentsSelectionAndInputDocumentRemainUnchanged() throws {
    var d = try fixture()
    d.layers[1].mask = try Surface(width: 8, height: 6, fill: .white)
    var hidden = Layer(name: "Hidden", content: .adjustment(.exposure(5))); hidden.visible = false
    d.layers.append(hidden); d.setCoverageSelection(try SelectionMask.make(.rectangle(.init(x: 1, y: 1, width: 2, height: 2)), width: 8, height: 6))
    let before = d, lut = try ColorLookupExport.bake(d, size: 2)
    XCTAssertEqual(d, before); XCTAssertEqual(Array(lut.values.prefix(3)), [1,1,1])
    d.layers[1].maskProperties = .init(); d.layers[1].maskProperties?.enabled = false
    d.layers[1].mask = try Surface(width: 1, height: 1, fill: .black)
    XCTAssertEqual(try ColorLookupExport.bake(d, size: 2), lut)
  }
  func testRejectSpatialMasksGroupsPixelsNoiseAndNeighborhoodsWithoutMutation() throws {
    let original = try fixture()
    var candidates = [CraftDocument]()
    var d = original; d.layers[1].mask = try Surface(width: 2, height: 2, fill: .black); candidates.append(d)
    d = original; d.layers.append(Layer(name: "Pixels", content: .raster(try Surface(width: 1, height: 1)))); candidates.append(d)
    d = original; d.layers[1].blendMode = .dissolve; candidates.append(d)
    d = original; var grain = ModernAdjustment(.grain); grain.values["grainAmount"] = 10; d.layers[1].content = .adjustment(.modern(grain)); candidates.append(d)
    d = original; var clarity = ModernAdjustment(.clarityDehaze); clarity.values["clarity"] = 10; d.layers[1].content = .adjustment(.modern(clarity)); candidates.append(d)
    d = original; var lookup = ColorLookupAdjustment(); lookup.dither = true; d.layers[1].content = .adjustment(.colorLookup(lookup)); candidates.append(d)
    d = original; d.layers[0].background = nil; candidates.append(d)
    for candidate in candidates {
      let before = candidate
      XCTAssertThrowsError(try ColorLookupExport.bake(candidate, size: 2))
      XCTAssertEqual(candidate, before)
    }
    XCTAssertThrowsError(try ColorLookupExport.bake(original, size: 1))
    XCTAssertThrowsError(try ColorLookupExport.bake(original, size: 130))
    XCTAssertThrowsError(try ColorLookupExport.bake(original, size: 2, title: "bad\nname"))
  }
  func testMaximumLogicalCanvasUsesOnlyTheRequestedColorGrid() throws {
    let d = try fixture(width: 300_000, height: 300_000)
    XCTAssertEqual(try ColorLookupExport.bake(d, size: 2).values,
      try ColorLookupExport.bake(fixture(), size: 2).values)
  }
  func testCancelledPreparationProducesNoFile() async throws {
    let d = try fixture()
    let task = Task { try Task.checkCancellation(); return try ColorLookupExport.cube(d, size: 32) }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled export returned bytes") }
    catch { XCTAssertTrue(error is CancellationError) }
  }
}
