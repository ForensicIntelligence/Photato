import Foundation
import XCTest

@testable import PhotoCraftCore

final class RenderStorageTests: XCTestCase {
  func testRepeatedTileWritesPreserveSnapshotsPaddingAndHiddenFloatBits() throws {
    for depth in PixelDepth.allCases {
      var surface = try Surface(
        width: 130, height: 129, depth: depth, fill: Pixel(-0.0, 0.4, 0.7, 0))
      let empty = surface
      var expected = [Pixel](repeating: surface.defaultPixel, count: surface.width * surface.height)
      var saved: [Surface] = []
      var savedBytes: [Data] = []
      for i in 0..<4096 {
        let x = (i * 67) % surface.width
        let y = (i * 31) % surface.height
        let pixel = Pixel(i % 2 == 0 ? -0.0 : -0.125, Float(i % 13) / 12, 1.25, Float(i % 5) / 4)
        surface.setPixel(x: x, y: y, pixel)
        expected[y * surface.width + x] = pixel.quantized(depth)
        if i % 512 == 0 {
          saved.append(surface)
          savedBytes.append(try surface.rgbaData(depth: .f32))
        }
      }
      for (snapshot, bytes) in zip(saved, savedBytes) {
        XCTAssertEqual(try snapshot.rgbaData(depth: .f32), bytes)
      }
      XCTAssertEqual(empty.tileCount, 0)
      for y in 0..<surface.height {
        for x in 0..<surface.width {
          XCTAssertTrue(surface.pixel(x: x, y: y).hasSameBits(as: expected[y * surface.width + x]))
        }
      }
      let expanded = try surface.expanded(
        to: .init(x: 0, y: 0, width: 160, height: 160), fill: .clear)
      XCTAssertEqual(expanded.pixel(x: 130, y: 128), .clear)
      XCTAssertEqual(expanded.pixel(x: 129, y: 129), .clear)
    }
  }
  func testPreparedPatternAndSparseFallbackMatchEverySampleBit() throws {
    var count = 0
    for depth in PixelDepth.allCases {
      var surface = try Surface(width: 67, height: 65, depth: depth)
      for y in 0..<surface.height {
        for x in 0..<surface.width {
          surface.setPixel(
            x: x, y: y,
            Pixel(
              x % 7 == 0 ? -0.0 : Float(x) / 15 - 1,
              Float(y) / 27, Float((x + y) % 19) / 18, Float((x * 3 + y) % 8) / 7))
        }
      }
      let tile = try RasterPattern(name: "Prepared", surface: surface)
      for i in 0..<4 {
        var placement = PatternPlacement()
        placement.scale = [1, 137, 100, 1000][i]
        placement.angle = [0, 37, -90, 360_000][i]
        placement.phaseX = [0, 0.37, -90.5, 999_999][i]
        placement.phaseY = [0, -17.8, 44.25, -999_999][i]
        let prepared = try PatternSampler(tile, placement: placement)
        let sparse = try PatternSampler(tile, placement: placement, preparePixels: false)
        XCTAssertEqual(prepared.prepared.count, surface.width * surface.height)
        XCTAssertTrue(sparse.prepared.isEmpty)
        for y in -20..<30 {
          for x in -30..<35 {
            let px = Double(x) + 0.5
            let py = Double(y) + 0.125
            XCTAssertTrue(
              prepared.sample(x: px, y: py).hasSameBits(as: sparse.sample(x: px, y: py)))
            count += 4
          }
        }
      }
    }
    XCTAssertEqual(count, 156_000)
  }
  func testPreparationBudgetAndCancellationKeepLargePatternsSparse() async throws {
    let surface = try Surface(width: 513, height: 513, depth: .f32, fill: Pixel(2, -1, 0.25, 0.7))
    let pattern = try RasterPattern(name: "Large sparse tile", surface: surface, id: "large-sparse")
    let sampler = try PatternSampler(pattern)
    XCTAssertTrue(sampler.prepared.isEmpty)
    XCTAssertEqual(sampler.surface.allocatedBytes, 0)
    let reference = try PatternSampler(pattern, placement: .init(), preparePixels: false)
    XCTAssertTrue(
      sampler.tile(u: -513.125, v: 799.25).hasSameBits(as: reference.tile(u: -513.125, v: 799.25)))
    let small = try RasterPattern(name: "Cancelled", surface: Surface(width: 128, height: 128))
    try await Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      XCTAssertThrowsError(try PatternSampler(small)) { XCTAssertTrue($0 is CancellationError) }
    }.value
  }
  func testIdentityMaskProofIsConservativeAtEdgesAndWithFractionalCoverage() throws {
    let rect = IntRect(x: 0, y: 0, width: 40, height: 30)
    var layer = Layer(name: "Mask", content: .fill(.white))
    layer.mask = try Surface(width: 40, height: 30, fill: .white)
    layer.maskProperties = MaskProperties()
    var sampler = try MaskSampler(layer: layer)
    XCTAssertTrue(sampler.isIdentity(over: rect))
    XCTAssertFalse(sampler.isIdentity(over: .init(x: -1, y: 0, width: 40, height: 30)))
    XCTAssertLessThan(sampler.coverage(x: 0.1, y: 0.5), 1)
    layer.maskProperties?.transform = .translation(0.001, 0)
    XCTAssertFalse(try MaskSampler(layer: layer).isIdentity(over: rect))
    layer.maskProperties?.transform = .identity
    layer.mask = try Surface(width: 40, height: 30, depth: .f32, fill: Pixel(0.7, 0.7, 0.7))
    XCTAssertFalse(try MaskSampler(layer: layer).isIdentity(over: rect))
    layer.maskProperties?.density = 0
    XCTAssertTrue(try MaskSampler(layer: layer).isIdentity(over: rect))
    layer.maskProperties?.density = 0.4
    layer.maskProperties?.inverted = true
    layer.mask = try Surface(width: 100, height: 100, fill: .black)
    layer.maskProperties?.transform = .translation(-20, -20) * .rotation(7) * .scale(1.03, 0.97)
    sampler = try MaskSampler(layer: layer)
    XCTAssertTrue(sampler.isIdentity(over: rect))
    for y in 0..<30 {
      for x in 0..<40 {
        XCTAssertEqual(
          sampler.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5).bitPattern, Float(1).bitPattern)
      }
    }
    layer.mask?.setPixel(x: 30, y: 30, .white)
    XCTAssertFalse(try MaskSampler(layer: layer).isIdentity(over: rect))
  }
}
