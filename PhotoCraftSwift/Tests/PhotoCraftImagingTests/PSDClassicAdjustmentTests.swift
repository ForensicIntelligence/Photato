import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDClassicAdjustmentTests: XCTestCase {
  func testEditablePSDAndPSBRoundTripsAtAllDepths() throws {
    for depth in PixelDepth.allCases {
      for kind in ClassicAdjustment.Kind.allCases {
        var d = try CraftDocument(width:6,height:4,depth:depth)
        d.layers[0].content = .raster(try Surface(width:6,height:4,depth:depth,fill:Pixel(0.8,0.2,0.4)))
        var value = ClassicAdjustment(kind); value.vibrance = 40; value.saturation = -10
        value.weights[0] = 80; value.tint = ClassicAdjustment.defaultTint
        value.color = Pixel(1,0.4,0); value.matrix[0] = [60,50,-10,5]; value.adjustments[0][0] = 25
        // Canonical defaults for unused fields, since PSD stores only the selected kind.
        var canonical = ClassicAdjustment(kind)
        switch kind {
        case .vibrance: canonical.vibrance = value.vibrance; canonical.saturation = value.saturation
        case .blackWhite: canonical.weights = value.weights; canonical.tint = value.tint
        case .photoFilter: canonical.color = value.color
        case .channelMixer: canonical.matrix = value.matrix
        case .selectiveColor: canonical.adjustments = value.adjustments
        }
        d.selection = IntRect(x:1,y:0,width:3,height:4)
        d.layers.append(try canonical.layer(in:d)); d.selection = nil
        for format in [PSDFileFormat.psd,.psb] {
          let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(d,format:format))
          XCTAssertEqual(reopened.layers.last?.content,d.layers.last?.content)
          let actual = try Renderer.composite(reopened), expected = try Renderer.composite(d)
          for x in 0..<6 { XCTAssertEqual(actual.pixel(x:x,y:0).r,expected.pixel(x:x,y:0).r,accuracy:0.001) }
        }
      }
    }
  }
  func testStrictBinaryValidationAndQuantizedPhotoFilter() throws {
    for kind in ClassicAdjustment.Kind.allCases {
      let a = ClassicAdjustment(kind), key = PSDClassicAdjustment.key(kind), data = try PSDClassicAdjustment.write(a)
      for n in [0,1,data.count/2] { XCTAssertThrowsError(try PSDClassicAdjustment.read(data.prefix(n),key:key)) }
      let reopened = try PSDClassicAdjustment.read(data,key:key)
      if kind == .photoFilter { XCTAssertEqual(reopened.color.r,a.color.r,accuracy:1/65535) }
      else { XCTAssertEqual(reopened,a) }
    }
    var mixer = try PSDClassicAdjustment.write(.init(.channelMixer)); mixer[2] = 2
    XCTAssertThrowsError(try PSDClassicAdjustment.read(mixer,key:"mixr"))
  }
  func testBakedAndEditableRenderingAgreeForOpaqueSelection() throws {
    for depth in PixelDepth.allCases {
      for kind in ClassicAdjustment.Kind.allCases {
        var d = try CraftDocument(width:4,height:2,depth:depth)
        d.layers[0].content = .raster(try Surface(width:4,height:2,depth:depth,fill:Pixel(0.8,0.2,0.4)))
        d.selection = IntRect(x:1,y:0,width:2,height:2)
        var a = ClassicAdjustment(kind); a.vibrance = 60; a.adjustments[0][0] = 20
        var baked = d; try Command.applyAdjustment(d.layers[0].id,.classic(a)).apply(to:&baked)
        d.layers.append(try a.layer(in:d))
        let x = try Renderer.composite(baked), y = try Renderer.composite(d)
        for i in 0..<4 { XCTAssertEqual(x.pixel(x:i,y:0).r,y.pixel(x:i,y:0).r,accuracy:0.005) }
      }
    }
  }
}
