import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class MovieIOTests:XCTestCase {
  func fixture(_ name:String="owned-vfr-audio") -> URL {Bundle.module.url(forResource:name,withExtension:"mov",subdirectory:"Fixtures/movies")!}
  func testNativeDecodePreservesVariableTimesOriginalAudioAndAllFrames() throws {
    let url=fixture(),bytes=try Data(contentsOf:url),d=try MovieIO.read(url),clip=try XCTUnwrap(d.layers[0].video),movie=try XCTUnwrap(clip.movie)
    XCTAssertFalse(MovieIO.recognizes(Data([0,0,0,20]+Array("ftypcrx ".utf8))))
    XCTAssertEqual(movie.data,bytes);XCTAssertEqual(movie.audioTracks,1);XCTAssertEqual(d.layers.count,1);XCTAssertEqual(d.width,16);XCTAssertEqual(d.height,12);XCTAssertEqual(d.depth,.u16);XCTAssertEqual(clip.frames.count,4)
    for (actual,expected) in zip(movie.presentationTimes.map(\.seconds),[0.0,0.12,0.32,0.40]){XCTAssertEqual(actual,expected,accuracy:1e-9)}
    XCTAssertEqual(movie.endTime.seconds,0.44,accuracy:1e-9)
    XCTAssertEqual(clip.sourceIndex(at:0.119),0);XCTAssertEqual(clip.sourceIndex(at:0.12),1);XCTAssertEqual(clip.sourceIndex(at:0.319),1);XCTAssertEqual(clip.sourceIndex(at:0.32),2);XCTAssertNil(clip.sourceIndex(at:0.44))
    for (i,color) in [Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1),Pixel(0,0,1)].enumerated(){
      let surface=clip.frames[i];XCTAssertEqual(surface.pixel(x:5,y:5),color)
      XCTAssertEqual(surface.pixel(x:0,y:0),.white);XCTAssertEqual(surface.pixel(x:15,y:11).a,128.0/255,accuracy:2.0/65535)
      if let dir=ProcessInfo.processInfo.environment["PHOTATO_MOVIE_OUTPUT_DIR"] {try RasterIO.encoded(surface,type:.png).write(to:URL(fileURLWithPath:dir).appendingPathComponent("movie-\(i).png"))}
    }
    XCTAssertEqual(d.minimumArchiveVersion,52)
    for data in [try NativeArchive.encode(d),try NativeArchive.encodeChunked(d)] {let decoded=try NativeArchive.decode(data);XCTAssertEqual(decoded,d)}
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d,minimumVersion:51)),d)
    XCTAssertEqual(try Data(contentsOf:url),bytes)
  }
  func testOrientationBudgetCorruptionAndTrim() throws {
    let d=try MovieIO.read(fixture("owned-rotated"));XCTAssertEqual(d.width,12);XCTAssertEqual(d.height,16)
    let frame=d.layers[0].video!.frames[0]
    XCTAssertEqual(frame.pixel(x:0,y:15),.white)
    XCTAssertEqual(frame.pixel(x:11,y:0).a,128.0/255,accuracy:2.0/65535)
    for i in 0..<4 {if let dir=ProcessInfo.processInfo.environment["PHOTATO_MOVIE_OUTPUT_DIR"] {try RasterIO.encoded(d.layers[0].video!.frames[i],type:.png).write(to:URL(fileURLWithPath:dir).appendingPathComponent("rotated-\(i).png"))}}
    XCTAssertThrowsError(try MovieIO.read(fixture("owned-too-many")))
    XCTAssertThrowsError(try MovieIO.read(fixture(),maximumBytes:1024))
    XCTAssertThrowsError(try MovieIO.read(fixture(),maximumPixels:100))
    XCTAssertThrowsError(try MovieIO.decode(Data("bogus movie".utf8),name:"Invalid"))
    var clip=try MovieIO.read(fixture()).layers[0].video!;let rate=clip.frameRate
    clip.inFrame=1;clip.outFrame=3;clip.frameRate=rate*2;clip.startTime=1
    XCTAssertEqual(clip.duration,0.14,accuracy:1e-9);XCTAssertEqual(clip.sourceIndex(at:1.099),1);XCTAssertEqual(clip.sourceIndex(at:1.10),2);XCTAssertNil(clip.sourceIndex(at:1.14))
    clip.movie!.presentationTimes[1]=clip.movie!.presentationTimes[0];XCTAssertThrowsError(try clip.validate(depth:.u16))
  }
  func testCancellationAndPlacementConversionAreAtomic() async throws {
    let url=fixture();let task=Task.detached{while !Task.isCancelled {await Task.yield()};return try MovieIO.read(url)};task.cancel()
    do{_=try await task.value;XCTFail("Cancelled read succeeded")}catch is CancellationError{}
    let movie=try MovieIO.read(url),target=try CraftDocument(width:32,height:24,depth:.u8)
    let layer=try MovieIO.layer(from:movie,into:target);XCTAssertEqual(layer.x,8);XCTAssertEqual(layer.y,6);XCTAssertEqual(layer.video!.frames[0].depth,.u8)
    var session=EditorSession(document:target);try session.execute(.video(.insert(layer)));let after=session.document
    XCTAssertEqual(after.layers.count,2);XCTAssertEqual(after.activeLayerID,layer.id);try after.validate()
    try session.undo();XCTAssertEqual(session.document,target);try session.redo();XCTAssertEqual(session.document,after)
  }
  func testOrdinaryH264MP4DecodesEveryPresentationFrameAndRetainsAAC() throws {
    let url=Bundle.module.url(forResource:"owned-h264",withExtension:"mp4",subdirectory:"Fixtures/movies")!,data=try Data(contentsOf:url)
    let d=try MovieIO.read(url),clip=try XCTUnwrap(d.layers[0].video),source=try XCTUnwrap(clip.movie)
    XCTAssertEqual(d.width,128);XCTAssertEqual(d.height,96);XCTAssertEqual(clip.frames.count,4);XCTAssertEqual(source.audioTracks,1);XCTAssertEqual(source.data,data)
    for (actual,expected) in zip(source.presentationTimes.map(\.seconds),[0.0,0.12,0.32,0.40]){XCTAssertEqual(actual,expected,accuracy:1e-9)}
    for i in 0..<4 {let pixel=clip.frames[i].pixel(x:60,y:40);let primary=i==0 ? pixel.r : i==1 ? pixel.g : pixel.b;XCTAssertGreaterThan(primary,0.9);XCTAssertEqual(pixel.a,1)}
    XCTAssertEqual(source.endTime.seconds,0.44,accuracy:1e-9)
  }

}
