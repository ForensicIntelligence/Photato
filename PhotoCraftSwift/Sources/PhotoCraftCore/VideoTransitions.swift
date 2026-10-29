import Foundation

public enum VideoTransitionKind: String, Codable, CaseIterable, Sendable {
  case fade, crossFade, black, white, color
  public var title: String { switch self {case .fade:"Fade";case .crossFade:"Cross Fade";case .black:"Fade With Black";case .white:"Fade With White";case .color:"Fade With Color"} }
}
public enum VideoTransitionEdge: String, Codable, CaseIterable, Sendable {case start,end}
public struct VideoTransition: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var layerID: UUID
  public var previousLayerID: UUID?
  public var kind: VideoTransitionKind
  public var edge: VideoTransitionEdge
  public var duration: Double
  public var color: Pixel?
  public init(id: UUID = UUID(), layerID: UUID, previousLayerID: UUID? = nil,
              kind: VideoTransitionKind, edge: VideoTransitionEdge = .start, duration: Double, color: Pixel? = nil) {
    self.id=id;self.layerID=layerID;self.previousLayerID=previousLayerID;self.kind=kind;self.edge=edge;self.duration=duration;self.color=color
  }
  public var participants: Set<UUID> {Set([layerID]+(previousLayerID.map{[$0]} ?? []))}
  public var fadeColor: Pixel? {switch kind{case .black:.black;case .white:.white;case .color:color;default:nil}}
  public func interval(in document: CraftDocument) -> VideoLayerTiming? {
    guard let clip=document.layers.first(where:{$0.id==layerID})?.videoInterval else{return nil}
    if kind == .crossFade {return .init(startTime:clip.startTime-duration/2,duration:duration)}
    return .init(startTime:edge == .start ? clip.startTime:clip.startTime+clip.duration-duration,duration:duration)
  }
  public func maximumDuration(in document: CraftDocument) -> Double? {
    guard let layer=document.layers.first(where:{$0.id==layerID}),!layer.isClipped,
      layer.group?.videoStartTime == nil,let interval=layer.videoInterval else{return nil}
    if kind != .crossFade {return interval.duration}
    guard edge == .start,let previousLayerID,let previous=document.layers.first(where:{$0.id==previousLayerID}),
      previous.parentID==layer.parentID,!previous.isClipped,previous.group?.videoStartTime == nil,
      let earlier=previous.videoInterval,abs(earlier.startTime+earlier.duration-interval.startTime)<1e-7 else{return nil}
    let siblings=document.children(of:layer.parentID).filter{!$0.isClipped}
    guard let index=siblings.firstIndex(where:{$0.id==layer.id}),index>0,siblings[index-1].id==previous.id else{return nil}
    return 2*min(earlier.duration,interval.duration)
  }
  public func validate(in document: CraftDocument) throws {
    guard duration.isFinite,duration>1e-9,let maximum=maximumDuration(in:document),duration<=maximum+1e-9 else {
      throw CraftError.invalid("Choose a positive transition duration inside the clip; crossfades require adjacent clips with a shared boundary.")
    }
    guard (kind == .crossFade) == (previousLayerID != nil),
      kind == .color ? color?.isFinite == true && color!.a == 1 && (0...1).contains(color!.r) && (0...1).contains(color!.g) && (0...1).contains(color!.b):color == nil else {
      throw CraftError.invalid("Invalid transition color or partner.")
    }
  }
}
public enum VideoTransitionCommand: Sendable {
  case set(VideoTransition),remove(UUID)
  public func apply(to document: inout CraftDocument) throws {
    guard var timeline=document.videoTimeline else{throw CraftError.invalid("Create a video Timeline first.")}
    var transitions=timeline.transitions ?? []
    switch self {
    case .set(let transition):
      if let old=transitions.first(where:{$0.id==transition.id}),old.participants.contains(where:{document.isPositionLocked($0)}) {throw CraftError.invalid("Unlock the original transition clips before replacing it.")}
      for id in transition.participants {
        guard let index=document.layers.firstIndex(where:{$0.id==id}),!document.isPositionLocked(id) else{throw CraftError.invalid("Choose unlocked transition clips.")}
        if document.layers[index].videoInterval == nil {document.layers[index].videoTiming = .init(startTime:0,duration:Double(timeline.durationFrames)/timeline.frameRate)}
      }
      try transition.validate(in:document)
      if let i=transitions.firstIndex(where:{$0.id==transition.id}){transitions[i]=transition}else{transitions.append(transition)}
    case .remove(let id):
      guard let index=transitions.firstIndex(where:{$0.id==id}),transitions[index].participants.allSatisfy({!document.isPositionLocked($0)}) else{throw CraftError.invalid("Choose an existing unlocked transition.")}
      transitions.remove(at:index)
    }
    timeline.transitions=transitions.isEmpty ? nil:transitions;document.videoTimeline=timeline
    try document.validateVideoTransitions()
  }
}
extension CraftDocument {
  func validateVideoTransitions() throws {
    let transitions=videoTimeline?.transitions ?? []
    guard transitions.count<=1024,Set(transitions.map(\.id)).count==transitions.count else{throw CraftError.invalid("Too many or duplicate video transitions.")}
    for transition in transitions{try transition.validate(in:self)}
    for i in transitions.indices {
      let a=transitions[i],x=a.interval(in:self)!
      for b in transitions.dropFirst(i+1) where !a.participants.isDisjoint(with:b.participants) {
        let y=b.interval(in:self)!
        guard min(x.startTime+x.duration,y.startTime+y.duration)-max(x.startTime,y.startTime)<=1e-9 else{throw CraftError.invalid("Transitions on the same clip cannot overlap.")}
      }
    }
  }
  /// Preserve valid transitions during ripple edits. Broken boundaries disappear
  /// with the edit and return with Undo; shorter clips shorten their edge effects.
  mutating func reconcileVideoTransitions() {
    guard var timeline=videoTimeline else{return}
    let ids=Set(layers.map(\.id))
    for i in timeline.frameTransitionKeys?.indices ?? 0..<0 {timeline.frameTransitionKeys![i].states.removeAll{!$0.transition.participants.isSubset(of:ids)}}
    var transitions=timeline.transitions ?? []
    transitions=transitions.compactMap{old in guard let maximum=old.maximumDuration(in:self),maximum>1e-9 else{return nil};var t=old;t.duration=min(t.duration,maximum);return t}
    for layer in layers {
      guard let clip=layer.videoInterval else{continue}
      let indices=transitions.indices.filter{transitions[$0].participants.contains(layer.id)}
      let used=indices.reduce(0.0){$0+transitions[$1].duration*(transitions[$1].kind == .crossFade ? 0.5:1)}
      if used>clip.duration {for i in indices{transitions[i].duration *= clip.duration/used}}
    }
    timeline.transitions=transitions.isEmpty ? nil:transitions;videoTimeline=timeline
  }
  mutating func transferSplitTransitions(from original: UUID, to right: UUID) {
    guard var transitions=videoTimeline?.transitions else{return}
    for i in transitions.indices {
      if transitions[i].previousLayerID==original {transitions[i].previousLayerID=right}
      if transitions[i].layerID==original,transitions[i].kind != .crossFade,transitions[i].edge == .end {transitions[i].layerID=right}
    }
    videoTimeline?.transitions=transitions
  }
}
extension VideoClip {
  /// Media handles beyond a trim are retained; unavailable handles hold an edge frame.
  public func extendedSourceIndex(at seconds: Double) -> Int {
    let value=sourceStart+(seconds-startTime)*frameRate
    var low=0,high=frames.count
    while low+1<high {let mid=(low+high)/2;if sourceUnit(mid)<=value+1e-9{low=mid}else{high=mid}}
    return low
  }
}
