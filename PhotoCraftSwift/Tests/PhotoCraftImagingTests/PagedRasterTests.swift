import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PagedRasterTests:XCTestCase {
  func image(width:Int,height:Int)throws->CGImage {
    var data=Data(count:width*height*4)
    data.withUnsafeMutableBytes{(p:UnsafeMutableRawBufferPointer)in
      for y in 0..<height{for x in 0..<width{let at=(y*width+x)*4
        p[at]=UInt8((x*13+y*3)%256);p[at+1]=UInt8((x*7+y*11)%256);p[at+2]=UInt8((x*5+y*17)%256);p[at+3]=255
      }}
    }
    return try XCTUnwrap(CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:RasterIO.colorSpace(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:CGDataProvider(data:data as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
  }
  func png(_ image:CGImage)throws->Data {
    let bytes=NSMutableData();let out=try XCTUnwrap(CGImageDestinationCreateWithData(bytes,UTType.png.identifier as CFString,1,nil));CGImageDestinationAddImage(out,image,nil);XCTAssertTrue(CGImageDestinationFinalize(out));return bytes as Data
  }
  func testBandedConversionsEqualWholeImageAtEveryDepth()throws {
    let source=try image(width:133,height:71)
    for depth in PixelDepth.allCases {
      let space=depth == .f32 ? CGColorSpace(name:CGColorSpace.linearSRGB)!:try RasterIO.colorSpace()
      let encoding:SurfaceColorEncoding=depth == .f32 ? .linearRGB:.sRGB
      let whole=try RasterIO.surface(source,depth:depth,space:space,colorEncoding:encoding)
      let paged=try RasterIO.pagedSurface(source,depth:depth,space:space,colorEncoding:encoding)
      for y in 0..<71{for x in 0..<133 {
        let a=depth == .f32 ? whole.linearPixel(x:x,y:y):whole.pixel(x:x,y:y)
        let b=depth == .f32 ? paged.linearPixel(x:x,y:y):paged.pixel(x:x,y:y)
        XCTAssertTrue(a.hasSameBits(as:b),"\(depth),\(x),\(y)")
      }}
      XCTAssertEqual(paged.mappedTileCount,paged.tileCount)
    }
  }
  func testFloatReaderReusesProviderAndRetainsHDRRegionBits()throws {
    let width=131,height=67
    var data=Data(count:width*height*16)
    data.withUnsafeMutableBytes{p in for y in 0..<height{for x in 0..<width {
      let v:[Float]=[x == 0 ? -0.0:Float(x)/3,Float(y)/5,-0.3,Float((x+y)%3)/2]
      for i in 0..<4{p.storeBytes(of:v[i].bitPattern.littleEndian,toByteOffset:(y*width+x)*16+i*4,as:UInt32.self)}
    }}}
    let space=CGColorSpace(name:CGColorSpace.linearSRGB)!
    let image=try XCTUnwrap(CGImage(width:width,height:height,bitsPerComponent:32,bitsPerPixel:128,bytesPerRow:width*16,space:space,bitmapInfo:[.floatComponents,.byteOrder32Little,CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue)],provider:CGDataProvider(data:data as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
    let whole=try RasterIO.surface(image,depth:.f32,space:space,colorEncoding:.linearRGB)
    let paged=try RasterIO.pagedSurface(image,depth:.f32,space:space,colorEncoding:.linearRGB)
    for y in 0..<height{for x in 0..<width{XCTAssertTrue(whole.linearPixel(x:x,y:y).hasSameBits(as:paged.linearPixel(x:x,y:y)))}}
    for orientation in 2...8 {
      let actual=try RasterIO.pagedOrientation(paged,orientation:orientation),expected=try RasterIO.oriented(whole,orientation:orientation)
      for y in 0..<actual.height{for x in 0..<actual.width{XCTAssertTrue(actual.linearPixel(x:x,y:y).hasSameBits(as:expected.linearPixel(x:x,y:y)))}}
    }
  }
  func testDenseFortyMegapixelPNGUsesScratchAndSupportsHistoryAndNativeSave()throws {
    let bytes=try png(image(width:8000,height:5000)),started=Date()
    let document=try RasterIO.read(bytes,name:"Owned dense40MP")
    XCTAssertEqual(document.width*document.height,40_000_000)
    guard case .raster(let pixels)=document.layers[0].content else{return XCTFail("Missing raster")}
    XCTAssertGreaterThanOrEqual(pixels.mappedBytes,640_000_000)
    XCTAssertGreaterThan(pixels.mappedTileIndexBytes,0)
    XCTAssertLessThan(document.estimatedBytes,16*1024*1024)
    for (x,y) in [(0,0),(63,63),(2048,64),(7999,4999),(4000,2500)]{
      let p=pixels.pixel(x:x,y:y)
      XCTAssertEqual(p,Pixel(Float((x*13+y*3)%256)/255,Float((x*7+y*11)%256)/255,Float((x*5+y*17)%256)/255))
    }
    let snapshot=try Renderer.render(document)
    XCTAssertEqual(snapshot.surface.mappedBytes,pixels.mappedBytes)
    var session=EditorSession(document:document);var brush=Brush();brush.size=8;brush.settings = .init()
    try session.execute(.stroke(document.layers[0].id,[.init(x:4000,y:2500),.init(x:4010,y:2500)],brush))
    XCTAssertNotEqual(session.document,document);try session.undo();XCTAssertEqual(session.document,document);try session.redo()
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
    let file=folder.appendingPathComponent("dense.photato");try NativeArchive.write(session.document,to:file)
    XCTAssertEqual(try NativeArchive.read(file),session.document)
    let paged = try NativeArchive.readPaged(file)
    XCTAssertEqual(paged,session.document)
    XCTAssertGreaterThanOrEqual(paged.mappedRasterBytes,640_000_000)
    XCTAssertGreaterThan(paged.mappedRasterIndexBytes,0)
    XCTAssertLessThan(paged.estimatedBytes,16*1024*1024)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let out=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
      try bytes.write(to:out.appendingPathComponent("owned-dense40mp.png"))
      let record:[String:Any]=["pixels":40_000_000,"inputBytes":bytes.count,"mappedSampleBytes":pixels.mappedBytes,"heapEstimateBytes":document.estimatedBytes,"seconds":Date().timeIntervalSince(started),"scope":"Owned analytic PNG/native pixels and history; not Photoshop byte or physical60fps qualification"]
      try JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("dense40mp.json"))
    }
  }
}


extension PagedRasterTests {
  func testPagedProfileConversionMatchesWholeConversion() throws {
    let sourceImage=try image(width:133,height:71)
    let pixels=try RasterIO.surface(sourceImage)
    var source=try CraftDocument(width:133,height:71)
    source.workingICC=CGColorSpace(name:CGColorSpace.sRGB)!.copyICCData() as Data?
    for depth in PixelDepth.allCases {
      var target=try CraftDocument(width:1,height:1,depth:depth)
      target.workingICC=CGColorSpace(name:depth == .f32 ? CGColorSpace.linearDisplayP3:CGColorSpace.displayP3)!.copyICCData() as Data?
      let whole=try ColorManagement.converted(pixels,from:source,to:target)
      let paged=try ColorManagement.convertedPaged(pixels,from:source,to:target)
      for y in 0..<71 {for x in 0..<133 {
        let a=depth == .f32 ? whole.linearPixel(x:x,y:y):whole.pixel(x:x,y:y)
        let b=depth == .f32 ? paged.linearPixel(x:x,y:y):paged.pixel(x:x,y:y)
        XCTAssertTrue(a.hasSameBits(as:b))
      }}
    }
  }
  func testPagedAssociatedTIFFUsesSameUnpremultiplyAndProfilePath()throws {
    for depth in PixelDepth.allCases {
      let encoding:SurfaceColorEncoding=depth == .f32 ? .linearRGB:.sRGB
      var pixels=try Surface(width:133,height:71,depth:depth,colorEncoding:encoding)
      for y in 0..<71 {for x in 0..<133 {
        let alpha=Float((x+y)%5)/4,p=Pixel(alpha*0.25,alpha*0.5,alpha*0.75,alpha)
        if depth == .f32 {pixels.setLinearPixel(x:x,y:y,p)}else{pixels.setPixel(x:x,y:y,p)}
      }}
      let bits=depth == .u8 ? 8:depth == .u16 ? 16:32
      let space=CGColorSpace(name:depth == .f32 ? CGColorSpace.linearSRGB:CGColorSpace.sRGB)!
      let data=try pixels.rgbaData(depth:depth,colorEncoding:encoding)
      var info=CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue)
      if depth == .u16 {info.insert(.byteOrder16Little)}
      if depth == .f32 {info.formUnion([.floatComponents,.byteOrder32Little])}
      let image=try XCTUnwrap(CGImage(width:133,height:71,bitsPerComponent:bits,bitsPerPixel:bits*4,bytesPerRow:133*(bits/8)*4,space:space,bitmapInfo:info,provider:CGDataProvider(data:data as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
      let expected=try RasterIO.surface(image,depth:depth,space:space,colorEncoding:encoding)
      let actual=try TIFFStorage.associatedPaged(pixels,bits:bits,depth:depth,encoding:encoding,space:space)
      for y in 0..<71 {for x in 0..<133 {
        let a=depth == .f32 ? actual.linearPixel(x:x,y:y):actual.pixel(x:x,y:y)
        let b=depth == .f32 ? expected.linearPixel(x:x,y:y):expected.pixel(x:x,y:y)
        XCTAssertTrue(a.hasSameBits(as:b))
      }}
    }
  }
}


extension PagedRasterTests {
  func testDenseFortyMegapixelLayerThumbnailRemainsOpaque() throws {
    let pixels = try RasterIO.pagedSurface(image(width:8000,height:5000))
    var document = try CraftDocument(width:8000,height:5000)
    document.layers[0].content = .raster(pixels)
    document.workingICC = CGColorSpace(name:CGColorSpace.sRGB)!.copyICCData() as Data?
    let start = Date()
    let thumb = try XCTUnwrap(Renderer.layerThumbnail(document.layers[0],in:document,framing:.entireDocument,maximumSize:74))
    let display = try ColorManagement.displayImage(thumb,in:document)
    for y in 0..<thumb.height { for x in 0..<thumb.width { XCTAssertGreaterThan(thumb.pixel(x:x,y:y).a,0.999) } }
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let out=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
      try png(display).write(to:out.appendingPathComponent("dense-layer-thumbnail.png"))
      try JSONSerialization.data(withJSONObject:["pixels":40_000_000,"width":thumb.width,"height":thumb.height,"seconds":Date().timeIntervalSince(start),"all_opaque":true],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("dense-layer-thumbnail.json"))
    }
  }
}
