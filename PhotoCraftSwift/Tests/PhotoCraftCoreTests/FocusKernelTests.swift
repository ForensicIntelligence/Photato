import Foundation
import XCTest

@testable import PhotoCraftCore

final class FocusKernelTests: XCTestCase {
  struct Reader {
    let data: Data
    var pos = 0
    init(_ name: String) throws {
      data = try Data(
        contentsOf: XCTUnwrap(
          Bundle.module.url(forResource: name, withExtension: "bin", subdirectory: "Fixtures")))
    }
    mutating func u() -> UInt32 {
      defer { pos += 4 }
      return (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[pos + $1]) << ($1 * 8) }
    }
    mutating func f() -> Float { Float(bitPattern: u()) }
    mutating func floats(_ n: Int) -> [Float] { (0..<n).map { _ in f() } }
  }
  func testOriginalRustBlurAndSharpenOracle() throws {
    var r = try Reader("focus-oracle")
    var exact = 0
    var count = 0
    var cases = 0
    var worst: Float = 0
    while r.pos < r.data.count {
      let w = Int(r.u())
      let h = Int(r.u())
      let ch = Int(r.u())
      let ai = r.u()
      let x0 = Int(r.u())
      let y0 = Int(r.u())
      let x1 = Int(r.u())
      let y1 = Int(r.u())
      let sigma = r.f()
      let amount = r.f()
      let data = r.floats(w * h * ch)
      let win = IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
      let alpha: Int? = ai == UInt32.max ? nil : Int(ai)
      let results = [
        try FocusKernels.blur(
          data, width: w, height: h, channels: ch, alpha: alpha, window: win, sigma: sigma),
        try FocusKernels.sharpen(
          data, width: w, height: h, channels: ch, alpha: alpha, window: win, amount: amount,
          protectDetail: false),
        try FocusKernels.sharpen(
          data, width: w, height: h, channels: ch, alpha: alpha, window: win, amount: amount,
          protectDetail: true),
      ]
      for result in results {
        let expected = r.floats(win.width * win.height * ch)
        for i in expected.indices {
          XCTAssertEqual(result[i], expected[i], accuracy: 0.000002, "region \(cases)")
          worst = max(worst, abs(result[i] - expected[i]))
          count += 1
          if result[i].bitPattern == expected[i].bitPattern { exact += 1 }
        }
      }
      cases += 1
    }
    XCTAssertEqual(cases, 8)
    print("Focus Rust oracle: \(exact)/\(count) exact Float32 values; maximum error \(worst)")
  }
  func testOriginalRustStatefulSmudgeOracle() throws {
    var r = try Reader("smudge-oracle")
    var exact = 0
    var count = 0
    var strokes = 0
    var dabs = 0
    var worst: Float = 0
    while r.pos < r.data.count {
      let w = Int(r.u())
      let h = Int(r.u())
      let ch = Int(r.u())
      let ai = r.u()
      let size = r.f()
      let strength = r.f()
      let fingerCount = Int(r.u())
      let steps = Int(r.u())
      let finger = r.floats(fingerCount)
      var data = r.floats(w * h * ch)
      var smudge = try SmudgeKernel(
        strength: strength, finger: finger.isEmpty ? nil : finger, maxBrushSize: size,
        alpha: ai == UInt32.max ? nil : Int(ai))
      for _ in 0..<steps {
        let cx = r.f()
        let cy = r.f()
        let x0 = Int(r.u())
        let y0 = Int(r.u())
        let x1 = Int(r.u())
        let y1 = Int(r.u())
        let win = IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        let coverage = r.floats(win.width * win.height)
        try smudge.apply(
          to: &data, width: w, height: h, channels: ch, center: .init(Double(cx), Double(cy)),
          window: win, coverage: coverage)
        let expected = r.floats(w * h * ch)
        for i in expected.indices {
          XCTAssertEqual(data[i], expected[i], accuracy: 0.000002, "stroke \(strokes), dab \(dabs)")
          worst = max(worst, abs(data[i] - expected[i]))
          count += 1
          if data[i].bitPattern == expected[i].bitPattern { exact += 1 }
        }
        dabs += 1
      }
      strokes += 1
    }
    XCTAssertEqual(strokes, 6)
    XCTAssertEqual(dabs, 36)
    print("Smudge Rust oracle: \(exact)/\(count) exact Float32 values; maximum error \(worst)")
  }
  func testPremultipliedBlurAndSharpenDetailProtection() throws {
    let data: [Float] = (0..<16).flatMap { $0 < 8 ? [1, 0, 0, 1] : [0, 1, 0, 0] }
    let win = IntRect(x: 4, y: 0, width: 8, height: 1)
    let blur = try FocusKernels.blur(
      data, width: 16, height: 1, channels: 4, alpha: 3, window: win, sigma: 1.5)
    for i in stride(from: 0, to: blur.count, by: 4) where blur[i + 3] > 0.001 {
      XCTAssertEqual(blur[i], 1, accuracy: 0.000001)
      XCTAssertEqual(blur[i + 1], 0)
    }
    let edge: [Float] = [0.2, 0.2, 0.3, 0.7, 0.8, 0.8]
    let protected = try FocusKernels.sharpen(
      edge, width: 6, height: 1, channels: 1, alpha: nil,
      window: .init(x: 0, y: 0, width: 6, height: 1), amount: 4, protectDetail: true)
    let unprotected = try FocusKernels.sharpen(
      edge, width: 6, height: 1, channels: 1, alpha: nil,
      window: .init(x: 0, y: 0, width: 6, height: 1), amount: 4, protectDetail: false)
    XCTAssertTrue(protected.allSatisfy { $0 >= 0.2 && $0 <= 0.8 })
    XCTAssertLessThan(unprotected.min()!, 0.2)
    XCTAssertGreaterThan(unprotected.max()!, 0.8)
  }
  func testMalformedKernelInputsAndSmudgeCancellationAreAtomic() async throws {
    let win = IntRect(x: 0, y: 0, width: 1, height: 1)
    for data: [Float] in [[.nan], [.infinity], [1e20]] {
      XCTAssertThrowsError(
        try FocusKernels.blur(
          data, width: 1, height: 1, channels: 1, alpha: nil, window: win, sigma: 1))
    }
    XCTAssertThrowsError(
      try FocusKernels.blur(
        [1], width: Int.max, height: 1, channels: 1, alpha: nil, window: win, sigma: 1))
    XCTAssertThrowsError(
      try FocusKernels.blur([1], width: 1, height: 1, channels: 1, alpha: 2, window: win, sigma: 1))
    XCTAssertThrowsError(
      try FocusKernels.blur(
        [1], width: 1, height: 1, channels: 1, alpha: nil, window: win, sigma: .nan))
    var sm = try SmudgeKernel(strength: 0.5, maxBrushSize: 4, alpha: nil)
    var data: [Float] = [0.5]
    XCTAssertThrowsError(
      try sm.apply(
        to: &data, width: 1, height: 1, channels: 1, center: .init(0, 0), window: win,
        coverage: [.nan]))
    XCTAssertEqual(data, [0.5])
    let task = Task { () -> Bool in
      withUnsafeCurrentTask { $0?.cancel() }
      var sm = try SmudgeKernel(strength: 0.5, maxBrushSize: 4, alpha: nil)
      var data: [Float] = [0.5]
      do {
        try sm.apply(
          to: &data, width: 1, height: 1, channels: 1, center: .init(0, 0), window: win,
          coverage: [1])
        return false
      } catch is CancellationError { return data == [0.5] } catch { return false }
    }
    do {
      let result = try await task.value
      XCTAssertTrue(result)
    } catch is CancellationError {
      // Constructor may itself gain cancellation checks later; no buffer was modified.
    }
  }
}
