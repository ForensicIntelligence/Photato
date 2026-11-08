import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class LargeWarpCompositeTests:XCTestCase {
  func testPreparedLargeWarpCompositeMatchesIndependentRegionalPathAtAllRGBDepths()throws {
    for depth in PixelDepth.allCases {
      var document=try CraftDocument(width:9001,height:4001,depth:depth)
      var pixels=try Surface(width:17,height:13,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      for y in 0..<13 {for x in 0..<17 {
        let p=Pixel(Float(x)/8,Float(y)/6,0.3,Float((x+y)%5)/4)
        if depth == .f32 {pixels.setLinearPixel(x:x,y:y,p)}else{pixels.setPixel(x:x,y:y,p)}
      }}
      let background=Layer(name:"Implicit background",content:.fill(Pixel(0.2,0.4,0.7,1)))
      var layer=Layer(name:"Warp source",content:.raster(pixels));layer.x=100;layer.y=150;layer.opacity=0.75
      document.layers=[background,layer];document.activeLayerID=layer.id
      try SmartObjectIO.convert(in:document,selected:[layer.id]).apply(to:&document)
      let id=try XCTUnwrap(document.activeLayerID)
      let retained=try XCTUnwrap(document.layers.first{$0.id==id})
      XCTAssertNotNil(retained.smartObject)
      var warp=WarpDefinition();warp.style = .arch;warp.bend=20
      document=try WarpEdit.prepare(document,layerID:id,warp:warp).result
      let original=document
      let full=try Renderer.composite(document)
      for region in [IntRect(x:80,y:130,width:64,height:64),.init(x:2040,y:60,width:32,height:16),.init(x:8980,y:3980,width:21,height:21)] {
        let reference=try Renderer.composite(document,region:region)
        XCTAssertEqual(try full.cropped(to:region),try reference.cropped(to:region),"\(depth)/\(region)")
      }
      XCTAssertEqual(document,original)
      let result=try XCTUnwrap(document.layers.first{$0.id==id})
      XCTAssertEqual(result.content,retained.content)
      XCTAssertEqual(result.smartObject,retained.smartObject)
      XCTAssertNotNil(result.warp)
    }
  }
}
