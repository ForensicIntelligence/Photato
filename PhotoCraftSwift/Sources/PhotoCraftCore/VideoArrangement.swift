import Foundation

/// A still retains its editable content; the interval only gates composition.
public struct VideoLayerTiming: Codable, Equatable, Sendable {
  public var startTime: Double
  public var duration: Double
  public init(startTime: Double, duration: Double) { self.startTime = startTime; self.duration = duration }
  public func contains(_ time: Double) -> Bool { time >= startTime - 1e-9 && time < startTime + duration - 1e-9 }
  public func validate() throws {
    guard startTime.isFinite, duration.isFinite, startTime >= -86_400, duration > 1e-9, duration <= 86_400,
      startTime + duration <= 86_400 else { throw CraftError.invalid("Clip timing must fit within one day and have a positive duration.") }
  }
}
extension Layer {
  public var videoInterval: VideoLayerTiming? {
    video.map { .init(startTime: $0.startTime, duration: $0.duration) } ?? videoTiming
  }
}
public enum VideoArrangementCommand: Sendable {
  case trim(UUID, startTime: Double, sourceIn: Double, sourceOut: Double)
  case split(Set<UUID>)
  case group(String, [UUID])
  case move(UUID, group: UUID?, position: Int, startTime: Double? = nil)
  case stillTiming(UUID, startTime: Double, duration: Double)
  case groupStart(UUID, Double)
  public var label: String {
    switch self {case .trim: "Trim Video Clip"; case .split: "Split At Playhead"; case .group: "New Video Group"; case .move: "Arrange Video Clips"; case .stillTiming: "Clip Duration"; case .groupStart: "Video Group Start" }
  }
  public func apply(to document: inout CraftDocument) throws {
    guard let timeline = document.videoTimeline else { throw CraftError.invalid("Create a video Timeline first.") }
    switch self {
    case .trim(let id,let start,let first,let last):
      guard let i=document.layers.firstIndex(where:{$0.id==id}),var clip=document.layers[i].video,!document.isPositionLocked(id) else{throw CraftError.invalid("Select an unlocked video clip.")}
      try document.validateIndependentClipStart(id,start:start)
      try document.shiftVideoKeys(in:document.subtreeIDs(id),by:start-clip.startTime,root:id)
      clip.startTime=start;clip.inFrame=0;clip.outFrame=clip.frames.count;clip.sourceIn=first;clip.sourceOut=last
      try clip.validate(depth:document.depth);document.layers[i].video=clip
    case .split(let selected):
      let roots = try LayerDuplication.roots(in: document, selected: selected)
      for root in roots {
        guard !document.isPositionLocked(root.id), root.group?.videoStartTime == nil,
          !root.isClipped, !document.isClippingBase(root.id) else {
          throw CraftError.invalid("Split unlocked clips. Select clips inside a video group; release clipping masks before splitting.")
        }
        let interval = root.videoInterval ?? VideoLayerTiming(startTime: 0, duration: Double(timeline.durationFrames) / timeline.frameRate)
        let time = timeline.seconds
        guard time > interval.startTime + 1e-9, time < interval.startTime + interval.duration - 1e-9 else {
          throw CraftError.invalid("Position the playhead inside every selected clip.")
        }
        let ids = document.subtreeIDs(root.id)
        guard document.layers.count + ids.count <= LayerLimits.maximumLayers,
          !document.layers.contains(where: { ids.contains($0.id) && $0.group?.videoStartTime != nil }) else {
          throw CraftError.invalid("Split individual clips within video groups and stay within \(LayerLimits.maximumLayers) layers.")
        }
        let mapping = Dictionary(uniqueKeysWithValues: ids.map { ($0, UUID()) })
        var copies = document.layers.filter { ids.contains($0.id) }
        for i in copies.indices {
          let old = copies[i].id; copies[i].id = mapping[old]!
          if let parent = copies[i].parentID, let mapped = mapping[parent] { copies[i].parentID = mapped }
          copies[i].videoKeyframes = copies[i].videoKeyframes?.map { var key = $0; key.id = UUID(); return key }
        }
        let index = document.layers.firstIndex { $0.id == root.id }!
        if var clip = root.video {
          let cut = clip.sourceStart + (time - clip.startTime) * clip.frameRate
          var right = clip; right.sourceIn = cut; right.startTime = time
          right.audio?.fadeIn = 0; clip.audio?.fadeOut = 0
          clip.sourceOut = cut; document.layers[index].video = clip; copies[copies.count - 1].video = right
        } else {
          document.layers[index].videoTiming = .init(startTime: interval.startTime, duration: time - interval.startTime)
          copies[copies.count - 1].videoTiming = .init(startTime: time, duration: interval.startTime + interval.duration - time)
        }
        copies[copies.count - 1].name = root.name + " split"
        document.layers.insert(contentsOf: copies, at: index + 1)
        document.transferSplitTransitions(from:root.id,to:mapping[root.id]!)
        document.activeLayerID = mapping[root.id]
      }
    case .group(let name, let ids):
      for id in ids {
        guard let layer = document.layers.first(where: { $0.id == id }), !document.isPositionLocked(id),
          layer.group?.videoStartTime == nil,
          !document.ancestors(of: id).contains(where: { $0.group?.videoStartTime != nil }),
          !document.layers.contains(where: { document.subtreeIDs(id).contains($0.id) && $0.group?.videoStartTime != nil }) else {
          throw CraftError.invalid("Choose unlocked clips outside existing video groups.")
        }
      }
      let start = ids.compactMap { id in document.layers.first { $0.id == id }?.videoInterval?.startTime }.min() ?? timeline.seconds
      if ids.isEmpty {document.activeLayerID=nil}
      try document.createLayerGroup(.init(name: name), children: ids, below: false)
      let i = document.layers.firstIndex { $0.id == document.activeLayerID }!
      var group = document.layers[i].group!; group.videoStartTime = start; document.layers[i].content = .group(group)
    case .move(let id, let parent, let position, let requestedStart):
      guard position >= 0, position <= document.children(of: parent).count,
        let layer = document.layers.first(where: { $0.id == id }), !document.isPositionLocked(id),
        layer.group?.videoStartTime == nil else { throw CraftError.invalid("Choose an unlocked clip and valid track position.") }
      if let parent {
        guard document.layers.first(where: { $0.id == parent })?.group?.videoStartTime != nil else { throw CraftError.invalid("Choose a video group.") }
      }
      if requestedStart != nil && parent != nil {throw CraftError.invalid("Sequential clips use their video group's start and ordering.")}
      try document.relocate(id, parent: parent, position: position)
      if let start=requestedStart {
        let i=document.layers.firstIndex{$0.id==id}!
        let interval=document.layers[i].videoInterval ?? .init(startTime:0,duration:Double(timeline.durationFrames)/timeline.frameRate)
        try VideoLayerTiming(startTime:start,duration:interval.duration).validate()
        try document.shiftVideoKeys(in:document.subtreeIDs(id),by:start-interval.startTime,root:id)
        if document.layers[i].video != nil{document.layers[i].video!.startTime=start}else{document.layers[i].videoTiming = .init(startTime:start,duration:interval.duration)}
      }
    case .stillTiming(let id, let start, let duration):
      guard let i = document.layers.firstIndex(where: { $0.id == id }), document.layers[i].video == nil,
        document.layers[i].group?.videoStartTime == nil, !document.isPositionLocked(id) else { throw CraftError.invalid("Choose an unlocked still, type, shape or ordinary group.") }
      let timing = VideoLayerTiming(startTime: start, duration: duration); try timing.validate()
      try document.validateIndependentClipStart(id, start: start)
      let previous = document.layers[i].videoInterval?.startTime ?? 0
      try document.shiftVideoKeys(in: document.subtreeIDs(id), by: start - previous, root: id)
      document.layers[i].videoTiming = timing
    case .groupStart(let id, let time):
      guard time.isFinite, (0...86_400).contains(time), let i = document.layers.firstIndex(where: { $0.id == id }),
        var group = document.layers[i].group, group.videoStartTime != nil, !document.isPositionLocked(id) else { throw CraftError.invalid("Choose an unlocked video group and a valid start time.") }
      group.videoStartTime = time; document.layers[i].content = .group(group)
    }
    try document.reflowVideoGroups()
    try document.refreshVideoDuration()
  }
}
extension CraftDocument {
  func validateIndependentClipStart(_ id: UUID, start: Double) throws {
    guard let layer=layers.first(where:{$0.id==id}),let parent=layer.parentID,
      layers.first(where:{$0.id==parent})?.group?.videoStartTime != nil else{return}
    guard abs((layer.videoInterval?.startTime ?? 0)-start)<1e-9 else {
      throw CraftError.invalid("Use clip ordering or Video Group Start to move a clip on a sequential track.")
    }
  }
  mutating func shiftVideoKeys(in ids: Set<UUID>, by delta: Double, root: UUID) throws {
    guard abs(delta) > 1e-9 else { return }
    guard !layers.contains(where:{ids.contains($0.id) && isPositionLocked($0.id)}) else {throw CraftError.invalid("Unlock affected clips and their contents before moving their timing.")}
    for i in layers.indices where ids.contains(layers[i].id) {
      if layers[i].id != root, let interval=layers[i].videoInterval {
        let start=interval.startTime+delta
        guard start >= 0 || videoTimeline?.trimmedToWorkArea == true else {throw CraftError.unsupported("Moving this group's nested clip before time zero requires trimming it first.")}
        if layers[i].video != nil {layers[i].video!.startTime=start} else {layers[i].videoTiming!.startTime=start}
      }
      guard let keys = layers[i].videoKeyframes else { continue }
      if videoTimeline?.trimmedToWorkArea == true {
        layers[i].videoKeyframes=keys.map{var key=$0;key.time += delta;return key}
        continue
      }
      var moved = keys.filter { $0.time + delta >= 0 }.map { var key = $0; key.time += delta; return key }
      // Preserve the value/interpolation at zero when moving keys before the Timeline.
      for property in VideoProperty.allCases where keys.contains(where: { $0.property == property && $0.time + delta < 0 }) {
        if !moved.contains(where: { $0.property == property && $0.time < 1e-9 }),
          var boundary = try VideoKeyframe.evaluate(keys, property: property, time: -delta) {
          boundary.id = UUID(); boundary.time = 0; moved.append(boundary)
        }
      }
      moved.sort { $0.time == $1.time ? $0.property.rawValue < $1.property.rawValue : $0.time < $1.time }
      layers[i].videoKeyframes = moved.isEmpty ? nil : moved
    }
  }
  mutating func reflowVideoGroups() throws {
    guard let timeline = videoTimeline else { return }
    for group in layers.filter({ $0.group?.videoStartTime != nil }) {
      var start = group.group!.videoStartTime!
      for child in children(of: group.id) {
        let interval = child.videoInterval ?? .init(startTime: 0, duration: Double(timeline.durationFrames) / timeline.frameRate)
        guard !isPositionLocked(child.id) || abs(start - interval.startTime) < 1e-9 else { throw CraftError.invalid("Unlock all affected clips before rearranging the video group.") }
        try shiftVideoKeys(in: subtreeIDs(child.id), by: start - interval.startTime, root: child.id)
        let i = layers.firstIndex { $0.id == child.id }!
        if layers[i].video != nil { layers[i].video!.startTime = start }
        else { layers[i].videoTiming = .init(startTime: start, duration: interval.duration) }
        start += interval.duration
      }
    }
  }
  mutating func refreshVideoDuration() throws {
    guard var timeline = videoTimeline else { return }
    if timeline.trimmedToWorkArea == true {try selectVideoFrame(timeline.currentFrame);return}
    let end = max(timelineAudioEnd,layers.compactMap(\.videoInterval).map { $0.startTime + $0.duration }.max() ?? 0)
    guard end.isFinite, end <= 86_400 else { throw CraftError.invalid("Clips exceed the one-day Timeline limit.") }
    let key = layers.flatMap { $0.videoKeyframes ?? [] }.map(\.time).max() ?? 0
    timeline.durationFrames = max(timeline.durationFrames, max(Int(ceil(end * timeline.frameRate - 1e-9)), Int(ceil(key * timeline.frameRate - 1e-9)) + 1))
    videoTimeline = timeline; try selectVideoFrame(timeline.currentFrame)
  }
  func validateVideoArrangement() throws {
    for layer in layers {
      try layer.videoTiming?.validate()
      guard layer.videoTiming == nil || (videoTimeline != nil && layer.video == nil && layer.group?.videoStartTime == nil) else { throw CraftError.invalid("Still timing requires a Timeline and an ordinary layer.") }
      if let start = layer.group?.videoStartTime {
        guard videoTimeline != nil, start.isFinite, (-86_400...86_400).contains(start),
          layer.group?.frame == nil, layer.group?.artboard == nil,
          !ancestors(of: layer.id).contains(where: { $0.group?.videoStartTime != nil }) else { throw CraftError.invalid("Invalid video group.") }
      }
    }
  }
  /// Temporary composition only; never write the visibility gate back to the document.
  public func videoCompositionSnapshot() -> CraftDocument {
    strippedVideoSnapshot(at: videoTimeline?.seconds)
  }
  /// Evaluate a detached composition at an exact export time, independent of the playhead grid.
  public func videoCompositionSnapshot(at seconds: Double) throws -> CraftDocument {
    guard let timeline = videoTimeline, seconds.isFinite, seconds >= 0,
      seconds < Double(timeline.durationFrames) / timeline.frameRate else {
      throw CraftError.invalid("Render time is outside the video Timeline.")
    }
    var result = self
    for i in result.layers.indices { if let clip = result.layers[i].video {
      result.layers[i].content = .raster(try clip.surface(at: seconds))
    } }
    try result.evaluateVideoKeyframes(at: seconds)
    return result.strippedVideoSnapshot(at: seconds)
  }
  private func strippedVideoSnapshot(at seconds: Double?) -> CraftDocument {
    var result = self
    for i in result.layers.indices {
      if let seconds, let timing = layers[i].videoInterval, !timing.contains(seconds) { result.layers[i].visible = false }
      result.layers[i].video = nil; result.layers[i].videoTiming = nil; result.layers[i].videoKeyframes = nil
      if var group = result.layers[i].group { group.videoStartTime = nil; result.layers[i].content = .group(group) }
    }
    result.videoTimeline = nil
    return result
  }
}
