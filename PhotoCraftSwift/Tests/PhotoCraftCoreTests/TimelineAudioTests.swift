import Foundation
import XCTest
@testable import PhotoCraftCore

final class TimelineAudioTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3);d.videoTimeline = .init(frameRate:4,durationFrames:4);return d
  }
  func clip()->TimelineAudioClip{.init(name:"Owned metadata fixture",source:.init(data:Data([1,2,3]),duration:2))}
  func testImportUndoNative56AndDeduplicatedSources()throws {
    let before=try fixture();var session=EditorSession(document:before);let value=clip()
    try session.execute(.video(.audio(.importClip(nil,value))));let after=session.document
    XCTAssertEqual(after.videoTimeline?.durationFrames,8);XCTAssertEqual(after.minimumArchiveVersion,56)
    XCTAssertGreaterThan(after.estimatedBytes,before.estimatedBytes)
    for data in [try NativeArchive.encode(after),try NativeArchive.encodeChunked(after)]{XCTAssertEqual(try NativeArchive.decode(data),after)}
    var old=try NativeArchive.encodeChunked(after);old[8]=55;XCTAssertThrowsError(try NativeArchive.decode(old))
    try session.undo();XCTAssertEqual(session.document,before);try session.redo();XCTAssertEqual(session.document,after)
    var copy=value;copy.id=UUID();try session.execute(.video(.audio(.insert(after.videoTimeline!.audioTracks![0].id,copy))))
    let bytes=try NativeArchive.encodeChunked(session.document);XCTAssertEqual(try NativeArchive.decode(bytes),session.document)
  }
  func testTrackMoveTrimSplitRetainSourceAndHistory()throws {
    var d=try fixture();let value=clip(),second=UUID()
    try Command.video(.audio(.importClip(nil,value))).apply(to:&d)
    try Command.video(.audio(.addTrack(second,"Music"))).apply(to:&d)
    var session=EditorSession(document:d)
    try session.execute(.video(.audio(.move(value.id,track:second,startTime:1))))
    try session.execute(.video(.audio(.trim(value.id,startTime:1,sourceIn:0.25,sourceOut:1.75))))
    try session.execute(.video(.audio(.split(value.id,1.5))))
    let clips=session.document.videoTimeline!.audioTracks![1].clips
    XCTAssertEqual(clips.count,2);XCTAssertEqual(clips.map(\.duration),[0.5,1])
    XCTAssertEqual(clips.map(\.sourceIn),[0.25,0.75]);XCTAssertEqual(clips.map(\.startTime),[1,1.5]);XCTAssertNotEqual(clips[0].id,clips[1].id)
    XCTAssertTrue(clips.allSatisfy{$0.source==value.source})
    try session.undo();try session.undo();try session.undo();XCTAssertEqual(session.document,d)
  }
  func testSettingsGainAndInvalidEditsAreAtomic()throws {
    var d=try fixture();let value=clip();try Command.video(.audio(.importClip(nil,value))).apply(to:&d)
    let settings=TimelineAudioSettings(volume:0.5,fadeIn:1,fadeOut:1)
    try Command.video(.audio(.settings(value.id,settings))).apply(to:&d)
    XCTAssertEqual(settings.gain(at:0,duration:2),0);XCTAssertEqual(settings.gain(at:0.5,duration:2),0.25)
    XCTAssertEqual(settings.gain(at:1,duration:2),0.5);XCTAssertEqual(settings.gain(at:1.5,duration:2),0.25);XCTAssertEqual(settings.gain(at:2,duration:2),0)
    let before=d,track=d.videoTimeline!.audioTracks![0].id
    let invalid:[TimelineAudioCommand]=[.settings(value.id,.init(volume:.nan)),.settings(value.id,.init(volume:2)),.settings(value.id,.init(fadeIn:-1)),.trim(value.id,startTime:0,sourceIn:2,sourceOut:1),.move(value.id,track:track,startTime:-1),.split(value.id,3),.addTrack(track,"Duplicate"),.renameTrack(track,"  "),.removeClip(UUID())]
    for command in invalid{XCTAssertThrowsError(try Command.video(.audio(command)).apply(to:&d));XCTAssertEqual(d,before)}
    XCTAssertThrowsError(try Command.video(.duration(2)).apply(to:&d));XCTAssertEqual(d,before)
  }
  func testMovieSettingsLockAndRemoval()throws {
    var d=try fixture();let frames=try [Pixel.black,.white].map{try Surface(width:4,height:3,fill:$0)}
    var video=VideoClip(frames:frames,frameRate:1);video.movie = .init(data:Data([1]),presentationTimes:[.init(value:0,timescale:1),.init(value:1,timescale:1)],endTime:.init(value:2,timescale:1),originalFrameRate:1,audioTracks:1)
    d.layers[0].video=video;try d.selectVideoFrame(0);let id=d.layers[0].id
    try Command.video(.audio(.movieSettings(id,.init(muted:true)))).apply(to:&d)
    XCTAssertTrue(d.layers[0].video!.audio!.muted);XCTAssertEqual(d.minimumArchiveVersion,56)
    var split=d;split.videoTimeline?.currentFrame=2
    try Command.video(.audio(.movieSettings(id,.init(fadeIn:0.25,fadeOut:0.25)))).apply(to:&split)
    try Command.video(.arrange(.split([id]))).apply(to:&split)
    XCTAssertEqual(split.layers[0].video?.audio?.fadeOut,0);XCTAssertEqual(split.layers[1].video?.audio?.fadeIn,0)
    d.layers[0].locked=true;let locked=d
    XCTAssertThrowsError(try Command.video(.audio(.movieSettings(id,.init()))).apply(to:&d));XCTAssertEqual(d,locked)
  }
  func testMalformedTracksAndNoTimelineReject()throws {
    var d=try fixture();let value=clip();d.videoTimeline?.audioTracks=[.init(name:"Track",clips:[value,value])];XCTAssertThrowsError(try d.validate())
    d.videoTimeline=nil;XCTAssertThrowsError(try Command.video(.audio(.importClip(nil,value))).apply(to:&d))
    var bad=TimelineAudioSource(data:Data(),duration:1);XCTAssertThrowsError(try bad.validate());bad.data=Data([1]);bad.duration = .infinity;XCTAssertThrowsError(try bad.validate())
  }
  func testExplicitTimelineRemovalDropsAudioAndUndoRestoresIt()throws {
    var d=try fixture();try Command.video(.audio(.importClip(nil,clip()))).apply(to:&d)
    var session=EditorSession(document:d);try session.execute(.video(.remove));XCTAssertNil(session.document.videoTimeline)
    try session.undo();XCTAssertEqual(session.document,d)
  }
}
