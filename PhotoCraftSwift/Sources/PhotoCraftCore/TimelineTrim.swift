import Foundation

extension CraftDocument {
  /// Crop the temporal domain without restarting fades or resampling media.
  /// Out-of-domain clip portions and bounding keys are source handles, not
  /// additional output frames. Native58 identifies this retained representation.
  mutating func trimTimelineToWorkArea() throws {
    guard var timeline = videoTimeline else { throw CraftError.invalid("Create a video Timeline first.") }
    let area = timeline.effectiveWorkArea
    try area.validate(durationFrames: timeline.durationFrames)
    guard area.startFrame != 0 || area.endFrame != timeline.durationFrames else { return }
    let start = Double(area.startFrame) / timeline.frameRate
    let end = Double(area.endFrame) / timeline.frameRate
    func intersects(_ interval: VideoLayerTiming) -> Bool {
      min(end, interval.startTime + interval.duration) - max(start, interval.startTime) > 1e-9
    }
    let transitions = (timeline.transitions ?? []).filter { $0.interval(in: self).map(intersects) == true }
    var keep = Set(layers.filter { layer in
      ([layer] + ancestors(of: layer.id)).allSatisfy { $0.videoInterval.map(intersects) ?? true }
    }.map(\.id))
    for transition in transitions {
      for id in transition.participants { keep.formUnion(subtreeIDs(id)) }
    }
    if let samples=timeline.frameTransitionKeys {
      let relevant=samples.filter{$0.time>=start && $0.time<end} + (samples.last(where:{$0.time<start}).map{[$0]} ?? [])
      for state in relevant.flatMap(\.states) {for id in state.transition.participants {keep.formUnion(subtreeIDs(id))}}
    }
    // A clipped sibling still depends on its base, including a transition handle.
    var previous: Set<UUID> = []
    while previous != keep {
      previous = keep
      for layer in layers where keep.contains(layer.id) {
        keep.formUnion(ancestors(of: layer.id).map(\.id))
        if layer.isClipped, let base = clippingBase(for: layer.id) { keep.formUnion(subtreeIDs(base.id)) }
      }
    }
    for layer in layers {
      let changesTiming = layer.videoInterval != nil || layer.videoKeyframes != nil || layer.group?.videoStartTime != nil
      guard !(changesTiming && isPositionLocked(layer.id)), keep.contains(layer.id) || !isLocked(layer.id) else {
        throw CraftError.invalid("Unlock affected Timeline layers before trimming the document duration.")
      }
    }
    layers.removeAll { !keep.contains($0.id) }
    if !layers.contains(where: { $0.id == activeLayerID }) { activeLayerID = layers.last?.id }
    for i in layers.indices {
      if layers[i].video != nil { layers[i].video!.startTime -= start }
      if layers[i].videoTiming != nil { layers[i].videoTiming!.startTime -= start }
      if var group = layers[i].group, let time = group.videoStartTime {
        group.videoStartTime = time - start; layers[i].content = .group(group)
      }
      if let keys = layers[i].videoKeyframes {
        var retained: [VideoKeyframe] = []
        for property in VideoProperty.allCases {
          let track = keys.filter { $0.property == property }.sorted { $0.time < $1.time }
          if let before = track.last(where: { $0.time < start }) { retained.append(before) }
          retained += track.filter { $0.time >= start && $0.time < end }
          if let after = track.first(where: { $0.time >= end }) { retained.append(after) }
        }
        layers[i].videoKeyframes = retained.map { var key = $0; key.time -= start; return key }
          .sorted { $0.time == $1.time ? $0.property.rawValue < $1.property.rawValue : $0.time < $1.time }
        if layers[i].videoKeyframes?.isEmpty == true { layers[i].videoKeyframes = nil }
      }
    }
    for i in layers.indices where layers[i].group?.videoStartTime != nil {
      if let first = children(of: layers[i].id).first?.videoInterval {
        var group = layers[i].group!; group.videoStartTime = first.startTime; layers[i].content = .group(group)
      }
    }
    for track in timeline.audioTracks?.indices ?? 0..<0 {
      timeline.audioTracks![track].clips = timeline.audioTracks![track].clips.filter {
        intersects(.init(startTime: $0.startTime, duration: $0.duration))
      }.map { var clip = $0; clip.startTime -= start; return clip }
    }
    if let samples=timeline.frameTransitionKeys {
      var retained:[FrameTransitionKey]=[]
      if let before=samples.last(where:{$0.time<start}) {retained.append(before)}
      retained += samples.filter{$0.time>=start && $0.time<end}
      timeline.frameTransitionKeys=retained.map{var key=$0;key.time-=start;return key}
    }
    timeline.transitions = transitions.isEmpty ? nil : transitions
    timeline.durationFrames = area.count
    timeline.currentFrame = min(area.count - 1, max(0, timeline.currentFrame - area.startFrame))
    timeline.workArea = nil
    timeline.trimmedToWorkArea = true
    videoTimeline = timeline
    try selectVideoFrame(timeline.currentFrame)
  }

  func validateTimelineTrim() throws {
    guard videoTimeline?.trimmedToWorkArea != true else { return }
    guard layers.allSatisfy({ ($0.videoInterval?.startTime ?? 0) >= 0 && ($0.group?.videoStartTime ?? 0) >= 0 }),
      (videoTimeline?.audioTracks ?? []).flatMap(\.clips).allSatisfy({ $0.startTime >= 0 }) else {
      throw CraftError.invalid("Pre-roll media handles require a trimmed Timeline.")
    }
  }
}
