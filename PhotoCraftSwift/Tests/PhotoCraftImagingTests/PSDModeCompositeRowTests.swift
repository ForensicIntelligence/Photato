import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDModeCompositeRowTests: XCTestCase {
  func testBoundedRowsMatchWholeModeConversionAcrossPatchAndBandEdges() throws {
    for mode in [DocumentColorMode.grayscale,.cmyk,.lab] {for depth in mode.depths {
      for (width,height) in [(2051,3),(33,67)] {
        var native=try NativeModeRaster(width:width,height:height,mode:mode,depth:depth)
        // The numerical source is sparse; the rendered reference is independently
        // composed as one image using the retained pre-existing conversion path.
        for i in [0,width-1,width*(height-1)+width-1] {
          for c in 0..<mode.componentCount {try native.set(Float(c+1)/5,component:c,index:i)}
          try native.set(0.5,component:mode.componentCount,index:i)
        }
        if depth == .f32 {try native.set(2.5,component:0,index:width-1)}
        var d=try CraftDocument(width:width,height:height,depth:depth)
        d.modeDescriptor=try .init(mode:mode,depth:depth,profile:native.profile)
        var layer=Layer(name:"Numeric source",content:.raster(try native.surface()));layer.nativeMode=native
        layer.mask=try Surface(width:width,height:height,depth:depth,fill:Pixel(0.75,0.75,0.75))
        let group=Layer(name:"Owned group",content:.group(.init(passThrough:false)))
        layer.parentID=group.id;d.layers=[layer,group];d.activeLayerID=layer.id
        let reference=try NativeModeRaster.converting(Renderer.composite(d),to:mode,depth:depth,profile:native.profile)
        let rows=try PSDModeCompositeRows(d),bits=depth == .u8 ? 8:depth == .u16 ? 16:32
        for c in 0...mode.componentCount {for y in 0..<height {
          var expected:[UInt8]=[]
          for x in 0..<width {try PSDChannelCodec.append(PSDModeStorage.mergedSample(reference,component:c,index:y*width+x),depth:bits,to:&expected)}
          XCTAssertEqual(try rows.row(y,channel:c,depth:bits),expected,"\(mode)/\(bits) row\(y) component\(c)")
        }}
        XCTAssertThrowsError(try rows.row(height,channel:0,depth:bits))
        XCTAssertThrowsError(try rows.row(0,channel:mode.componentCount+1,depth:bits))
      }
    }}
  }
}
