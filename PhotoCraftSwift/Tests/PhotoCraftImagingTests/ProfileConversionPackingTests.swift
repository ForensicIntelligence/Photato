import CoreGraphics
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class ProfileConversionPackingTests: XCTestCase {
  private func archivedSurface(alpha: Float) throws -> Surface {
    let implicit = Pixel(0.4265824, 0.515371, 0.737119, alpha)
    var tile = [Pixel](repeating: implicit, count: Surface.tileSide * Surface.tileSide)
    tile[0] = Pixel(0.0525327, 0.2412248, 0.833527, alpha)
    tile[127] = Pixel(0.3386573, 0.8918533, 0.195527, alpha)
    let value = LegacySurface(width: 67, height: 71, depth: .u16, defaultPixel: implicit, tiles: [0: tile])
    return try JSONDecoder().decode(Surface.self, from: JSONEncoder().encode(value))
  }

  private struct LegacySurface: Encodable {
    let width: Int
    let height: Int
    let depth: PixelDepth
    let defaultPixel: Pixel
    let tiles: [Int: [Pixel]]
  }

  func testPackedSourceMatchesLegacyOpaqueFloatBytesForBothColorEncodings() throws {
    let integer = try archivedSurface(alpha: 0)
    var float = try Surface(width: 69, height: 67, depth: .f32, colorEncoding: .linearRGB)
    float.setLinearPixel(x: 65, y: 66, Pixel(-0.0, -0.25, 1.3, 0.05))
    float.setLinearPixel(x: 64, y: 65, Pixel(0.81, 0.06, 7.0, 1))
    for surface in [integer, float, try float.interpretingSamples(as: .sRGB)] {
      let opaque = try legacyOpaque(surface)
      for targetEncoding in [SurfaceColorEncoding.sRGB, .linearRGB] {
        let expected = try opaque.rgbaData(depth: .f32, colorEncoding: targetEncoding)
        XCTAssertTrue(try surface.profileConversionRGBA(colorEncoding: targetEncoding) == expected)
      }
    }
  }

  func testProfileConversionMatchesLegacyDepthAlphaAndHiddenSamples() throws {
    let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?)
    let rgb8 = try Surface(width: 69, height: 71, depth: .u8, fill: Pixel(0.721, 0.188, 0.352, 1))
    var rgb16 = try archivedSurface(alpha: 1)
    rgb16.setPixel(x: 66, y: 70, Pixel(0.44, 0.72, 0.18, 1))
    let hidden = try archivedSurface(alpha: 0)
    var mixed = hidden
    mixed.setPixel(x: 63, y: 70, Pixel(0.17, 0.828, 0.26, 0.37))
    mixed.setPixel(x: 66, y: 70, Pixel(0.33, 0.81, 0.16, 1))
    var hdr = try Surface(width: 65, height: 67, depth: .f32, colorEncoding: .linearRGB)
    hdr.setLinearPixel(x: 62, y: 61, Pixel(-0.0, 1.06, 0.27, 0))
    hdr.setLinearPixel(x: 64, y: 66, Pixel(0.965, 1.6, 0.18, 0.125))
    for surface in [rgb8, rgb16, hidden, mixed, hdr] {
      var source = try CraftDocument(width: 1, height: 1, depth: surface.depth)
      source.workingICC = try ColorManagement.importedProfile(p3, depth: surface.depth)
      for depth in PixelDepth.allCases {
        let target = try CraftDocument(width: 1, height: 1, depth: depth)
        let expected = try legacyConvert(surface, from: source, to: target)
        let result = try ColorManagement.converted(surface, from: source, to: target)
        XCTAssertTrue(result == expected, "Changed profile-conversion samples at \(surface.depth) → \(depth).")
        XCTAssertTrue(try result.rgbaData(depth: .f32) == expected.rgbaData(depth: .f32))
      }
    }
    XCTAssertFalse(try mixed.isOpaque())
    XCTAssertTrue(try rgb16.isOpaque())
  }
}

private func legacyOpaque(_ surface: Surface) throws -> Surface {
  var opaque = try surface.interpretingSamples(as: surface.colorEncoding)
  if opaque.colorEncoding == .linearRGB {
    for y in 0..<opaque.height {
      for x in 0..<opaque.width {
        let p = opaque.linearPixel(x: x, y: y)
        opaque.setLinearPixel(x: x, y: y, Pixel(p.r, p.g, p.b))
      }
    }
  } else {
    opaque.mapPixels { _, _, p in Pixel(p.r, p.g, p.b) }
  }
  return opaque
}

private func legacyConvert(_ surface: Surface, from source: CraftDocument, to target: CraftDocument) throws -> Surface {
  let inputEncoding: SurfaceColorEncoding = source.depth == .f32 ? .linearRGB : .sRGB
  let outputEncoding: SurfaceColorEncoding = target.depth == .f32 ? .linearRGB : .sRGB
  let image = try RasterIO.cgImage(legacyOpaque(surface), space: ColorManagement.space(for: source),
    colorEncoding: inputEncoding)
  var result = try RasterIO.surface(image, depth: target.depth, space: ColorManagement.space(for: target),
    colorEncoding: outputEncoding)
  for y in 0..<result.height {
    for x in 0..<result.width {
      var p = outputEncoding == .linearRGB ? result.linearPixel(x: x, y: y) : result.pixel(x: x, y: y)
      p.a = surface.pixel(x: x, y: y).a
      if outputEncoding == .linearRGB { result.setLinearPixel(x: x, y: y, p) }
      else { result.setPixel(x: x, y: y, p) }
    }
  }
  return result
}
