import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class VideoFrameConversionRendererTests:XCTestCase {
  func fixture(depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3,depth:depth)
    var a=Layer(name:"Red",content:.fill(Pixel(1,0,0))),b=Layer(name:"Blue",content:.fill(Pixel(0,0,1)))
    a.videoTiming = .init(startTime:0,duration:1);b.videoTiming = .init(startTime:1,duration:1)
    d.layers=[a,b];d.activeLayerID=b.id;d.videoTimeline = .init(frameRate:4,durationFrames:8)
    try Command.video(.transition(.set(.init(layerID:b.id,previousLayerID:a.id,kind:.crossFade,duration:1)))).apply(to:&d)
    return d
  }
  func testCrossfadeRetainsEveryRenderedSampleAtAllDepths()throws {
    for depth in [PixelDepth.u8,.u16,.f32] {
      let original=try fixture(depth:depth),converted=try original.convertingVideoToFrameAnimation()
      let back=try converted.convertingFrameAnimation(frameRate:4)
      XCTAssertEqual(converted.layers.count,original.layers.count)
      for i in 0..<8 {
        XCTAssertEqual(try Renderer.composite(converted.animationDocument(at:converted.animation!.frames[i].id)),try Renderer.composite(original.videoDocument(at:i)))
        XCTAssertEqual(try Renderer.composite(back.videoDocument(at:i)),try Renderer.composite(original.videoDocument(at:i)))
      }
      XCTAssertEqual(try converted.restoringFrameVideoSource(),original)
    }
  }
  func testMovieSamplesGeometryMasksAndStyle()throws {
    var d=try CraftDocument(width:4,height:3)
    let pixels=try [Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1)].map{try Surface(width:2,height:2,fill:$0)}
    var layer=Layer(name:"Clip",content:.raster(pixels[0]));layer.video = .init(frames:pixels,frameRate:2)
    layer.mask=try Surface(width:2,height:2,fill:Pixel(0.5,0.5,0.5))
    var end=layer;end.x=2;end.y=1
    layer.videoKeyframes=[.init(property:.position,time:0,layer:layer),.init(property:.position,time:1,layer:end)]
    d.layers=[layer];d.activeLayerID=layer.id;d.videoTimeline = .init(frameRate:4,durationFrames:6)
    let converted=try d.convertingVideoToFrameAnimation()
    let back=try converted.convertingFrameAnimation(frameRate:4)
    for i in 0..<6 {XCTAssertEqual(try Renderer.composite(back.videoDocument(at:i)),try Renderer.composite(d.videoDocument(at:i)));XCTAssertEqual(try Renderer.composite(converted.animationDocument(at:converted.animation!.frames[i].id)),try Renderer.composite(d.videoDocument(at:i)))}
  }
  func testIndependentCrossfadePNGs()throws {
    let d=try fixture().convertingVideoToFrameAnimation(),back=try d.convertingFrameAnimation(frameRate:4)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_REVERSE_OUTPUT_DIR"] {
      for i in 0..<8 {
        let pixels=try Renderer.composite(d.animationDocument(at:d.animation!.frames[i].id))
        try ClipboardRenderer.imageData(pixels,type:.png).write(to:URL(fileURLWithPath:root).appendingPathComponent("reverse-\(i).png"))
        try ClipboardRenderer.imageData(Renderer.composite(back.videoDocument(at:i)),type:.png).write(to:URL(fileURLWithPath:root).appendingPathComponent("roundtrip-\(i).png"))
      }
    }
  }
  func testTrimmedSampledTransitionsAndParticipantRemoval()throws {
    let original=try fixture()
    var back=try original.convertingVideoToFrameAnimation().convertingFrameAnimation(frameRate:4)
    try Command.video(.workspace(.workArea(.init(startFrame:3,endFrame:6)))).apply(to:&back)
    try Command.video(.workspace(.trimToWorkArea)).apply(to:&back)
    for i in 0..<3 {XCTAssertEqual(try Renderer.composite(back.videoDocument(at:i)),try Renderer.composite(original.videoDocument(at:i+3)))}
    XCTAssertEqual(try back.restoringFrameVideoSource(),original)
    try Command.deleteLayer(back.layers[0].id).apply(to:&back)
    XCTAssertTrue(back.videoTimeline!.frameTransitionKeys!.allSatisfy{$0.states.isEmpty})
    try back.validate()
  }
  func testRetainedMovieAudioRateAndTrimRoundTrip()throws {
    let helper=TimelineAudioIOTests(),data=try Data(contentsOf:helper.fixture())
    let surfaces=try [Pixel.black,.white].map{try Surface(width:4,height:3,fill:$0)}
    var clip=VideoClip(frames:surfaces,frameRate:4)
    clip.movie = .init(data:data,presentationTimes:[.init(value:0,timescale:2),.init(value:1,timescale:2)],endTime:.init(value:2,timescale:2),originalFrameRate:2,audioTracks:1)
    clip.startTime = -0.25;clip.audio = .init(fadeOut:0.25)
    var d=try CraftDocument(width:4,height:3);d.videoTimeline = .init(frameRate:4,durationFrames:2)
    d.videoTimeline!.trimmedToWorkArea=true;d.layers[0].video=clip;try d.selectVideoFrame(0)
    let frames=try d.convertingVideoToFrameAnimation(),back=try frames.convertingFrameAnimation(frameRate:4)
    XCTAssertNil(try TimelineAudioMixer.render(frames))
    XCTAssertEqual(try TimelineAudioMixer.render(back),try TimelineAudioMixer.render(d))
    XCTAssertEqual(back.videoTimeline?.audioTracks?.first?.clips.first?.effectiveRate,2)
    let faster=try frames.convertingFrameAnimation(frameRate:8)
    let repeated=try faster.convertingVideoToFrameAnimation().convertingFrameAnimation(frameRate:8)
    XCTAssertEqual(try TimelineAudioMixer.render(repeated),try TimelineAudioMixer.render(d))
    if let root=ProcessInfo.processInfo.environment["PHOTATO_REVERSE_OUTPUT_DIR"] {
      try TimelineAudioMixer.render(back)?.wave().write(to:URL(fileURLWithPath:root).appendingPathComponent("reverse-audio.wav"))
    }
    var split=back;let id=try XCTUnwrap(split.videoTimeline?.audioTracks?.first?.clips.first?.id)
    try Command.video(.audio(.split(id,-0.125))).apply(to:&split)
    XCTAssertEqual(split.videoTimeline?.audioTracks?.first?.clips.last?.sourceIn,0.25)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(back)),back)
  }

  func testGradientPatternAndVectorMasksRetainEditableSamples()throws {
    for original in [try GradientFillRenderTests().fixture(.u8),try PatternFillRenderTests().fixture(.u8)] {
      var d=original;let id=d.layers.last!.id,i=d.layers.count-1
      d.layers[i].vectorMask=VectorMask(path:VectorPath(components:[PathComponent(knots:[PathKnot(.init(4,4)),PathKnot(.init(60,4)),PathKnot(.init(60,44)),PathKnot(.init(4,44))],closed:true)]))
      d.videoTimeline = .init(frameRate:4,durationFrames:5)
      var session=EditorSession(document:d)
      try session.execute(.video(.keyframe(.enable(id,.position))))
      try session.selectVideoFrame(4);try session.execute(.move(id,8,4));try session.selectVideoFrame(1)
      let video=session.document,frames=try video.convertingVideoToFrameAnimation(),back=try frames.convertingFrameAnimation(frameRate:4)
      XCTAssertNotNil(frames.animation?.frames[0].layers[i].payload)
      for frame in 0..<5 {
        let sample=try frames.animationDocument(at:frames.animation!.frames[frame].id)
        XCTAssertEqual(sample.layers[i].content,try video.videoDocument(at:frame).layers[i].content)
        XCTAssertEqual(try Renderer.composite(sample),try Renderer.composite(video.videoDocument(at:frame)))
        XCTAssertEqual(try Renderer.composite(back.videoDocument(at:frame)),try Renderer.composite(video.videoDocument(at:frame)))
      }
    }
  }
  func testSixtyFPSAnimationMovieExportPreservesDurationAndSamples()throws {
    var video=try CraftDocument(width:32,height:24)
    let colors=[Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1),Pixel.white]
    let surfaces=try colors.map{try Surface(width:32,height:24,fill:$0)}
    video.layers[0].video = .init(frames:surfaces,frameRate:60)
    video.videoTimeline = .init(frameRate:60,durationFrames:4);try video.selectVideoFrame(0)
    let frames=try video.convertingVideoToFrameAnimation()
    let output=try VideoRender.render(frames,options:.init(codec:.uncompressed,frameRate:60,includeAudio:false));defer{output.discard()}
    XCTAssertEqual(output.plan.frameCount,4);XCTAssertEqual(output.plan.duration,4.0/60,accuracy:1e-12)
    let decoded=try MovieIO.read(output.url),samples=try XCTUnwrap(decoded.layers[0].video?.frames)
    XCTAssertEqual(samples.count,4)
    for i in samples.indices {for y in 0..<24 {for x in 0..<32 {XCTAssertEqual(samples[i].pixel(x:x,y:y),colors[i])}}}
    if let root=ProcessInfo.processInfo.environment["PHOTATO_REVERSE_OUTPUT_DIR"] {try output.publish(to:URL(fileURLWithPath:root).appendingPathComponent("sampled-60fps.mov"))}
  }

}
