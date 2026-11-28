import CoreGraphics
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFLargeRGBOutputTests: XCTestCase {
  func testStreamedPackedRGBKeepsLegacySamplesAndICCAtEachDepth() throws {
    for depth in PixelDepth.allCases {
      let width = 37, height = 23
      var surface = try Surface(width: width, height: height, depth: depth)
      if depth == .f32 { surface = try surface.interpretingSamples(as: .linearRGB) }
      for y in 0..<height { for x in 0..<width {
        let pixel = Pixel(Float((x * 7 + y * 3) % 47) / 46,
          Float((x * 19 + y * 13) % 51) / 50, Float((x * 31 + y * 19) % 57) / 56,
          Float((x * 13 + y * 29) % 31) / 30)
        if depth == .f32 { surface.setLinearPixel(x: x, y: y, pixel) }
        else { surface.setPixel(x: x, y: y, pixel) }
      } }
      var document = try CraftDocument(width: width, height: height, depth: depth)
      document.layers[0].content = .raster(surface)
      let top = try Surface(width: 15, height: 7, depth: depth, fill: Pixel(0.67, 0.31, 0.51, 0.487))
      var layer = Layer(name: "Second transparency source", content: .raster(top))
      layer.x = 6; layer.y = 4
      document.layers.append(layer)
      let wide = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?)
      for profile in [nil, wide] {
        document.workingICC = try ColorManagement.importedProfile(profile, depth: depth)
        for transparent in [false, true] {
          for embed in [false, true] {
            let options = RasterEncodingOptions(tiffCompression: RasterEncodingOptions.TIFFCompression.none,
              tiffByteOrder: .bigEndian, tiffTransparency: transparent, tiffEmbedProfile: embed)
            let prior = try samples(RasterIO.encoded(document, type: .tiff, options: options))
            let streamed = try samples(TIFFComponentExport.encoded(document, options: options))
            XCTAssertEqual(streamed.pixels, prior.pixels)
            XCTAssertEqual(streamed.profile, prior.profile)
            XCTAssertEqual(streamed.extras, prior.extras)
          }
        }
      }
    }
  }

  private func samples(_ bytes: Data) throws -> (pixels: Data, profile: Data?, extras: [Int]) {
    let container = try TIFFContainer(bytes, metadata: false, additionalTags: [34675])
    let format = try XCTUnwrap(TIFFStorage.Geometry(container, allowAssociatedAlpha: true))
    XCTAssertFalse(format.planar)
    XCTAssertEqual(format.compression, 1)
    var pixels = Data()
    for (offset, count) in zip(format.offsets, format.counts) {
      pixels.append(try container.bytes(at: offset, count: count))
    }
    return (pixels, container.root.fields[34675]?.data, try container.numbers(338, default: []))
  }
}
