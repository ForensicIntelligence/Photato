import Foundation
import XCTest
@testable import PhotoCraftCore

final class VideoArrangementTests:XCTestCase {
  func fixture(movie:Bool=false)throws->CraftDocument {
    var d=try VideoTimelineTests().fixture()
    d.videoTimeline=VideoTimeline(frameRate:8,durationFrames:12)
    if movie { d.layers[0].video!.movie=MovieSource(data:Data([1,2,3]),presentationTimes:[0,3,8].map{MovieTime(value:$0,timescale:10)},endTime:.init(value:15,timescale:10),originalFrameRate:2,audioTracks:1) }
    try d.validate();return d
  }
  func testSplitAtNonSourceBoundaryPreservesEveryFrameAndHistory()throws {
    for movie in [false,true] {
      var session=EditorSession(document:try fixture(movie:movie));try session.selectVideoFrame(3)
      let before=session.document,id=before.layers[0].id
      try session.execute(.video(.arrange(.split([id]))));let after=session.document
      XCTAssertEqual(after.layers.count,2);XCTAssertEqual(after.layers[0].video!.duration,0.375,accuracy:1e-12)
      XCTAssertEqual(after.layers[1].video!.startTime,0.375);XCTAssertEqual(after.layers[1].video!.duration,1.125,accuracy:1e-12)
      for frame in 0..<12 {
        let time=Double(frame)/8,old=before.layers[0].video!,clips=after.layers.compactMap(\.video)
        let active=clips.filter{$0.sourceIndex(at:time) != nil};XCTAssertEqual(active.count,1)
        XCTAssertEqual(active.first?.sourceIndex(at:time),old.sourceIndex(at:time))
      }
      XCTAssertEqual(after.layers[0].video!.frames,after.layers[1].video!.frames)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(after)),after)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(after)),after)
      try session.undo();XCTAssertEqual(session.document,before);try session.redo();XCTAssertEqual(session.document,after)
    }
  }
  func testSplitCopiesCanBePaintedIndependentlyAndSplitAgain()throws {
    var session=EditorSession(document:try fixture());try session.selectVideoFrame(3)
    try session.execute(.video(.arrange(.split([session.document.layers[0].id]))))
    let right=session.document.layers[1].id,original=session.document.layers[0].video!.frames
    try session.execute(.fill(right,.white));XCTAssertEqual(session.document.layers[0].video!.frames,original)
    XCTAssertNotEqual(session.document.layers[1].video!.frames,original)
    try session.selectVideoFrame(6);try session.execute(.video(.arrange(.split([right]))))
    XCTAssertEqual(session.document.layers.compactMap(\.video).map(\.duration),[0.375,0.375,0.75])
  }
  func testVideoGroupReorderTrimAndOrdinaryHierarchyMoveReflow()throws {
    var d=try fixture();let a=d.layers[0].id
    var still=Layer(name:"Title",content:.fill(.white));still.videoTiming = .init(startTime:0,duration:1)
    d.layers.append(still)
    try Command.video(.arrange(.group("Story",[a,still.id]))).apply(to:&d)
    let group=d.activeLayerID!
    XCTAssertEqual(d.layers[1].videoTiming?.startTime,1.5)
    try Command.video(.arrange(.move(still.id,group:group,position:0))).apply(to:&d)
    XCTAssertEqual(d.layers[0].id,still.id);XCTAssertEqual(d.layers[1].video?.startTime,1)
    try Command.video(.arrange(.stillTiming(still.id,startTime:0,duration:0.5))).apply(to:&d)
    XCTAssertEqual(d.layers[1].video?.startTime,0.5)
    try Command.relocate(still.id,nil,0).apply(to:&d)
    XCTAssertEqual(d.layers.first{$0.id==a}?.video?.startTime,0)
    try Command.video(.arrange(.groupStart(group,2))).apply(to:&d)
    XCTAssertEqual(d.layers.first{$0.id==a}?.video?.startTime,2)
    let bytes=try NativeArchive.encodeChunked(d);XCTAssertEqual(bytes[8],54);XCTAssertEqual(try NativeArchive.decode(bytes),d)
    var downgrade=bytes;downgrade[8]=53;XCTAssertThrowsError(try NativeArchive.decode(downgrade))
  }
  func testSplitAnimatedStillRetainsInterpolatedMotionAndMovesKeys()throws {
    var d=try VideoKeyframeTests().fixture();let id=d.layers[0].id
    try Command.video(.keyframe(.enable(id,.opacity))).apply(to:&d)
    try d.selectVideoFrame(8);try Command.opacity(id,0).apply(to:&d);try d.selectVideoFrame(4)
    let before=d
    try Command.video(.arrange(.split([id]))).apply(to:&d)
    for frame in 0..<9 {
      let snapshot=try d.videoDocument(at:frame),reference=try before.videoDocument(at:frame)
      for layer in snapshot.layers {XCTAssertEqual(layer.opacity,reference.layers[0].opacity)}
    }
    let right=d.layers[1].id
    try Command.video(.arrange(.stillTiming(right,startTime:0,duration:1.25))).apply(to:&d)
    try d.selectVideoFrame(0);XCTAssertEqual(d.layers[1].opacity,0.5)
    try d.selectVideoFrame(4);XCTAssertEqual(d.layers[1].opacity,0)
    XCTAssertEqual(d.layers[0].videoKeyframes,before.layers[0].videoKeyframes)
  }
  func testInvalidSplitAndLockedGroupMutationsAreAtomic()throws {
    var d=try fixture();let id=d.layers[0].id,before=d
    XCTAssertThrowsError(try Command.video(.arrange(.split([id]))).apply(to:&d));XCTAssertEqual(d,before)
    try d.selectVideoFrame(3);d.layers[0].locked=true;let locked=d
    XCTAssertThrowsError(try Command.video(.arrange(.split([id]))).apply(to:&d));XCTAssertEqual(d,locked)
    d.layers[0].locked=false
    try Command.video(.arrange(.group("Track",[id]))).apply(to:&d)
    d.layers[0].locked=true;let grouped=d,group=d.activeLayerID!
    XCTAssertThrowsError(try Command.video(.arrange(.groupStart(group,1))).apply(to:&d));XCTAssertEqual(d,grouped)
    d.layers[0].locked=false;let current=d
    XCTAssertThrowsError(try Command.video(.arrange(.move(id,group:UUID(),position:0))).apply(to:&d));XCTAssertEqual(d,current)
  }
  func testStillDurationSnapshotDoesNotMutateVisibilityAndTimelineRemovalClearsMetadata()throws {
    var d=try VideoKeyframeTests().fixture();let id=d.layers[0].id
    try Command.video(.arrange(.stillTiming(id,startTime:1,duration:1))).apply(to:&d)
    XCTAssertTrue(d.layers[0].visible);XCTAssertFalse(d.videoCompositionSnapshot().layers[0].visible)
    try d.selectVideoFrame(4);XCTAssertTrue(d.videoCompositionSnapshot().layers[0].visible)
    try d.selectVideoFrame(8);XCTAssertFalse(d.videoCompositionSnapshot().layers[0].visible)
    try Command.video(.remove).apply(to:&d);XCTAssertNil(d.layers[0].videoTiming)
  }
  func testNewEmptyTrackIsNotNestedInsideSelectedTrack()throws {
    var d=try fixture()
    try Command.video(.arrange(.group("First",[d.layers[0].id]))).apply(to:&d)
    let first=d.activeLayerID!
    try Command.video(.arrange(.group("Second",[]))).apply(to:&d)
    let second=d.activeLayerID!
    XCTAssertNotEqual(first,second);XCTAssertNil(d.layers.first{$0.id==second}?.parentID)
    try d.validate()
  }
  func testMovingOrdinaryGroupMovesNestedClipAndRejectsNegativeNestedTime()throws {
    var d=try fixture();let clip=d.layers[0].id
    try Command.groupLayers([clip],"Nested content").apply(to:&d);let group=d.activeLayerID!
    try Command.video(.arrange(.stillTiming(group,startTime:2,duration:2))).apply(to:&d)
    XCTAssertEqual(d.layers.first{$0.id==clip}?.video?.startTime,2)
    try d.selectVideoFrame(16);XCTAssertEqual(d.layers.first{$0.id==clip}?.video?.sourceIndex(at:2),0)
    try Command.video(.arrange(.stillTiming(group,startTime:0,duration:2))).apply(to:&d)
    XCTAssertEqual(d.layers.first{$0.id==clip}?.video?.startTime,0)
  }
  func testGroupedStartCannotSilentlyOverrideRequestedTime()throws {
    var d=try fixture();let id=d.layers[0].id
    try Command.video(.arrange(.group("Track",[id]))).apply(to:&d);let before=d
    XCTAssertThrowsError(try Command.video(.timing(id,startTime:2,inFrame:0,outFrame:3,frameRate:2)).apply(to:&d))
    XCTAssertEqual(d,before)
    try Command.video(.timing(id,startTime:0,inFrame:1,outFrame:3,frameRate:2)).apply(to:&d)
    XCTAssertEqual(d.layers[0].video?.duration,1)
  }
  func testMalformedPreciseBoundariesRejectedWithoutTraps()throws {
    var d=try fixture()
    for value in [-1.0,Double.nan,10] {d.layers[0].video!.sourceIn=value;XCTAssertThrowsError(try d.validate())}
    d=try fixture();d.layers[0].video!.sourceOut=0;XCTAssertThrowsError(try d.validate())
  }
}
