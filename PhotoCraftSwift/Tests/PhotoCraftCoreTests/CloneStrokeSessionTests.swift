import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest

final class CloneStrokeSessionTests: XCTestCase {
  func testEveryPrefixMatchesPreservedPreOptimizationPixels() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "clone-prefix-step262", withExtension: "json", subdirectory: "Fixtures"))
    let records = try XCTUnwrap((JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["cases"] as? [[String: Any]])
    for depth in PixelDepth.allCases { for variant in 0..<4 {
      var pixels = try Surface(width: 64, height: 64, depth: depth)
      var source = try Surface(width: 64, height: 64, depth: depth)
      for y in 0..<64 { for x in 0..<64 {
        pixels.setPixel(x: x, y: y, Pixel(Float((x*3+y)%31)/30, Float((x+y*5)%23)/22, Float((x*7+y)%17)/16, Float((x+y)%7)/6))
        source.setPixel(x: x, y: y, Pixel(Float((x+y*3)%19)/18, Float((x*2+y)%29)/28, Float((x+y)%13)/12, Float((x+y*2)%5)/4))
      }}
      var layer = Layer(name: "Target", content: .raster(pixels))
      if variant == 1 { layer.x = -15; layer.y = -15; layer.affine = .rotation(12) }
      if variant == 3 { layer.mask = pixels }
      var brush = CloneBrush(); brush.size = 9; brush.opacity = 0.65; brush.flow = 0.3
      brush.spacing = 0.17; brush.hardness = 0.45; brush.pressureOpacity = true
      if variant == 2 { brush.mode = .multiply }
      if variant == 3 { brush.mode = .dissolve }
      var mapping = CloneMapping(source: .init(10, 10), anchor: .init(15, 10))
      if variant == 1 { mapping.width = 120; mapping.height = 75; mapping.rotation = 22 }
      let sample = CloneSample(surface: source, transform: variant == 1 ? .translation(3, -2) : .identity, outside: Pixel(0.2, 0.8, 0.4, 0.5))
      let selection = variant == 1 ? IntRect(x: 2, y: 3, width: 27, height: 19) : IntRect(x: 0, y: 0, width: 32, height: 24)
      let mask = variant == 1 ? try SelectionMask(width: 32, height: 24, bytes: (0..<768).map { UInt8(($0%3)*127) }) : nil
      let points = (0..<12).map { i in StrokePoint(x: 4+Double(i)*2, y: 12+sin(Double(i)/2)*7, pressure: [Float(0.2), 0.6, 1, 0][i%4]) }
      let stroke = CloneStroke(source: sample, mapping: mapping, brush: brush, points: [points[0]], mask: variant == 3)
      let session = try CloneStrokeSession(surface: pixels, stroke: stroke,
        transform: variant == 3 ? layer.maskCoordinateTransform : layer.coordinateTransform,
        selection: selection, selectionMask: mask, preserveTransparency: variant == 2)
      let expected = try XCTUnwrap(records.first { $0["depth"] as? String == String(describing: depth) && $0["variant"] as? Int == variant }?["prefix_sha256"] as? [String])
      let retained = session.surface; let retainedHash = hash(retained)
      for i in points.indices {
        let result = i == 0 ? session.surface : try session.append([points[i]])
        XCTAssertEqual(hash(result), expected[i], "\(depth) variant\(variant) prefix\(i+1)")
      }
      XCTAssertEqual(hash(retained), retainedHash, "Published snapshots must remain immutable")
      XCTAssertEqual(hash(try session.append([])), expected.last)
    }}
  }
  func testInvalidAppendPoisonsSessionWithoutPublishingPartialPixels() throws {
    let source = try Surface(width: 32, height: 32, fill: .white)
    let stroke = CloneStroke(source: .init(surface: source), mapping: .init(source: .init(0, 0), anchor: .init(0, 0)), brush: CloneBrush(), points: [.init(x: 4, y: 4)])
    let session = try CloneStrokeSession(surface: Surface(width: 32, height: 32), stroke: stroke, transform: .identity)
    let before = session.surface
    XCTAssertThrowsError(try session.append([.init(x: 6, y: 6), .init(x: .nan, y: 8)]))
    XCTAssertEqual(session.surface, before)
    XCTAssertThrowsError(try session.append([.init(x: 6, y: 6)]))
  }
  private func hash(_ surface: Surface) -> String {
    var bytes = Data()
    for y in 0..<surface.height { for x in 0..<surface.width {
      let p = surface.pixel(x: x, y: y)
      for value in [p.r, p.g, p.b, p.a] {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) }
      }
    }}
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}
