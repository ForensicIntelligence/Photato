import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class LargeTonePreviewTests: XCTestCase {
  func testOverviewUsesExistingExactCompositionAndBoundedSparseMaximumExtent() throws {
    for depth in PixelDepth.allCases { for opacity: Float in [1,0.63] {
      var d=try CraftDocument(width:52,height:39,depth:depth)
      var pixels=try Surface(width:52,height:39,depth:depth,fill:Pixel(0.2,0.5,0.8,0.7))
      for x in 0..<52 {pixels.setPixel(x:x,y:x%39,Pixel(Float(x)/52,0.3,0.2,Float(x%3)/2))}
      d.layers[0].content = .raster(pixels);d.layers[0].opacity=opacity
      var mask=try Surface(width:52,height:39,depth:.u8,fill:Pixel(0.5,0.5,0.5));mask.setPixel(x:2,y:3,.white)
      d.layers[0].mask=mask
      d.layers.append(Layer(name:"Top",content:.raster(try Surface(width:52,height:39,depth:depth,fill:Pixel(0.9,0.2,0.1,0.37)))))
      let reference=try ColorManagement.displayImage(Renderer.composite(d),in:d)
      let preview=try ColorManagement.displayImage(ClassicToneInput.equalizeOverview(in:d),in:d)
      XCTAssertEqual(reference.width,preview.width);XCTAssertEqual(reference.height,preview.height)
      XCTAssertEqual(reference.dataProvider?.data as Data?,preview.dataProvider?.data as Data?,"\(depth) opacity\(opacity)")
    } }
    var large=try CraftDocument(width:300000,height:300000)
    large.layers[0].content = .raster(try Surface(width:large.width,height:large.height,fill:Pixel(0.2,0.5,0.8)))
    let image=try ClassicToneInput.equalizeOverview(in:large)
    XCTAssertEqual(image.width,2048);XCTAssertEqual(image.height,2048);XCTAssertLessThan(image.allocatedBytes,1_000_000)
    XCTAssertEqual(image.pixel(x:0,y:0),Pixel(0.2,128.0/255,0.8));XCTAssertEqual(image.pixel(x:2047,y:2047),image.pixel(x:0,y:0))
  }
}
