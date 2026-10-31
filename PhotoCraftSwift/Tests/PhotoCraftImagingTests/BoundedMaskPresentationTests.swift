import XCTest
import PhotoCraftCore
import PhotoCraftImaging

final class BoundedMaskPresentationTests: XCTestCase {
  func testNativePixelProjectionMatchesLegacyRawMaskAcrossGeometryAndProperties() throws {
    var mask = try Surface(width:5,height:4,depth:.f32,fill:Pixel(0.25,1,0,0))
    mask.setPixel(x:2,y:1,Pixel(0.75,0,1,0))
    var layer = Layer(name:"Mask",content:.raster(try Surface(width:12,height:10)))
    layer.mask=mask;layer.opacity=0
    for inverted in [false,true] { for transform in [Transform2D.translation(2,1), .translation(4,3) * .rotation(19)] {
      var properties=MaskProperties();properties.enabled=false;properties.density=0
      properties.feather=40;properties.outside=0.625;properties.inverted=inverted;properties.transform=transform
      layer.maskProperties=properties
      let before=layer,request=try RasterPreviewRequest(region:.init(x:1,y:2,width:8,height:6),width:8,height:6)
      for mode in [MaskViewMode.gray,.overlay] {
        let legacy=try Renderer.maskPresentation(layer,mode:mode,width:12,height:10).cropped(to:request.region)
        let bounded=try Renderer.maskPresentation(layer,mode:mode,request:request)
        XCTAssertEqual(try bounded.rgbaData(depth:.f32),try legacy.rgbaData(depth:.f32))
      }
      XCTAssertEqual(layer,before)
    } }
  }

  func testMaximumMaskAndSelectionOverlayUseBoundedDocumentCoordinates() throws {
    var layer=Layer(name:"Large",content:.raster(try Surface(width:300_000,height:300_000)))
    layer.mask=try Surface(width:300_000,height:300_000,depth:.f32,fill:Pixel(0.25,0,0,0))
    let request=try RasterPreviewRequest(region:.init(x:299_990,y:299_990,width:10,height:10),width:5,height:5)
    let gray=try Renderer.maskPresentation(layer,mode:.gray,request:request)
    XCTAssertEqual(gray.width,5);XCTAssertEqual(gray.pixel(x:4,y:4),Pixel(0.25,0.25,0.25))
    let selection=try SelectionMask.make(.rectangle(.init(x:299_990,y:299_990,width:4,height:10)),width:300_000,height:300_000)
    let overlay=try XCTUnwrap(SelectionToolPreparation.overlay(selection,color:Pixel(1,0,0,0.5),request:request))
    let pixels=try RasterIO.surface(overlay)
    XCTAssertEqual(pixels.width,5);XCTAssertEqual(pixels.pixel(x:0,y:0).a,128/255)
    XCTAssertEqual(pixels.pixel(x:4,y:4).a,0)
  }

  func testPreviewRequestValidationAndCancellation() async throws {
    for (region,w,h) in [(IntRect(x:-1,y:0,width:2,height:2),1,1),(.init(x:0,y:0,width:2,height:2),3,1),(.init(x:0,y:0,width:300_000,height:300_000),300_000,300_000),(.init(x:300_000,y:0,width:1,height:1),1,1)] {
      XCTAssertThrowsError(try RasterPreviewRequest(region:region,width:w,height:h))
    }
    let maximum=try RasterPreviewRequest.overview(width:300_000,height:300_000)
    XCTAssertEqual(maximum.width,2048);XCTAssertEqual(maximum.height,2048)
    var layer=Layer(name:"Cancel",content:.raster(try Surface(width:1,height:1)))
    layer.mask=try Surface(width:1,height:1,fill:.white)
    let frozen=layer
    let task=Task {
      while !Task.isCancelled {await Task.yield()}
      return try Renderer.maskPresentation(frozen,mode:.gray,request:maximum)
    }
    task.cancel()
    do {_ = try await task.value;XCTFail("Cancelled mask preview accepted")}catch is CancellationError {}
  }
}
