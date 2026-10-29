import AVFoundation
import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class VideoRenderTests:XCTestCase {
  func document(alpha:Bool=false)throws->CraftDocument {
    var d=try CraftDocument(width:32,height:24)
    var surface=try Surface(width:32,height:24,fill:.black)
    for y in 0..<24{for x in 0..<32{
      let p:Pixel = y<12 ? (x<16 ? Pixel(1,0,0):.white) : (x<16 ? Pixel(0,0,1):Pixel(0,1,0,alpha ? 0.5:1))
      surface.setPixel(x:x,y:y,p)
    }}
    d.layers[0].content = .raster(surface);d.videoTimeline = .init(frameRate:4,durationFrames:4);return d
  }
  func save(_ output:RenderedVideo,_ name:String)throws {
    if let path=ProcessInfo.processInfo.environment["PHOTATO_VIDEO_RENDER_OUTPUT_DIR"] {
      try output.publish(to:URL(fileURLWithPath:path).appendingPathComponent(name+"."+output.codec.fileExtension))
    }
  }
  func testUncompressedNarrowRowsPreserveEveryPixel()throws {
    let colors=[Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1),Pixel.clear]
    for width in [3,12,17,33] {
      var d=try CraftDocument(width:width,height:4),surface=try Surface(width:width,height:4)
      for y in 0..<4{for x in 0..<width{surface.setPixel(x:x,y:y,colors[(x+y)%4])}}
      d.layers[0].content = .raster(surface);d.videoTimeline = .init(frameRate:4,durationFrames:1)
      let output=try VideoRender.render(d,options:.init(codec:.uncompressed,preserveAlpha:true));defer{output.discard()}
      let movie=try MovieIO.read(output.url),frame=try XCTUnwrap(movie.layers[0].video?.frames.first)
      XCTAssertEqual(frame.width,width);XCTAssertEqual(frame.height,4)
      for y in 0..<4{for x in 0..<width{XCTAssertEqual(frame.pixel(x:x,y:y),colors[(x+y)%4],"width \(width), pixel \(x),\(y)")}}
      if let root=ProcessInfo.processInfo.environment["PHOTATO_WORKSPACE_OUTPUT_DIR"]{try output.publish(to:URL(fileURLWithPath:root).appendingPathComponent("raw-stride-\(width).mov"))}
    }
  }
  func testEveryNativeCodecDurationDimensionsAndIndependentFixtures()throws {
    let d=try document()
    for codec in VideoRenderCodec.allCases {
      let output=try VideoRender.render(d,options:.init(codec:codec,frameRate:8,firstFrame:1,lastFrame:2,includeAudio:false));defer{output.discard()}
      XCTAssertEqual(output.plan.frameCount,4);XCTAssertEqual(output.plan.duration,0.5);XCTAssertFalse(output.hasAudio)
      let asset=AVURLAsset(url:output.url),track=try XCTUnwrap(asset.tracks(withMediaType:.video).first)
      XCTAssertEqual(track.naturalSize,CGSize(width:32,height:24));XCTAssertEqual(track.timeRange.duration.seconds,0.5,accuracy:0.00001)
      let decoded=try MovieIO.read(output.url);XCTAssertEqual(decoded.layers[0].video?.frames.count,4)
      let frame=try XCTUnwrap(decoded.layers[0].video?.frames.first)
      XCTAssertGreaterThan(frame.pixel(x:4,y:4).r,0.95);XCTAssertLessThan(frame.pixel(x:4,y:4).b,0.05)
      XCTAssertGreaterThan(frame.pixel(x:4,y:20).b,0.95);XCTAssertLessThan(frame.pixel(x:4,y:20).r,0.05)
      try save(output,codec.rawValue)
    }
    XCTAssertEqual(d,try documentWithIDs(d))
  }
  func documentWithIDs(_ d:CraftDocument)throws->CraftDocument{try NativeArchive.decode(NativeArchive.encodeChunked(d))}
  func testAlphaRawAndProResAndOpaqueMatte()throws {
    let d=try document(alpha:true)
    for codec in [VideoRenderCodec.uncompressed,.proRes4444] {
      for alpha in [true,false] {
        let output=try VideoRender.render(d,options:.init(codec:codec,includeAudio:false,preserveAlpha:alpha));defer{output.discard()}
        let decoded=try MovieIO.read(output.url),frame=try XCTUnwrap(decoded.layers[0].video?.frames.first),p=frame.pixel(x:24,y:20)
        XCTAssertEqual(p.a,alpha ? 128.0/255:1,accuracy:0.012)
        if alpha{XCTAssertGreaterThan(p.g,0.96)}else{XCTAssertLessThan(p.g,0.85);XCTAssertGreaterThan(p.g,0.5)}
        try save(output,codec.rawValue+(alpha ? "-alpha":"-matte"))
      }
    }
  }
  func testExactTimeKeyframesTransitionsAndVariableAnimationDelay()throws {
    var d=try VideoTransitionRendererTests().fixture()
    let pixel=try Renderer.composite(d,videoTime:0.875).pixel(x:0,y:0)
    XCTAssertEqual(pixel.r,0.625,accuracy:0.00001);XCTAssertEqual(pixel.b,0.375,accuracy:0.00001)
    XCTAssertThrowsError(try Renderer.composite(d,videoTime:2));XCTAssertThrowsError(try Renderer.composite(d,videoTime:.nan))
    d.videoTimeline!.transitions=nil;d.layers.removeLast();d.activeLayerID=d.layers[0].id
    let id=d.layers[0].id;try Command.video(.keyframe(.enable(id,.opacity))).apply(to:&d)
    try d.selectVideoFrame(4);try Command.opacity(id,0).apply(to:&d)
    let snapshot=try d.videoCompositionSnapshot(at:0.125)
    XCTAssertEqual(snapshot.layers[0].opacity,0.875);XCTAssertNil(snapshot.videoTimeline);try snapshot.validate()
    var animation=try document();animation.videoTimeline=nil;animation.animation=FrameAnimation(layers:animation.layers)
    animation.animation!.frames[0].delay=0.125
    var second=AnimationFrame(layers:animation.layers);second.delay=0.375;animation.animation!.frames.append(second)
    let output=try VideoRender.render(animation,options:.init(codec:.uncompressed,frameRate:8,includeAudio:false));defer{output.discard()}
    XCTAssertEqual(output.plan.frameCount,4);XCTAssertEqual(output.plan.duration,0.5);try save(output,"frame-animation")
    let range=try VideoRenderOptions(codec:.uncompressed,frameRate:8,firstFrame:1).plan(for:animation)
    XCTAssertEqual(range.sourceStart,0.125);XCTAssertEqual(range.frameCount,3)
  }
  func testRangeAudioPCMAndAAC()throws {
    var d=try document()
    let url=Bundle.module.url(forResource:"owned-stereo",withExtension:"wav",subdirectory:"Fixtures/audio")!
    let source=try TimelineAudioIO.read(url).0
    try Command.video(.audio(.importClip(nil,.init(name:"Owned stereo",source:source,startTime:0)))).apply(to:&d)
    for codec in [VideoRenderCodec.uncompressed,.h264] {
      let output=try VideoRender.render(d,options:.init(codec:codec,firstFrame:1,lastFrame:2));defer{output.discard()}
      XCTAssertTrue(output.hasAudio)
      let pcm=try TimelineAudioIO.decode(Data(contentsOf:output.url)).1
      XCTAssertEqual(pcm.frames,24000)
      XCTAssertEqual(pcm.samples[10000],0.25,accuracy:codec == .uncompressed ? 0:0.02)
      XCTAssertEqual(pcm.samples[10001],-0.5,accuracy:codec == .uncompressed ? 0:0.02)
      try save(output,codec.rawValue+"-audio")
    }
    let tail=try XCTUnwrap(TimelineAudioMixer.render(d,startTime:0.75,duration:0.5))
    XCTAssertEqual(tail.frames,24000);XCTAssertEqual(tail.samples[0],0.25);XCTAssertEqual(tail.samples.last,0)
  }
  func testResizeAndExportedTransitionAtNonSourceRate()throws {
    let resized=try VideoRender.render(document(),options:.init(codec:.uncompressed,width:64,height:48,includeAudio:false));defer{resized.discard()}
    let decoded=try MovieIO.read(resized.url);XCTAssertEqual(decoded.width,64);XCTAssertEqual(decoded.height,48)
    let first=try XCTUnwrap(decoded.layers[0].video?.frames.first);XCTAssertGreaterThan(first.pixel(x:8,y:8).r,0.99);XCTAssertGreaterThan(first.pixel(x:8,y:40).b,0.99)
    let d=try VideoTransitionRendererTests().fixture()
    let output=try VideoRender.render(d,options:.init(codec:.uncompressed,frameRate:8,firstFrame:2,lastFrame:3,includeAudio:false));defer{output.discard()}
    let movie=try MovieIO.read(output.url),frames=try XCTUnwrap(movie.layers[0].video?.frames)
    XCTAssertEqual(frames.count,4)
    // Exact 0.625s evaluates a 12.5% blend instead of snapping to the 0.5s source frame.
    XCTAssertEqual(frames[1].pixel(x:1,y:1).r,0.875,accuracy:0.012)
    XCTAssertEqual(frames[1].pixel(x:1,y:1).b,0.125,accuracy:0.012)
  }
  func testPlanRationalRateBoundsBudgetAndCancellation()async throws {
    let d=try document()
    let plan=try VideoRenderOptions(frameRate:30000.0/1001).plan(for:d)
    XCTAssertEqual(plan.rateNumerator,30000);XCTAssertEqual(plan.rateDenominator,1001)
    XCTAssertEqual(plan.timestamp(30000).seconds,1001,accuracy:1e-9)
    for bad in [VideoRenderOptions(width:31),.init(firstFrame:4),.init(lastFrame:-1),.init(frameRate:.infinity),.init(preserveAlpha:true),.init(codec:.proRes422,bitRate:1_000_000),.init(width:8192,height:8192)]{XCTAssertThrowsError(try bad.plan(for:d))}
    var malformed=d;malformed.videoTimeline!.frameRate=0
    XCTAssertThrowsError(try VideoRenderOptions().plan(for:malformed))
    XCTAssertThrowsError(try VideoRender.render(d,options:.init(),maximumBytes:10))
    let worker=Task.detached{while !Task.isCancelled{await Task.yield()};return try VideoRender.render(d,options:.init())};worker.cancel()
    do{let output=try await worker.value;output.discard();XCTFail("Cancelled video succeeded")}catch is CancellationError{}
  }
}
