import Foundation

/// The current sequence's audio clock is distinct from its earliest recoverable
/// original. Repeated conversions must preserve active audio without resurrecting
/// a soundtrack intentionally left inactive after a frame reorder or retiming.
public struct FrameSampledTimeline:Codable,Equatable,Sendable {
  public var frameRate:Double
  public var durationFrames:Int
  public var trimmedToWorkArea:Bool?
  public var audioTracks:[TimelineAudioTrack]
  public init(_ document:CraftDocument)throws {
    guard let timeline=document.videoTimeline else{throw CraftError.invalid("A sampled source needs a video Timeline.")}
    frameRate=timeline.frameRate;durationFrames=timeline.durationFrames;trimmedToWorkArea=timeline.trimmedToWorkArea
    audioTracks=timeline.audioTracks ?? []
    for layer in document.layers {
      guard let clip=layer.video,let movie=clip.movie,movie.audioTracks>0 else{continue}
      let source=TimelineAudioSource(data:movie.data,duration:movie.endTime.seconds,trackCount:movie.audioTracks)
      var sound=TimelineAudioClip(name:String((layer.name+" Audio").prefix(256)),source:source,startTime:clip.startTime,sourceIn:clip.sourceStart/movie.originalFrameRate,sourceOut:clip.sourceEnd/movie.originalFrameRate,settings:clip.audio ?? .init())
      sound.playbackRate=clip.frameRate/movie.originalFrameRate
      audioTracks.append(.init(name:String((layer.name+" Audio").prefix(256)),clips:[sound]))
    }
  }
  public var estimatedBytes:Int {audioTracks.reduce(128){$0+256+$1.clips.reduce(0){$0+256+$1.source.data.count}}}
  public var hasAudio:Bool {audioTracks.contains{!$0.clips.isEmpty}}
  public func matches(_ animation:FrameAnimation)->Bool {
    animation.frames.count==durationFrames && animation.frames.enumerated().allSatisfy {
      $0.element.sourceVideoFrame==$0.offset && abs(animation.playbackDelay(at:$0.offset)-1/frameRate)<1e-9
    }
  }
  public func validate(in document:CraftDocument)throws {
    let timeline=VideoTimeline(frameRate:frameRate,durationFrames:durationFrames);try timeline.validate()
    var sample=document;sample.animation=nil;sample.videoTimeline=timeline
    sample.videoTimeline!.trimmedToWorkArea=trimmedToWorkArea;sample.videoTimeline!.audioTracks=audioTracks
    try sample.validateTimelineAudio();try sample.validateTimelineTrim()
  }
}
