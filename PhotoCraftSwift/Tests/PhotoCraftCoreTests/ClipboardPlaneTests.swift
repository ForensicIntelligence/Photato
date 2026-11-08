import Foundation
import XCTest
@testable import PhotoCraftCore

final class ClipboardPlaneTests:XCTestCase {
  func fixture(_ depth:PixelDepth,target:Int=0)throws->(CraftDocument,ClipboardPlaneTarget) {
    var d=try CraftDocument(width:8,height:6,depth:depth),values=try Surface(width:8,height:6,depth:depth,fill:Pixel(0.25,0.25,0.25));values.setPixel(x:3,y:2,Pixel(0.75,0.75,0.75))
    let channel=AlphaChannel(name:"Owned",pixels:values)
    switch target {
    case 0:d.alphaChannels=[channel];return(d,.alpha(channel.id))
    case 1:d.quickMask=channel;return(d,.quickMask)
    case 2:d.layers[0].mask=values;return(d,.layerMask(d.layers[0].id))
    default:
      d.layers[0].smartObject=try SmartObject(fileName:"Owned.photato",mediaType:"application/vnd.photato.document",data:try NativeArchive.encode(d),width:8,height:6)
      var stack=SmartFilterStack();stack.mask=values;d.layers[0].smartFilters=stack;return(d,.smartFilterMask(d.layers[0].id))
    }
  }
  func values(_ d:CraftDocument,_ t:ClipboardPlaneTarget)throws->Surface{try ClipboardPlane.projection(d,t).0}
  func testNumericCopyEveryDepthTargetAndTransportKeepSamplesCoverageOrigin()throws {
    for depth in PixelDepth.allCases{for kind in 0..<4{
      var (d,target)=try fixture(depth,target:kind);d.selection = .init(x:2,y:1,width:3,height:3)
      let original=d,content=try ClipboardPlane.copy(d,target:target),decoded=try ClipboardContent.decode(content.encoded()),image=try XCTUnwrap(ClipboardPlane.numericImage(decoded))
      XCTAssertEqual(content.bounds,.init(x:2,y:1,width:3,height:3));XCTAssertEqual(decoded.document.colorMode,.grayscale);XCTAssertEqual(image.values.depth,depth)
      XCTAssertEqual(image.values.pixel(x:1,y:1).r,try values(d,target).pixel(x:3,y:2).r);XCTAssertEqual(image.coverage.pixel(x:1,y:1).r,1)
      XCTAssertTrue(d==original);XCTAssertTrue(content==decoded)
    }}
  }
  func testCopyIrregularSelectionKeepsNumericGraySeparateFromOpacity()throws {
    var (d,target)=try fixture(.u16)
    var bytes=[UInt8](repeating:0,count:48);bytes[2*8+3]=128;bytes[2*8+4]=255
    d.setCoverageSelection(try .init(width:8,height:6,bytes:bytes))
    let content=try ClipboardPlane.copy(d,target:target),image=try XCTUnwrap(ClipboardPlane.numericImage(content))
    XCTAssertEqual(content.bounds,.init(x:3,y:2,width:2,height:1))
    XCTAssertEqual(image.values.pixel(x:0,y:0).r,Float(49151)/65535);XCTAssertEqual(image.coverage.pixel(x:0,y:0).r,Float(32896)/65535)
    XCTAssertEqual(image.values.pixel(x:1,y:0).r,Float(16384)/65535);XCTAssertEqual(image.coverage.pixel(x:1,y:0).r,1)
  }
  func testCutPasteEachTargetPreserveUnrelatedContentAndUndoRedo()throws {
    for depth in PixelDepth.allCases{for kind in 0..<4{
      var (d,target)=try fixture(depth,target:kind);d.selection = .init(x:2,y:1,width:3,height:3)
      let content=try ClipboardPlane.copy(d,target:target),image=try XCTUnwrap(ClipboardPlane.numericImage(content))
      var session=EditorSession(document:d);let cut=try ClipboardPlane.cut(d,target:target,background:0)
      try session.executePrepared(PreparedEdit(clipboardPlane:cut));XCTAssertEqual(try values(session.document,target).pixel(x:3,y:2).r,0);XCTAssertEqual(session.undoStack.last?.label,"Cut")
      XCTAssertEqual(session.document.layers[0].content,d.layers[0].content);XCTAssertEqual(try values(session.document,target).pixel(x:0,y:0).r,try values(d,target).pixel(x:0,y:0).r)
      let removed=session.document;try session.executePrepared(PreparedEdit(clipboardPlane:ClipboardPlane.paste(image,into:removed,target:target,placement:.inPlace)))
      XCTAssertEqual(try values(session.document,target).pixel(x:3,y:2).r,try values(d,target).pixel(x:3,y:2).r)
      try session.undo();XCTAssertTrue(session.document==removed);try session.undo();XCTAssertTrue(session.document==d);try session.redo();XCTAssertTrue(session.document==removed)
    }}
  }
  func testTranslatedMaskPasteExpandsStorageAndPreservesEffectsAndImage()throws {
    var d=try CraftDocument(width:8,height:6,depth:.f32);d.layers[0].mask=try Surface(width:2,height:2,depth:.f32,fill:.black)
    var props=MaskProperties();props.transform = .translation(2,1);props.outside=0.25;props.density=0.6;props.feather=1;props.linked=false;d.layers[0].maskProperties=props
    let image=try ClipboardPlaneImage(values:Surface(width:2,height:2,depth:.f32,fill:.white),coverage:Surface(width:2,height:2,depth:.f32,fill:.white),bounds:.init(x:0,y:0,width:2,height:2))
    let edit=try ClipboardPlane.paste(image,into:d,target:.layerMask(d.layers[0].id),placement:.inPlace)
    XCTAssertEqual(edit.result.layers[0].content,d.layers[0].content);let next=edit.result.layers[0]
    XCTAssertEqual(next.maskCoordinateTransform,.identity);XCTAssertEqual(next.effectiveMaskProperties.outside,props.outside);XCTAssertEqual(next.effectiveMaskProperties.density,props.density);XCTAssertEqual(next.effectiveMaskProperties.feather,props.feather);XCTAssertFalse(next.effectiveMaskProperties.linked)
    XCTAssertEqual(next.mask?.pixel(x:0,y:0).r,1);XCTAssertEqual(next.mask?.pixel(x:2,y:1).r,0)
  }
  func testSpotGrayRetentionAndSelectedAreaIndicationUseEditingValues()throws {
    var (d,target)=try fixture(.f32);var channel=try d.channel(target.channel!);channel.spot = .init();channel.psdSpotGray=try Surface(width:8,height:6,depth:.f32,fill:Pixel(0.3,0.3,0.3));channel.pixels=try Surface(width:8,height:6,depth:.f32,fill:Pixel(0.7,0.7,0.7));d.alphaChannels=[channel]
    let copied=try XCTUnwrap(ClipboardPlane.numericImage(ClipboardPlane.copy(d,target:target)));XCTAssertEqual(copied.values.pixel(x:0,y:0).r.bitPattern,Float(0.3).bitPattern)
    d.selection = .init(x:1,y:1,width:1,height:1);let cut=try ClipboardPlane.cut(d,target:target,background:1)
    XCTAssertEqual(cut.result.alphaChannels?[0].pixels.pixel(x:1,y:1).r,0);XCTAssertEqual(cut.result.alphaChannels?[0].psdSpotGray?.pixel(x:1,y:1).r,1);XCTAssertEqual(cut.result.alphaChannels?[0].psdSpotGray?.pixel(x:0,y:0).r.bitPattern,Float(0.3).bitPattern)
    channel.spot=nil;channel.psdSpotGray=nil;channel.options.indicates = .selectedAreas;d.alphaChannels=[channel]
    let inverted=try XCTUnwrap(ClipboardPlane.numericImage(ClipboardPlane.copy(d,target:target)));XCTAssertEqual(inverted.values.pixel(x:0,y:0).r,1-Float(0.7))
  }
  func testMaximumSparsePlaneCopyCutPasteAndNativeTransport()throws {
    var d=try CraftDocument(width:300000,height:300000,depth:.f32);let channel=AlphaChannel(name:"Maximum",pixels:try Surface(width:300000,height:300000,depth:.f32,fill:Pixel(0.25,0.25,0.25)));d.alphaChannels=[channel];let target=ClipboardPlaneTarget.alpha(channel.id)
    let copied=try ClipboardPlane.copy(d,target:target),data=try copied.encoded(),reopened=try ClipboardContent.decode(data)
    XCTAssertLessThan(data.count,1024*1024);let image=try XCTUnwrap(ClipboardPlane.numericImage(reopened));XCTAssertEqual(image.values.width,300000);XCTAssertEqual(image.values.height,300000);XCTAssertEqual(image.values.tileCount,0);XCTAssertEqual(image.values.pixel(x:299999,y:299999).r,0.25)
    let cut=try ClipboardPlane.cut(d,target:target,background:1);XCTAssertEqual(cut.result.alphaChannels?[0].pixels.pixel(x:299999,y:299999).r,1)
    let paste=try ClipboardPlane.paste(image,into:cut.result,target:target,placement:.inPlace);XCTAssertEqual(paste.result.alphaChannels?[0].pixels.pixel(x:299999,y:299999).r,0.25)
  }
  func testInvalidLockedMissingAndCancelledOperationsAreAtomic()async throws {
    var (d,target)=try fixture(.u8,target:2);d.layers[0].protection = [.all]
    XCTAssertTrue(ClipboardPlane.available(d,target:target));XCTAssertFalse(ClipboardPlane.available(d,target:target,writing:true));XCTAssertThrowsError(try ClipboardPlane.cut(d,target:target,background:0))
    XCTAssertThrowsError(try ClipboardPlane.copy(d,target:.alpha(UUID())))
    let frozen=d,selected=target
    try await Task.detached{withUnsafeCurrentTask{$0?.cancel()};do{_ = try ClipboardPlane.copy(frozen,target:selected);XCTFail("Cancelled copy published")}catch is CancellationError{}}.value
  }
}
