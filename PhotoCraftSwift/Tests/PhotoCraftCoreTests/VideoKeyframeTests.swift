import Foundation
import XCTest
@testable import PhotoCraftCore

final class VideoKeyframeTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:16,height:12)
    let layer=Layer(name:"Animated",content:.raster(try Surface(width:2,height:2,fill:Pixel(1,0,0))))
    d.layers=[layer];d.activeLayerID=layer.id;try Command.video(.create(frameRate:4,durationFrames:9)).apply(to:&d);return d
  }
  func testIndependentTracksAutoCaptureSeekAndHistory()throws {
    var s=EditorSession(document:try fixture());let id=s.document.layers[0].id
    for p in [VideoProperty.position,.opacity]{try s.execute(.video(.keyframe(.enable(id,p))))}
    try s.selectVideoFrame(8);try s.execute(.move(id,8,4));try s.execute(.opacity(id,0))
    let after=s.document
    XCTAssertEqual(after.layers[0].videoKeyframes?.count,4)
    try s.undo();XCTAssertEqual(s.document.layers[0].opacity,1);try s.redo();XCTAssertEqual(s.document,after)
    let history=s.undoStack.count;try s.selectVideoFrame(4)
    XCTAssertEqual(s.document.layers[0].x,4);XCTAssertEqual(s.document.layers[0].y,2);XCTAssertEqual(s.document.layers[0].opacity,0.5)
    XCTAssertEqual(s.undoStack.count,history);try s.document.validate()
    try s.execute(.opacity(id,0.25));XCTAssertEqual(s.document.layers[0].videoKeyframes?.count,5)
    try s.execute(.opacity(id,0.75));XCTAssertEqual(s.document.layers[0].videoKeyframes?.count,5)
    try s.selectVideoFrame(2);XCTAssertEqual(s.document.layers[0].opacity,0.875)
  }
  func testSubpixelPositionAndHoldSwitchAtExactKey()throws {
    var s=EditorSession(document:try fixture());let id=s.document.layers[0].id
    try s.execute(.video(.keyframe(.enable(id,.position))));try s.selectVideoFrame(8);try s.execute(.move(id,3,-3))
    try s.selectVideoFrame(4);XCTAssertEqual(s.document.layers[0].coordinateTransform.tx,1.5);XCTAssertEqual(s.document.layers[0].coordinateTransform.ty,-1.5)
    let key=s.document.layers[0].videoKeyframes![0].id
    try s.execute(.video(.keyframe(.interpolation(id,key,.hold))));XCTAssertEqual(s.document.layers[0].x,0)
    try s.selectVideoFrame(7);XCTAssertEqual(s.document.layers[0].x,0)
    try s.selectVideoFrame(8);XCTAssertEqual(s.document.layers[0].x,3);XCTAssertEqual(s.document.layers[0].y,-3)
  }
  func testTransformAnimationKeepsSourceAndInterpolatesRotationScale()throws {
    var s=EditorSession(document:try fixture());let id=s.document.layers[0].id,source=s.document.layers[0].content
    try s.execute(.video(.keyframe(.enable(id,.transform))));try s.selectVideoFrame(8)
    try s.execute(.transform(id,.translation(8,4) * .rotation(90) * .scale(3,3),.bicubic))
    XCTAssertEqual(s.document.layers[0].content,source)
    try s.selectVideoFrame(4);let m=s.document.layers[0].coordinateTransform
    XCTAssertEqual(m.a,sqrt(2),accuracy:1e-12);XCTAssertEqual(m.b,sqrt(2),accuracy:1e-12);XCTAssertEqual(m.c,-sqrt(2),accuracy:1e-12);XCTAssertEqual(m.d,sqrt(2),accuracy:1e-12);XCTAssertEqual(m.tx,4);XCTAssertEqual(m.ty,2)
    for frame in [8,0,7,1,8,0] {try s.selectVideoFrame(frame);try s.document.validate();XCTAssertEqual(s.document.layers[0].content,source)}
    XCTAssertEqual(s.document.layers[0].coordinateTransform,.identity)
  }
  func testTransformShortestRotationAndReflectionHold()throws {
    var layer=try fixture().layers[0];layer.affine = .rotation(170)
    let a=VideoKeyframe(property:.transform,time:0,layer:layer);layer.affine = .rotation(-170)
    let b=VideoKeyframe(property:.transform,time:2,layer:layer)
    let m=try XCTUnwrap(VideoKeyframe.evaluate([a,b],property:.transform,time:1)?.geometry?.matrix)
    XCTAssertEqual(m.a,-1,accuracy:1e-12);XCTAssertEqual(m.b,0,accuracy:1e-12)
    layer.affine = .scale(-1,1);let c=VideoKeyframe(property:.transform,time:2,layer:layer)
    XCTAssertEqual(try VideoKeyframe.evaluate([a,c],property:.transform,time:1)?.geometry,a.geometry)
    XCTAssertEqual(try VideoKeyframe.evaluate([a,c],property:.transform,time:2)?.geometry,c.geometry)
  }
  func testStyleAutomaticKeysInterpolateAndNilEndpointIsExact()throws {
    var s=EditorSession(document:try fixture());let id=s.document.layers[0].id
    try s.execute(.video(.keyframe(.enable(id,.style))));try s.selectVideoFrame(8)
    var effect=LayerEffect(.colorOverlay);effect.color=Pixel(0,0,1)
    let style=LayerStyle(effects:[effect]);try s.execute(.layerStyle([id],style))
    try s.selectVideoFrame(4);XCTAssertEqual(s.document.layers[0].style?.effects[0].opacity,0.5)
    try s.selectVideoFrame(0);XCTAssertNil(s.document.layers[0].style)
    try s.selectVideoFrame(8);XCTAssertEqual(s.document.layers[0].style,style)
    effect.color=Pixel(1,0,0);effect.size=13
    try s.selectVideoFrame(0);try s.execute(.layerStyle([id],LayerStyle(effects:[effect])))
    try s.selectVideoFrame(4);let middle=try XCTUnwrap(s.document.layers[0].style?.effects[0])
    XCTAssertEqual(middle.color,Pixel(0.5,0,0.5));XCTAssertEqual(middle.size,9)
  }
  func testMoveDeleteDisableAndGeometryTrackReplacement()throws {
    var s=EditorSession(document:try fixture());let id=s.document.layers[0].id
    try s.execute(.video(.keyframe(.enable(id,.opacity))));try s.selectVideoFrame(8);try s.execute(.opacity(id,0))
    let keys=s.document.layers[0].videoKeyframes!,before=s.document
    XCTAssertThrowsError(try s.execute(.video(.keyframe(.move(id,keys[1].id,0)))));XCTAssertEqual(s.document,before)
    try s.execute(.video(.keyframe(.move(id,keys[1].id,1))));try s.selectVideoFrame(2);XCTAssertEqual(s.document.layers[0].opacity,0.5)
    try s.execute(.video(.keyframe(.disable(id,.opacity))));XCTAssertNil(s.document.layers[0].videoKeyframes)
    try s.selectVideoFrame(0);XCTAssertEqual(s.document.layers[0].opacity,0.5)
    try s.execute(.video(.keyframe(.enable(id,.position))));try s.execute(.video(.keyframe(.enable(id,.transform))))
    XCTAssertEqual(s.document.layers[0].videoKeyframes?.map(\.property),[.transform])
    let last=s.document.layers[0].videoKeyframes![0].id;try s.execute(.video(.keyframe(.delete(id,last))));XCTAssertNil(s.document.layers[0].videoKeyframes)
  }
  func testNative53PreservesInterpolatedPlayheadAndRejectsDowngrade()throws {
    var s=EditorSession(document:try fixture());let id=s.document.layers[0].id
    try s.execute(.video(.keyframe(.enable(id,.position))));try s.selectVideoFrame(8);try s.execute(.move(id,7,3));try s.selectVideoFrame(3)
    let d=s.document;XCTAssertEqual(d.minimumArchiveVersion,53)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
    let bytes=try NativeArchive.encodeChunked(d);XCTAssertEqual(bytes[8],53);XCTAssertEqual(try NativeArchive.decode(bytes),d)
    var old=bytes;old[8]=52;XCTAssertThrowsError(try NativeArchive.decode(old))
    try s.execute(.video(.remove));XCTAssertNil(s.document.videoTimeline);XCTAssertNil(s.document.layers[0].videoKeyframes)
    XCTAssertEqual(s.document.layers[0].coordinateTransform,d.layers[0].coordinateTransform)
    try s.undo();XCTAssertEqual(s.document,d)
  }
  func testTimelineDurationRateAndLoopKeepChosenLength()throws {
    var s=EditorSession(document:try fixture());let id=s.document.layers[0].id
    try s.execute(.video(.duration(40)));try s.execute(.video(.loop(false)));XCTAssertEqual(s.document.videoTimeline?.durationFrames,40)
    try s.execute(.video(.frameRate(8)));XCTAssertEqual(s.document.videoTimeline?.durationFrames,80)
    try s.execute(.video(.keyframe(.set(id,.opacity,12))));XCTAssertEqual(s.document.videoTimeline?.durationFrames,97)
    let before=s.document;XCTAssertThrowsError(try s.execute(.video(.duration(96))));XCTAssertEqual(s.document,before)
  }
  func testVideoTransformRetainsAllFramesAndCurrentFramePainting()throws {
    var d=try VideoTimelineTests().fixture();let id=d.layers[0].id,frames=d.layers[0].video!.frames
    try Command.video(.keyframe(.enable(id,.transform))).apply(to:&d)
    try d.selectVideoFrame(2);try Command.transform(id,.scale(2,2),.bicubic).apply(to:&d)
    XCTAssertEqual(d.layers[0].video!.frames,frames)
    try Command.fill(id,.white).apply(to:&d);XCTAssertEqual(d.layers[0].video!.frames[0],frames[0]);XCTAssertEqual(d.layers[0].video!.frames[1],frames[1]);XCTAssertEqual(d.layers[0].video!.frames[2].pixel(x:0,y:0),.white)
    try d.selectVideoFrame(0);XCTAssertEqual(d.layers[0].coordinateTransform,.identity)
    XCTAssertThrowsError(try Command.video(.remove).apply(to:&d))
  }
  func testMalformedKeysAndLockedEditsRejectAtomically()throws {
    var d=try fixture();let id=d.layers[0].id,before=d
    for edit in [VideoKeyframeCommand.set(id,.opacity,.nan),.set(id,.opacity,-1),.set(id,.opacity,86401),.delete(id,UUID()),.move(id,UUID(),1)] {XCTAssertThrowsError(try Command.video(.keyframe(edit)).apply(to:&d));XCTAssertEqual(d,before)}
    d.layers[0].locked=true;let locked=d;XCTAssertThrowsError(try Command.video(.keyframe(.enable(id,.opacity))).apply(to:&d));XCTAssertEqual(d,locked)
    d=before;let key=VideoKeyframe(property:.opacity,time:0,layer:d.layers[0]);d.layers[0].videoKeyframes=[key,key];XCTAssertThrowsError(try d.validate())
    d.layers[0].videoKeyframes=[key];d.layers[0].videoKeyframes![0].opacity=2;XCTAssertThrowsError(try d.validate())
    d.layers[0].videoKeyframes=[key];d.layers[0].videoKeyframes![0].time=3;XCTAssertThrowsError(try d.validate())
    d.layers[0].videoKeyframes=[key];d.videoTimeline=nil;XCTAssertThrowsError(try d.validate())
  }
  func testLinkedAndUnlinkedMasksRemainInTheirCoordinateSpaces()throws {
    for linked in [true,false] {
      var d=try fixture();d.layers[0].mask=try Surface(width:2,height:2,fill:.white)
      d.layers[0].maskProperties=MaskProperties();d.layers[0].maskProperties!.linked=linked
      var s=EditorSession(document:d);let id=d.layers[0].id
      try s.execute(.video(.keyframe(.enable(id,.transform))));try s.selectVideoFrame(8);try s.execute(.transform(id,.translation(8,4) * .scale(2,2),.bicubic))
      for frame in [4,0,8,0] {
        try s.selectVideoFrame(frame);let layer=s.document.layers[0]
        XCTAssertEqual(layer.maskCoordinateTransform,linked ? layer.coordinateTransform:.identity);XCTAssertEqual(layer.mask,d.layers[0].mask)
      }
    }
  }
}
