import Foundation

extension CraftDocument {
  /// Convert shared editable frame compositions into discrete property tracks.
  /// Fixed-rate playback samples the original delays without flattening artwork.
  public func convertingFrameAnimation(frameRate: Double) throws -> CraftDocument {
    try validate()
    guard let animation, videoTimeline == nil, !hasAuthoritativeModeStorage,
      frameRate.isFinite, (1...240).contains(frameRate) else {
      throw CraftError.invalid("Choose a frame animation and a video rate from 1 to 240 fps.")
    }
    var starts: [Double] = [], duration = 0.0
    for frame in animation.frames.indices {
      starts.append(duration); duration += animation.playbackDelay(at:frame)
    }
    guard duration.isFinite, duration <= 86_400 else {
      throw CraftError.invalid("The converted Timeline must fit within one day.")
    }
    var result = self
    var timeline = VideoTimeline(frameRate: frameRate, durationFrames: max(1, Int(ceil(duration * frameRate - 1e-9))))
    timeline.looping = animation.loopCount != 1
    if animation.loopCount > 0 { timeline.finiteLoopCount = animation.loopCount }
    timeline.currentFrame = min(timeline.durationFrames - 1, Int(ceil(starts[animation.selectedIndex] * frameRate - 1e-9)))
    if let source=animation.retainedVideoSource {timeline.retainedFrameSources=[source]}
    let sampling:FrameSampledTimeline?
    if let current=animation.sampledTimeline {sampling=current}
    else if let source=animation.retainedVideoSource {sampling=try FrameSampledTimeline(source.document(in:self))}
    else{sampling=nil}
    if let sampling,sampling.matches(animation) {
      timeline.trimmedToWorkArea=sampling.trimmedToWorkArea
      timeline.audioTracks=sampling.audioTracks.isEmpty ? nil:sampling.audioTracks
    }
    if animation.frames.contains(where:{$0.transitions != nil}) {
      timeline.frameTransitionKeys=animation.frames.indices.map{.init(time:starts[$0],states:animation.frames[$0].transitions ?? [])}
    }
    let frames = animation.frames.map { Dictionary(uniqueKeysWithValues: $0.layers.map { ($0.layerID, $0) }) }
    for i in result.layers.indices {
      try Task.checkCancellation()
      let layer = result.layers[i]
      var keys: [VideoKeyframe] = []
      for property in [VideoProperty.transform, .opacity, .style, .visibility, .content] {
        var track: [VideoKeyframe] = []
        for frame in frames.indices {
          var sample = layer; frames[frame][layer.id]!.apply(to: &sample)
          if track.last?.matches(sample) == true { continue }
          var key = VideoKeyframe(property: property, time: starts[frame], layer: sample, interpolation: .hold)
          key.frameComposition = true; track.append(key)
        }
        // Constant properties remain ordinary editable layer properties.
        if track.count > 1 { keys += track }
      }
      keys.sort { $0.time == $1.time ? $0.property.rawValue < $1.property.rawValue : $0.time < $1.time }
      result.layers[i].videoKeyframes = keys.isEmpty ? nil : keys
    }
    result.animation = nil; result.videoTimeline = timeline
    try result.selectVideoFrame(timeline.currentFrame)
    try result.validate()
    return result
  }
}
