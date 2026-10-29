import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class TimelineTrimRendererTests:XCTestCase {
  func fixture(depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3,depth:depth)
    var a=Layer(name:"Red",content:.fill(Pixel(1,0,0))),b=Layer(name:"Blue",content:.fill(Pixel(0,0,1)))
    a.videoTiming = .init(startTime:0,duration:1);b.videoTiming = .init(startTime:1,duration:1)
    d.layers=[a,b];d.activeLayerID=b.id;d.videoTimeline = .init(frameRate:8,durationFrames:16)
    try Command.video(.transition(.set(.init(layerID:b.id,previousLayerID:a.id,kind:.crossFade,duration:1)))).apply(to:&d)
    return d
  }
  func testCrossfadeBoundaryParticipantsRemainPixelExactInAllDepths()throws {
    for depth in [PixelDepth.u8,.u16,.f32] {
      for area in [TimelineWorkArea(startFrame:5,endFrame:7),.init(startFrame:10,endFrame:13),.init(startFrame:7,endFrame:11)] {
        var d=try fixture(depth:depth);d.videoTimeline!.workArea=area;let original=d
        try Command.video(.workspace(.trimToWorkArea)).apply(to:&d)
        XCTAssertEqual(d.layers.count,2);XCTAssertEqual(d.videoTimeline?.transitions?.count,1)
        for frame in 0..<area.count {
          XCTAssertEqual(try Renderer.composite(d.videoDocument(at:frame)),try Renderer.composite(original.videoDocument(at:frame+area.startFrame)))
        }
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
      }
    }
  }
  func testFadesAndGroupedEditableContentDoNotRestartAtCropBoundary()throws {
    for kind in [VideoTransitionKind.fade,.black,.white,.color] {
      var d=try fixture();d.videoTimeline!.transitions=nil;d.layers.removeLast();d.activeLayerID=d.layers[0].id
      d.layers[0].videoTiming = .init(startTime:0,duration:2)
      try Command.video(.transition(.set(.init(layerID:d.layers[0].id,kind:kind,duration:2,color:kind == .color ? Pixel(0,1,0):nil)))).apply(to:&d)
      d.videoTimeline!.workArea = .init(startFrame:5,endFrame:12);let original=d
      try Command.video(.workspace(.trimToWorkArea)).apply(to:&d)
      XCTAssertEqual(d.layers[0].content,original.layers[0].content)
      for frame in 0..<7 {XCTAssertEqual(try Renderer.composite(d.videoDocument(at:frame)),try Renderer.composite(original.videoDocument(at:frame+5)))}
    }
  }
  func testAudioFadeEnvelopeAndSourceSamplesSurviveTrimExactly()throws {
    let pcm=TimelinePCM(samples:(0..<48000).flatMap{_ in [Float(0.25),Float(-0.5)]}),data=try pcm.wave()
    var d=try fixture();d.videoTimeline!.audioTracks=[.init(name:"Sound",clips:[.init(name:"Fades",source:.init(data:data,duration:1),settings:.init(fadeIn:0.5,fadeOut:0.5)),.init(name:"Outside",source:.init(data:data,duration:1),startTime:1)])]
    d.videoTimeline!.workArea = .init(startFrame:2,endFrame:6)
    let before=try XCTUnwrap(TimelineAudioMixer.render(d,startTime:0.25,duration:0.5))
    try Command.video(.workspace(.trimToWorkArea)).apply(to:&d)
    let after=try XCTUnwrap(TimelineAudioMixer.render(d));XCTAssertEqual(after,before)
    XCTAssertEqual(d.videoTimeline?.audioTracks?.first?.clips.count,1)
    XCTAssertEqual(d.videoTimeline?.audioTracks?.first?.clips.first?.source.data,data)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_TRIM_OUTPUT_DIR"] {
      try after.wave().write(to:URL(fileURLWithPath:root).appendingPathComponent("trimmed-audio.wav"))
    }
  }
  func testTrimmedFramesProduceIndependentPNGFixtures()throws {
    var d=try fixture();d.videoTimeline!.workArea = .init(startFrame:6,endFrame:11)
    try Command.video(.workspace(.trimToWorkArea)).apply(to:&d)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_TRIM_OUTPUT_DIR"] {
      for frame in 0..<5 {
        let pixels=try Renderer.composite(d.videoDocument(at:frame))
        try ClipboardRenderer.imageData(pixels,type:.png).write(to:URL(fileURLWithPath:root).appendingPathComponent("trimmed-\(frame).png"))
      }
    }
  }
  func testTrimmedMovieExportsTheRetainedInterval()throws {
    var d=try fixture();d.videoTimeline!.workArea = .init(startFrame:6,endFrame:11)
    let original=d
    try Command.video(.workspace(.trimToWorkArea)).apply(to:&d)
    let output=try VideoRender.render(d,options:.init(codec:.uncompressed,includeAudio:false));defer{output.discard()}
    let reference=try VideoRender.render(original,options:.init(codec:.uncompressed,firstFrame:6,lastFrame:10,includeAudio:false));defer{reference.discard()}
    XCTAssertEqual(output.plan.frameCount,5);XCTAssertEqual(output.plan.duration,0.625)
    XCTAssertEqual(reference.plan.sourceStart,0.75);XCTAssertEqual(output.plan.sourceStart,0)
    let movie=try MovieIO.read(output.url),frames=try XCTUnwrap(movie.layers[0].video?.frames)
    let before=try MovieIO.read(reference.url),referenceFrames=try XCTUnwrap(before.layers[0].video?.frames)
    XCTAssertEqual(frames.count,5);XCTAssertEqual(frames,referenceFrames)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_TRIM_OUTPUT_DIR"] {
      try output.publish(to:URL(fileURLWithPath:root).appendingPathComponent("trimmed.mov"))
      try reference.publish(to:URL(fileURLWithPath:root).appendingPathComponent("original-work-area.mov"))
    }
  }
}
