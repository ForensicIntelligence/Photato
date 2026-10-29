import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class MovieFramesTests: XCTestCase {
  func bytes(_ name: String = "owned-vfr-audio") throws -> Data {try Data(contentsOf:MovieIOTests().fixture(name))}
  func testEveryFrameBecomesEditableLayerWithExactVariableDelays() throws {
    let data = try bytes(),original = try MovieIO.decode(data,name:"Original"),frames = try XCTUnwrap(original.layers[0].video).frames
    let result = try MovieFrames.decode(data,name:"Frames",options:.init()),animation = try XCTUnwrap(result.animation)
    XCTAssertEqual(result.layers.count,4);XCTAssertNil(result.videoTimeline);XCTAssertTrue(result.layers.allSatisfy{$0.video == nil});XCTAssertEqual(result.depth,.u16)
    for i in frames.indices {
      guard case .raster(let pixels) = result.layers[i].content else {return XCTFail("Missing editable pixels")}
      XCTAssertEqual(pixels,frames[i]);XCTAssertEqual(animation.frames[i].sourceVideoFrame,i)
      XCTAssertEqual(animation.frames[i].delay,[0.12,0.20,0.08,0.04][i],accuracy:1e-9)
      let preview = try result.animationDocument(at:animation.frames[i].id)
      XCTAssertEqual(preview.layers.filter(\.visible).map(\.id),[result.layers[i].id])
      if let dir = ProcessInfo.processInfo.environment["PHOTATO_MOVIE_FRAMES_OUTPUT"] {
        let root = URL(fileURLWithPath:dir);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try RasterIO.encoded(preview).write(to:root.appendingPathComponent("frame-\(i).png"))
      }
    }
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
    var session = EditorSession(document:result)
    try session.execute(.renameLayer(result.layers[1].id,"Editable frame"));try session.undo();XCTAssertEqual(session.document,result)
    XCTAssertEqual(try bytes(),data)
  }
  func testSelectedRangesIntervalsAndStillLayers() throws {
    let data = try bytes();var options = MovieFrameImportOptions();options.every = 2
    let sparse = try MovieFrames.decode(data,name:"Every second",options:options)
    XCTAssertEqual(sparse.layers.count,2);XCTAssertEqual(sparse.animation?.frames.map(\.sourceVideoFrame),[0,2])
    XCTAssertEqual(sparse.animation!.frames[0].delay,0.32,accuracy:1e-9);XCTAssertEqual(sparse.animation!.frames[1].delay,0.12,accuracy:1e-9)
    options.selectedRange = true;options.start = 0.12;options.end = 0.40
    let selected = try MovieFrames.decode(data,name:"Range",options:options)
    XCTAssertEqual(selected.layers.count,1);XCTAssertEqual(selected.animation?.frames.first?.sourceVideoFrame,1);XCTAssertEqual(selected.animation!.frames[0].delay,0.28,accuracy:1e-9)
    options.start = 0.13;options.every = 1;options.makeAnimation = false
    let still = try MovieFrames.decode(data,name:"Layers",options:options)
    XCTAssertNil(still.animation);XCTAssertEqual(still.layers.count,1);XCTAssertEqual(try Renderer.composite(still).pixel(x:5,y:5),Pixel(0,0,1))
    XCTAssertEqual(try PSDCodec.read(PSDCodec.writeRasterLayers(still)).layers.count,1)
  }
  func testSubsamplingHappensBeforeTheDecodedFrameLimit() throws {
    let data = try bytes("owned-too-many");var options = MovieFrameImportOptions();options.every = 9
    let limited = try MovieFrames.decode(data,name:"Long movie subset",options:options,maximumLayers:64)
    XCTAssertGreaterThan(limited.layers.count,1);XCTAssertLessThanOrEqual(limited.layers.count,64)
    XCTAssertTrue(limited.animation!.frames.allSatisfy{($0.sourceVideoFrame ?? -1)%9 == 0})
    options.every = 1;XCTAssertThrowsError(try MovieFrames.decode(data,name:"Too many",options:options))
  }
  func testOrientationBudgetsInvalidSelectionAndCancellation() async throws {
    let data = try bytes("owned-rotated"),result = try MovieFrames.decode(data,name:"Rotated",options:.init())
    XCTAssertEqual(result.width,12);XCTAssertEqual(result.height,16)
    guard case .raster(let pixels) = result.layers[0].content else{return XCTFail("Missing frame")}
    XCTAssertEqual(pixels.pixel(x:0,y:15),.white)
    XCTAssertThrowsError(try MovieFrames.decode(data,name:"Small budget",options:.init(),maximumBytes:1024))
    XCTAssertThrowsError(try MovieFrames.decode(data,name:"Layer limit",options:.init(),maximumLayers:2))
    var bad = MovieFrameImportOptions();bad.every = 0;XCTAssertThrowsError(try bad.validate());bad.every = 1;bad.start = .nan;XCTAssertThrowsError(try bad.validate())
    bad.start = 10;bad.end = 11;bad.selectedRange = true;XCTAssertThrowsError(try MovieFrames.decode(data,name:"Outside",options:bad))
    let task = Task.detached {while !Task.isCancelled {await Task.yield()};return try MovieFrames.decode(data,name:"Cancelled",options:.init())};task.cancel()
    do {_ = try await task.value;XCTFail("Cancelled import returned a document")} catch is CancellationError {}
    let info = try MovieFrames.info(MovieIOTests().fixture("owned-rotated"));XCTAssertEqual(info.width,12);XCTAssertEqual(info.height,16);XCTAssertEqual(info.duration,0.44,accuracy:1e-9)
  }
}
