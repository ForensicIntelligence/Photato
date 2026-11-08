import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class ClipboardPlaneImagingTests:XCTestCase {
  func testNumericGrayBypassesProfilesAndPreservesEveryDepthAndAlpha()throws {
    for depth in PixelDepth.allCases {
      var d=try CraftDocument(width:4,height:3,depth:depth);let p=try Surface(width:4,height:3,depth:depth,fill:Pixel(0.37,0.37,0.37)),channel=AlphaChannel(name:"Data",pixels:p)
      d.alphaChannels=[channel];let content=try ClipboardPlane.copy(d,target:.alpha(channel.id)),image=try ClipboardPlaneIO.image(content,depth:depth,settings:.init())
      XCTAssertEqual(image.values.pixel(x:1,y:1).r.bitPattern,p.pixel(x:1,y:1).r.bitPattern);XCTAssertEqual(image.coverage.pixel(x:1,y:1).r,1)
      let restored=try ClipboardContent.decode(content.encoded()).newDocument(name:"Copied channel")
      XCTAssertEqual(restored.colorMode,.grayscale);XCTAssertEqual(restored.layers[0].nativeMode?.value(component:0,index:5).bitPattern,p.pixel(x:1,y:1).r.bitPattern)
    }
  }
  func testRGBBlackWhiteAndOpacityUseNativeGrayConversion()throws {
    for depth in PixelDepth.allCases {
      var s=try Surface(width:2,height:1,depth:depth,fill:Pixel(0,0,0,0.5));s.setPixel(x:1,y:0,Pixel(1,1,1,0.75))
      let content=try ClipboardContent.pixels(s),image=try ClipboardPlaneIO.image(content,depth:depth,settings:.init())
      XCTAssertEqual(image.values.pixel(x:0,y:0).r,0);XCTAssertEqual(image.values.pixel(x:1,y:0).r,1)
      XCTAssertEqual(image.coverage.pixel(x:0,y:0).r,s.pixel(x:0,y:0).a);XCTAssertEqual(image.coverage.pixel(x:1,y:0).r,s.pixel(x:1,y:0).a)
    }
  }
  func testEncodedFloat32ColorInputIsConvertedFromLinearRGBOnce()throws {
    let source=try ClipboardContent.pixels(Surface(width:1,height:1,depth:.f32,fill:Pixel(0.5,0.5,0.5)))
    let image=try ClipboardPlaneIO.image(source,depth:.f32,settings:.init())
    XCTAssertEqual(image.values.pixel(x:0,y:0).r,0.21404114,accuracy:0.000001)
  }
  func testLayerClipboardFlatteningThenTargetedPastePreservesDestinationImage()throws {
    var source=try CraftDocument(width:3,height:2);source.layers[0].content = .fill(.white)
    let content=try ClipboardRenderer.copy(source,layerIDs:[source.layers[0].id]),image=try ClipboardPlaneIO.image(content,depth:.u16,settings:.init())
    var d=try CraftDocument(width:8,height:6,depth:.u16);d.layers[0].mask=try Surface(width:8,height:6,depth:.u16,fill:.black)
    let result=try ClipboardPlane.paste(image,into:d,target:.layerMask(d.layers[0].id),center:.init(2.5,2)).result
    XCTAssertEqual(result.layers[0].content,d.layers[0].content);XCTAssertEqual(result.layers[0].mask?.pixel(x:1,y:1).r,1);XCTAssertEqual(result.layers[0].mask?.pixel(x:0,y:0).r,0)
  }
  func testStrictClipboardPlaneRawCaptures()throws {
    guard let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]else{return}
    var bytes=Data()
    for depth in PixelDepth.allCases {
      var d=try CraftDocument(width:7,height:5,depth:depth),s=try Surface(width:7,height:5,depth:depth)
      for y in 0..<5{for x in 0..<7{let v=Float((x*37+y*19)%256)/255;s.setPixel(x:x,y:y,Pixel(v,v,v))}}
      let channel=AlphaChannel(name:"Owned",pixels:s);d.alphaChannels=[channel];d.selection = .init(x:1,y:1,width:4,height:3)
      let target=ClipboardPlaneTarget.alpha(channel.id),copy=try ClipboardPlane.copy(d,target:target),image=try XCTUnwrap(ClipboardPlane.numericImage(copy))
      let cut=try ClipboardPlane.cut(d,target:target,background:0.3),paste=try ClipboardPlane.paste(image,into:cut.result,target:target,placement:.inPlace)
      for plane in [image.values,cut.result.alphaChannels![0].pixels,paste.result.alphaChannels![0].pixels]{for y in 0..<plane.height{for x in 0..<plane.width{var word=plane.pixel(x:x,y:y).r.bitPattern.littleEndian;withUnsafeBytes(of:&word){bytes.append(contentsOf:$0)}}}}
    }
    try bytes.write(to:URL(fileURLWithPath:path).appendingPathComponent("clipboard-plane-numerics.f32"))
  }
}
