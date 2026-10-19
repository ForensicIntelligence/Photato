import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class LayerViaRenderTests: XCTestCase {
  struct Reference: Decodable {
    var depth: Int
    var variant, source, copy, cut: String
  }
  func file(_ name: String) throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/layer-via")
      ))
  }
  func compareLayers(_ actual: CraftDocument, _ expected: CraftDocument, label: String) throws {
    XCTAssertEqual(actual.layers.count, expected.layers.count, label)
    for (a, b) in zip(actual.layers, expected.layers) {
      XCTAssertEqual(a.name, b.name, label)
      XCTAssertEqual(a.x, b.x, label)
      XCTAssertEqual(a.y, b.y, label)
      XCTAssertEqual(a.opacity, b.opacity, label)
      XCTAssertEqual(a.blendMode, b.blendMode, label)
      XCTAssertEqual(a.visible, b.visible, label)
      guard case .raster(let p) = a.content, case .raster(let q) = b.content else {
        return XCTFail(label)
      }
      XCTAssertEqual(p.width, q.width, label)
      XCTAssertEqual(p.height, q.height, label)
      var mismatches = 0
      for y in 0..<min(p.height, q.height) {
        for x in 0..<min(p.width, q.width) {
          if !p.pixel(x: x, y: y).hasSameBits(as: q.pixel(x: x, y: y)) { mismatches += 1 }
        }
      }
      XCTAssertEqual(mismatches, 0, label + " stored native RGBA")
      XCTAssertEqual(a.mask != nil, b.mask != nil, label)
      if a.mask != nil {
        XCTAssertEqual(a.maskCoordinateTransform, b.maskCoordinateTransform, label)
      }
    }
  }
  func testIndependentPhotoshopStoredPixelsAndNativePersistenceAtAllDepths() throws {
    let cases = try JSONDecoder().decode([Reference].self, from: file("cases.json"))
    XCTAssertEqual(cases.count, 9)
    for row in cases {
      var original = try PSDCodec.read(file(row.source))
      let bytes = (0..<original.width * original.height).map { UInt8($0 % original.width) }
      try Command.selectionCoverage(
        SelectionMask(width: original.width, height: original.height, bytes: bytes), .replace
      ).apply(to: &original)
      for operation in LayerViaOperation.allCases {
        var result = original
        try Command.layerVia(try XCTUnwrap(original.activeLayerID), operation).apply(to: &result)
        let reference = try PSDCodec.read(file(operation == .copy ? row.copy : row.cut))
        let label = "\(row.variant) RGB/\(row.depth) \(operation.rawValue)"
        try compareLayers(result, reference, label: label)
        let persisted = try NativeArchive.decode(NativeArchive.encode(result))
        XCTAssertEqual(persisted, result, label)
        let exported = try PSDCodec.writeRasterLayers(result)
        let reopened = try PSDCodec.read(exported)
        if row.depth != 32 {
          try compareLayers(reopened, reference, label: label + " PSD")
        } else {
          // Existing RGB32 sRGB/linear conversion is not bit-reversible. Alpha is unaffected.
          for (a, b) in zip(reopened.layers, reference.layers) {
            guard case .raster(let p) = a.content, case .raster(let q) = b.content else {
              return XCTFail()
            }
            for y in 0..<p.height {
              for x in 0..<p.width {
                XCTAssertEqual(
                  p.pixel(x: x, y: y).a.bitPattern, q.pixel(x: x, y: y).a.bitPattern, label)
              }
            }
          }
        }
      }
    }
  }
}
