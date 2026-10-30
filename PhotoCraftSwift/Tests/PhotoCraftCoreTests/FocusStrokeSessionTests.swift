import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest

final class FocusStrokeSessionTests: XCTestCase {
  func testCompleteAndIncrementalPrefixesMatchPreOptimizationPixels() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "focus-prefix-step264", withExtension: "json", subdirectory: "Fixtures"))
    let records = try XCTUnwrap(
      (JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["cases"]
        as? [[String: Any]])
    for depth in PixelDepth.allCases {
      for tool in FocusTool.allCases {
        for variant in 0..<6 {
          var pixels = try Surface(width: 128, height: 128, depth: depth)
          var source = try Surface(width: 128, height: 128, depth: depth)
          for y in 0..<128 {
            for x in 0..<128 {
              pixels.setPixel(
                x: x, y: y,
                Pixel(
                  Float((x * 3 + y) % 31) / 30, Float((x + y * 5) % 23) / 22,
                  Float((x * 7 + y) % 17) / 16, Float((x + y) % 7) / 6))
              source.setPixel(
                x: x, y: y,
                Pixel(
                  Float((x + y * 3) % 19) / 18, Float((x * 2 + y) % 29) / 28,
                  Float((x + y) % 13) / 12, Float((x + y * 2) % 5) / 4))
            }
          }
          var original = Layer(name: "Target", content: .raster(pixels))
          if variant == 1 {
            original.x = -20
            original.y = -25
            original.affine = .rotation(6)
          }
          if variant == 3 { original.mask = pixels }
          var b = CloneBrush()
          b.size = 9
          b.opacity = 0.65
          b.flow = 0.3
          b.spacing = 0.17
          b.hardness = 0.45
          b.pressureOpacity = true
          var options = FocusOptions()
          options.strength = 0.6
          options.protectDetail = variant != 2
          options.fingerPainting = variant == 2
          options.sampleAllLayers = variant == 4
          var mapping = CloneMapping(source: .init(10, 10), anchor: .init(15, 10))
          if variant == 1 {
            mapping.width = 120
            mapping.height = 75
            mapping.rotation = 22
          }
          let sample = CloneSample(
            surface: source, transform: variant == 1 ? .translation(3, -2) : .identity,
            outside: Pixel(0.2, 0.8, 0.4, 0.5))
          let mask = try SelectionMask(
            width: 96, height: 80, bytes: (0..<7680).map { UInt8(($0 % 3) * 127) })
          let points = (0..<12).map { i in
            StrokePoint(
              x: 20 + Double(i) * 4, y: 35 + sin(Double(i) / 2) * 13,
              pressure: [Float(0.2), 0.6, 1, 0][i % 4])
          }
          if variant == 5 { original.protection = [.transparency] }

          let expected = try XCTUnwrap(
            records.first {
              $0["depth"] as? String == String(describing: depth)
                && $0["variant"] as? Int == variant && $0["tool"] as? String == tool.rawValue
            }?["prefix_sha256"] as? [String])
          var stroke = FocusStroke(
            tool: tool, options: options, brush: b, points: [points[0]], mask: variant == 3,
            foreground: Pixel(0.7, 0.2, 0.4, 0.8), sample: variant == 4 ? sample : nil)
          let selection = variant == 1 ? IntRect(x: 16, y: 20, width: 64, height: 40) : nil
          let selectionMask = (variant == 1 || variant == 3) ? mask : nil
          let session = try FocusStrokeSession(
            layer: original, stroke: stroke, canvasWidth: 96, canvasHeight: 80,
            selection: selection, selectionMask: selectionMask)
          let retained = session.surface
          let retainedHash = hash(retained)
          for count in 1...points.count {
            stroke.points = Array(points.prefix(count))
            var output = original
            try FocusPainter.paint(
              stroke, on: &output, canvasWidth: 96, canvasHeight: 80, selection: selection,
              selectionMask: selectionMask)
            let result: Surface
            if variant == 3 {
              result = output.mask!
            } else {
              guard case .raster(let s) = output.content else { fatalError() }
              result = s
            }
            XCTAssertEqual(
              hash(result), expected[count - 1],
              "Complete \(tool) \(depth) variant\(variant) prefix\(count)")
            let preview = count == 1 ? session.surface : try session.append([points[count - 1]])
            XCTAssertEqual(
              hash(preview), expected[count - 1],
              "Incremental \(tool) \(depth) variant\(variant) prefix\(count)")
          }
          XCTAssertEqual(hash(retained), retainedHash)
          XCTAssertEqual(hash(try session.append([])), expected.last)
        }
      }
    }
  }
  func testInvalidAndBoundaryAppendDoNotPublishAndPoisonTheSession() throws {
    let layer = Layer(
      name: "Owned",
      content: .raster(try Surface(width: 96, height: 80, fill: Pixel(0.3, 0.5, 0.7))))
    var brush = CloneBrush()
    brush.size = 9
    for point in [StrokePoint(x: .nan, y: 30), StrokePoint(x: 1, y: 30)] {
      let session = try FocusStrokeSession(
        layer: layer, stroke: FocusStroke(tool: .blur, brush: brush, points: [.init(x: 30, y: 30)]),
        canvasWidth: 96, canvasHeight: 80)
      let before = session.surface
      XCTAssertThrowsError(try session.append([.init(x: 35, y: 35), point]))
      XCTAssertEqual(session.surface, before)
      XCTAssertThrowsError(try session.append([.init(x: 40, y: 40)]))
    }
  }
  private func hash(_ surface: Surface) -> String {
    var bytes = Data()
    for y in 0..<surface.height {
      for x in 0..<surface.width {
        let c = surface.pixel(x: x, y: y)
        for v in [c.r, c.g, c.b, c.a] {
          var bits = v.bitPattern.littleEndian
          withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) }
        }
      }
    }
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}
