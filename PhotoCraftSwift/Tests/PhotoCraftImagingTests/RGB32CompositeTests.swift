import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class RGB32CompositeTests: XCTestCase {
  let names = [
    "01-opaque-samples", "02-alpha-samples", "03-opaque-base",
    "04-translucent-base", "05-mask-opacity", "06-cartesian-alpha",
    "07-random-mask", "08-three-layers", "09-offset-hdr", "10-opaque-base-random-mask",
  ]

  func fixture(_ name: String, extension ext: String = "psd") throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: name, withExtension: ext, subdirectory: "Fixtures/rgb32-composite")))
  }

  func merged(_ data: Data, width: Int, height: Int) throws -> Data {
    var reader = PSDReader(data: data)
    _ = try reader.bytes(12)
    let channels = try reader.u16()
    XCTAssertEqual(channels, 4)
    _ = try reader.bytes(12)
    for _ in 0..<3 { _ = try reader.section() }
    return Data(
      try PSDChannelCodec.decode(
        reader.bytes(reader.remaining), width: width, height: height, depth: 32, channels: channels)
    )
  }

  func assertMatchingMerged(_ actual: Data, appleSilicon reference: Data, fixtureGroup: String,
    name: String) throws {
    XCTAssertEqual(actual.count, reference.count, name)
    #if arch(x86_64)
    struct SavedReference: Decodable { let mergedSHA256: String }
    let intel = try JSONDecoder().decode([String: [String: SavedReference]].self,
      from: fixture("intel-merged-references", extension: "json"))
    let expected = try XCTUnwrap(intel[fixtureGroup]?[name], name)
    let hash = SHA256.hash(data: actual).map { String(format: "%02x", $0) }.joined()
    XCTAssertEqual(hash, expected.mergedSHA256, name)
    #else
    XCTAssertEqual(zip(actual, reference).filter { $0 != $1 }.count, 0, name)
    #endif
  }

  func testPhotoshopMergedSamplesAndStraightLayersForEveryProbe() throws {
    for name in names {
      let document = try PSDCodec.read(fixture(name))
      let before = try NativeArchive.encode(document)
      let expected = try fixture(name, extension: "merged")
      for compression in PSDCompression.allCases {
        let encoded = try PSDCodec.writeRasterLayers(document, compression: compression)
        let actual = try merged(encoded, width: document.width, height: document.height)
        try assertMatchingMerged(actual, appleSilicon: expected, fixtureGroup: "rgb32-composite",
          name: name)
        let reopened = try PSDCodec.read(encoded)
        for (a, b) in zip(document.layers, reopened.layers) {
          XCTAssertEqual(a.content, b.content, name)
          XCTAssertEqual(a.mask, b.mask, name)
          XCTAssertEqual(a.opacity.bitPattern, b.opacity.bitPattern, name)
        }
      }
      XCTAssertEqual(try NativeArchive.encode(document), before, name)
    }
  }

  func testNormalPositiveCoverageMatchesPhotoshopAtTheFloatUnderflowBoundary() throws {
    struct Reference: Decodable {
      struct Capture: Decodable { let rgbaWordsSHA256: String }
      let name: String
      let inputSHA256: String
      let nPixels: Int
      let architectures: [String: Capture]
    }
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    func read(_ name: String, extension ext: String) throws -> Data {
      try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext,
        subdirectory: "Fixtures/rgb32-composite/subnormal")))
    }
    func hash(_ data: Data) -> String {
      SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    let references = try JSONDecoder().decode([Reference].self, from: read("references", extension: "json"))
    XCTAssertEqual(Set(references.map(\.name)), ["opaque", "translucent"])
    for reference in references {
      let input = try read(reference.name, extension: "psd")
      XCTAssertEqual(hash(input), reference.inputSHA256)
      let document = try PSDCodec.read(input)
      guard document.layers.count == 2, case .raster(let backdrop) = document.layers[0].content,
        case .raster(let source) = document.layers[1].content else {
        XCTFail("Expected two raster layers in \(reference.name)")
        continue
      }
      let rendered = try Renderer.composite(document)
      var samples = Data()
      for y in 0..<document.height {
        for x in 0..<document.width where backdrop.linearPixel(x: x, y: y).a > 0
          && source.linearPixel(x: x, y: y).a > 0 {
          let pixel = rendered.linearPixel(x: x, y: y)
          for component in [pixel.r, pixel.g, pixel.b, pixel.a] {
            var word = component.bitPattern.bigEndian
            withUnsafeBytes(of: &word) { samples.append(contentsOf: $0) }
          }
        }
      }
      XCTAssertEqual(samples.count, reference.nPixels * 16, reference.name)
      XCTAssertEqual(hash(samples), try XCTUnwrap(reference.architectures[architecture]).rgbaWordsSHA256,
        reference.name)
    }
  }

  func testOpaqueNormalCopyUsesTheWholeSourceLayerAndCanvasExtent() throws {
    let modes = ["full", "near", "far", "translucent-back", "offset", "offscreen-alpha"]
    let expected = ["ordinary", "clipped"].flatMap { kind in modes.map { "\(kind)-\($0)" } }
    try checkOpaqueCopyReferences(in: "opaque-source", names: expected)

    var encoded = try CraftDocument(width: 2, height: 1, depth: .f32)
    let surface = try Surface(width: 2, height: 1, depth: .f32,
      fill: Pixel(Float.greatestFiniteMagnitude, 0, 0, 1), colorEncoding: .sRGB)
    encoded.layers.append(Layer(name: "Opaque encoded HDR", content: .raster(surface)))
    encoded.activeLayerID = encoded.layers.last?.id
    XCTAssertThrowsError(try Renderer.composite(encoded))
  }

  func testOpaqueCopyUsesUniformAlphaOfOrdinaryBackdropButKeepsClippedCoverage() throws {
    let backdrops = ["opaque", "uniform", "variable"].flatMap { state in
      [16, 72, 144].map { "base-\(state)-\($0)" }
    }
    let stacks = ["clip-opaque", "clip-uniform", "clip-variable", "stack-opaque-base",
      "stack-uniform", "stack-variable", "stack-variable-opaque-middle"]
    try checkOpaqueCopyReferences(in: "backdrop-alpha", names: backdrops + stacks)
  }

  private func checkOpaqueCopyReferences(in folder: String, names: [String]) throws {
    struct Reference: Decodable {
      struct Capture: Decodable { let rgbaWordsSHA256: String }
      let name: String
      let inputSHA256: String
      let width: Int
      let height: Int
      let architectures: [String: Capture]
    }
    #if arch(x86_64)
    let architecture = "intel"
    #else
    let architecture = "arm"
    #endif
    func fixture(_ name: String, extension ext: String) throws -> Data {
      try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext,
        subdirectory: "Fixtures/rgb32-composite/subnormal/\(folder)")))
    }
    func hash(_ data: Data) -> String {
      SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    let references = try JSONDecoder().decode([Reference].self, from: fixture("references", extension: "json"))
    XCTAssertEqual(Set(references.map(\.name)), Set(names))
    XCTAssertEqual(references.count, names.count)
    for reference in references {
      let input = try fixture(reference.name, extension: "psd")
      XCTAssertEqual(hash(input), reference.inputSHA256)
      let document = try PSDCodec.read(input)
      XCTAssertEqual(document.width, reference.width)
      XCTAssertEqual(document.height, reference.height)
      let composed = try Renderer.composite(document)
      let bytes = straightRGBAWords(composed)
      XCTAssertEqual(hash(bytes), try XCTUnwrap(reference.architectures[architecture]).rgbaWordsSHA256,
        reference.name)
      XCTAssertEqual(straightRGBAWords(try Renderer.compositePaged(document)), bytes, reference.name)
      if !document.layers.contains(where: { $0.isClipped || $0.isGroup }) {
        let sparse = try XCTUnwrap(SparseCanvasRenderer.composite(document))
        XCTAssertEqual(straightRGBAWords(sparse), bytes, reference.name)
      }
      let left = min(32, document.width / 4)
      let region = IntRect(x: left, y: 0, width: min(64, document.width - left), height: 1)
      let partial = try Renderer.composite(document, region: region)
      for x in region.x..<region.x + region.width {
        XCTAssertTrue(partial.linearPixel(x: x, y: 0).hasSameBits(as: composed.linearPixel(x: x, y: 0)),
          "\(reference.name) at x = \(x)")
      }
    }
  }

  private func straightRGBAWords(_ composed: Surface) -> Data {
    var bytes = Data()
    for y in 0..<composed.height {
      for x in 0..<composed.width {
        let pixel = composed.linearPixel(x: x, y: y)
        for component in [pixel.r, pixel.g, pixel.b, pixel.a] {
          var bits = component.bitPattern.bigEndian
          withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) }
        }
      }
    }
    return bytes
  }

  func testRegionsAndIncrementalRenderMatchWholeNormalStack() throws {
    var document = try PSDCodec.read(fixture("08-three-layers"))
    let baseline = try Renderer.render(document)
    var hidden = Layer(name: "Hidden fill", content: .fill(.white))
    hidden.visible = false
    var hiddenDocument = document
    hiddenDocument.layers.append(hidden)
    XCTAssertEqual(
      try Renderer.composite(hiddenDocument).rgbaData(depth: .f32, colorEncoding: .linearRGB),
      try baseline.surface.rgbaData(depth: .f32, colorEncoding: .linearRGB))
    let region = IntRect(x: 7, y: 9, width: 31, height: 27)
    let partial = try Renderer.composite(document, region: region)
    for y in 9..<36 {
      for x in 7..<38 {
        XCTAssertTrue(
          partial.linearPixel(x: x, y: y).hasSameBits(
            as:
              baseline.surface.linearPixel(x: x, y: y)))
      }
    }
    XCTAssertEqual(partial.linearPixel(x: 0, y: 0), .clear)
    guard case .raster(var source) = document.layers[1].content else { return XCTFail() }
    source.setLinearPixel(x: 15, y: 15, Pixel(2, -0.5, 0.01, 0.3))
    document.layers[1].content = .raster(source)
    let incremental = try Renderer.render(document, reusing: baseline)
    guard case .region = incremental.update else { return XCTFail("Expected regional update") }
    XCTAssertEqual(
      try incremental.surface.rgbaData(depth: .f32, colorEncoding: .linearRGB),
      try Renderer.composite(document).rgbaData(depth: .f32, colorEncoding: .linearRGB))
  }

  func testPSD32OpacityKeepsCanonicalStoredByteValue() throws {
    let document = try PSDCodec.read(fixture("08-three-layers"))
    XCTAssertEqual(document.layers[1].opacity.bitPattern, UInt32(0x3f55_d5d6))
  }
  func testFiniteRangeOverflowIsReportedInsteadOfSilentlyReplacingPixels() throws {
    var document = try CraftDocument(width: 1, height: 1, depth: .f32)
    let layers = try [Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude].map { value in
      var pixels = try Surface(width: 1, height: 1, depth: .f32, colorEncoding: .linearRGB)
      pixels.setLinearPixel(x: 0, y: 0, Pixel(value, 0, 0, 1))
      return Layer(name: "HDR", content: .raster(pixels))
    }
    document.layers = layers
    document.activeLayerID = layers.last?.id

    let copied = try Renderer.composite(document).linearPixel(x: 0, y: 0)
    XCTAssertTrue(copied.hasSameBits(as: Pixel(-Float.greatestFiniteMagnitude, 0, 0, 1)))

    // With a translucent backdrop and overlay, the subtraction is required.
    guard case .raster(var backdrop) = document.layers[0].content else {
      return XCTFail("Expected the HDR backdrop raster")
    }
    backdrop.setLinearPixel(x: 0, y: 0, Pixel(Float.greatestFiniteMagnitude, 0, 0, 0.5))
    document.layers[0].content = .raster(backdrop)
    document.layers[1].opacity = 0.5
    XCTAssertThrowsError(try Renderer.composite(document))
  }

}
