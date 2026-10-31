import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class ChannelArithmeticPreparationTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:8,height:5,depth:depth)
    d.layers[0].content = .raster(try Surface(width:8,height:5,depth:depth,fill:Pixel(0.8,0.4,0.2)))
    return d
  }
  func testCrossDocumentChannelsInversionAndMismatchValidation() throws {
    let target=try fixture(),source=try fixture()
    let spec=ChannelArithmeticSource(documentID:source.id,channel:.component(1),invert:true)
    let input=try ChannelArithmeticPreparation.input(spec,destination:target,sources:[source])
    XCTAssertEqual(input.components,1);XCTAssertEqual(input.samples.pixel(x:2,y:2).r,1-Float(102)/255)
    var bad=source;bad.depth = .u16
    XCTAssertThrowsError(try ChannelArithmeticPreparation.input(spec,destination:target,sources:[bad]))
    XCTAssertThrowsError(try ChannelArithmeticPreparation.input(.init(documentID:UUID()),destination:target,sources:[]))
    let gray=try ChannelArithmeticPreparation.input(.init(channel:.gray),destination:target,sources:[])
    XCTAssertEqual(gray.samples.pixel(x:1,y:1).r,0.299*(204/255 as Float)+0.587*(102/255 as Float)+0.114*(51/255 as Float))
  }
  func testAllCalculationOutputsHistoryAndNativeReopen() throws {
    var source=try fixture();source.resolution=300
    var first=try Surface(width:8,height:5,fill:.black),second=first
    for y in 0..<5 {for x in 0..<8 {
      if x<5 {first.setPixel(x:x,y:y,.white)}
      if x>=3 {second.setPixel(x:x,y:y,.white)}
    }}
    let a=AlphaChannel(name:"A",pixels:first),b=AlphaChannel(name:"B",pixels:second)
    try Command.channel(.create(a)).apply(to:&source);try Command.channel(.create(b)).apply(to:&source)
    for kind in ChannelCalculationResult.allCases {
      var request=ChannelArithmeticRequest(.calculations)
      request.source1.channel = .alpha(a.id);request.source2.channel = .alpha(b.id);request.result=kind;request.name="Intersection"
      let prepared=try ChannelArithmeticPreparation.prepare(request,target:nil,document:source)
      if kind == .newDocument {
        let doc=try XCTUnwrap(prepared.newDocument);XCTAssertEqual(doc.colorMode,.grayscale);XCTAssertEqual(doc.resolution,300)
        let native=try XCTUnwrap(doc.layers[0].nativeMode)
        XCTAssertEqual(native.value(component:0,index:4),1);XCTAssertEqual(native.value(component:0,index:1),0)
      } else {
        var session=EditorSession(document:source);try session.execute(XCTUnwrap(prepared.command))
        if kind == .newChannel {
          let channel=try XCTUnwrap(session.document.alphaChannels?.last)
          XCTAssertEqual(channel.name,"Intersection");XCTAssertEqual(channel.pixels.pixel(x:4,y:1),.white)
          XCTAssertEqual(channel.pixels.pixel(x:2,y:1),.black)
        } else {
          XCTAssertEqual(session.document.selectionCoverage(x:4,y:1),1)
          XCTAssertEqual(session.document.selectionCoverage(x:2,y:1),0)
        }
        XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(session.document)),session.document)
        try session.undo();XCTAssertEqual(session.document,source)
      }
    }
  }
  func testPreparedApplyImageIsAtomicPreservesSourcesAndRejectsStaleCommit()throws {
    let source=try fixture(),external=try fixture()
    var request=ChannelArithmeticRequest(.applyImage)
    request.source1 = .init(documentID:external.id,channel:.component(1),invert:true)
    let prepared=try ChannelArithmeticPreparation.prepare(request,target:.pixels(source.layers[0].id,[]),document:source,sources:[external])
    var session=EditorSession(document:source);try session.execute(XCTUnwrap(prepared.command))
    XCTAssertEqual(session.undoStack.last?.label,"Apply Image")
    XCTAssertNotEqual(session.document.layers[0].content,source.layers[0].content)
    var changed=source;changed.name="Changed";let before=changed
    XCTAssertThrowsError(try prepared.command?.apply(to:&changed));XCTAssertEqual(changed,before)
    try session.undo();XCTAssertEqual(session.document,source)
  }
  func testMaximumSparseCalculationsProducesEditableChannel()throws {
    var source=try CraftDocument(width:300_000,height:300_000)
    source.layers[0].content = .fill(.white)
    let result=try ChannelArithmeticPreparation.prepare(.init(.calculations),target:nil,document:source)
    var d=source;try XCTUnwrap(result.command).apply(to:&d)
    let channel=try XCTUnwrap(d.alphaChannels?.last)
    XCTAssertEqual(channel.pixels.pixel(x:200_000,y:200_000),.white)
    XCTAssertLessThan(channel.pixels.allocatedBytes,1_048_576)
  }
}
