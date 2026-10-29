import Foundation
import XCTest
@testable import PhotoCraftCore

final class VideoTimelineTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d=try CraftDocument(width:4,height:3)
    let frames=try [Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1)].map{try Surface(width:4,height:3,fill:$0)}
    var layer=Layer(name:"Video",content:.raster(frames[0]));layer.video=VideoClip(frames:frames,frameRate:2)
    d.layers=[layer];d.activeLayerID=layer.id;d.videoTimeline=VideoTimeline(frameRate:2,durationFrames:3);try d.validate();return d
  }
  func testSeekPaintingAndHistoryKeepOtherFrames() throws {
    var session=EditorSession(document:try fixture());let id=session.document.layers[0].id
    try session.selectVideoFrame(1);let before=session.document
    XCTAssertTrue(session.undoStack.isEmpty)
    try session.execute(.fill(id,.white));let after=session.document
    XCTAssertEqual(after.layers[0].video!.frames.map{$0.pixel(x:0,y:0)},[Pixel(1,0,0),.white,Pixel(0,0,1)])
    try session.undo();XCTAssertEqual(session.document,before);try session.redo();XCTAssertEqual(session.document,after)
    try session.selectVideoFrame(2);XCTAssertEqual(session.document.layers[0].content,.raster(after.layers[0].video!.frames[2]));try session.document.validate()
  }
  func testTrimStartSourceRateAndTimelineRateAreIndependent() throws {
    var d=try fixture();let id=d.layers[0].id
    try Command.video(.timing(id,startTime:1,inFrame:1,outFrame:3,frameRate:4)).apply(to:&d)
    XCTAssertEqual(d.videoTimeline!.durationFrames,3)
    guard case .raster(let outside)=d.layers[0].content else{return XCTFail()};XCTAssertEqual(outside.pixel(x:0,y:0),.clear)
    let unchanged=d;XCTAssertThrowsError(try Command.fill(id,.white).apply(to:&d));XCTAssertEqual(d,unchanged)
    try Command.video(.frameRate(4)).apply(to:&d);XCTAssertEqual(d.videoTimeline!.durationFrames,6)
    try d.selectVideoFrame(4);XCTAssertEqual(d.layers[0].content,.raster(d.layers[0].video!.frames[1]))
    try d.selectVideoFrame(5);XCTAssertEqual(d.layers[0].content,.raster(d.layers[0].video!.frames[2]))
    XCTAssertEqual(d.layers[0].video!.frames.count,3)
  }
  func testPlaybackClockAndMalformedTiming() throws {
    var t=VideoTimeline(frameRate:24,durationFrames:48);t.currentFrame=24
    XCTAssertEqual(try t.playbackFrame(elapsed:0.5).frame,36);XCTAssertEqual(try t.playbackFrame(elapsed:1).frame,0)
    t.looping=false;XCTAssertTrue(try t.playbackFrame(elapsed:1).finished)
    var d=try fixture();let before=d,id=d.layers[0].id
    for c in [VideoCommand.frameRate(.nan),.timing(id,startTime:0,inFrame:2,outFrame:1,frameRate:24),.timing(id,startTime:-1,inFrame:0,outFrame:3,frameRate:24)] {XCTAssertThrowsError(try Command.video(c).apply(to:&d));XCTAssertEqual(d,before)}
    XCTAssertThrowsError(try d.selectVideoFrame(3));XCTAssertEqual(d,before)
    d.layers[0].video!.frames=[];XCTAssertThrowsError(try d.validate())
  }
  func testNative51RoundTripAndUnsupportedGlobalEditsAreAtomic() throws {
    var d=try fixture();try d.selectVideoFrame(2)
    XCTAssertEqual(d.minimumArchiveVersion,51)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
    let bytes=try NativeArchive.encodeChunked(d);XCTAssertEqual(bytes[8],51);XCTAssertEqual(try NativeArchive.decode(bytes),d)
    var downgrade=bytes;downgrade[8]=50;XCTAssertThrowsError(try NativeArchive.decode(downgrade))
    let before=d
    XCTAssertThrowsError(try Command.canvasSize(10,10,.center,nil).apply(to:&d));XCTAssertEqual(d,before)
    XCTAssertThrowsError(try Command.animation(.create).apply(to:&d));XCTAssertEqual(d,before)
  }
  func testRasterizeRetainsCurrentPixelsAndHistoryCanRestoreVideo() throws {
    var session=EditorSession(document:try fixture());try session.selectVideoFrame(1)
    let before=session.document,id=before.layers[0].id
    guard case .raster(let pixels)=before.layers[0].content else{return XCTFail()}
    try session.execute(.rasterize(id,pixels));XCTAssertNil(session.document.layers[0].video)
    guard case .raster(let still)=session.document.layers[0].content else{return XCTFail()}
    XCTAssertEqual(still.width,pixels.width);XCTAssertEqual(still.height,pixels.height)
    for y in 0..<pixels.height { for x in 0..<pixels.width { XCTAssertEqual(still.pixel(x:x,y:y),pixels.pixel(x:x,y:y)) } }
    try session.undo();XCTAssertEqual(session.document,before)
  }
}
