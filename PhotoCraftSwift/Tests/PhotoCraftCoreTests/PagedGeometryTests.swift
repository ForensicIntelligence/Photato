import Foundation
import XCTest
@testable import PhotoCraftCore

final class PagedGeometryTests:XCTestCase {
  private var fixtures:URL {get throws {try XCTUnwrap(Bundle.module.url(forResource:"Fixtures",withExtension:nil)).appendingPathComponent("paged-geometry")}}
  func testExistingSRGBKernelsRetainPrior286BytesAcrossDepthsAndTransforms() throws {
    let path=try fixtures
    let manifest=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:path.appendingPathComponent("prior286.json")))as?[String:Any])
    let cases=try XCTUnwrap(manifest["cases"]as?[[String:Any]]);XCTAssertEqual(cases.count,36)
    for depth in PixelDepth.allCases {
      var source=try Surface(width:67,height:65,depth:depth)
      for y in 0..<65 {for x in 0..<67 {source.setPixel(x:x,y:y,Pixel(Float((x*13+y)%251)/250,Float((x+y*11)%251)/250,Float((x*3+y*7)%251)/250,Float((x+y)%5)/4))}}
      let transforms:[(String,Transform2D)]=[("identity",.identity),("scale",.scale(1.3,0.7)),("rotate",.rotation(21)),("flip",.init(a:-1,tx:67))]
      for (name,t) in transforms {for method in Resampling.allCases {
        let prefix="\(depth.rawValue)-\(name)-\(method.rawValue.replacingOccurrences(of:" ",with:"-"))"
        let expected=try Data(contentsOf:path.appendingPathComponent(prefix+".rgba"))
        let result=try RasterGeometry.render(source,transform:t,bounds:t.bounds(width:67,height:65),method:method,clampEdges:true)
        XCTAssertEqual(try result.rgbaData(depth:.f32),expected,prefix)
        XCTAssertTrue(cases.contains{$0["prefix"]as?String == prefix})
      }}
    }
  }
  func testAllFiveGridTurnsMatchIndependentRaw32BitMapsAndRetainEncoding() throws {
    let path=try fixtures,bytes=try Data(contentsOf:path.appendingPathComponent("linear-input.rgba"))
    var source=try Surface(width:129,height:65,depth:.f32,colorEncoding:.linearRGB)
    bytes.withUnsafeBytes { raw in
      for y in 0..<65 {for x in 0..<129 {
        let at=(y*129+x)*16
        func v(_ c:Int)->Float {Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:at+c*4,as:UInt32.self)))}
        source.setLinearPixel(x:x,y:y,Pixel(v(0),v(1),v(2),v(3)))
      }}
    }
    for (name,turn) in [("clockwise",CanvasTurn.clockwise),("counterclockwise",.counterclockwise),("half",.half),("horizontal",.horizontal),("vertical",.vertical)] {
      let t=turn.transform(width:129,height:65)
      let result=try RasterGeometry.render(source,transform:t,bounds:t.bounds(width:129,height:65),method:.nearest,clampEdges:true)
      XCTAssertEqual(result.colorEncoding,.linearRGB)
      XCTAssertEqual(try result.rgbaData(depth:.f32,colorEncoding:.linearRGB),try Data(contentsOf:path.appendingPathComponent("linear-"+name+".rgba")))
    }
    let identity=try RasterGeometry.render(source,transform:.identity,bounds:.init(x:0,y:0,width:129,height:65),method:.nearest)
    XCTAssertEqual(try identity.rgbaData(depth:.f32,colorEncoding:.linearRGB),bytes)
  }
  func testLinearInterpolationOperatesInStoredWorkingSpaceWithoutEncodedRoundTrip() throws {
    var source=try Surface(width:2,height:1,depth:.f32,colorEncoding:.linearRGB)
    source.setLinearPixel(x:0,y:0,Pixel(4,-0.25,0,1));source.setLinearPixel(x:1,y:0,Pixel(0,0.75,0,1))
    let result=try RasterGeometry.render(source,transform:.scale(2,1),bounds:.init(x:0,y:0,width:4,height:1),method:.bilinear,clampEdges:true)
    XCTAssertEqual(result.colorEncoding,.linearRGB)
    XCTAssertTrue(result.linearPixel(x:1,y:0).hasSameBits(as:Pixel(3,0,0,1)))
    XCTAssertTrue(result.linearPixel(x:2,y:0).hasSameBits(as:Pixel(1,0.5,0,1)))
  }
  func testSparseMaximumCanvasTurnsAndConstantNearestResizeStayBoundedAndBitExact() throws {
    let fill=Pixel(-0.0,4,-0.25,0.5)
    var source=try Surface(width:300000,height:300000,depth:.f32,fill:fill).interpretingSamples(as:.linearRGB)
    let changed=Pixel(2,-0.0,0.25,0)
    source.setLinearPixel(x:299999,y:0,changed);source.setLinearPixel(x:64,y:299999,changed)
    for turn in CanvasTurn.allCases {
      let transform=turn.transform(width:300000,height:300000)
      let result=try RasterGeometry.render(source,transform:transform,bounds:transform.bounds(width:300000,height:300000),method:.nearest)
      XCTAssertEqual(result.colorEncoding,.linearRGB);XCTAssertLessThan(result.allocatedBytes,1024*1024)
      for (x,y) in [(299999,0),(64,299999),(150000,150000)] {
        let p=transform.point(Double(x)+0.5,Double(y)+0.5)
        XCTAssertTrue(result.linearPixel(x:Int(floor(p.x)),y:Int(floor(p.y))).hasSameBits(as:source.linearPixel(x:x,y:y)))
      }
    }
    let constant=try Surface(width:1,height:1,depth:.f32,fill:fill).interpretingSamples(as:.linearRGB)
    let enlarged=try RasterGeometry.render(constant,transform:.scale(300000,300000),bounds:.init(x:0,y:0,width:300000,height:300000),method:.nearest)
    XCTAssertEqual(enlarged.tileCount,0);XCTAssertTrue(enlarged.linearPixel(x:299999,y:299999).hasSameBits(as:fill))
  }
  func testCanvasExtensionRectanglesMatchIndependentPixelsIncludingPartialTiles() throws {
    for depth in PixelDepth.allCases {
      let color=Pixel(0.25,0.5,0.75,0.5),value=color.quantized(depth)
      for original in [IntRect(x:10,y:9,width:67,height:64),.init(x:-9,y:-10,width:63,height:200),.init(x:500,y:500,width:1,height:1)] {
        let result=try Surface.canvasExtension(width:129,height:131,depth:depth,color:color,original:original)
        for y in 0..<131 {for x in 0..<129 {
          let inside=x>=original.x && y>=original.y && x<original.x+original.width && y<original.y+original.height
          XCTAssertTrue(result.pixel(x:x,y:y).hasSameBits(as:inside ? .clear:value))
        }}
      }
    }
    let large=try Surface.canvasExtension(width:300000,height:300000,depth:.u16,color:.white,original:.init(x:149999,y:149999,width:2,height:2))
    XCTAssertEqual(large.pixel(x:0,y:0),.white);XCTAssertEqual(large.pixel(x:149999,y:149999),.clear)
    XCTAssertEqual(large.pixel(x:150001,y:150001),.white);XCTAssertLessThan(large.allocatedBytes,1024*1024)
  }
  func testActualDense40MPResizeRotateHistoryAndNativeRoundTrip() throws {
    let width=8000,height=5000,builder=try Surface.PagedBuilder(width:width,height:height,depth:.u8)
    func color(_ x:Int,_ y:Int)->Pixel {Pixel(Float((x/2048+y/64)%7)/6,0.5,0.25,1).quantized(.u8)}
    for y in stride(from:0,to:height,by:64) {for x in stride(from:0,to:width,by:2048) {
      try builder.append(Surface(width:min(2048,width-x),height:min(64,height-y),depth:.u8,fill:color(x,y)),atX:x,atY:y)
    }}
    let pixels=try builder.finish();XCTAssertGreaterThanOrEqual(pixels.mappedBytes,640_000_000)
    var original=try CraftDocument(width:width,height:height);original.layers[0].content = .raster(pixels)
    var session=EditorSession(document:original)
    try session.execute(.imageSize(8001,5003,144,.nearest))
    guard case .raster(let resized)=session.document.layers[0].content else {return XCTFail("Raster")}
    XCTAssertGreaterThan(resized.mappedBytes,640_000_000);XCTAssertLessThan(session.document.estimatedBytes,16*1024*1024)
    for (x,y) in [(0,0),(2048,64),(7999,5001)] {
      let sx=Int(floor((Double(x)+0.5)*8000/8001)),sy=Int(floor((Double(y)+0.5)*5000/5003))
      XCTAssertEqual(resized.pixel(x:x,y:y),color(sx,sy))
    }
    try session.undo();XCTAssertEqual(session.document,original)
    try session.execute(.rotateCanvas(.clockwise))
    guard case .raster(let rotated)=session.document.layers[0].content else {return XCTFail("Raster")}
    XCTAssertEqual(rotated.width,height);XCTAssertEqual(rotated.height,width)
    for (x,y) in [(0,0),(2048,64),(7999,4999)] {XCTAssertEqual(rotated.pixel(x:height-1-y,y:x),color(x,y))}
    let data=try NativeArchive.encodeChunked(session.document,minimumVersion:63)
    XCTAssertEqual(try NativeArchive.decodePaged(data),session.document)
    try session.undo();XCTAssertEqual(session.document,original);try session.redo();XCTAssertEqual(session.document.width,height)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
      try JSONSerialization.data(withJSONObject:["inputPixels":width*height,"resizedMappedBytes":resized.mappedBytes,"rotatedMappedBytes":rotated.mappedBytes,"heapEstimate":session.document.estimatedBytes,"nativeBytes":data.count],options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("geometry-40mp.json"))
    }
  }
  func testCancelledGeometryAndLargeSelectionHistoryAreAtomic() async throws {
    let result=try await Task.detached { () throws -> Bool in
      let source=try Surface(width:8000,height:5000,fill:.white)
      withUnsafeCurrentTask {$0?.cancel()}
      do {_ = try RasterGeometry.render(source,transform:.scale(1.01,1.01),bounds:.init(x:0,y:0,width:8080,height:5050),method:.bilinear);return false}
      catch is CancellationError {return true}
    }.value
    XCTAssertTrue(result)
    let constant=try await Task.detached { () throws -> Bool in
      let source=try Surface(width:1,height:1,fill:.white)
      withUnsafeCurrentTask {$0?.cancel()}
      do {_ = try RasterGeometry.render(source,transform:.scale(300000,300000),bounds:.init(x:0,y:0,width:300000,height:300000),method:.nearest);return false}
      catch is CancellationError {return true}
    }.value
    XCTAssertTrue(constant)
    var d=try CraftDocument(width:2,height:2)
    d.selectionMask=try SelectionMask(width:2,height:2,bytes:[255,128,0,255]);d.selection=d.selectionMask?.bounds
    var session=EditorSession(document:d)
    try session.execute(.imageSize(8000,5000,72,.nearest))
    XCTAssertEqual(session.document.width,8000);XCTAssertTrue(session.document.selectionMask?.isPaged == true)
    XCTAssertEqual(session.undoStack.count,1);try session.undo();XCTAssertEqual(session.document,d)
  }
}
