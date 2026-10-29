import XCTest
@testable import PhotoCraftCore

final class TimelineWorkspaceTests:XCTestCase {
  func document()throws->CraftDocument{var d=try CraftDocument(width:12,height:4);d.videoTimeline = .init(frameRate:4,durationFrames:8);return d}
  func testWorkAreaPlaybackInsideOutsideLoopAndStop()throws {
    var t=VideoTimeline(frameRate:4,durationFrames:8);t.workArea = .init(startFrame:2,endFrame:6)
    XCTAssertEqual(t.playbackStartFrame,2);XCTAssertEqual(try t.playbackFrame(elapsed:0).frame,2)
    XCTAssertEqual(try t.playbackFrame(elapsed:0.75).frame,5);XCTAssertEqual(try t.playbackFrame(elapsed:1).frame,2)
    t.currentFrame=4;XCTAssertEqual(try t.playbackFrame(elapsed:0).frame,4);XCTAssertEqual(try t.playbackFrame(elapsed:0.5).frame,2)
    t.looping=false;let end=try t.playbackFrame(elapsed:0.5);XCTAssertTrue(end.finished);XCTAssertEqual(end.frame,5)
    t.currentFrame=7;XCTAssertEqual(try t.playbackFrame(elapsed:0.25).frame,3)
    t.workArea = .init(startFrame:4,endFrame:4);XCTAssertThrowsError(try t.validate())
  }
  func testCommandsHistoryRescaleClampAndReset()throws {
    var session=EditorSession(document:try document());let original=session.document
    try session.execute(.video(.workspace(.workArea(.init(startFrame:1,endFrame:3)))))
    let area=session.document;try session.undo();XCTAssertEqual(session.document,original);try session.redo();XCTAssertEqual(session.document,area)
    try session.execute(.video(.frameRate(10)));XCTAssertEqual(session.document.videoTimeline?.workArea,.init(startFrame:2,endFrame:8))
    try session.execute(.video(.duration(5)));XCTAssertEqual(session.document.videoTimeline?.workArea,.init(startFrame:2,endFrame:5))
    try session.execute(.video(.duration(1)));XCTAssertEqual(session.document.videoTimeline?.workArea,.init(startFrame:0,endFrame:1))
    try session.execute(.video(.workspace(.workArea(nil))));XCTAssertNil(session.document.videoTimeline?.workArea)
    let before=session.document;XCTAssertThrowsError(try session.execute(.video(.workspace(.workArea(.init(startFrame:-1,endFrame:1))))));XCTAssertEqual(session.document,before)
  }
  func testOnionSamplingSpacingOpacityEdgesAndValidation()throws {
    var settings=OnionSkinSettings(enabled:true,framesBefore:3,framesAfter:2,spacing:2,minimumOpacity:0.1,maximumOpacity:0.5,blendMode:.normal)
    let samples=try settings.samples(currentFrame:6,durationFrames:12)
    XCTAssertEqual(samples.map(\.frame),[0,2,10,4,8]);for (actual,expected) in zip(samples.map(\.opacity),[Float(0.1),0.3,0.1,0.5,0.5]){XCTAssertEqual(actual,expected,accuracy:0.00001)}
    XCTAssertEqual(try settings.samples(currentFrame:0,durationFrames:3).map(\.frame),[2])
    settings.framesBefore=0;settings.framesAfter=0;XCTAssertTrue(try settings.samples(currentFrame:0,durationFrames:1).isEmpty)
    settings.spacing=0;XCTAssertThrowsError(try settings.validate());settings.spacing=1;settings.minimumOpacity = .nan;XCTAssertThrowsError(try settings.validate())
  }
  func testNative57RoundtripAndDowngradeRejection()throws {
    var d=try document();XCTAssertEqual(d.minimumArchiveVersion,51)
    try Command.video(.workspace(.workArea(.init(startFrame:1,endFrame:5)))).apply(to:&d)
    try Command.video(.workspace(.onionSkin(.init(enabled:true)))).apply(to:&d)
    XCTAssertEqual(d.minimumArchiveVersion,57);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
    var bytes=try NativeArchive.encodeChunked(d);XCTAssertEqual(bytes[8],57);XCTAssertEqual(try NativeArchive.decode(bytes),d)
    bytes[8]=56;XCTAssertThrowsError(try NativeArchive.decode(bytes))
    try Command.video(.workspace(.workArea(nil))).apply(to:&d);try Command.video(.workspace(.onionSkin(nil))).apply(to:&d);XCTAssertEqual(d.minimumArchiveVersion,51)
  }
}
