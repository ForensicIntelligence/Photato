import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class LargeChannelArithmeticPreparationTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u16)throws->CraftDocument {
    var document=try CraftDocument(width:300000,height:300000,depth:depth)
    let a=AlphaChannel(name:"First",pixels:try Surface(width:document.width,height:document.height,depth:depth,fill:Pixel(0.75,0.75,0.75)))
    let b=AlphaChannel(name:"Second",pixels:try Surface(width:document.width,height:document.height,depth:depth,fill:Pixel(0.25,0.25,0.25)))
    document.alphaChannels=[a,b];document.name="Arithmetic source";document.resolution=300
    return document
  }
  func request(_ document:CraftDocument)->ChannelArithmeticRequest {
    var request=ChannelArithmeticRequest(.calculations)
    request.source1.channel = .alpha(document.alphaChannels![0].id);request.source2.channel = .alpha(document.alphaChannels![1].id)
    request.options.blending="subtract";request.options.scale=2;request.options.offset=127.5
    request.name="Calculated";return request
  }
  func testMaximumCalculationsNewGrayDocumentAllDepthsIndependentWordsAndNative86()throws {
    for depth in PixelDepth.allCases {
      let source=try fixture(depth);var options=request(source);options.result = .newDocument
      let prepared=try ChannelArithmeticPreparation.prepare(options,target:nil,document:source)
      let document=try XCTUnwrap(prepared.newDocument),native=try XCTUnwrap(document.layers[0].nativeMode)
      let expected:UInt32=depth == .u8 ? 64:depth == .u16 ? 16384:Float(0.25).bitPattern
      let alpha:UInt32=depth == .u8 ? 255:depth == .u16 ? 65535:Float(1).bitPattern
      var data=Data()
      for i in [0,300000*12345+1234,89_999_999_999] {
        XCTAssertEqual(native.rawWord(component:0,index:i),expected);XCTAssertEqual(native.rawWord(component:1,index:i),alpha)
        for value in [native.rawWord(component:0,index:i),native.rawWord(component:1,index:i)] {var word=value.littleEndian;withUnsafeBytes(of:&word){data.append(contentsOf:$0)}}
      }
      XCTAssertEqual(document.width,300000);XCTAssertEqual(document.height,300000);XCTAssertEqual(document.resolution,300)
      XCTAssertEqual(document.colorMode,.grayscale);XCTAssertEqual(document.name,"Calculated");XCTAssertNil(prepared.command)
      XCTAssertTrue(document.layers[0].protection.locksTransparency);XCTAssertLessThan(native.estimatedBytes,1024*1024)
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(document)),document)
      if let dir=ProcessInfo.processInfo.environment["PHOTATO_COMPONENT_OUTPUT_DIR"] {try data.write(to:URL(fileURLWithPath:dir).appendingPathComponent("calculations-\(depth.rawValue).bin"))}
    }
  }
  func testAllMaximumCalculationDestinationsAndPreparedStaleness()throws {
    let source=try fixture();let before=source
    for kind in [ChannelCalculationResult.newChannel,.selection] {
      var options=request(source);options.result=kind
      let prepared=try ChannelArithmeticPreparation.prepare(options,target:nil,document:source)
      var session=EditorSession(document:source);try session.execute(XCTUnwrap(prepared.command))
      if kind == .newChannel {XCTAssertEqual(session.document.alphaChannels?.last?.pixels.pixel(x:299999,y:299999).r,Float(16384)/65535)}
      else {XCTAssertEqual(session.document.selectionCoverage(x:299999,y:299999),Float(64)/255)}
      var changed=source;changed.name="Stale";let preserved=changed
      XCTAssertThrowsError(try prepared.command?.apply(to:&changed));XCTAssertEqual(changed,preserved)
      try session.undo();XCTAssertEqual(session.document,before)
    }
  }
  func testMaximumNativeSourceApplyImageExternalMaskAndArchive()throws {
    let source=try fixture(),external=try fixture()
    var destination=try DocumentCreation.blank(width:300000,height:300000,depth:.u16,background:.white,mode:.cmyk)
    destination.selection = .init(x:299999,y:299999,width:1,height:1)
    var options=ChannelArithmeticRequest(.applyImage);options.source1 = .init(documentID:source.id,channel:.alpha(source.alphaChannels![0].id))
    options.mask = .init(documentID:external.id,channel:.alpha(external.alphaChannels![1].id));options.options.blending="normal"
    let prepared=try ChannelArithmeticPreparation.prepare(options,target:.pixels(destination.layers[0].id,[0]),document:destination,sources:[source,external])
    var session=EditorSession(document:destination);try session.execute(XCTUnwrap(prepared.command))
    let native=try XCTUnwrap(session.document.layers[0].nativeMode)
    XCTAssertEqual(native.rawWord(component:0,index:0),0);XCTAssertGreaterThan(native.rawWord(component:0,index:89_999_999_999),0)
    XCTAssertEqual(native.rawWord(component:4,index:89_999_999_999),65535)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(session.document)),session.document)
    try session.undo();XCTAssertEqual(session.document,destination)
  }
}
