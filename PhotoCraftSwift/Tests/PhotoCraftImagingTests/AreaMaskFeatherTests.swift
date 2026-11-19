import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class AreaMaskFeatherTests: XCTestCase {
  func testIntegerFeatherMatchesStoredPhotoshopCoverageAtCanvasAndMaskEdges() throws {
    XCTAssertEqual(MaskSampler.featherDamageRadius(100), 311)
    let records = try readFixture("references", fileExtension: "json")
    let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: records) as? [String: Any])
    let cases = try XCTUnwrap(manifest["cases"] as? [[Any]])
    XCTAssertEqual(cases.count, 21)
    for row in cases {
      let name = try XCTUnwrap(row[0] as? String)
      let radius = try XCTUnwrap(row[1] as? Int)
      let document = try PSDCodec.read(readFixture(name))
      var layer = try XCTUnwrap(document.layers.first { $0.name == "Reference Mask" })
      var properties = layer.effectiveMaskProperties
      properties.feather = Double(radius)
      layer.maskProperties = properties
      let sampler = try MaskSampler(layer: layer, canvasSize: (document.width, document.height))
      let oracle = try PSDCodec.read(readFixture("\(name)-\(radius)"))
      guard let merged = oracle.layers.first, case .raster(let expected) = merged.content else {
        return XCTFail("Missing stored result for \(name), radius \(radius)")
      }
      var differingSamples = 0
      for y in 0..<expected.height {
        for x in 0..<expected.width {
          let actual = sampler.coverage(x: Double(x + merged.x) + 0.5, y: Double(y + merged.y) + 0.5)
          if actual.bitPattern != expected.linearPixel(x: x, y: y).r.bitPattern { differingSamples += 1 }
        }
      }
      XCTAssertEqual(differingSamples, 0, "\(name), radius \(radius)")
    }
  }

  func testMaximumCanvasUsesTheAreaKernelInRequestedRGB32Regions() throws {
    let size = Surface.maxDimension
    var d = try CraftDocument(width: size, height: size, depth: .f32)
    let raster = try Surface(width: size, height: size, depth: .f32, fill: .black)
    var layer = Layer(name: "One stored mask sample", content: .raster(raster))
    var mask = try Surface(width: size, height: size, depth: .f32, fill: .black)
    mask.setPixel(x: 150_000, y: 150_000, .white)
    layer.mask = mask
    var properties = MaskProperties()
    properties.feather = 3
    layer.maskProperties = properties
    d.layers.append(layer)
    // The recorded point-spread function survives the maximum-size coordinate grid.
    let oracle = try PSDCodec.read(readFixture("impulse-centered-3"))
    guard let merged = oracle.layers.first, case .raster(let expected) = merged.content else {
      return XCTFail("Missing point-spread function")
    }
    let sampler = try MaskSampler(layer: layer, canvasSize: (size, size))
    XCTAssertEqual(sampler.coverage(x: 150_000.5, y: 150_000.5).bitPattern,
      expected.linearPixel(x: 32, y: 32).r.bitPattern)
    XCTAssertEqual(sampler.coverage(x: 0.5, y: 0.5), 0)
    var count = 0
    let bounds = IntRect(x: 149_990, y: 149_990, width: 22, height: 22)
    let sparse = try PagedCanvasRenderer.composite(d, region: bounds) { count = $0 }
    XCTAssertGreaterThan(count, 0)
    XCTAssertLessThanOrEqual(sparse.tileCount, 4)
    XCTAssertLessThan(sparse.linearPixel(x: 150_000, y: 150_000).r, 1)
  }

  private func readFixture(_ name: String, fileExtension ext: String = "psd") throws -> Data {
    try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext,
      subdirectory: "Fixtures/layer-mask-area")))
  }
}
