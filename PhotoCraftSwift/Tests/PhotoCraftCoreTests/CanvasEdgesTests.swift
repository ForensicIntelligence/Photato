import Foundation
import XCTest
@testable import PhotoCraftCore

final class CanvasEdgesTests:XCTestCase {
  func testTrimBasesAndAllSixteenEdgeCombinations()throws {
    for depth in PixelDepth.allCases {
      for basis in TrimOptions.Basis.allCases {
        var pixels=try Surface(width:8,height:6,depth:depth,fill:basis == .transparent ? .clear:Pixel(0.5,0.5,0.5))
        for y in 2..<4{for x in 3..<5{pixels.setPixel(x:x,y:y,Pixel(1,0,0))}}
        for bits in 0..<16 {
          var options=TrimOptions(basis:basis);options.top=bits&1 != 0;options.left=bits&2 != 0;options.bottom=bits&4 != 0;options.right=bits&8 != 0
          let x=options.left ? 3:0,y=options.top ? 2:0,x1=options.right ? 5:8,y1=options.bottom ? 4:6
          XCTAssertEqual(try options.bounds(in:pixels),IntRect(x:x,y:y,width:x1-x,height:y1-y))
        }
      }
    }
  }
  func testUniformEmptyAndNoEdgesHaveExplicitAtomicBehavior()throws {
    let blank=try Surface(width:3,height:2)
    XCTAssertThrowsError(try TrimOptions(basis:.transparent).bounds(in:blank))
    XCTAssertThrowsError(try TrimOptions(basis:.topLeft).bounds(in:blank))
    var options=TrimOptions();options.top=false;options.left=false;options.bottom=false;options.right=false
    XCTAssertEqual(try options.bounds(in:blank),IntRect(x:0,y:0,width:3,height:2))
    XCTAssertEqual(TrimOptions().basis,.topLeft)
  }
  func testMatchingBoundsUsesSparseDefaultsAndPagedSamplesAtMaximumExtent()throws {
    var pixels=try Surface(width:300000,height:300000,depth:.f32,fill:.white)
    pixels.setPixel(x:150000,y:170000,Pixel(1,0,0))
    XCTAssertEqual(try pixels.matchingBounds{$0.g==0},IntRect(x:150000,y:170000,width:1,height:1))
    XCTAssertEqual(try pixels.contentBounds(),IntRect(x:0,y:0,width:300000,height:300000))
    let builder=try Surface.PagedBuilder(template:try Surface(width:300000,height:300000,depth:.f32))
    var patch=try Surface(width:32,height:32,depth:.f32);patch.setPixel(x:31,y:31,Pixel(0,1,0))
    try builder.append(patch,atX:299968,atY:299968)
    XCTAssertEqual(try builder.finish().contentBounds(),IntRect(x:299999,y:299999,width:1,height:1))
  }
  func testExactCanvasFramingRetainsRawWordsAndEncoding()throws {
    for encoding in [SurfaceColorEncoding.sRGB,.linearRGB] {
      var source=try Surface(width:3,height:2,depth:.f32,fill:Pixel(4,-0.25,0.5,1)).interpretingSamples(as:encoding)
      if encoding == .linearRGB {source.setLinearPixel(x:1,y:1,Pixel(-0.0,8,2,1))}else{source.setPixel(x:1,y:1,Pixel(-0.0,8,2,1))}
      for box in [IntRect(x:-1,y:-2,width:6,height:6),IntRect(x:1,y:0,width:2,height:2)] {
        let result=try source.reframedExactly(bounds:box,fill:.white)
        let raw=try result.interpretingSamples(as:.sRGB),old=try source.interpretingSamples(as:.sRGB)
        XCTAssertEqual(result.colorEncoding,encoding)
        for y in 0..<box.height{for x in 0..<box.width{
          let sx=x+box.x,sy=y+box.y,expected=sx>=0 && sy>=0 && sx<3 && sy<2 ? old.pixel(x:sx,y:sy):Pixel.white
          XCTAssertTrue(raw.pixel(x:x,y:y).hasSameBits(as:expected))
        }}
      }
    }
  }
  func testUnquantizedImplicitDefaultsRetainTheirBits()throws {
    for depth in [PixelDepth.u8,.u16] {
      let source=try Surface(width:1,height:1,depth:depth,fill:.white).expanded(to:.init(x:-1,y:-1,width:3,height:3),fill:Pixel(0.5,0.5,0.5),preservingFillBits:true)
      XCTAssertTrue(source.defaultPixel.hasSameBits(as:Pixel(0.5,0.5,0.5)))
      let result=try source.reframedExactly(bounds:.init(x:-1,y:0,width:4,height:3),fill:.white)
      XCTAssertTrue(result.defaultPixel.hasSameBits(as:source.defaultPixel))
      for y in 0..<3{for x in 0..<3{XCTAssertTrue(result.pixel(x:x+1,y:y).hasSameBits(as:source.pixel(x:x,y:y)))}}
    }
  }
  func testTinySourceInMaximumCanvasAndLargeInteriorWithBorderStayPaged()throws {
    let tiny=try Surface(width:1,height:1,depth:.f32,fill:Pixel(1,0,0))
    let large=try tiny.reframedExactly(bounds:.init(x:-100,y:-100,width:300000,height:300000),fill:.white)
    XCTAssertEqual(large.defaultPixel,.white);XCTAssertEqual(large.pixel(x:100,y:100),Pixel(1,0,0));XCTAssertLessThan(large.allocatedBytes,2*1024*1024)
    let interior=try Surface(width:40000,height:1000,depth:.f32,fill:.white)
    let border=try interior.reframedExactly(bounds:.init(x:-1,y:-1,width:40002,height:1002),fill:.black)
    XCTAssertEqual(border.defaultPixel,.white);XCTAssertEqual(border.pixel(x:0,y:0),.black);XCTAssertEqual(border.pixel(x:40001,y:1001),.black);XCTAssertEqual(border.pixel(x:1,y:1),.white)
    XCTAssertGreaterThan(border.mappedBytes,0);XCTAssertLessThan(border.allocatedBytes,2*1024*1024)
  }
  func testNativePlaneFramingCopiesBytesAndKeepsSignedZero()throws {
    var source=try NativeModeRaster(width:3,height:2,mode:.grayscale,depth:.f32)
    for i in 0..<6 {try source.set(Float(i)+0.25,component:0,index:i);try source.set(1,component:1,index:i)}
    try source.set(-0.0,component:0,index:4)
    let result=try source.reframedExactly(bounds:.init(x:1,y:0,width:2,height:2))
    for c in try source.planes.indices {
      let expected=Data(try source.planes[c][4..<12])+Data(try source.planes[c][16..<24])
      XCTAssertEqual(try result.planes[c],expected)
    }
    XCTAssertEqual(result.value(component:0,index:2).bitPattern,Float(-0.0).bitPattern)
  }
  func testDocumentFrameRebasesChannelsGuidesSelectionAndCompPositions()throws {
    var source=try CraftDocument(width:8,height:6)
    source.layers[0].x=3;source.layers[0].content = .raster(try Surface(width:2,height:2,fill:Pixel(1,0,0)))
    source.guides=[DocumentGuide(axis:.vertical,position:1.5)];source.selection=IntRect(x:1,y:1,width:2,height:2)
    var channel=try Surface(width:8,height:6,fill:.black);channel.setPixel(x:1,y:1,.white)
    source.alphaChannels=[AlphaChannel(name:"Saved",pixels:channel)];source.resolution=300;source.sourceMetadata=["owned":Data([1,2,3])]
    try Command.layerComp(.capture(id:UUID(),name:"Before",comment:"Owned",options:LayerCompOptions())).apply(to:&source)
    let result=try CanvasFrameGeometry.reframed(source,bounds:.init(x:-2,y:-1,width:12,height:9))
    XCTAssertEqual(result.layers[0].x,5);XCTAssertEqual(result.layers[0].y,1)
    XCTAssertEqual(result.selection,IntRect(x:3,y:2,width:2,height:2));XCTAssertEqual(result.guides?.first?.position,3.5)
    XCTAssertEqual(result.alphaChannels?.first?.pixels.pixel(x:3,y:2),.white)
    XCTAssertEqual(result.layerComps?.comps.first?.layers.first?.x,5);XCTAssertEqual(result.layerComps?.comps.first?.layers.first?.y,1)
    XCTAssertEqual(result.sourceMetadata,source.sourceMetadata);XCTAssertEqual(result.pixelsPerInch,300)
  }
  func testPreparedCanvasEditIsSourceBoundAndUndoable()throws {
    let source=try CraftDocument(width:2,height:1);var result=source;result.width=3
    let operation=CanvasEdgeOperation.revealAll,command=Command.canvasEdges(.init(source:source,result:result,operation:operation))
    var session=EditorSession(document:source);try session.execute(command);XCTAssertEqual(session.document,result);try session.undo();XCTAssertEqual(session.document,source);try session.redo();XCTAssertEqual(session.document,result)
    var stale=source;stale.name="Changed";let before=stale;XCTAssertThrowsError(try command.apply(to:&stale));XCTAssertEqual(stale,before)
  }
}
