import Foundation
import XCTest
@testable import PhotoCraftCore

final class LinkedPreviewGeometryTests:XCTestCase {
  func fixture(_ depth:PixelDepth)throws->CraftDocument {
    var d=try CraftDocument(width:12,height:12,depth:depth)
    d.layers[0].content = .raster(try Surface(width:4,height:3,depth:depth,fill:Pixel(1,0,0),colorEncoding:depth == .f32 ? .linearRGB:.sRGB))
    d.layers[0].x=3;d.layers[0].y=4;d.layers[0].affine = .scale(2,2);return d
  }
  func testExplicitTransparentRasterBoundaryDoesNotChangeDefaultGeometry()throws {
    for depth in PixelDepth.allCases {
      let d=try fixture(depth),layer=d.layers[0]
      let ordinary=try DocumentGeometry.transformLayer(layer,by:.identity,in:d,method:.bilinear)
      let preview=try DocumentGeometry.transformLayer(layer,by:.identity,in:d,method:.bilinear,clampRasterEdges:false)
      guard case .raster(let a)=ordinary.content,case .raster(let b)=preview.content else{return XCTFail("Raster")}
      XCTAssertEqual(a.pixel(x:0,y:0).a,1);XCTAssertEqual(b.pixel(x:0,y:0).a,depth.quantize(0.5625))
      XCTAssertEqual(b.pixel(x:1,y:0).a,depth.quantize(0.75));XCTAssertEqual(b.pixel(x:1,y:1).a,1)
      XCTAssertEqual(preview.x,3);XCTAssertEqual(preview.y,4);XCTAssertNil(preview.affine)
    }
  }
  func testExplicitUnlinkedMaskCoordinatesAndPixelsStayIndependentOfRasterPolicy()throws {
    var d=try fixture(.u8);let mask=try Surface(width:3,height:2,fill:.white)
    d.layers[0].mask=mask;var properties=MaskProperties();properties.linked=false;properties.transform = .translation(-0.5,0.25);d.layers[0].maskProperties=properties
    let source=d.layers[0],result=try DocumentGeometry.transformLayer(source,by:.translation(1,2),in:d,method:.bilinear,clampRasterEdges:false)
    XCTAssertEqual(result.mask,mask);XCTAssertEqual(result.maskCoordinateTransform,source.maskCoordinateTransform)
    XCTAssertEqual(result.maskProperties?.linked,false);XCTAssertEqual(d.layers[0],source)
  }
  func testCancelledPreviewGeometryCannotProduceOutput()async throws {
    let d=try fixture(.f32)
    let task=Task {withUnsafeCurrentTask{$0?.cancel()};return try DocumentGeometry.transformLayer(d.layers[0],by:.identity,in:d,method:.bilinear,clampRasterEdges:false)}
    do{_=try await task.value;XCTFail("Cancelled transform returned output")}catch is CancellationError{}
  }
}
