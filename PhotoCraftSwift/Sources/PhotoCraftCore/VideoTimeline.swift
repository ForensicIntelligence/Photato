import Foundation

/// A retained video source plus its placement and trim. Image sequences are one
/// clip, not a stack of frame layers. Source surfaces share tiles with history.
public struct VideoClip: Codable, Equatable, Sendable {
  public static let maximumFrames = 512
  public var frames: [Surface]
  public var frameRate: Double
  public var movie: MovieSource?
  public var audio: TimelineAudioSettings?
  /// Exact source-frame units preserve cuts between movie timestamps.
  public var sourceIn: Double?
  public var sourceOut: Double?
  public func sourceUnit(_ frame: Int) -> Double { movie.map { $0.time(frame) * $0.originalFrameRate } ?? Double(frame) }
  public var sourceStart: Double { sourceIn ?? sourceUnit(inFrame) }
  public var sourceEnd: Double { sourceOut ?? sourceUnit(outFrame) }
  public var startTime: Double = 0
  public var inFrame: Int = 0
  public var outFrame: Int
  public init(frames: [Surface], frameRate: Double) { self.frames = frames; self.frameRate = frameRate; outFrame = frames.count }
  public var duration: Double { (sourceEnd - sourceStart) / frameRate }
  public var estimatedBytes: Int { frames.reduce(256 + (movie?.data.count ?? 0)) { $0 + $1.allocatedBytes + 128 } }
  public func sourceIndex(at seconds: Double) -> Int? {
    let local = seconds - startTime
    guard local >= -1e-9, local < duration - 1e-9 else { return nil }
    if let movie {
      let time=(sourceStart+max(0,local)*frameRate)/movie.originalFrameRate
      var low=inFrame,high=outFrame
      while low+1<high {let mid=(low+high)/2;if movie.time(mid)<=time+1e-9 {low=mid}else{high=mid}}
      return low
    }
    return min(outFrame - 1, Int(floor(sourceStart + max(0,local) * frameRate + 1e-9)))
  }
  public func surface(at seconds: Double) throws -> Surface {
    if let index = sourceIndex(at: seconds) { return frames[index] }
    guard let first = frames.first else { throw CraftError.invalid("Video clip has no frames.") }
    return try Surface(width:first.width,height:first.height,depth:first.depth,colorEncoding:first.colorEncoding)
  }
  public func validate(depth: PixelDepth) throws {
    guard !frames.isEmpty, frames.count <= Self.maximumFrames, frameRate.isFinite, (1...240).contains(frameRate),
      startTime.isFinite, (-86_400...86_400).contains(startTime), inFrame >= 0, outFrame <= frames.count, inFrame < outFrame else { throw CraftError.invalid("Invalid video clip timing.") }
    try movie?.validate(frameCount:frames.count)
    guard sourceStart.isFinite, sourceEnd.isFinite, sourceStart >= sourceUnit(inFrame) - 1e-9, sourceEnd <= sourceUnit(outFrame) + 1e-9, sourceEnd > sourceStart + 1e-9, duration <= 86_400, startTime + duration <= 86_400 else { throw CraftError.invalid("Invalid exact clip boundaries.") }
    let first = frames[0]
    guard frames.allSatisfy({ $0.width == first.width && $0.height == first.height && $0.depth == depth && $0.colorEncoding == first.colorEncoding }) else { throw CraftError.invalid("Video frames must share dimensions, depth and color encoding.") }
  }
}
public struct VideoTimeline: Codable, Equatable, Sendable {
  public var retainedFrameSources:[FrameVideoSource]?
  public var frameTransitionKeys:[FrameTransitionKey]?
  public var finiteLoopCount: Int?
  public var trimmedToWorkArea: Bool?
  public var workArea: TimelineWorkArea?
  public var onionSkin: OnionSkinSettings?
  public var transitions: [VideoTransition]?
  public var audioTracks: [TimelineAudioTrack]?
  public var frameRate: Double
  public var currentFrame = 0
  public var durationFrames: Int
  public var looping = true
  public init(frameRate: Double, durationFrames: Int) { self.frameRate = frameRate; self.durationFrames = durationFrames }
  public var seconds: Double { Double(currentFrame) / frameRate }
  public func validate() throws {
    guard frameRate.isFinite, (1...240).contains(frameRate), (1...20_736_001).contains(durationFrames), (0..<durationFrames).contains(currentFrame) else { throw CraftError.invalid("Invalid video Timeline.") }
    guard finiteLoopCount.map({(1...65535).contains($0)}) ?? true else{throw CraftError.invalid("Invalid Timeline loop count.")}
    try workArea?.validate(durationFrames:durationFrames);try onionSkin?.validate()
  }
  public func playbackFrame(elapsed: Double) throws -> (frame: Int, finished: Bool) {
    try validate()
    guard elapsed.isFinite, elapsed >= 0, elapsed < 1e9 else { throw CraftError.invalid("Invalid video playback clock.") }
    let advance = Int(floor(elapsed * frameRate))
    let area=effectiveWorkArea,start=playbackStartFrame
    if let passes=finiteLoopCount, advance >= area.count*passes { return (area.startFrame+(start-area.startFrame+area.count-1)%area.count,true) }
    if finiteLoopCount == nil, !looping, advance >= area.endFrame-start { return (area.endFrame-1,true) }
    return (area.startFrame+(start-area.startFrame+advance)%area.count,false)
  }
}
public enum VideoCommand: Sendable {
  case create(frameRate:Double,durationFrames:Int),duration(Int),remove
  case keyframe(VideoKeyframeCommand)
  case arrange(VideoArrangementCommand)
  case transition(VideoTransitionCommand)
  case audio(TimelineAudioCommand)
  case workspace(TimelineWorkspaceCommand)
  case insert(Layer)
  case timing(UUID, startTime: Double, inFrame: Int, outFrame: Int, frameRate: Double)
  case frameRate(Double)
  case loop(Bool)
  public var label: String { switch self {case .create: "Create Video Timeline";case .duration: "Timeline Duration";case .remove: "Remove Video Timeline";case .keyframe: "Edit Video Keyframe"; case .arrange(let edit): edit.label; case .transition: "Edit Video Transition"; case .audio(let edit): edit.label; case .workspace(let edit): edit.label; case .insert: "New Video Layer"; case .timing: "Video Clip Timing"; case .frameRate: "Timeline Frame Rate"; case .loop: "Loop Playback" } }
  public func apply(to document: inout CraftDocument) throws {
    if case .workspace(let edit)=self {try edit.apply(to:&document);return}
    if case .audio(let edit)=self {try edit.apply(to:&document);return}
    if case .transition(let edit)=self {try edit.apply(to:&document);return}
    if case .arrange(let edit)=self {try edit.apply(to:&document);return}
    if case .keyframe(let edit)=self {try edit.apply(to:&document);return}
    if case .create(let rate,let frames)=self {
      guard document.videoTimeline==nil,document.animation==nil,!document.hasArtboards,!document.hasAuthoritativeModeStorage else{throw CraftError.invalid("Create a video Timeline in an RGB document without animation or artboards.")}
      let timeline=VideoTimeline(frameRate:rate,durationFrames:frames);try timeline.validate();document.videoTimeline=timeline;return
    }
    if case .remove=self {
      guard document.videoTimeline != nil,!document.layers.contains(where:{$0.video != nil}) else{throw CraftError.invalid("Rasterize video clips before removing the Timeline.")}
      for i in document.layers.indices{document.layers[i].videoKeyframes=nil;document.layers[i].videoTiming=nil;if var group=document.layers[i].group{group.videoStartTime=nil;document.layers[i].content = .group(group)}};document.videoTimeline=nil;return
    }
    if case .duration(let frames)=self {
      guard var timeline=document.videoTimeline else{throw CraftError.invalid("Create a video Timeline first.")}
      let clipEnd=max(document.timelineAudioEnd,document.layers.compactMap(\.videoInterval).map{$0.startTime+$0.duration}.max() ?? 0)
      let keyEnd=document.layers.flatMap{$0.videoKeyframes ?? []}.map(\.time).max() ?? 0
      guard timeline.trimmedToWorkArea == true || (frames>=Int(ceil(clipEnd*timeline.frameRate-1e-9)) && frames>Int(floor(keyEnd*timeline.frameRate+1e-9))) else{throw CraftError.invalid("Timeline duration must include all clips and keyframes.")}
      timeline.durationFrames=frames;timeline.currentFrame=min(timeline.currentFrame,frames-1);timeline.workArea=timeline.workArea?.clamped(to:frames);try timeline.validate();document.videoTimeline=timeline;try document.selectVideoFrame(timeline.currentFrame);return
    }
    if case .insert(let layer)=self {
      guard let clip=layer.video,document.animation==nil,!document.hasArtboards,!document.hasAuthoritativeModeStorage,document.layers.count<512,!document.layers.contains(where:{$0.id==layer.id}) else{throw CraftError.unsupported("Cannot add a video layer to this document.")}
      try clip.validate(depth:document.depth)
      var timeline=document.videoTimeline ?? VideoTimeline(frameRate:clip.frameRate,durationFrames:1)
      timeline.durationFrames=max(timeline.durationFrames,Int(ceil((clip.startTime+clip.duration)*timeline.frameRate-1e-9)))
      document.layers.append(layer);document.activeLayerID=layer.id;document.videoTimeline=timeline
      try document.selectVideoFrame(timeline.currentFrame);return
    }
    guard var timeline = document.videoTimeline else { throw CraftError.invalid("Create a video Timeline first.") }
    let previousDuration=Double(timeline.durationFrames)/timeline.frameRate
    switch self {
    case .create,.duration,.remove,.keyframe,.arrange,.transition,.audio,.workspace,.insert: break
    case .timing(let id,let start,let first,let end,let rate):
      guard let i = document.layers.firstIndex(where:{$0.id == id}), var clip = document.layers[i].video else { throw CraftError.invalid("Select a video layer.") }
      guard !document.isPositionLocked(id) else { throw CraftError.invalid("Unlock video timing before trimming.") }
      try document.validateIndependentClipStart(id,start:start)
      try document.shiftVideoKeys(in:document.subtreeIDs(id),by:start-clip.startTime,root:id)
      if clip.inFrame != first {clip.sourceIn=nil};if clip.outFrame != end {clip.sourceOut=nil}
      clip.startTime = start; clip.inFrame = first; clip.outFrame = end; clip.frameRate = rate
      try clip.validate(depth:document.depth); document.layers[i].video = clip
    case .frameRate(let rate):
      guard rate.isFinite, (1...240).contains(rate) else { throw CraftError.invalid("Frame rate must be from 1 to 240.") }
      if let area=timeline.workArea {timeline.workArea = .init(startFrame:Int(floor(Double(area.startFrame)/timeline.frameRate*rate)),endFrame:Int(ceil(Double(area.endFrame)/timeline.frameRate*rate)))}
      timeline.currentFrame = Int((timeline.seconds * rate).rounded()); timeline.frameRate = rate
    case .loop(let enabled): timeline.looping = enabled;timeline.finiteLoopCount=nil
    }
    let end = timeline.trimmedToWorkArea == true ? previousDuration : max(previousDuration,document.layers.compactMap(\.videoInterval).map { $0.startTime + $0.duration }.max() ?? 0)
    let keyEnd=timeline.trimmedToWorkArea == true ? nil : document.layers.flatMap{$0.videoKeyframes ?? []}.map(\.time).max()
    timeline.durationFrames = max(1,max(Int(ceil(end * timeline.frameRate - 1e-9)),keyEnd.map{Int(ceil($0*timeline.frameRate-1e-9))+1} ?? 1))
    timeline.currentFrame = min(timeline.currentFrame,timeline.durationFrames-1)
    timeline.workArea=timeline.workArea?.clamped(to:timeline.durationFrames)
    document.videoTimeline = timeline; try document.reflowVideoGroups(); try document.refreshVideoDuration()
  }
}
extension CraftDocument {
  public mutating func selectVideoFrame(_ frame: Int) throws {
    guard var timeline = videoTimeline, (0..<timeline.durationFrames).contains(frame) else { throw CraftError.invalid("Video playhead is outside the Timeline.") }
    timeline.currentFrame = frame; try timeline.validate()
    for i in layers.indices { if let clip = layers[i].video {
      try clip.validate(depth:depth); layers[i].content = .raster(try clip.surface(at:timeline.seconds))
    } }
    videoTimeline = timeline
    try evaluateVideoKeyframes(at:timeline.seconds)
  }
  public func videoDocument(at frame: Int) throws -> CraftDocument { var result = self; try result.selectVideoFrame(frame); return result }
  func validateVideo() throws {
    try validateSampledTimelineContent()
    try validateTimelineTrim()
    try validateTimelineAudio()
    try validateVideoTransitions()
    try validateVideoArrangement()
    try videoTimeline?.validate()
    try validateVideoKeyframes()
    guard let timeline = videoTimeline else {
      guard !layers.contains(where:{$0.video != nil}) else { throw CraftError.invalid("Video layers require a Timeline.") }; return
    }
    try timeline.validate()
    guard animation == nil, !hasArtboards, !hasAuthoritativeModeStorage else { throw CraftError.unsupported("Video currently requires an RGB document without frame animation or artboards.") }
    for layer in layers { if let clip = layer.video {
      try clip.validate(depth:depth)
      guard layer.smartObject == nil, layer.smartFilters == nil, layer.warp == nil, layer.nativeMode == nil,
        layer.content == .raster(try clip.surface(at:timeline.seconds)) else { throw CraftError.invalid("Video layer preview does not match its current source frame.") }
    } }
  }
  mutating func captureVideoChanges() throws {
    guard let timeline = videoTimeline else { return }
    try captureVideoKeyframeChanges()
    for i in layers.indices { if var clip = layers[i].video {
      guard case .raster(let surface) = layers[i].content else { throw CraftError.unsupported("Rasterize the video before replacing its content type.") }
      if let index = clip.sourceIndex(at:timeline.seconds) {
        guard surface.width == clip.frames[index].width, surface.height == clip.frames[index].height else { throw CraftError.unsupported("Video frame painting currently retains the source dimensions; rasterize before resizing pixels.") }
        clip.frames[index] = surface; layers[i].video = clip
      } else if surface != (try clip.surface(at:timeline.seconds)) { throw CraftError.invalid("Move the playhead into the video clip before painting.") }
    } }
  }
}
extension Command {
  func validateVideoContext(in document: CraftDocument) throws {
    guard document.videoTimeline != nil else { return }
    if case .animation(.convertFromVideo)=self {return}
    if case .animation(.restoreVideoSource)=self {return}
    switch self {
    case .crop, .cropDocument, .canvasSize, .imageSize, .rotateCanvas, .mergeLayers, .documentMode, .preparedDocumentMode, .preparedColorProfile, .artboard, .animation:
      throw CraftError.unsupported("This operation needs an all-frame video implementation. Keep the video original and use a still copy for this operation.")
    default: break
    }
  }
}
extension EditorSession {
  public mutating func selectVideoFrame(_ frame: Int) throws {
    var candidate = document; try candidate.selectVideoFrame(frame); try candidate.validate(); endCoalescing(); setAnimationSelection(candidate)
  }
}
