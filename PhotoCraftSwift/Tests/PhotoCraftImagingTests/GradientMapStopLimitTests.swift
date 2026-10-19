import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class GradientMapStopLimitTests: XCTestCase {
  private struct References: Decodable {
    var cases: [Reference]
  }
  private struct Reference: Decodable {
    var name: String
    var inputRecord: Data
    var photoshopRecord: Data
    var inputColors: Int
    var inputOpacity: Int
    var exceedsPhotoshopLimit: Bool { inputColors > 100 || inputOpacity > 100 }
  }
  private func references() throws -> [Reference] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "gradient-map-stop-limits", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(References.self, from: Data(contentsOf: url)).cases
  }
  func testPhotoshopPreservesOneHundredStopsAndTruncatesOneHundredOne() throws {
    let cases = try references()
    XCTAssertEqual(cases.count, 5)
    for reference in cases {
      let input = try PSDGradientMap.read(reference.inputRecord)
      let saved = try PSDGradientMap.read(reference.photoshopRecord)
      XCTAssertEqual(input.gradient.colors.count, reference.inputColors, reference.name)
      XCTAssertEqual(input.gradient.opacity.count, reference.inputOpacity, reference.name)
      XCTAssertEqual(
        saved.gradient.colors, Array(input.gradient.colors.prefix(100)), reference.name)
      XCTAssertEqual(
        saved.gradient.opacity, Array(input.gradient.opacity.prefix(100)), reference.name)
      XCTAssertEqual(saved.gradient.method, input.gradient.method, reference.name)
      XCTAssertEqual(
        try PSDGradientMap.write(saved, original: reference.photoshopRecord),
        reference.photoshopRecord, reference.name)
    }
  }
  func testUnsafeExportRejectsFreshAndPreservedRecordsWithoutTruncating() throws {
    for reference in try references() where reference.exceedsPhotoshopLimit {
      let input = try PSDGradientMap.read(reference.inputRecord)
      for original: Data? in [nil, reference.inputRecord] {
        XCTAssertThrowsError(try PSDGradientMap.write(input, original: original), reference.name) {
          error in
          guard case CraftError.unsupported(let message) = error else { return XCTFail("\(error)") }
          XCTAssertTrue(message.contains("100"), message)
          XCTAssertTrue(
            message.contains(reference.inputColors > 100 ? "color stops" : "opacity stops"), message
          )
        }
      }
      for method in GradientMethod.allCases {
        var changed = input
        changed.gradient.method = method
        XCTAssertThrowsError(try PSDGradientMap.write(changed), "\(reference.name), \(method)")
      }
      XCTAssertEqual(try PSDGradientMap.read(reference.inputRecord), input)
    }
  }
  func testNativeDocumentsRetainEveryStopAcrossFailedPSDExport() throws {
    for reference in try references() {
      let input = try PSDGradientMap.read(reference.inputRecord)
      for depth: PixelDepth in [.u8, .u16] {
        var document = try CraftDocument(width: 3, height: 2, depth: depth)
        let layer = Layer(name: reference.name, content: .adjustment(.gradientMap(input)))
        document.layers.append(layer)
        document.activeLayerID = layer.id
        let archive = try NativeArchive.encode(document)
        XCTAssertEqual(try NativeArchive.decode(archive), document)
        if reference.exceedsPhotoshopLimit {
          XCTAssertThrowsError(try PSDCodec.writeRasterLayers(document), reference.name)
        } else {
          let restored = try PSDCodec.read(PSDCodec.writeRasterLayers(document))
          XCTAssertEqual(restored.layers.last?.content, layer.content, reference.name)
        }
        XCTAssertEqual(try NativeArchive.encode(document), archive, reference.name)
      }
    }
  }
}
