import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

/// Compare editable path coverage with the original PSD's stored shape alpha, before blends,
/// pixel masks, density, feather and color conversion can obscure the source of a mismatch.
final class PSDVectorCacheTests: XCTestCase {
  struct Record {
    let name: String
    let x: Int, y: Int, width: Int, height: Int
    let channels: [(id: Int, bytes: Int)]
    let vector: VectorMask?
  }

  func testOriginalShapeAlphaMeasuresVectorRasterizationSeparatelyFromCompositing() throws {
    let bounds: [String: [String: Float]] = [
      "clipping-mask": ["Shape 4": 9 / 255, "Shape 1": 20 / 255, "Shape 2": 14 / 255],
      "layer_mask_data": ["1": 18 / 255, "2": 24 / 255, "3": 21 / 255, "4": 36 / 255],
      "mask-parameters-no-real-channel": ["heart": 33 / 255],
    ]
    var report: [[String: Any]] = []
    for file in bounds.keys.sorted() {
      let url = try XCTUnwrap(
        Bundle.module.url(
          forResource: "psdtools-" + file, withExtension: "psd", subdirectory: "Fixtures"))
      var reader = PSDReader(data: try Data(contentsOf: url))
      XCTAssertEqual(try reader.string(4), "8BPS")
      XCTAssertEqual(try reader.u16(), 1)
      _ = try reader.bytes(8)
      let height = try reader.u32()
      let width = try reader.u32()
      XCTAssertEqual(try reader.u16(), 8)
      XCTAssertEqual(try reader.u16(), 3)
      _ = try reader.section()
      _ = try reader.section()
      var layerSection = try reader.section()
      var info = try layerSection.section()
      let count = abs(try info.i16())
      XCTAssertLessThan(count, 20)
      var records: [Record] = []
      for _ in 0..<count {
        let top = try info.i32()
        let left = try info.i32()
        let bottom = try info.i32()
        let right = try info.i32()
        let channelCount = try info.u16()
        var channels: [(Int, Int)] = []
        for _ in 0..<channelCount { channels.append((try info.i16(), try info.u32())) }
        _ = try info.bytes(12)
        var extra = try info.section()
        _ = try extra.section()  // Mask metadata is independent of the shape's intrinsic alpha.
        _ = try extra.section()
        let length = Int(try extra.u8())
        let name = try extra.string(length)
        _ = try extra.bytes((4 - (length + 1) % 4) % 4)
        var vector: VectorMask?
        while extra.remaining >= 12 {
          XCTAssertEqual(try extra.string(4), "8BIM")
          let key = try extra.string(4)
          let size = try extra.u32()
          let data = try extra.bytes(size)
          if size % 2 != 0 { _ = try extra.bytes(1) }
          if key == "vmsk" || key == "vsms" {
            vector = try PSDPaths.readMask(data, width: width, height: height)
          }
        }
        records.append(
          Record(
            name: name, x: left, y: top, width: right - left, height: bottom - top,
            channels: channels, vector: vector))
      }
      var compared = Set<String>()
      for record in records {
        var alpha: [UInt8]?
        for channel in record.channels {
          let data = try info.bytes(channel.bytes)
          if channel.id == -1, record.vector != nil, record.width > 0, record.height > 0 {
            alpha = try PSDChannelCodec.decode(
              data, width: record.width, height: record.height, depth: 8)
          }
        }
        guard let vector = record.vector, let alpha else { continue }
        let bound = try XCTUnwrap(bounds[file]?[record.name])
        compared.insert(record.name)
        XCTAssertTrue(
          alpha.allSatisfy { $0 % 3 == 0 }, "Observed reference alpha has 85 coverage steps")
        let coverage = try VectorRasterizer.coverage(vector.path, width: width, height: height)
        var maximum: Float = 0
        var absoluteError: Double = 0
        var different = 0
        for y in 0..<record.height {
          for x in 0..<record.width {
            let dx = x + record.x
            let dy = y + record.y
            guard dx >= 0, dy >= 0, dx < width, dy < height else { continue }
            let actual = coverage.coverage(x: dx, y: dy)
            let reference = Float(alpha[y * record.width + x]) / 255
            let error = abs(actual - reference)
            maximum = max(maximum, error)
            absoluteError += Double(error)
            if (actual * 255).rounded() != Float(alpha[y * record.width + x]) { different += 1 }
          }
        }
        // These bounds prevent regressions. The exact-parity gate remains maximum == 0.
        XCTAssertLessThanOrEqual(maximum, bound + 0.000001, "\(file) / \(record.name)")
        report.append([
          "file": file + ".psd", "layer": record.name,
          "maximum_alpha_error": maximum, "sum_absolute_alpha_error": absoluteError,
          "differing_visible_pixels": different, "pixel_identical": different == 0,
        ])
      }
      XCTAssertEqual(compared, Set(try XCTUnwrap(bounds[file]).keys))
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: root.appendingPathComponent("artifacts/vector-source-alpha-comparison.json"))
  }
}
