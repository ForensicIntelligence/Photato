import Foundation
import XCTest
@testable import PhotoCraftCore

final class EraserModeTests:XCTestCase {
  func testOwnedPhotoshopBlockSingleClickRGBBytesAtEveryCapturedZoom()throws {
    let cases:[(String,Double,Int)]=[("100",1,256),("125",1.25,144),("200",2,64),("1600",16,1),("6400",64,0),("6400-center",64,0)]
    for (name,zoom,count) in cases {
      var surface=try Surface(width:96,height:72,fill:Pixel(128.0/255,128.0/255,128.0/255))
      var brush=Brush();brush.erase=true;brush.backgroundColor = .white;brush.size=30;brush.opacity=0.2
      if let effective=try EraserBrush.resolve(brush,mode:.block,zoom:zoom) {
        try Painter.stroke(surface:&surface,points:[.init(x:48,y:36)],brush:effective,selection:nil,selectionMask:nil,transform:.identity,grayscaleMask:false,preserveTransparency:true)
      }
      let rgba=try surface.rgbaData(depth:.u8,colorEncoding:.sRGB)
      var rgb=Data();for i in 0..<(96*72){rgb.append(contentsOf:rgba[(i*4)..<(i*4+3)])}
      let url=try XCTUnwrap(Bundle.module.url(forResource:"owned-block-"+name,withExtension:"rgb",subdirectory:"Fixtures/OwnedEraser455"))
      XCTAssertEqual(rgb,try Data(contentsOf:url),"IndependentPS singleclick reference \(name)")
      XCTAssertEqual((0..<(96*72)).filter{rgb[$0*3] != 128}.count,count)
      if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {try rgb.write(to:URL(fileURLWithPath:path).appendingPathComponent("eraser-block-"+name+".rgb"))}
    }
  }
  func testBrushIdentityPencilFlagsAndBlockIgnoresUnrelatedDynamicsWithoutMutatingSource()throws {
    var source=Brush();source.size=23;source.hardness=0.2;source.opacity=0.3;source.erase=true;source.settings = .init()
    source.settings!.flow=0.2;source.settings!.buildUp=true;source.settings!.shape.enabled=true;source.settings!.texture.enabled=true;source.settings!.symmetry.mode = .vertical;source.settings!.smoothing.amount=0.4
    let original=source
    XCTAssertEqual(try EraserBrush.resolve(source,mode:.brush,zoom:1),source)
    let pencil=try XCTUnwrap(EraserBrush.resolve(source,mode:.pencil,zoom:1))
    XCTAssertEqual(pencil.hardness,1);XCTAssertTrue(pencil.settings!.aliased);XCTAssertEqual(pencil.opacity,source.opacity);XCTAssertEqual(pencil.settings!.flow,1);XCTAssertFalse(pencil.settings!.buildUp)
    let block=try XCTUnwrap(EraserBrush.resolve(source,mode:.block,zoom:2))
    XCTAssertEqual(block.size,8);XCTAssertEqual(block.opacity,1);XCTAssertEqual(block.settings?.flow,1)
    XCTAssertFalse(block.settings!.shape.enabled);XCTAssertFalse(block.settings!.texture.enabled);XCTAssertEqual(block.settings!.symmetry.mode,.off)
    XCTAssertEqual(block.settings!.tip?.bytes,Data(repeating:255,count:256));XCTAssertEqual(block.settings!.smoothing,source.settings!.smoothing)
    XCTAssertEqual(source,original);XCTAssertNil(try EraserBrush.resolve(source,mode:.block,zoom:64))
    for zoom in [Double.nan,Double.infinity,0,-1,65] {XCTAssertThrowsError(try EraserBrush.resolve(source,mode:.block,zoom:zoom))}
  }
  func testAllDepthsOpacitySelectionsAndBackgroundVersusTransparencyUseExistingStroke()throws {
    for depth in PixelDepth.allCases {
      let original=try Surface(width:32,height:24,depth:depth,fill:Pixel(0.3,0.4,0.5))
      for mode in EraserMode.allCases {for preserve in [false,true] {
        var brush=Brush();brush.size=9;brush.erase=true;brush.opacity=0.25;brush.backgroundColor = .white
        let resolved=try XCTUnwrap(EraserBrush.resolve(brush,mode:mode,zoom:1))
        var result=original
        try Painter.stroke(surface:&result,points:[.init(x:15,y:12)],brush:resolved,selection:.init(x:12,y:9,width:6,height:6),selectionMask:nil,transform:.identity,grayscaleMask:false,preserveTransparency:preserve)
        XCTAssertNotEqual(result,original)
        for y in 0..<24 {for x in 0..<32 where x<12 || x>=18 || y<9 || y>=15 {XCTAssertEqual(result.pixel(x:x,y:y),original.pixel(x:x,y:y))}}
        if preserve {XCTAssertEqual(result.pixel(x:15,y:12).a,1)}else{XCTAssertLessThan(result.pixel(x:15,y:12).a,1)}
      }}
    }
  }
}
