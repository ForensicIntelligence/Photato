import Foundation
import XCTest
@testable import PhotoCraftCore

final class CameraRawLightTests: XCTestCase {
  private func reference(_ input: Surface, settings: CameraRawSettings) -> Surface {
    var gains = SIMD3<Float>(1 + 0.35 * settings.temperature / 100,
      1 - 0.25 * settings.tint / 100, 1 - 0.35 * settings.temperature / 100)
    let luminance = 0.2126 * gains.x + 0.7152 * gains.y + 0.0722 * gains.z
    gains *= pow(2, settings.exposure) / luminance
    var output = input
    for y in 0..<input.height {
      for x in 0..<input.width {
        let p = input.pixel(x: x, y: y)
        let rgb = p.rgb
        var adjusted = SIMD3<Float>.zero
        for channel in 0..<3 {
          adjusted[channel] = SRGBTransfer.encoded(max(0, SRGBTransfer.linear(rgb[channel]) * gains[channel]))
        }
        output.setPixel(x: x, y: y, Pixel(adjusted.x, adjusted.y, adjusted.z, p.a))
      }
    }
    return output
  }

  func testGainLUTMatchesEveryIntegerCodeAndPreservesArchivedTiles() throws {
    for depth in [PixelDepth.u8, .u16] {
      let side = depth == .u8 ? 65 : 513
      let maxCode = depth == .u8 ? 255 : 65_535
      let scale = Float(maxCode)
      var input = try Surface(width: side, height: side, depth: depth)
      for y in 0..<side {
        for x in 0..<side {
          let code = (y * side + x) & maxCode
          input.setPixel(x: x, y: y, Pixel(Float(code) / scale, Float(code ^ maxCode) / scale,
            Float((code * 17) & maxCode) / scale, Float(x % 7) / 6))
        }
      }
      var settings = CameraRawSettings()
      settings.exposure = depth == .u8 ? 1.25 : -0.75
      settings.temperature = 33
      settings.tint = -21
      let expected = reference(input, settings: settings)
      let result = try CameraRawEngine.develop(input, settings: settings)
      XCTAssertEqual(result, expected)
      XCTAssertEqual(result.depth, input.depth)
      XCTAssertEqual(result.colorEncoding, input.colorEncoding)
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      XCTAssertEqual(try encoder.encode(result), try encoder.encode(expected))
    }
  }

  func testGainLUTUsesScalarForLegacySamplesOutsideTheNominalIntegerGrid() throws {
    struct LegacySurface: Encodable {
      let width = 513
      let height = 513
      let depth = PixelDepth.u16
      let defaultPixel = Pixel.black
      let tiles: [String: [Pixel]]
    }

    var storage = [Pixel](repeating: .black, count: Surface.tileSide * Surface.tileSide)
    storage[0] = Pixel(0.001234, 0.1234, -0.08, 0)
    storage[1] = Pixel(0.83735, 0.62426, 0.137525, 0.6)
    storage[2] = Pixel(1.13, -0.0, 0.512562)
    let encoded = try JSONEncoder().encode(LegacySurface(tiles: ["0": storage]))
    let input = try JSONDecoder().decode(Surface.self, from: encoded)
    XCTAssertEqual(input.pixel(x: 0, y: 0).r, 0.001234)
    var settings = CameraRawSettings()
    settings.exposure = -2.17
    settings.temperature = -9
    settings.tint = 17
    XCTAssertEqual(try CameraRawEngine.develop(input, settings: settings), reference(input, settings: settings))
  }
}
