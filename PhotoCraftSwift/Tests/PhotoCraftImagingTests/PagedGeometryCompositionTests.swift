import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PagedGeometryCompositionTests:XCTestCase {
  func testSparseCoordinateMaskCompositionMatchesFullRendererAcrossDepthsAndTranslations() throws {
    for depth in PixelDepth.allCases {for translated in [false,true] {for mode in 0..<5 {for opacity:Float in [0.4,1] {
      for maskEncoding:SurfaceColorEncoding in (depth == .f32 ? [.sRGB,.linearRGB]:[.sRGB]) {
      var d=try CraftDocument(width:129,height:65,depth:depth)
      let encoding:SurfaceColorEncoding=depth == .f32 ? .linearRGB:.sRGB
      var pixels=try Surface(width:translated ? 63:129,height:translated ? 33:65,depth:depth,fill:Pixel(0.25,0.5,0.75,1),colorEncoding:encoding)
      if depth == .f32 {pixels.setLinearPixel(x:3,y:2,Pixel(2,-0.25,4,0.5))}
      else {pixels.setPixel(x:3,y:2,Pixel(0.75,0.25,0.5,0.5))}
      var layer=Layer(name:"Owned masked pixels",content:.raster(pixels));layer.opacity=opacity
      if translated {layer.x=3;layer.y=4}
      var mask=try Surface(width:129,height:65,depth:depth,fill:.white)
      mask.setPixel(x:6,y:6,Pixel(0.25,0.25,0.25));layer.mask=try mask.interpretingSamples(as:maskEncoding)
      var properties=MaskProperties();properties.transform = .translation(Double(-layer.x),Double(-layer.y))
      if mode==1 {properties.inverted=true}
      if mode==2 {properties.density=0.5}
      if mode==3 {properties.enabled=false}
      if mode==4 {layer.mask=nil}
      layer.maskProperties=layer.mask == nil ? nil:properties
      var overlay=Layer(name:"Owned overlay",content:.raster(try Surface(width:129,height:65,depth:depth,fill:Pixel(0.75,0.5,0.25,0.25),colorEncoding:encoding)))
      overlay.opacity=0.6;d.layers=[layer,overlay];d.activeLayerID=layer.id
      let full=try Renderer.composite(d),sparse=try XCTUnwrap(SparseCanvasRenderer.composite(d))
      XCTAssertEqual(try sparse.rgbaData(depth:.f32,colorEncoding:encoding),try full.rgbaData(depth:.f32,colorEncoding:encoding),"\(depth),\(translated),\(mode),\(opacity),\(maskEncoding)")
    }}}}}
  }
  func testMaximumMaskedGeometryRendersWithoutWholeCanvasAllocation() throws {
    var d=try CraftDocument(width:300000,height:200000,depth:.f32)
    var pixels=try Surface(width:d.width,height:d.height,depth:.f32,fill:.white).interpretingSamples(as:.linearRGB)
    pixels.setLinearPixel(x:299999,y:199999,Pixel(4,-0.25,-0.0,0.5))
    d.layers[0].content = .raster(pixels)
    var mask=try Surface(width:d.width,height:d.height,depth:.f32,fill:.white)
    mask.setPixel(x:299999,y:199999,Pixel(0.5,0.5,0.5));d.layers[0].mask=mask
    let snapshot=try Renderer.render(d)
    XCTAssertTrue(snapshot.surface.linearPixel(x:299999,y:199999).hasSameBits(as:Pixel(4,-0.25,-0.0,0.25)))
    XCTAssertLessThan(snapshot.surface.allocatedBytes,1024*1024)
  }
  func testMaximumColouredCanvasGrowthRendersTranslatedOriginalCorrectly() throws {
    var d=try CraftDocument(width:2,height:2,depth:.u16)
    try Command.canvasSize(300000,300000,.center,Pixel(0.25,0.5,0.75)).apply(to:&d)
    let snapshot=try Renderer.render(d)
    XCTAssertEqual(snapshot.surface.pixel(x:0,y:0),Pixel(0.25,0.5,0.75).quantized(.u16))
    XCTAssertEqual(snapshot.surface.pixel(x:149999,y:149999),.white)
    XCTAssertLessThan(snapshot.surface.allocatedBytes,1024*1024)
  }
}
