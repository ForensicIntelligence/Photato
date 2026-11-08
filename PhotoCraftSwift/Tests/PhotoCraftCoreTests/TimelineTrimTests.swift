import XCTest
@testable import PhotoCraftCore

final class TimelineTrimTests:XCTestCase {
  func fixture() throws -> CraftDocument {
    var d=try CraftDocument(width:4,height:3)
    let frames=try (0..<16).map { i in try Surface(width:4,height:3,fill:Pixel(Float(i)/15,0,1)) }
    var layer=Layer(name:"Editable movie",content:.raster(frames[0]));layer.video = .init(frames:frames,frameRate:4)
    d.layers=[layer];d.activeLayerID=layer.id;d.videoTimeline = .init(frameRate:4,durationFrames:16)
    d.videoTimeline!.workArea = .init(startFrame:3,endFrame:11)
    return d
  }
  func testSourceHandlesDurationPlayheadHistoryAndNative58()throws {
    var d=try fixture();try d.selectVideoFrame(7);let original=d
    var session=EditorSession(document:d);try session.execute(.video(.workspace(.trimToWorkArea)))
    let trimmed=session.document
    XCTAssertEqual(trimmed.videoTimeline?.durationFrames,8);XCTAssertEqual(trimmed.videoTimeline?.currentFrame,4)
    XCTAssertNil(trimmed.videoTimeline?.workArea);XCTAssertEqual(trimmed.videoTimeline?.trimmedToWorkArea,true)
    XCTAssertEqual(trimmed.layers[0].video?.startTime,-0.75);XCTAssertEqual(trimmed.layers[0].video?.frames,original.layers[0].video?.frames)
    for frame in 0..<8 {XCTAssertEqual(try trimmed.videoDocument(at:frame).layers[0].content,try original.videoDocument(at:frame+3).layers[0].content)}
    XCTAssertEqual(trimmed.minimumArchiveVersion,58)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(trimmed)),trimmed)
    var chunked=try NativeArchive.encodeChunked(trimmed);XCTAssertEqual(chunked[8],58)
    XCTAssertEqual(try NativeArchive.decode(chunked),trimmed);chunked[8]=57;XCTAssertThrowsError(try NativeArchive.decode(chunked))
    try session.undo();XCTAssertEqual(session.document,original);try session.redo();XCTAssertEqual(session.document,trimmed)
    try session.execute(.video(.loop(false)));XCTAssertEqual(session.document.videoTimeline?.durationFrames,8)
    try session.execute(.video(.frameRate(8)));XCTAssertEqual(session.document.videoTimeline?.durationFrames,16)
  }
  func testRepeatedTrimAndVariablePresentationTimesKeepSourceIndex()throws {
    var d=try fixture();d.layers[0].video!.frames=VideoFrames(Array(d.layers[0].video!.frames.prefix(4)));d.layers[0].video!.outFrame=4
    d.layers[0].video!.movie = .init(data:Data("owned metadata fixture".utf8),presentationTimes:[0,1,3,6].map{.init(value:$0,timescale:4)},endTime:.init(value:16,timescale:4),originalFrameRate:4,audioTracks:0)
    let original=d
    try Command.video(.workspace(.trimToWorkArea)).apply(to:&d)
    d.videoTimeline!.workArea = .init(startFrame:1,endFrame:6);try Command.video(.workspace(.trimToWorkArea)).apply(to:&d)
    XCTAssertEqual(d.videoTimeline?.durationFrames,5);XCTAssertEqual(d.layers[0].video?.movie,original.layers[0].video?.movie)
    for frame in 0..<5 {XCTAssertEqual(try d.videoDocument(at:frame).layers[0].content,try original.videoDocument(at:frame+4).layers[0].content)}
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
  }
  func testOutsideClipsRemovedAndSequentialGroupRetainsOriginalBoundary()throws {
    var d=try CraftDocument(width:4,height:3);d.videoTimeline = .init(frameRate:4,durationFrames:12)
    d.layers=(0..<3).map { i in var layer=Layer(name:"Clip\(i)",content:.fill(Pixel(Float(i)/2,0,1)));layer.videoTiming = .init(startTime:Double(i),duration:1);return layer }
    let ids=d.layers.map(\.id);d.activeLayerID=ids[0]
    try Command.video(.arrange(.group("Video",ids))).apply(to:&d)
    d.videoTimeline!.workArea = .init(startFrame:5,endFrame:11)
    try Command.video(.workspace(.trimToWorkArea)).apply(to:&d)
    XCTAssertFalse(d.layers.contains{$0.id==ids[0]});XCTAssertEqual(d.layers.first{$0.id==ids[1]}?.videoTiming?.startTime,-0.25)
    XCTAssertEqual(d.layers.first{$0.isGroup}?.group?.videoStartTime,-0.25);XCTAssertEqual(d.videoTimeline?.durationFrames,6)
    try d.validate()
  }
  func testKeyframeHandlesPreserveInterpolationAndRejectUnversionedPreroll()throws {
    var d=try fixture();d.layers[0].video=nil;d.layers[0].content = .fill(.white)
    d.layers[0].opacity=0;var keys:[VideoKeyframe]=[]
    for (time,value) in [(0.0,Float(0)),(0.5,0.25),(2.0,1),(3.0,0.5),(3.5,0)] {
      var sample=d.layers[0];sample.opacity=value;keys.append(.init(property:.opacity,time:time,layer:sample))
    }
    d.layers[0].videoKeyframes=keys;let original=d
    try Command.video(.workspace(.trimToWorkArea)).apply(to:&d)
    XCTAssertEqual(d.layers[0].videoKeyframes?.count,3)
    for frame in 0..<8 {XCTAssertEqual(try d.videoDocument(at:frame).layers[0].opacity,try original.videoDocument(at:frame+3).layers[0].opacity)}
    d.videoTimeline!.trimmedToWorkArea=nil;XCTAssertThrowsError(try d.validate())
  }
  func testLockInvalidAreaAndMissingTimelineAreAtomicAndFullAreaIsNoop()throws {
    var d=try fixture();d.layers[0].locked=true;let locked=d
    XCTAssertThrowsError(try Command.video(.workspace(.trimToWorkArea)).apply(to:&d));XCTAssertEqual(d,locked)
    d.layers[0].locked=false;d.videoTimeline!.workArea = .init(startFrame:7,endFrame:7);let invalid=d
    XCTAssertThrowsError(try Command.video(.workspace(.trimToWorkArea)).apply(to:&d));XCTAssertEqual(d,invalid)
    d=try fixture();d.videoTimeline!.workArea=nil;let full=d;try Command.video(.workspace(.trimToWorkArea)).apply(to:&d);XCTAssertEqual(d,full)
    var still=try CraftDocument(width:4,height:3);XCTAssertThrowsError(try Command.video(.workspace(.trimToWorkArea)).apply(to:&still))
  }
  func testClippingBaseDependencyAndEmptyWorkAreaContent()throws {
    var d=try fixture();d.layers[0].video=nil;d.layers[0].videoTiming = .init(startTime:0,duration:0.5)
    var upper=Layer(name:"Clipped",content:.fill(.white));upper.clipped=true
    upper.videoTiming = .init(startTime:1,duration:1);d.layers.append(upper)
    try Command.video(.workspace(.trimToWorkArea)).apply(to:&d)
    XCTAssertEqual(d.layers.count,2);XCTAssertTrue(d.layers[1].isClipped);try d.validate()
    d=try fixture();d.layers[0].video=nil;d.layers[0].videoTiming = .init(startTime:0,duration:0.5)
    try Command.video(.workspace(.trimToWorkArea)).apply(to:&d)
    XCTAssertTrue(d.layers.isEmpty);XCTAssertNil(d.activeLayerID);try d.validate()
  }
  func testMovingTrimmedKeysPreservesHandlesAndAddingAudioExtendsOnlyNewMedia()throws {
    var d=try fixture();d.layers[0].video=nil;d.layers[0].content = .fill(.white)
    d.layers[0].videoTiming = .init(startTime:0,duration:4)
    d.layers[0].videoKeyframes=[.init(property:.opacity,time:0,layer:d.layers[0]),.init(property:.opacity,time:3,layer:d.layers[0])]
    try Command.video(.workspace(.trimToWorkArea)).apply(to:&d)
    let id=d.layers[0].id,keys=d.layers[0].videoKeyframes!
    try Command.video(.arrange(.stillTiming(id,startTime:-0.5,duration:4))).apply(to:&d)
    XCTAssertEqual(d.layers[0].videoKeyframes?.map(\.time),keys.map{$0.time+0.25})
    XCTAssertEqual(d.videoTimeline?.durationFrames,8)
    let source=TimelineAudioSource(data:Data([1]),duration:1)
    try Command.video(.audio(.importClip(nil,.init(name:"New",source:source,startTime:2)))).apply(to:&d)
    XCTAssertEqual(d.videoTimeline?.durationFrames,12)
  }
}
