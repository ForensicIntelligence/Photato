import Foundation
import XCTest

@testable import PhotoCraftCore

final class InpaintingTests: XCTestCase {
  func testOriginalRustCompletionTextureAndOffsetOracle() throws {
    let data = try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: "inpaint-oracle", withExtension: "bin", subdirectory: "Fixtures")))
    var pos = 0
    var cases = 0
    var values = 0
    var exact = 0
    var maximum: Float = 0
    func u32() -> UInt32 {
      defer { pos += 4 }
      return (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[pos + $1]) << ($1 * 8) }
    }
    func floats(_ n: Int) -> [Float] { (0..<n).map { _ in Float(bitPattern: u32()) } }
    while pos < data.count {
      let w = Int(u32())
      let h = Int(u32())
      let ch = Int(u32())
      let kind = Int(u32())
      let refine = Int(u32())
      let hole = (0..<w * h).map { _ -> Bool in
        defer { pos += 1 }
        return data[pos] != 0
      }
      let image = floats(w * h * ch)
      let hasCompletion = data[pos] != 0
      pos += 1
      let expectedCompletion = hasCompletion ? floats(w * h * ch) : nil
      let expectedTexture = floats(w * h * ch)
      let dx = Int(Int32(bitPattern: u32()))
      let dy = Int(Int32(bitPattern: u32()))
      var p = Inpainting.Parameters()
      p.refineExtent = refine
      let completion = try Inpainting.complete(
        width: w, height: h, channels: ch, image: image, hole: hole, parameters: p)
      let texture = try Inpainting.synthesize(
        width: w, height: h, channels: ch, image: image, hole: hole, block: 6)
      let offset = try Inpainting.bestOffset(
        width: w, height: h, channels: ch, image: image, hole: hole, ring: 3, maxRadius: 24)
      XCTAssertEqual(offset?.x, dx == Int32.min ? nil : dx, "case \(kind)")
      XCTAssertEqual(offset?.y, dy == Int32.min ? nil : dy, "case \(kind)")
      XCTAssertEqual(completion != nil, hasCompletion)
      var comparisons = [(texture, expectedTexture)]
      if let completion, let expectedCompletion {
        comparisons.append((completion, expectedCompletion))
      }
      for (actual, expected) in comparisons {
        var worst: Float = 0
        for i in actual.indices {
          worst = max(worst, abs(actual[i] - expected[i]))
          if actual[i].bitPattern == expected[i].bitPattern { exact += 1 }
          if !hole[i / ch] { XCTAssertEqual(actual[i].bitPattern, image[i].bitPattern) }
        }
        XCTAssertLessThanOrEqual(worst, 0.000002, "Rust region \(kind)")
        maximum = max(maximum, worst)
        values += actual.count
      }
      cases += 1
    }
    XCTAssertEqual(cases, 6)
    print(
      "Inpainting Rust oracle: \(exact)/\(values) exact Float32 values; maximum error \(maximum); six proximity offsets agree"
    )
  }

  func testContentCompletionRestoresPeriodicStructureAndIsDeterministic() throws {
    let w = 64
    let h = 64
    let clean: [Float] = (0..<w * h).map { ($0 % w / 4) % 2 == 0 ? 0.2 : 0.8 }
    let hole = (0..<w * h).map { hypot(Double($0 % w - 32), Double($0 / w - 32)) < 6 }
    let dirty = clean.indices.map { hole[$0] ? Float(0.5) : clean[$0] }
    let output = try XCTUnwrap(
      Inpainting.complete(width: w, height: h, channels: 1, image: dirty, hole: hole))
    let sum = output.indices.filter { hole[$0] }.reduce(Float(0)) {
      $0 + pow(output[$1] - clean[$1], 2)
    }
    XCTAssertLessThan(sqrt(sum / Float(hole.filter { $0 }.count)), 0.15)
    XCTAssertEqual(
      try Inpainting.complete(width: w, height: h, channels: 1, image: dirty, hole: hole), output)
  }

  func testValidationAndUnavailableTextureSources() throws {
    let image: [Float] = [0.2, 0.8, 0.4, 1]
    let hole = [true, true, true, true]
    XCTAssertNil(
      try Inpainting.complete(width: 2, height: 2, channels: 1, image: image, hole: hole))
    XCTAssertEqual(
      try Inpainting.synthesize(
        width: 2, height: 2, channels: 1, image: image, hole: hole, block: 4), [0, 0, 0, 0])
    for (w, h, ch) in [(Int.max, 1, 1), (0, 0, 1), (4096, 4096, 4), (1, 1, 5)] {
      XCTAssertThrowsError(
        try Inpainting.complete(width: w, height: h, channels: ch, image: [1], hole: [false]))
    }
    XCTAssertThrowsError(
      try Inpainting.complete(width: 1, height: 1, channels: 1, image: [.nan], hole: [false]))
    var p = Inpainting.Parameters()
    p.patchRadius = Int.max
    XCTAssertThrowsError(
      try Inpainting.complete(
        width: 1, height: 1, channels: 1, image: [0], hole: [false], parameters: p))
    XCTAssertThrowsError(
      try Inpainting.bestOffset(
        width: 2, height: 2, channels: 1, image: image, hole: hole, ring: 3, maxRadius: Int.max))
  }
  @MainActor func testCancellationIsReported() async {
    let task = Task { () -> Bool in
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        _ = try Inpainting.complete(width: 1, height: 1, channels: 1, image: [1], hole: [true])
        return false
      } catch is CancellationError { return true } catch { return false }
    }
    let cancelled = await task.value
    XCTAssertTrue(cancelled)
  }
}
