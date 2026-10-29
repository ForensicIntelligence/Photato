import Foundation
import XCTest
@testable import PhotoCraftCore

final class VideoTransitionTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3)
    var a=Layer(name:"Red",content:.fill(Pixel(1,0,0))),b=Layer(name:"Blue",content:.fill(Pixel(0,0,1)))
    a.videoTiming = .init(startTime:0,duration:1);b.videoTiming = .init(startTime:1,duration:1)
    d.layers=[a,b];d.activeLayerID=b.id;d.videoTimeline = .init(frameRate:4,durationFrames:8);try d.validate();return d
  }
  func cross(_ d:CraftDocument,duration:Double=1)->VideoTransition {.init(layerID:d.layers[1].id,previousLayerID:d.layers[0].id,kind:.crossFade,duration:duration)}
  func testTransitionSetUpdateDeleteUndoAndNative55()throws {
    var session=EditorSession(document:try fixture());let before=session.document
    var transition=cross(before)
    try session.execute(.video(.transition(.set(transition))));let after=session.document
    XCTAssertEqual(after.minimumArchiveVersion,55)
    let bytes=try NativeArchive.encodeChunked(after);XCTAssertEqual(bytes[8],55);XCTAssertEqual(try NativeArchive.decode(bytes),after)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(after)),after)
    var old=bytes;old[8]=54;XCTAssertThrowsError(try NativeArchive.decode(old))
    try session.undo();XCTAssertEqual(session.document,before);try session.redo();XCTAssertEqual(session.document,after)
    transition.duration=0.5;try session.execute(.video(.transition(.set(transition))))
    XCTAssertEqual(session.document.videoTimeline?.transitions?.count,1)
    try session.execute(.video(.transition(.remove(transition.id))));XCTAssertNil(session.document.videoTimeline?.transitions)
    try session.undo();XCTAssertEqual(session.document.videoTimeline?.transitions?.first?.duration,0.5)
  }
  func testInvalidPartnersDurationColorsOverlapAndLocksAreAtomic()throws {
    var d=try fixture();let before=d
    let invalid:[VideoTransition]=[
      cross(d,duration:3),cross(d,duration:.nan),.init(layerID:d.layers[0].id,previousLayerID:d.layers[1].id,kind:.crossFade,duration:1),
      .init(layerID:d.layers[0].id,kind:.color,duration:1,color:Pixel(1,0,0,0.5)),
      .init(layerID:d.layers[0].id,kind:.fade,duration:1,color:.black),
      .init(layerID:UUID(),kind:.fade,duration:1)]
    for t in invalid{XCTAssertThrowsError(try Command.video(.transition(.set(t))).apply(to:&d));XCTAssertEqual(d,before)}
    let first=VideoTransition(layerID:d.layers[0].id,kind:.fade,duration:0.6)
    try Command.video(.transition(.set(first))).apply(to:&d);let valid=d
    XCTAssertThrowsError(try Command.video(.transition(.set(.init(layerID:d.layers[0].id,kind:.fade,edge:.end,duration:0.5)))).apply(to:&d));XCTAssertEqual(d,valid)
    d.layers[0].locked=true;let locked=d
    var replacement=first;replacement.layerID=d.layers[1].id
    XCTAssertThrowsError(try Command.video(.transition(.set(replacement))).apply(to:&d));XCTAssertEqual(d,locked)
    XCTAssertThrowsError(try Command.video(.transition(.remove(first.id))).apply(to:&d));XCTAssertEqual(d,locked)
  }
  func testReorderDeletionAndTrimReconcileWithUndo()throws {
    var d=try fixture();let ids=d.layers.map(\.id)
    try Command.video(.arrange(.group("Track",ids))).apply(to:&d);let group=d.activeLayerID!
    try Command.video(.transition(.set(cross(d)))).apply(to:&d)
    var session=EditorSession(document:d)
    try session.execute(.video(.arrange(.stillTiming(ids[0],startTime:0,duration:0.25))))
    XCTAssertEqual(session.document.videoTimeline?.transitions?.first?.duration,0.5)
    XCTAssertEqual(session.document.layers[1].videoTiming?.startTime,0.25)
    try session.undo();XCTAssertEqual(session.document,d)
    try session.execute(.video(.arrange(.move(ids[1],group:group,position:0))))
    XCTAssertNil(session.document.videoTimeline?.transitions);try session.undo();XCTAssertEqual(session.document,d)
    try session.execute(.deleteLayer(ids[0]));XCTAssertNil(session.document.videoTimeline?.transitions)
    try session.undo();XCTAssertEqual(session.document,d)
  }
  func testOpposingFadesShortenTogetherWhenClipShrinks()throws {
    var d=try fixture();let id=d.layers[0].id
    for edge in VideoTransitionEdge.allCases {try Command.video(.transition(.set(.init(layerID:id,kind:.fade,edge:edge,duration:0.4)))).apply(to:&d)}
    try Command.video(.arrange(.stillTiming(id,startTime:0,duration:0.5))).apply(to:&d)
    XCTAssertEqual(d.videoTimeline?.transitions?.map(\.duration),[0.25,0.25]);try d.validate()
  }
  func testSplitTransfersOutgoingTransitionAndCrossfadePartner()throws {
    var d=try fixture();let a=d.layers[0].id,b=d.layers[1].id
    try Command.video(.transition(.set(cross(d,duration:0.5)))).apply(to:&d)
    let end=VideoTransition(layerID:b,kind:.black,edge:.end,duration:0.25)
    try Command.video(.transition(.set(end))).apply(to:&d)
    try d.selectVideoFrame(2);try Command.video(.arrange(.split([a]))).apply(to:&d)
    let splitA=d.activeLayerID!;XCTAssertEqual(d.videoTimeline?.transitions?.first?.previousLayerID,splitA)
    try d.selectVideoFrame(6);try Command.video(.arrange(.split([b]))).apply(to:&d)
    XCTAssertEqual(d.videoTimeline?.transitions?.first{$0.id==end.id}?.layerID,d.activeLayerID)
    try d.validate()
  }
  func testExactTrimAndMediaHandlesForVariableRateSource()throws {
    var d=try VideoArrangementTests().fixture(movie:true);let id=d.layers[0].id
    try Command.video(.arrange(.trim(id,startTime:1,sourceIn:0.75,sourceOut:2.25))).apply(to:&d)
    let clip=d.layers[0].video!
    XCTAssertEqual(clip.duration,0.75);XCTAssertEqual(clip.extendedSourceIndex(at:0),0)
    XCTAssertEqual(clip.extendedSourceIndex(at:1),1);XCTAssertEqual(clip.extendedSourceIndex(at:2),2)
    XCTAssertEqual(clip.extendedSourceIndex(at:200),2)
    let before=d;XCTAssertThrowsError(try Command.video(.arrange(.trim(id,startTime:1,sourceIn:2,sourceOut:1))).apply(to:&d));XCTAssertEqual(d,before)
  }
  func testMoveOutOfTrackAndTimeIsOneTransaction()throws {
    var d=try fixture();let id=d.layers[0].id
    try Command.video(.arrange(.group("Track",d.layers.map(\.id)))).apply(to:&d)
    var session=EditorSession(document:d)
    try session.execute(.video(.arrange(.move(id,group:nil,position:0,startTime:3))))
    XCTAssertNil(session.document.layers[0].parentID);XCTAssertEqual(session.document.layers[0].videoTiming?.startTime,3)
    XCTAssertEqual(session.undoStack.count,1);try session.undo();XCTAssertEqual(session.document,d)
  }
  func testDuplicateWholeTrackRetainsIndependentTransitions()throws {
    var d=try fixture();let ids=d.layers.map(\.id)
    try Command.video(.arrange(.group("Track",ids))).apply(to:&d);let group=d.activeLayerID!
    try Command.video(.transition(.set(cross(d)))).apply(to:&d)
    var session=EditorSession(document:d)
    try session.execute(.duplicateLayer(group))
    let result=session.document,copy=try XCTUnwrap(result.activeLayerID)
    let transitions=try XCTUnwrap(result.videoTimeline?.transitions)
    XCTAssertEqual(transitions.count,2);XCTAssertNotEqual(transitions[0].id,transitions[1].id)
    XCTAssertTrue(transitions[0].participants.isDisjoint(with:transitions[1].participants))
    XCTAssertTrue(transitions[1].participants.isSubset(of:result.subtreeIDs(copy)))
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
    try session.undo();XCTAssertEqual(session.document,d)
    try session.redo();XCTAssertEqual(session.document,result)
  }
  func testDuplicatingClipBreaksOldBoundaryAtomically()throws {
    var d=try fixture();let ids=d.layers.map(\.id)
    try Command.video(.arrange(.group("Track",ids))).apply(to:&d)
    try Command.video(.transition(.set(cross(d)))).apply(to:&d)
    var session=EditorSession(document:d)
    try session.execute(.duplicateLayer(ids[0]))
    XCTAssertNil(session.document.videoTimeline?.transitions)
    XCTAssertEqual(session.document.layers.first{$0.id==ids[1]}?.videoTiming?.startTime,2)
    try session.undo();XCTAssertEqual(session.document,d)
  }

}
