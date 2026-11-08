import Foundation
import CoreGraphics
import ImageIO
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class OpenEXRTests:XCTestCase {
  struct Fixture:Decodable {let file:String,width:Int,height:Int,rgba:[Float]}
  func fixtures()throws->(URL,[Fixture]) {
    let url=try XCTUnwrap(Bundle.module.url(forResource:"Fixtures",withExtension:nil)).appendingPathComponent("OpenEXR")
    return (url,try JSONDecoder().decode([Fixture].self,from:Data(contentsOf:url.appendingPathComponent("reference.json"))))
  }
  func model()throws->CraftDocument {
    var d=try CraftDocument(width:5,height:17,depth:.f32,name:"HDR")
    var s=try Surface(width:5,height:17,depth:.f32,colorEncoding:.linearRGB)
    for y in 0..<17 {for x in 0..<5 {let a:Float=[1,0.5,0,1,0.25][x];s.setLinearPixel(x:x,y:y,Pixel(Float(x-2)*0.5+Float(y)*0.125,2+Float(x)*0.25,-0.5+Float(y)*0.25,a))}}
    let layer=Layer(name:"HDR",content:.raster(s));d.layers=[layer];d.activeLayerID=layer.id;d.resolution=144;return d
  }
  func assertWords(_ doc:CraftDocument,_ expected:[Float],file:StaticString=#filePath,line:UInt=#line)throws {
    guard case .raster(let s)=doc.layers[0].content else{return XCTFail("Not raster",file:file,line:line)}
    var actual=[UInt32]();for y in 0..<s.height {for x in 0..<s.width {let p=s.linearPixel(x:x,y:y);actual += [p.r,p.g,p.b,p.a].map(\.bitPattern)}}
    XCTAssertEqual(actual,expected.map(\.bitPattern),file:file,line:line)
  }
  func testIndependentHalfAndFloatAllThreeCompressions()throws {
    let (url,fixtures)=try fixtures()
    for f in fixtures {let data=try Data(contentsOf:url.appendingPathComponent(f.file));let doc=try OpenEXR.read(data,name:f.file)
      XCTAssertEqual(doc.width,f.width);XCTAssertEqual(doc.height,f.height);XCTAssertEqual(doc.depth,.f32);XCTAssertEqual(doc.pixelsPerInch,144)
      try assertWords(doc,f.rgba)
      var sliced=Data([5]);sliced.append(data);sliced.removeFirst();try assertWords(OpenEXR.read(sliced),f.rgba)
    }
  }
  func testNativeExportRetainsEveryWordAndIsIndependentlyDecodable()throws {
    let d=try model(),(_,f)=try fixtures()
    for c in OpenEXR.Compression.allCases {for s in OpenEXR.Sample.allCases {
      let data=try OpenEXR.encoded(d,compression:c,sample:s)
      try assertWords(OpenEXR.read(data),f[0].rgba)
      let h=try OpenEXR.header(data);XCTAssertEqual(h.compression,c);XCTAssertTrue(h.channels.allSatisfy{$0.sample==s})
      let imageSource=try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil));XCTAssertEqual(CGImageSourceGetType(imageSource) as String?,OpenEXR.contentType.identifier)
      let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource,0,nil));XCTAssertEqual(image.width,5);XCTAssertEqual(image.height,17)
      if let capture=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {try data.write(to:URL(fileURLWithPath:capture).appendingPathComponent("native-\(c.rawValue)-\(s.rawValue).exr"))}
    }}
  }
  func testOverflowMalformedBudgetAndDepthRejectWithoutMutation()throws {
    let d=try model(),before=try NativeArchive.encodeChunked(d),data=try OpenEXR.encoded(d)
    for cut in [0,4,8,64,data.count-1] {XCTAssertThrowsError(try OpenEXR.read(data.prefix(cut)))}
    XCTAssertThrowsError(try OpenEXR.read(data,rasterByteLimit:1));XCTAssertThrowsError(try OpenEXR.encoded(d,maximumBytes:16))
    var bad=data;bad[4]=3;XCTAssertThrowsError(try OpenEXR.read(bad))
    let h=try OpenEXR.header(data);bad=data;bad.replaceSubrange(h.offset..<h.offset+8,with:Data(repeating:0,count:8));XCTAssertThrowsError(try OpenEXR.read(bad))
    guard case .raster(var huge)=d.layers[0].content else{return XCTFail("Not raster")};huge.setLinearPixel(x:0,y:0,Pixel(70000,0,0,1));var overflow=d;overflow.layers[0].content = .raster(huge)
    XCTAssertThrowsError(try OpenEXR.encoded(overflow,sample:.half));XCTAssertNoThrow(try OpenEXR.encoded(overflow,sample:.float))
    XCTAssertThrowsError(try OpenEXR.encoded(CraftDocument(width:2,height:2,depth:.u8)))
    XCTAssertEqual(try NativeArchive.encodeChunked(d),before)
  }
  func testLargeImplicitExportHasNoDensePixelLimitAndUsesDeclaredFloatChannels()throws {
    let d=try CraftDocument(width:10000,height:4001,depth:.f32)
    let data=try OpenEXR.encoded(d),h=try OpenEXR.header(data)
    XCTAssertEqual(h.width,10000);XCTAssertEqual(h.height,4001);XCTAssertTrue(h.channels.allSatisfy{$0.sample == .float})
    XCTAssertLessThan(data.count,4*1024*1024)
    let (w,height)=try OpenEXR.dimensions(data);XCTAssertEqual(w,10000);XCTAssertEqual(height,4001)
    // Logical300000 geometry is separately admitted; a tiny output budget fails
    // before allocating dense canvas storage or building any pixel payload.
    let max=try CraftDocument(width:300000,height:300000,depth:.f32)
    XCTAssertThrowsError(try OpenEXR.encoded(max,maximumBytes:1024))
  }
  func testMissingOrInvalidAttributesAndOverlappingChunksReject()throws {
    let data=try OpenEXR.encoded(model()),h=try OpenEXR.header(data)
    var overlap=data;overlap.replaceSubrange(h.offset+8..<h.offset+16,with:data[h.offset..<h.offset+8]);XCTAssertThrowsError(try OpenEXR.read(overlap))
    func attr(_ name:String,_ type:String)throws->Int {
      let needle=Data((name+"\0"+type+"\0").utf8);return try XCTUnwrap(data.range(of:needle)).upperBound+4
    }
    var nan=data;let at=try attr("xDensity","float");nan.replaceSubrange(at..<at+4,with:Data([0,0,192,127]));XCTAssertThrowsError(try OpenEXR.read(nan))
    var comp=data;comp[try attr("compression","compression")]=4;XCTAssertThrowsError(try OpenEXR.read(comp))
    var chroma=data;chroma[try attr("chromaticities","chromaticities")+3]^=16;XCTAssertThrowsError(try OpenEXR.read(chroma))
    var screen=data;screen.replaceSubrange(try attr("screenWindowWidth","float")..<(try attr("screenWindowWidth","float"))+4,with:Data(repeating:0,count:4));XCTAssertThrowsError(try OpenEXR.read(screen))
  }
  func testCancelledCodecTasksNeverPublishBytesOrDocuments()async throws {
    let d=try model(),data=try OpenEXR.encoded(d)
    let encoding=Task {withUnsafeCurrentTask{$0?.cancel()};return try OpenEXR.encoded(d)}
    let decoding=Task {withUnsafeCurrentTask{$0?.cancel()};return try OpenEXR.read(data)}
    do{_ = try await encoding.value;XCTFail("Encoded after cancellation")}catch is CancellationError {}catch{XCTFail("Unexpected \(error)")}
    do{_ = try await decoding.value;XCTFail("Decoded after cancellation")}catch is CancellationError {}catch{XCTFail("Unexpected \(error)")}
  }

  func testFloatMantissaAndZeroAlphaHDRBitsSurviveWithoutHalfQuantization()throws {
    let words:[UInt32]=[0x3f800001,0xbeaaaaab,0x477fe100,0x3f800000,0x3e4ccccd,0x3f000001,0x3f7fffff,0x3f800000,0xc0490fdb,0x3f800001,0x47c35000,0]
    var d=try CraftDocument(width:3,height:1,depth:.f32),s=try Surface(width:3,height:1,depth:.f32,colorEncoding:.linearRGB)
    for x in 0..<3 {let p=words[x*4..<x*4+4].map{Float(bitPattern:$0)};s.setLinearPixel(x:x,y:0,Pixel(p[0],p[1],p[2],p[3]))}
    d.layers[0].content = .raster(s)
    let data=try OpenEXR.encoded(d,compression:.none);try assertWords(OpenEXR.read(data),words.map{Float(bitPattern:$0)})
    XCTAssertThrowsError(try OpenEXR.encoded(d,sample:.half))
    if let capture=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {try data.write(to:URL(fileURLWithPath:capture).appendingPathComponent("float-precision.exr"))}
    var half=try CraftDocument(width:1,height:1,depth:.f32);var h=try Surface(width:1,height:1,depth:.f32,colorEncoding:.linearRGB)
    h.setLinearPixel(x:0,y:0,Pixel(0.2,0.2,0.2,1));half.layers[0].content = .raster(h)
    let decoded=try OpenEXR.read(OpenEXR.encoded(half,sample:.half)),reduced=Float(bitPattern:0x3e4cc000)
    try assertWords(decoded,[reduced,reduced,reduced,1]);XCTAssertNotEqual(reduced.bitPattern,Float(0.2).bitPattern)
  }

  func testUniversalHalfConversionMatchesEveryIndependentFiniteWordAndBoundaryTies()throws {
    let (folder,_)=try fixtures(),data=try Data(contentsOf:folder.appendingPathComponent("half-f32-reference.bin"));XCTAssertEqual(data.count,65536*4)
    var count=0
    for bits in 0..<65536 {
      let exponent=(bits>>10)&31,fraction=bits&1023
      let at=bits*4,word=(0..<4).reduce(UInt32(0)){$0|UInt32(data[at+$1])<<($1*8)}
      let value=OpenEXR.halfValue(UInt16(bits))
      if exponent==31 {XCTAssertFalse(value.isFinite);if fraction==0 {XCTAssertEqual(value.bitPattern,word)};continue}
      XCTAssertEqual(value.bitPattern,word,"Half pattern \(bits)")
      XCTAssertEqual(try OpenEXR.halfBits(Float(bitPattern:word)),UInt16(bits));count += 1
    }
    XCTAssertEqual(count,63488)
    let ties:[(UInt32,UInt16)] = [(0x3f801000,0x3c00),(0x3f803000,0x3c02),(0x33000000,0),(0x33000001,1),(0x33800000,1),(0xb3000000,0x8000),(0x387fe000,0x400),(0x477fefff,0x7bff)]
    for (word,half) in ties {
      XCTAssertEqual(try OpenEXR.halfBits(Float(bitPattern:word)),half)
    }
    for word in [UInt32(0x477ff000),0x7f800000,0x7fc00000] {XCTAssertThrowsError(try OpenEXR.halfBits(Float(bitPattern:word)))}
  }

}
