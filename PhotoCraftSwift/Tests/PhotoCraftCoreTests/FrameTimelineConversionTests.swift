import XCTest
@testable import PhotoCraftCore

final class FrameTimelineConversionTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width: 8, height: 6)
    d.layers[0].content = .raster(try Surface(width: 2, height: 2, fill: Pixel(1,0,0)))
    var animation = FrameAnimation(layers: d.layers)
    var first = AnimationFrame(layers: d.layers, delay: 0.25)
    var second = AnimationFrame(layers: d.layers, delay: 0.5)
    second.layers[0].x = 3; second.layers[0].opacity = 0.5
    var effect = LayerEffect(.colorOverlay); effect.color = Pixel(0,0,1)
    second.layers[0].style = LayerStyle(effects: [effect])
    var third = AnimationFrame(layers: d.layers, delay: 0.25)
    third.layers[0].visible = false
    first.layers[0].visible = true
    animation.frames = [first,second,third]; animation.selectedFrameID = first.id; animation.loopCount = 3
    d.animation = animation; try d.selectAnimationFrame(first.id); return d
  }
  func testEditableTracksDurationLoopHistoryAndNative59() throws {
    let source = try fixture(); var session = EditorSession(document: source)
    try session.execute(.animation(.convertToVideo(4)))
    let d = session.document
    XCTAssertNil(d.animation); XCTAssertEqual(d.videoTimeline?.durationFrames,4)
    XCTAssertEqual(d.videoTimeline?.finiteLoopCount,3)
    XCTAssertEqual(d.layers[0].content,source.layers[0].content)
    XCTAssertEqual(Set(d.layers[0].videoKeyframes!.map(\.property)),Set([.transform,.opacity,.style,.visibility]))
    for frame in 0..<4 {
      let snapshot = try d.videoDocument(at:frame)
      let index = [0,1,1,2][frame]
      let expected = try source.animationDocument(at:source.animation!.frames[index].id)
      XCTAssertEqual(AnimationLayerState(snapshot.layers[0]),AnimationLayerState(expected.layers[0]))
      XCTAssertEqual(snapshot.layers[0].content,expected.layers[0].content)
    }
    XCTAssertEqual(d.minimumArchiveVersion,59)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
    var data = try NativeArchive.encodeChunked(d); XCTAssertEqual(data[8],59)
    XCTAssertEqual(try NativeArchive.decode(data),d); data[8] = 58
    XCTAssertThrowsError(try NativeArchive.decode(data))
    try session.undo(); XCTAssertEqual(session.document,source)
    try session.redo(); XCTAssertEqual(session.document,d)
    XCTAssertFalse(try d.videoTimeline!.playbackFrame(elapsed:2.99).finished)
    XCTAssertTrue(try d.videoTimeline!.playbackFrame(elapsed:3).finished)
    try session.execute(.video(.loop(true))); XCTAssertNil(session.document.videoTimeline?.finiteLoopCount)
  }
  func testVisibilityIsHoldAndConvertedTracksRemainEditable() throws {
    var session = EditorSession(document:try fixture().convertingFrameAnimation(frameRate:8))
    let id = session.document.layers[0].id
    try session.selectVideoFrame(7); XCTAssertFalse(session.document.layers[0].visible)
    try session.execute(.visibility(id,true))
    XCTAssertTrue(session.document.layers[0].visible)
    let key = try XCTUnwrap(session.document.layers[0].videoKeyframes?.first{$0.property == .visibility})
    let before = session.document
    XCTAssertThrowsError(try session.execute(.video(.keyframe(.interpolation(id,key.id,.linear)))))
    XCTAssertEqual(session.document,before)
    try session.selectVideoFrame(6); XCTAssertFalse(session.document.layers[0].visible)
    try session.selectVideoFrame(7); XCTAssertTrue(session.document.layers[0].visible)
    try session.execute(.video(.keyframe(.disable(id,.visibility))))
    XCTAssertFalse(session.document.layers[0].videoKeyframes!.contains{$0.property == .visibility})
  }
  func testFractionalAndZeroDelaySamplingSelectedFrameAndBounds() throws {
    var source = try fixture(); source.animation!.frames[0].delay = 0
    source.animation!.frames[1].delay = 0.13; source.animation!.frames[2].delay = 0.2
    try source.selectAnimationFrame(source.animation!.frames[1].id)
    let d = try source.convertingFrameAnimation(frameRate:10)
    XCTAssertEqual(d.videoTimeline?.durationFrames,4); XCTAssertEqual(d.videoTimeline?.currentFrame,1)
    XCTAssertEqual(d.layers[0].videoKeyframes?.filter{$0.property == .transform}.map(\.time),[0,0.02,0.15])
    for rate in [0.0,241,.nan,.infinity] {XCTAssertThrowsError(try source.convertingFrameAnimation(frameRate:rate))}
    XCTAssertThrowsError(try CraftDocument(width:4,height:3).convertingFrameAnimation(frameRate:30))
    for count in [1,3] {
      source.animation!.loopCount=count
      let converted=try source.convertingFrameAnimation(frameRate:10),timeline=converted.videoTimeline!
      XCTAssertEqual(timeline.currentFrame,1)
      XCTAssertFalse(try timeline.playbackFrame(elapsed:0.4*Double(count)-0.001).finished)
      let end=try timeline.playbackFrame(elapsed:0.4*Double(count))
      XCTAssertTrue(end.finished);XCTAssertEqual(end.frame,0)
    }
  }
  func testConvertedGroupPlacementPreservesTreeAndSharedMasks() throws {
    var d = try CraftDocument(width:8,height:6)
    d.layers[0].mask = try Surface(width:8,height:6,fill:Pixel(0.5,0.5,0.5))
    let child = d.layers[0].id
    try Command.newGroup(.init(name:"Group"),children:[child],below:false).apply(to:&d)
    var animation = FrameAnimation(layers:d.layers)
    var next = AnimationFrame(layers:d.layers,delay:0.25)
    next.layers[next.layers.count-1].x = 2
    animation.frames[0].delay = 0.25; animation.frames.append(next)
    d.animation = animation; let original = d
    let converted = try d.convertingFrameAnimation(frameRate:4)
    XCTAssertEqual(converted.layers.map(\.parentID),original.layers.map(\.parentID))
    XCTAssertEqual(converted.layers[0].mask,original.layers[0].mask)
    XCTAssertEqual(try converted.videoDocument(at:1).layers.last?.x,2)
  }
}
