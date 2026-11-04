import Foundation
import XCTest
@testable import PhotoCraftCore

final class FitImageTests: XCTestCase {
  func fixture(_ width: Int = 8, _ height: Int = 4, depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: width, height: height, depth: depth)
    let layer = Layer(name: "Owned white", content: .raster(try Surface(width: width, height: height, depth: depth, fill: .white)))
    d.layers = [layer]; d.activeLayerID = layer.id; return d
  }
  func testIndependentBoundingBoxDimensionsAndMaximumLogicalGeometry() throws {
    let cases: [(Int, Int, Int, Int, Bool, Int, Int)] = [
      (8,4,6,6,false,6,3), (4,8,6,6,false,3,6), (8,4,12,3,false,6,3),
      (2,1,6,6,false,6,3), (2,1,6,6,true,2,1), (8,4,20,3,true,6,3),
      (4,5,2,5,false,2,3), (5,4,5,2,false,3,2), (8,4,7,7,false,7,4),
      (300000,1,1,300000,false,1,1), (1,300000,300000,1,false,1,1),
      (300000,300000,300000,300000,false,300000,300000), (1,1,300000,300000,true,1,1)]
    for (w,h,bw,bh,small,ew,eh) in cases {
      let size = try FitImageOptions(width:bw,height:bh,dontEnlarge:small).dimensions(sourceWidth:w,sourceHeight:h)
      XCTAssertEqual(size.width,ew); XCTAssertEqual(size.height,eh)
      XCTAssertLessThanOrEqual(size.width,bw); XCTAssertLessThanOrEqual(size.height,bh)
    }
    for w in 1...17 { for h in 1...17 { for bound in 1...11 {
      let size = try FitImageOptions(width:bound,height:12-bound).dimensions(sourceWidth:w,sourceHeight:h)
      XCTAssertTrue((1...bound).contains(size.width)); XCTAssertTrue((1...(12-bound)).contains(size.height))
    } } }
  }
  func testAllDepthsUseImageSizeAndRetainResolutionChannelsMasksAndHistory() throws {
    for depth in [PixelDepth.u8,.u16,.f32] {
      var source = try fixture(depth:depth); source.resolution = 240
      source.layers[0].mask = try Surface(width:8,height:4,depth:depth,fill:Pixel(0.25,0.25,0.25))
      source.alphaChannels = [AlphaChannel(name:"Owned saved",pixels:try Surface(width:8,height:4,depth:depth,fill:Pixel(0.5,0.5,0.5)))]
      source.selection = .init(x:0,y:0,width:4,height:4)
      let options = FitImageOptions(width:6,height:6,method:.nearest)
      var expected = source; try Command.imageSize(6,3,240,.nearest).apply(to:&expected)
      var session = EditorSession(document:source); try session.execute(.fitImage(options))
      XCTAssertEqual(session.document,expected); XCTAssertEqual(session.document.resolution,240)
      XCTAssertEqual(session.document.layers.map(\.id),source.layers.map(\.id))
      XCTAssertEqual(session.document.alphaChannels?.first?.id,source.alphaChannels?.first?.id)
      XCTAssertEqual(session.document.layers[0].mask?.width,6); XCTAssertEqual(session.document.alphaChannels?.first?.pixels.height,3)
      XCTAssertEqual(session.undoStack.count,1); XCTAssertEqual(session.undoStack.last?.label,"Fit Image")
      try session.undo(); XCTAssertEqual(session.document,source)
      try session.redo(); XCTAssertEqual(session.document,expected)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(session.document)),session.document)
    }
  }
  func testNoOpIsExactAndStillRecordsReusableConstraint() throws {
    let source = try fixture(2,1); var session = EditorSession(document:source)
    let options = FitImageOptions(width:6,height:6,dontEnlarge:true,method:.nearest)
    try session.startActionRecording(name:"Fit mixed photos")
    try session.execute(.fitImage(options))
    XCTAssertEqual(session.document,source); XCTAssertNil(session.document.resolution)
    XCTAssertTrue(session.undoStack.isEmpty); XCTAssertTrue(session.redoStack.isEmpty)
    let action = try XCTUnwrap(session.actionRecording?.snapshot); XCTAssertEqual(action.steps.count,1)
    guard case .fitImage(let recorded) = action.steps[0].operation else { return XCTFail("Semantic fit operation required") }
    XCTAssertEqual(recorded,options)
    for (w,h,ew,eh) in [(24,12,6,3),(12,24,3,6),(2,1,2,1)] {
      var document = try fixture(w,h); let before = document
      try action.apply(to:&document); XCTAssertEqual(document.width,ew); XCTAssertEqual(document.height,eh)
      XCTAssertNil(document.resolution); XCTAssertEqual(document.id,before.id)
    }
  }
  func testDefaultResolutionRepresentationAndPortableActionRoundTrip() throws {
    let source = try fixture(); var session = EditorSession(document:source)
    try session.startActionRecording(name:"Fit")
    try session.execute(.fitImage(.init(width:6,height:6,method:.nearest)))
    XCTAssertNil(session.document.resolution); XCTAssertEqual(session.document.pixelsPerInch,72)
    let action = try XCTUnwrap(session.actionRecording?.snapshot)
    let copy = try JSONDecoder().decode(RecordedAction.self,from:JSONEncoder().encode(action))
    let target = try fixture(4,8); var playback = EditorSession(document:target)
    try playback.execute(.action(copy)); XCTAssertEqual(playback.document.width,3); XCTAssertEqual(playback.document.height,6)
    XCTAssertEqual(playback.undoStack.count,1); try playback.undo(); XCTAssertEqual(playback.document,target)
  }
  func testInvalidAndUnsupportedInputsRejectWithoutMutationOrHistory() throws {
    let source = try fixture(); var session = EditorSession(document:source)
    for options in [FitImageOptions(width:0),.init(width:-1),.init(height:300001)] {
      XCTAssertThrowsError(try session.execute(.fitImage(options))); XCTAssertEqual(session.document,source); XCTAssertTrue(session.undoStack.isEmpty)
      XCTAssertThrowsError(try RecordedAction(name:"Invalid",steps:[.init(name:"Fit",operation:.fitImage(options))]).validate())
    }
    for video in [true,false] {
      var d = source
      if video { try Command.video(.create(frameRate:4,durationFrames:9)).apply(to:&d) }
      else { try Command.animation(.create).apply(to:&d) }
      let original = d
      XCTAssertThrowsError(try Command.fitImage(.init(width:8,height:8,dontEnlarge:true)).apply(to:&d))
      XCTAssertEqual(d,original)
    }
  }
}
