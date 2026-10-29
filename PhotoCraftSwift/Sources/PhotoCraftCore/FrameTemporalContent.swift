import Foundation

/// Only fields whose rendered values can change under video sampling.
/// Shared naming, protection, blending and hierarchy remain ordinary layer data.
public struct AnimationLayerPayload: Codable, Equatable, Sendable {
  public var content: LayerContent
  public var mask: Surface?
  public var maskProperties: MaskProperties?
  public var vectorMask: VectorMask?
  public var smartFilters: SmartFilterStack?
  public init(_ layer: Layer) {
    content=layer.content;mask=layer.mask;maskProperties=layer.maskProperties
    vectorMask=layer.vectorMask;smartFilters=layer.smartFilters
  }
  public func apply(to layer: inout Layer) {
    layer.content=content;layer.mask=mask;layer.maskProperties=maskProperties
    layer.vectorMask=vectorMask;layer.smartFilters=smartFilters
  }
  public var rasterBytes: Int {
    let image: Int
    if case .raster(let surface)=content {image=surface.allocatedBytes}else{image=0}
    return image+(mask?.allocatedBytes ?? 0)+(smartFilters?.mask?.allocatedBytes ?? 0)
  }
  public var metadataBytes: Int {
    let lookup: Int
    if case .adjustment(.colorLookup(let a))=content {lookup=a.lut?.estimatedBytes ?? 0}else{lookup=0}
    return 256+lookup+(vectorMask?.path.knotCount ?? 0)*64+(smartFilters?.programBytes ?? 0)
  }
  public func validate(layer: Layer, in document: CraftDocument)throws {
    var sample=layer;apply(to:&sample);sample.parentID=nil;sample.clipped=nil
    sample.video=nil;sample.videoTiming=nil;sample.videoKeyframes=nil
    if var group=sample.group {group.videoStartTime=nil;sample.content = .group(group)}
    var check=document;check.variables=nil;check.animation=nil;check.videoTimeline=nil;check.layers=[sample];check.activeLayerID=sample.id
    try check.validate()
  }
}

/// A sampled transition remains an editable composition of the participating
/// layers. Its fraction is frozen for the frame; it is not a flattened bitmap.
public struct AnimationTransitionState: Codable, Equatable, Sendable {
  public var transition: VideoTransition
  public var progress: Float
  public init(transition:VideoTransition,progress:Float){self.transition=transition;self.progress=progress}
  public func validate(in document:CraftDocument)throws {
    guard progress.isFinite,(0...1).contains(progress),transition.duration.isFinite,
      transition.duration>1e-9,transition.duration<=86_400,
      transition.participants.isSubset(of:Set(document.layers.map(\.id))),
      (transition.kind == .crossFade) == (transition.previousLayerID != nil) else {throw CraftError.invalid("Invalid sampled frame transition.")}
    if transition.kind == .color {
      guard let c=transition.color,c.isFinite,c.a==1,(0...1).contains(c.r),(0...1).contains(c.g),(0...1).contains(c.b) else{throw CraftError.invalid("Invalid sampled transition color.")}
    }else if transition.color != nil {throw CraftError.invalid("Unexpected sampled transition color.")}
  }
}

/// Recoverable original temporal sources. Conversion never silently drops audio
/// or source frames. Frame animation itself is a visual, silent sequence.
public struct FrameVideoSource: Codable, Equatable, Sendable {
  public var width:Int
  public var height:Int
  public var depth:PixelDepth
  public var layers:[Layer]
  public var timeline:VideoTimeline
  public var activeLayerID:UUID?
  public init(_ document:CraftDocument)throws {
    guard let timeline=document.videoTimeline,document.animation==nil,timeline.retainedFrameSources==nil else{throw CraftError.invalid("Choose a video Timeline source.")}
    width=document.width;height=document.height;depth=document.depth;layers=document.layers
    self.timeline=timeline;activeLayerID=document.activeLayerID
  }
  public func document(in template:CraftDocument)throws->CraftDocument {
    guard timeline.retainedFrameSources==nil,width==template.width,height==template.height,depth==template.depth else{throw CraftError.invalid("Retained Timeline dimensions or depth changed.")}
    var source=template;source.animation=nil;source.layers=layers;source.videoTimeline=timeline;source.activeLayerID=activeLayerID
    return source
  }
  public var estimatedBytes:Int {
    let audio=timeline.audioTracks?.reduce(0){$0+$1.clips.reduce(0){$0+$1.source.data.count+256}} ?? 0
    return layers.reduce(audio){total,layer in
      let payload=AnimationLayerPayload(layer)
      let objectBytes = layer.smartObject?.data.count ?? 0
      let styleBytes = layer.style?.estimatedBytes ?? 0
      let tagBytes = layer.sourceTags?.values.reduce(0) { $0 + $1.count } ?? 0
      return total + payload.rasterBytes + payload.metadataBytes + (layer.video?.estimatedBytes ?? 0) + layer.keyframeBytes + objectBytes + styleBytes + tagBytes
    }
  }
}

extension CraftDocument {
  public func restoringFrameVideoSource()throws->CraftDocument {
    guard let origin=animation?.retainedVideoSource ?? videoTimeline?.retainedFrameSources?.first else{throw CraftError.invalid("This frame animation has no retained video source.")}
    let source=try origin.document(in:self);try source.validate();return source
  }
  public func convertingVideoToFrameAnimation()throws->CraftDocument {
    try validate()
    guard let timeline=videoTimeline,animation==nil,timeline.durationFrames<=FrameAnimation.maximumFrames,
      timeline.durationFrames*layers.count<=FrameAnimation.maximumLayerStates else {
      throw CraftError.invalid("Conversion requires a video Timeline within the current 512-frame and 65,536 layer-state limits.")
    }
    let origin:FrameVideoSource
    if let retained=timeline.retainedFrameSources?.first {origin=retained}else{origin=try FrameVideoSource(self)}
    var frames:[AnimationFrame]=[],payloads:[[AnimationLayerPayload]]=[],selected:[Layer]=[]
    let retainedBytes=origin.estimatedBytes
    var varying=Set<Int>(),sampleBytes=0
    for index in 0..<timeline.durationFrames {
      try Task.checkCancellation()
      let sampled=try videoDocument(at:index)
      var snapshot=sampled.videoCompositionSnapshot()
      let time=Double(index)/timeline.frameRate
      var transitions=(timeline.transitions ?? []).compactMap { transition -> AnimationTransitionState? in
        guard let interval=transition.interval(in:self),interval.contains(time) else{return nil}
        return .init(transition:transition,progress:Float(min(1,max(0,(time-interval.startTime)/interval.duration))))
      }
      transitions += timeline.frameTransitionKeys?.last(where:{$0.time<=time})?.states ?? []
      for item in transitions where item.transition.kind == .crossFade {
        for id in item.transition.participants {
          guard let i=sampled.layers.firstIndex(where:{$0.id==id}) else{continue}
          snapshot.layers[i].visible=sampled.layers[i].visible
          if let clip=sampled.layers[i].video {snapshot.layers[i].content = .raster(clip.frames[clip.extendedSourceIndex(at:time)])}
        }
      }
      var frame=AnimationFrame(layers:snapshot.layers,delay:1/timeline.frameRate)
      frame.sourceVideoFrame=index;frame.transitions=transitions.isEmpty ? nil:transitions
      let values=snapshot.layers.map(AnimationLayerPayload.init)
      sampleBytes += 128 + layers.count*192
      for j in values.indices {
        if let first=payloads.first,!varying.contains(j),values[j] != first[j] {
          varying.insert(j);sampleBytes += index*(first[j].rasterBytes+first[j].metadataBytes)
        }
        if varying.contains(j) {sampleBytes += values[j].rasterBytes+values[j].metadataBytes}
      }
      guard sampleBytes+retainedBytes<=1_073_741_824 else{throw CraftError.invalid("Sampled frames exceed the current 1 GiB document budget.")}
      frames.append(frame);payloads.append(values)
      if index==timeline.currentFrame {selected=snapshot.layers}
    }
    for layer in layers.indices where payloads.dropFirst().contains(where:{$0[layer] != payloads[0][layer]}) {
      for frame in frames.indices {frames[frame].layers[layer].payload=payloads[frame][layer]}
    }
    var result=self;result.layers=selected;result.videoTimeline=nil
    var converted=FrameAnimation(layers:selected);converted.frames=frames
    converted.selectedFrameID=frames[timeline.currentFrame].id
    converted.loopCount=timeline.finiteLoopCount ?? (timeline.looping ? 0:1)
    converted.retainedVideoSource=origin;converted.sampledTimeline=try FrameSampledTimeline(self);result.animation=converted
    try result.validate();return result
  }
}

public struct FrameTransitionKey:Codable,Equatable,Sendable {
  public var time:Double
  public var states:[AnimationTransitionState]
  public init(time:Double,states:[AnimationTransitionState]){self.time=time;self.states=states}
}
extension CraftDocument {
  public var retainedFrameSourceBytes:Int {videoTimeline?.retainedFrameSources?.reduce(0){$0+$1.estimatedBytes} ?? 0}
  public var sampledTransitionBytes:Int {videoTimeline?.frameTransitionKeys?.reduce(0){$0+128+$1.states.count*256} ?? 0}
  func validateSampledTimelineContent()throws {
    guard let timeline=videoTimeline else{return}
    guard (timeline.retainedFrameSources?.count ?? 0)<=1 else{throw CraftError.invalid("Only one original Timeline source may be retained.")}
    for source in timeline.retainedFrameSources ?? [] {try source.document(in:self).validate()}
    let keys=timeline.frameTransitionKeys ?? []
    guard keys.count<=512,keys.reduce(0,{$0+$1.states.count})<=65536,
      zip(keys,keys.dropFirst()).allSatisfy({$1.time>$0.time}) else{throw CraftError.invalid("Invalid sampled transition keys.")}
    for key in keys {
      guard key.time.isFinite,key.time < Double(timeline.durationFrames)/timeline.frameRate,
        key.time >= (timeline.trimmedToWorkArea == true ? -86400:0) else{throw CraftError.invalid("Sampled transition time is outside the Timeline.")}
      for state in key.states {try state.validate(in:self)}
    }
  }
}
