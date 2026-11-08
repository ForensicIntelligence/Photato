import Foundation
import XCTest
@testable import PhotoCraftCore

final class VideoFrameConversionTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try VideoTimelineTests().fixture()
    d.videoTimeline!.frameRate=4;d.videoTimeline!.durationFrames=6
    let clip=TimelineAudioClip(name:"Retained metadata audio",source:.init(data:Data([1,2,3]),duration:1.5))
    d.videoTimeline!.audioTracks=[.init(name:"Audio",clips:[clip])]
    try d.selectVideoFrame(3);return d
  }
  func testSampledContentSourceAudioAndNative60()throws {
    let original=try fixture(),d=try original.convertingVideoToFrameAnimation()
    XCTAssertNil(d.videoTimeline);XCTAssertEqual(d.animation?.frames.count,6)
    XCTAssertEqual(d.animation?.selectedIndex,3);XCTAssertEqual(d.layers.map(\.id),original.layers.map(\.id))
    for i in 0..<6 {
      let sample=try d.animationDocument(at:d.animation!.frames[i].id)
      XCTAssertEqual(sample.layers[0].content,try original.videoDocument(at:i).layers[0].content)
      XCTAssertEqual(d.animation!.frames[i].delay,0.25)
    }
    XCTAssertEqual(try d.restoringFrameVideoSource(),original)
    XCTAssertEqual(d.minimumArchiveVersion,60)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
    var bytes=try NativeArchive.encodeChunked(d);XCTAssertEqual(bytes[8],60)
    XCTAssertEqual(try NativeArchive.decode(bytes),d);bytes[8]=59;XCTAssertThrowsError(try NativeArchive.decode(bytes))
    let back=try d.convertingFrameAnimation(frameRate:4)
    XCTAssertEqual(back.videoTimeline?.audioTracks,original.videoTimeline?.audioTracks)
    XCTAssertEqual(back.videoTimeline?.durationFrames,6)
    XCTAssertEqual(try back.restoringFrameVideoSource(),original)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(back)),back)
    for i in 0..<6 {XCTAssertEqual(try back.videoDocument(at:i).layers[0].content,try original.videoDocument(at:i).layers[0].content)}
  }
  func testPaintingOneSampleUndoAndFrameReorder()throws {
    let original=try fixture();var session=EditorSession(document:try original.convertingVideoToFrameAnimation())
    let before=session.document,id=before.layers[0].id,selected=before.animation!.selectedFrameID
    try session.execute(.fill(id,.white));let painted=session.document
    XCTAssertEqual(try painted.animationDocument(at:painted.animation!.frames[2].id).layers[0].content,try before.animationDocument(at:before.animation!.frames[2].id).layers[0].content)
    XCTAssertNotEqual(painted.layers[0].content,before.layers[0].content)
    XCTAssertEqual(try painted.restoringFrameVideoSource(),original)
    try session.undo();XCTAssertEqual(session.document,before);try session.redo();XCTAssertEqual(session.document,painted)
    try session.execute(.animation(.reverse));XCTAssertEqual(session.document.animation?.selectedFrameID,selected)
    XCTAssertEqual(session.document.layers[0].content,painted.layers[0].content)
    try session.document.validate()
  }
  func testUnsupportedCapacityAndMalformedPayloadAreRejected()throws {
    var source=try fixture();source.videoTimeline!.durationFrames=513
    XCTAssertThrowsError(try source.convertingVideoToFrameAnimation())
    var converted=try fixture().convertingVideoToFrameAnimation()
    converted.animation!.frames[0].layers[0].payload!.mask=nil
    converted.animation!.frames[0].layers[0].payload!.maskProperties = .init()
    XCTAssertThrowsError(try converted.validate())
    XCTAssertThrowsError(try CraftDocument(width:2,height:2).convertingVideoToFrameAnimation())
  }
  func testCommandsRoundTripRecoveryHistoryAndReorderedAudio()throws {
    let original=try fixture();var session=EditorSession(document:original)
    try session.execute(.animation(.convertFromVideo));let frames=session.document
    try session.execute(.animation(.convertToVideo(4)));let back=session.document
    XCTAssertEqual(try back.restoringFrameVideoSource(),original)
    try session.undo();XCTAssertEqual(session.document,frames)
    try session.redo();XCTAssertEqual(session.document,back)
    try session.execute(.animation(.restoreVideoSource));XCTAssertEqual(session.document,original)
    try session.undo();XCTAssertEqual(session.document,back)
    try session.execute(.animation(.convertFromVideo))
    try session.execute(.animation(.reverse));let reordered=session.document
    try session.execute(.animation(.convertToVideo(4)))
    XCTAssertNil(session.document.videoTimeline?.audioTracks)
    XCTAssertEqual(try session.document.restoringFrameVideoSource(),original)
    for i in 0..<6 {XCTAssertEqual(try session.document.videoDocument(at:i).layers[0].content,try reordered.animationDocument(at:reordered.animation!.frames[i].id).layers[0].content)}
  }
  func testHighFrameRateTimingContentCaptureAndInvalidKeys()throws {
    var original=try fixture();original.videoTimeline!.frameRate=60;original.videoTimeline!.durationFrames=60;original.videoTimeline!.audioTracks=nil
    try original.selectVideoFrame(3)
    let frames=try original.convertingVideoToFrameAnimation()
    XCTAssertEqual(frames.animation!.playbackDelay(at:0),1.0/60)
    XCTAssertEqual(try frames.animation!.playbackFrame(elapsed:0.05,startingAt:0).index,3)
    var session=EditorSession(document:try frames.convertingFrameAnimation(frameRate:60))
    XCTAssertEqual(session.document.videoTimeline?.durationFrames,60)
    let id=session.document.layers[0].id
    try session.execute(.fill(id,.white))
    let painted=session.document
    try session.selectVideoFrame(0)
    XCTAssertNotEqual(session.document.layers[0].content,painted.layers[0].content)
    try session.selectVideoFrame(3);XCTAssertEqual(session.document.layers[0].content,painted.layers[0].content)
    let key=try XCTUnwrap(painted.layers[0].videoKeyframes?.first{$0.property == .content})
    XCTAssertThrowsError(try session.execute(.video(.keyframe(.interpolation(id,key.id,.linear)))))
    var nested=painted
    nested.videoTimeline!.retainedFrameSources![0].timeline.retainedFrameSources=painted.videoTimeline!.retainedFrameSources
    XCTAssertThrowsError(try nested.validate())
  }

  func testRepeatedRateConversionKeepsCurrentSoundtrackAndEarliestOriginal()throws {
    let original=try fixture(),first=try original.convertingVideoToFrameAnimation().convertingFrameAnimation(frameRate:8)
    XCTAssertEqual(first.videoTimeline?.durationFrames,12)
    let secondFrames=try first.convertingVideoToFrameAnimation(),second=try secondFrames.convertingFrameAnimation(frameRate:8)
    XCTAssertEqual(second.videoTimeline?.audioTracks,first.videoTimeline?.audioTracks)
    XCTAssertEqual(secondFrames.animation?.sampledTimeline?.frameRate,8)
    XCTAssertEqual(try second.restoringFrameVideoSource(),original)
    var reordered=secondFrames;try Command.animation(.reverse).apply(to:&reordered)
    let silent=try reordered.convertingFrameAnimation(frameRate:8)
    XCTAssertNil(silent.videoTimeline?.audioTracks)
    let again=try silent.convertingVideoToFrameAnimation().convertingFrameAnimation(frameRate:8)
    XCTAssertNil(again.videoTimeline?.audioTracks,"Repeated conversion must not reactivate the original soundtrack after a retiming.")
    XCTAssertEqual(try again.restoringFrameVideoSource(),original)
  }

  func testSamplingRejectsOversizedPayloadBeforeCompletingSequence()throws {
    var d=try CraftDocument(width:1024,height:1024)
    let pixels=try [Pixel(1,0,0),Pixel(0,0,1)].map { color in
      var surface=try Surface(width:1024,height:1024,fill:color)
      for y in stride(from:0,to:1024,by:64) {for x in stride(from:0,to:1024,by:64) {surface.setPixel(x:x,y:y,.white)}}
      return surface
    }
    d.layers[0].video = .init(frames:pixels,frameRate:1)
    d.videoTimeline = .init(frameRate:60,durationFrames:128);try d.selectVideoFrame(0)
    try d.validate()
    XCTAssertGreaterThan(pixels[0].allocatedBytes*128+d.estimatedBytes,1_073_741_824)
    XCTAssertThrowsError(try d.convertingVideoToFrameAnimation()) {error in
      XCTAssertTrue(error.localizedDescription.contains("1 GiB"))
    }
    XCTAssertNil(d.animation);XCTAssertEqual(d.layers[0].video?.frames,VideoFrames(pixels))
  }

}
