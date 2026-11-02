import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFLayerCompositeBoundaryTests: XCTestCase {
  func testLayerTransparencyUsesTheExternalTIFFCompositeConvention() throws {
    let helper = TIFFLayerTests()
    for depth in PixelDepth.allCases {
      for alpha: Float in [0.25, 1] {
        var model = try CraftDocument(width: 5, height: 3, depth: depth)
        let surface = try Surface(width: 5, height: 3, depth: depth, fill: Pixel(0.25, 0.5, 0.75, alpha))
        model.layers[0].content = .raster(surface)
        model.layers[0].name = "Owned layer"
        for order in RasterEncodingOptions.TIFFByteOrder.allCases {
          let bytes = try RasterIO.encoded(model, type: .tiff,
            options: .init(tiffByteOrder: order, tiffLayers: true))
          let reopened = try RasterIO.read(bytes)
          XCTAssertEqual(reopened.layers.count, 1)
          XCTAssertEqual(reopened.layers[0].name, "Owned layer")
          XCTAssertEqual(try helper.raw(helper.raster(reopened.layers[0])), try helper.raw(surface))
          XCTAssertNil(reopened.alphaChannels)
        }
      }
    }
  }
}
