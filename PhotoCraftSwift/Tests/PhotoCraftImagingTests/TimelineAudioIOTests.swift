import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class TimelineAudioIOTests:XCTestCase {
  func fixture(_ name:String="owned-stereo")->URL{Bundle.module.url(forResource:name,withExtension:"wav",subdirectory:"Fixtures/audio")!}
  func document()throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3);d.videoTimeline = .init(frameRate:4,durationFrames:8)
    let source=try TimelineAudioIO.read(fixture()).0
    let first=TimelineAudioClip(name:"Faded",source:source,startTime:0.5,sourceIn:0.25,sourceOut:0.75,settings:.init(volume:0.5,fadeIn:0.25,fadeOut:0.25))
    let second=TimelineAudioClip(name:"Full",source:source,startTime:1)
    try Command.video(.audio(.importClip(nil,first))).apply(to:&d)
    try Command.video(.audio(.importClip(nil,second))).apply(to:&d);return d
  }
  func testNativePCMDecodePreservesOriginalAndExactSamples()throws {
    let (source,pcm)=try TimelineAudioIO.read(fixture())
    XCTAssertEqual(try TimelineAudioIO.containerExtension(source.data),"wav")
    XCTAssertEqual(source.data,try Data(contentsOf:fixture()));XCTAssertEqual(source.duration,1);XCTAssertEqual(source.trackCount,1)
    XCTAssertEqual(pcm.frames,48000)
    for i in 0..<pcm.frames {XCTAssertEqual(pcm.samples[i*2],0.25);XCTAssertEqual(pcm.samples[i*2+1],-0.5)}
    XCTAssertEqual(try TimelineAudioIO.decode(pcm.wave()).1,pcm)
  }
  func testMonoResampleAndRetainedMovieAACDecode()throws {
    let (_,mono)=try TimelineAudioIO.read(fixture("owned-mono"));XCTAssertEqual(mono.frames,24000);XCTAssertEqual(mono.duration,0.5);XCTAssertGreaterThan(mono.samples.last!,0.15)
    XCTAssertEqual(mono.samples[2000],mono.samples[2001],accuracy:0.00001);XCTAssertGreaterThan(mono.samples[2000],0.15)
    let url=Bundle.module.url(forResource:"owned-h264",withExtension:"mp4",subdirectory:"Fixtures/movies")!
    let data=try Data(contentsOf:url),(source,pcm)=try TimelineAudioIO.decode(data)
    XCTAssertEqual(source.data,data);XCTAssertEqual(source.trackCount,1);XCTAssertGreaterThan(pcm.frames,1000);XCTAssertTrue(pcm.samples.allSatisfy(\.isFinite))
  }
  func testMixTrimFadesSilenceAndWaveExport()throws {
    let d=try document(),pcm=try XCTUnwrap(TimelineAudioMixer.render(d));XCTAssertEqual(pcm.frames,96000)
    func left(_ time:Double)->Float{pcm.samples[Int(time*48000)*2]}
    XCTAssertEqual(left(0.25),0);XCTAssertEqual(left(0.5),0);XCTAssertEqual(left(0.625),0.0625);XCTAssertEqual(left(0.75),0.125);XCTAssertEqual(left(0.875),0.0625);XCTAssertEqual(left(1),0.25);XCTAssertEqual(left(1.5),0.25)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_AUDIO_OUTPUT_DIR"]{try pcm.wave().write(to:URL(fileURLWithPath:root).appendingPathComponent("audio-mix.wav"))}
    var muted=d;for i in muted.videoTimeline!.audioTracks!.indices {muted.videoTimeline!.audioTracks![i].muted=true};XCTAssertNil(try TimelineAudioMixer.render(muted))
    XCTAssertEqual(d,try documentPreservingIDs(d))
  }
  func documentPreservingIDs(_ d:CraftDocument)throws->CraftDocument{try NativeArchive.decode(NativeArchive.encodeChunked(d))}
  func testMovieSourceRateTrimVolumeAndMute()throws {
    let data=try Data(contentsOf:fixture()),frames=try [Pixel.black,.white].map{try Surface(width:4,height:3,fill:$0)}
    var clip=VideoClip(frames:frames,frameRate:4)
    clip.movie = .init(data:data,presentationTimes:[.init(value:0,timescale:2),.init(value:1,timescale:2)],endTime:.init(value:2,timescale:2),originalFrameRate:2,audioTracks:1)
    clip.startTime=0.25;clip.audio = .init(fadeOut:0.25)
    var d=try CraftDocument(width:4,height:3);d.videoTimeline = .init(frameRate:4,durationFrames:4);d.layers[0].video=clip;try d.selectVideoFrame(0)
    let pcm=try XCTUnwrap(TimelineAudioMixer.render(d))
    XCTAssertEqual(pcm.samples[6000*2],0);XCTAssertEqual(pcm.samples[24000*2],0.25);XCTAssertEqual(pcm.samples[30000*2],0.125);XCTAssertEqual(pcm.samples[36000*2],0)
    d.layers[0].video?.audio?.muted=true;XCTAssertNil(try TimelineAudioMixer.render(d))
  }
  func testMixingClampsAndInvalidBudgetCorruptionCancellation()async throws {
    var d=try document();let track=d.videoTimeline!.audioTracks![1]
    for _ in 0..<4 {var duplicate=track;duplicate.id=UUID();duplicate.clips[0].id=UUID();d.videoTimeline!.audioTracks!.append(duplicate)}
    let pcm=try XCTUnwrap(TimelineAudioMixer.render(d));XCTAssertEqual(pcm.samples[60000*2],1);XCTAssertEqual(pcm.samples[60000*2+1],-1)
    XCTAssertThrowsError(try TimelineAudioIO.read(fixture(),maximumBytes:100))
    XCTAssertThrowsError(try TimelineAudioMixer.render(d,maximumBytes:100))
    XCTAssertThrowsError(try TimelineAudioIO.decode(Data("not audio".utf8)))
    let data=try Data(contentsOf:fixture()),task=Task.detached{while !Task.isCancelled{await Task.yield()};return try TimelineAudioIO.decode(data)};task.cancel()
    do{_=try await task.value;XCTFail("Cancelled audio decode succeeded")}catch is CancellationError{}
  }
}
