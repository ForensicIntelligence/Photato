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

  func testWideStreamedKernelMatchesStoredControlsOnBothReferenceArchitectures() throws {
    XCTAssertEqual(MaskSampler.featherDamageRadius(1000), 3032)
    let original = try PSDCodec.read(readFixture("texture"))
    var layer = try XCTUnwrap(original.layers.first { $0.name == "Reference Mask" })
    for radius in [250, 1000] {
      var p = layer.effectiveMaskProperties
      p.feather = Double(radius)
      layer.maskProperties = p
      let sampler = try MaskSampler(layer: layer, canvasSize: (original.width, original.height))
      for arch in ["arm", "intel"] {
        let oracle = try PSDCodec.read(readFixture("\(arch)-\(radius)", folder: "wide-pixel-mask-feather"))
        guard let merged = oracle.layers.first, case .raster(let expected) = merged.content else {
          return XCTFail("Missing saved wide-feather raster")
        }
        for y in 0..<expected.height {
          for x in 0..<expected.width {
            XCTAssertEqual(sampler.coverage(x: Double(x + merged.x) + 0.5, y: Double(y + merged.y) + 0.5).bitPattern,
              expected.linearPixel(x: x, y: y).r.bitPattern, "\(arch), \(radius), (\(x), \(y))")
          }
        }
      }
    }
  }

  func testWideFeatherRoundTripsNativePhotoshopAndLargeDocumentFiles() throws {
    let reference = try PSDCodec.read(readFixture("editable-1000", folder: "wide-pixel-mask-feather"))
    let referenceLayer = try XCTUnwrap(reference.layers.first { $0.mask != nil })
    XCTAssertEqual(referenceLayer.effectiveMaskProperties.feather, 1000)

    var document = try CraftDocument(width: 8, height: 7, depth: .f32)
    var layer = Layer(name: "Editable wide mask", content: .raster(try Surface(width: 8, height: 7,
      depth: .f32, fill: .white, colorEncoding: .linearRGB)))
    layer.mask = try Surface(width: 8, height: 7, depth: .f32, fill: .white)
    var properties = MaskProperties()
    properties.feather = 1000
    properties.outside = 1
    properties.linked = false
    layer.maskProperties = properties
    document.layers.append(layer)
    let native = try NativeArchive.decodePaged(NativeArchive.encode(document))
    XCTAssertEqual(native.layers.last?.effectiveMaskProperties, properties)
    for format in [PSDFileFormat.psd, .psb] {
      let imported = try PSDCodec.read(PSDCodec.writeRasterLayers(document, format: format))
      let retained = try XCTUnwrap(imported.layers.first { $0.name == layer.name })
      XCTAssertEqual(retained.effectiveMaskProperties, properties, "\(format)")
      XCTAssertEqual(retained.mask, layer.mask)
    }
  }

  func testWideRadiusOnSparseMaximumCanvasAndAffineLowerDepthMasks() throws {
    let size = Surface.maxDimension
    var document = try CraftDocument(width: size, height: size, depth: .f32)
    var layer = Layer(name: "Wide sparse mask", content: .raster(try Surface(width: size, height: size,
      depth: .f32, fill: .black)))
    var mask = try Surface(width: size, height: size, depth: .f32, fill: .black)
    mask.setPixel(x: 150_000, y: 150_000, .white)
    layer.mask = mask
    var properties = MaskProperties()
    properties.feather = 1000
    layer.maskProperties = properties
    let far = try MaskSampler(layer: layer, canvasSize: (size, size))
    XCTAssertEqual(far.coverage(x: 0.5, y: 0.5), 0)
    layer.maskProperties?.feather = 250
    document.layers.append(layer)
    let region = IntRect(x: 149_997, y: 149_997, width: 7, height: 7)
    let rendered = try PagedCanvasRenderer.composite(document, region: region)
    XCTAssertLessThan(rendered.linearPixel(x: 150_000, y: 150_000).r, 1)
    XCTAssertLessThanOrEqual(rendered.tileCount, 4)

    for depth in [PixelDepth.u8, .u16] {
      var affine = Layer(name: "Affine range", content: .fill(.white))
      affine.mask = try Surface(width: 7, height: 5, depth: depth, fill: .white)
      properties.feather = 100.75
      properties.transform = .rotation(12) * .scale(1.25, 0.9)
      affine.maskProperties = properties
      let sample = try MaskSampler(layer: affine, canvasSize: (20, 20)).coverage(x: 3.5, y: 3.5)
      XCTAssertGreaterThan(sample, 0)
      XCTAssertLessThan(sample, 1)
    }
  }

  private func readFixture(_ name: String, fileExtension ext: String = "psd", folder: String = "layer-mask-area") throws -> Data {
    try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext,
      subdirectory: "Fixtures/\(folder)")))
  }
}
