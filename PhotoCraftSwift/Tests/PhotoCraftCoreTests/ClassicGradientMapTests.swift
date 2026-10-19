import Foundation
import XCTest

@testable import PhotoCraftCore

final class ClassicGradientMapTests: XCTestCase {
  private struct Reference: Decodable {
    let name: String
    let positions: [Int]
    let midpoints: [Int]
    let colors: [[Int]]
    let smoothness: Int
    let knownDifferencePositions: [Int]
    func gradient(storedColors: Bool = false) -> GradientDefinition {
      func component(_ n: Int) -> Float {
        storedColors ? Float((n * 65535 + 16384) / 32768) / 65535 : Float(n) / 32768
      }
      return GradientDefinition(
        name: name,
        colors: positions.indices.map { i in
          let c = colors[i].map(component)
          return .init(
            Float(positions[i]) / 4096, .rgb(Pixel(c[0], c[1], c[2])),
            midpoint: Float(midpoints[i]) / 100)
        }, smoothness: Float(smoothness) / 4096, method: .classic)
    }
  }
  private func fixture(_ ext: String) throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: "photoshop-classic-rgb16", withExtension: ext, subdirectory: "Fixtures")))
  }
  func testIndependentPhotoshopRampsAndExplicitRoundingResiduals() throws {
    let references = try JSONDecoder().decode([Reference].self, from: fixture("json"))
    let bytes = try fixture("bin")
    XCTAssertEqual(Array(bytes.prefix(12)), [80, 67, 76, 83, 0, 0, 0, 1, 0, 0, 0, 21])
    XCTAssertEqual(bytes.count, 12 + 21 * 4097 * 3 * 2)
    for stored in [false, true] {
      for (index, reference) in references.enumerated() {
        let transfer = try GradientMapTransfer(
          .init(gradient: reference.gradient(storedColors: stored)), depth: .u16)
        var differences: [Int] = []
        var maximum = 0
        for t in 0...4096 {
          let input = Float(t) / 4096
          let output = transfer.apply(Pixel(input, input, input))
          let rgb = [output.r, output.g, output.b].map { Int(($0 * 32768).rounded()) }
          var changed = false
          for c in 0..<3 {
            let at = 12 + ((index * 4097 + t) * 3 + c) * 2
            let expected = Int(bytes[at]) << 8 | Int(bytes[at + 1])
            let error = abs(rgb[c] - expected)
            changed = changed || error != 0
            maximum = max(maximum, error)
          }
          if changed { differences.append(t) }
        }
        // Two unresolved one-level positions are tracked, never labeled exact parity.
        XCTAssertEqual(
          differences.count, reference.knownDifferencePositions.count,
          "\(reference.name), stored \(stored); first \(Array(differences.prefix(12)))")
        XCTAssertEqual(
          Array(differences.prefix(12)), reference.knownDifferencePositions, reference.name)
        XCTAssertLessThanOrEqual(
          maximum, reference.knownDifferencePositions.isEmpty ? 0 : 1, reference.name)
      }
    }
  }
  func testReversePreservesAlphaAndExtremeMidpointsUsePhotoshopBounds() throws {
    let references = try JSONDecoder().decode([Reference].self, from: fixture("json"))
    let reference = try XCTUnwrap(references.first { $0.name == "midpoints-zero-full" })
    let bounded = reference.gradient()
    var extremes = bounded
    for i in extremes.colors.indices {
      if extremes.colors[i].midpoint == 0.05 { extremes.colors[i].midpoint = 0 }
      if extremes.colors[i].midpoint == 0.95 { extremes.colors[i].midpoint = 1 }
    }
    let normal = try GradientMapTransfer(.init(gradient: bounded), depth: .u16)
    let clamped = try GradientMapTransfer(.init(gradient: extremes), depth: .u16)
    let reversed = try GradientMapTransfer(.init(gradient: bounded, reverse: true), depth: .u16)
    for t in 0...4096 {
      let v = Float(t) / 4096
      let p = Pixel(v, v, v, 0.37)
      XCTAssertEqual(normal.apply(p), clamped.apply(p))
      XCTAssertEqual(reversed.apply(p), normal.apply(Pixel(1 - v, 1 - v, 1 - v, p.a)))
      XCTAssertEqual(reversed.apply(p).a, p.a)
    }
  }
  func testSingleCoincidentAndOnePositionSegmentsRemainFinite() throws {
    for positions: [Float] in [[0.5], [0, 0], [1, 1], [0, 1 / 4096, 2 / 4096, 1]] {
      for midpoint: Float in [0, 0.05, 0.95, 1] {
        let gradient = GradientDefinition(
          name: "Boundary",
          colors: positions.enumerated().map { index, position in
            .init(position, .rgb(index.isMultiple(of: 2) ? .black : .white), midpoint: midpoint)
          }, method: .classic)
        let transfer = try GradientMapTransfer(.init(gradient: gradient), depth: .u16)
        for i in 0...4096 {
          let t = Float(i) / 4096
          let p = transfer.apply(Pixel(t, t, t))
          XCTAssertTrue(p.isFinite)
          XCTAssertTrue((0...1).contains(p.r))
        }
      }
    }
  }
}
