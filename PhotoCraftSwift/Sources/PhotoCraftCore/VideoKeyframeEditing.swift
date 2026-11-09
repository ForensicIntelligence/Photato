import Foundation

public struct VideoKeyframeReference: Hashable, Sendable {
  public let layerID: UUID
  public let keyframeID: UUID
  public init(layerID: UUID, keyframeID: UUID) { self.layerID=layerID; self.keyframeID=keyframeID }
}

/// Immutable application-local clipboard. Surfaces share copy-on-write tiles;
/// no unrelated layer pixels, movie data or system pasteboard are read.
public struct VideoKeyframeClipboard: Sendable {
  public struct Track: Sendable {
    public let sourceLayerID: UUID
    public let keys: [VideoKeyframe]
  }
  public let sourceDocumentID: UUID
  public let tracks: [Track]
  public let origin: Double
  public let depth: PixelDepth
  public let colorSpace: String
  public let workingICC: Data?
  public let profileIsUntagged: Bool?
  public var count: Int { tracks.reduce(0) { $0+$1.keys.count } }
  public static func capture(_ selection: Set<VideoKeyframeReference>, in document: CraftDocument) throws -> Self {
    guard document.videoTimeline != nil, !selection.isEmpty, selection.count<=65_536 else { throw CraftError.invalid("Select Timeline keyframes to copy.") }
    var found=Set<VideoKeyframeReference>(), tracks=[Track]()
    for layer in document.layers {
      let keys=(layer.videoKeyframes ?? []).filter { selection.contains(.init(layerID:layer.id,keyframeID:$0.id)) }
        .sorted { $0.time == $1.time ? $0.property.rawValue<$1.property.rawValue : $0.time<$1.time }
      if !keys.isEmpty {
        for key in keys { try key.validate(in:document); found.insert(.init(layerID:layer.id,keyframeID:key.id)) }
        tracks.append(Track(sourceLayerID:layer.id,keys:keys))
      }
    }
    guard found==selection, let origin=tracks.flatMap(\.keys).map(\.time).min() else { throw CraftError.invalid("The selected keyframes no longer exist.") }
    return Self(sourceDocumentID:document.id,tracks:tracks,origin:origin,depth:document.depth,colorSpace:document.colorSpace,workingICC:document.workingICC,profileIsUntagged:document.profileIsUntagged)
  }
}

public enum VideoKeyframeEdit: Sendable {
  case delete(Set<VideoKeyframeReference>)
  case interpolation(Set<VideoKeyframeReference>, KeyframeInterpolation)
  case move(Set<VideoKeyframeReference>, seconds: Double, duplicate: Bool)
  case paste(VideoKeyframeClipboard, layers: [UUID], time: Double)
  public var label: String {
    switch self {
    case .delete: "Delete Keyframes"
    case .interpolation(_,let value): value == .linear ? "Linear Interpolation" : "Hold Interpolation"
    case .move(_,_,let duplicate): duplicate ? "Duplicate Keyframes" : "Move Keyframes"
    case .paste: "Paste Keyframes"
    }
  }
  public func apply(to document: inout CraftDocument) throws {
    try Task.checkCancellation()
    guard var timeline=document.videoTimeline else { throw CraftError.invalid("Create a video Timeline first.") }
    var result=document
    func eligible(_ layerID: UUID, _ property: VideoProperty, converted: Bool) throws -> Int {
      guard let i=result.layers.firstIndex(where:{$0.id==layerID}), !result.isLocked(layerID) else { throw CraftError.invalid("Choose unlocked Timeline layers.") }
      let layer=result.layers[i]
      if property == .content, layer.video != nil { throw CraftError.unsupported("Content keys require an ordinary layer.") }
      if case .adjustment=layer.content, property != .opacity, property != .visibility, !converted { throw CraftError.unsupported("This adjustment layer cannot animate that property.") }
      if property.isGeometry {
        guard !result.isPositionLocked(layerID), converted || (!layer.isGroup && layer.smartFilters==nil && layer.warp==nil) else { throw CraftError.unsupported("Unlock a supported geometry track first.") }
      }
      return i
    }
    func insert(_ key: VideoKeyframe, into layerID: UUID, overwrite: Bool) throws {
      let i=try eligible(layerID,key.property,converted:key.frameComposition == true)
      try key.validate(in:result)
      var keys=result.layers[i].videoKeyframes ?? []
      guard !key.property.isGeometry || !keys.contains(where:{$0.property.isGeometry && $0.property != key.property}) else { throw CraftError.invalid("Choose either Position or Transform animation for the destination.") }
      if let at=keys.firstIndex(where:{$0.property==key.property && abs($0.time-key.time)<1e-9}) {
        guard overwrite else { throw CraftError.invalid("A keyframe already exists at a destination time.") }
        var replacement=key; replacement.id=keys[at].id; keys[at]=replacement
      } else { keys.append(key) }
      result.layers[i].videoKeyframes=keys
    }
    switch self {
    case .paste(let clipboard,let destinations,let time):
      guard time.isFinite, (0...86_400).contains(time), !destinations.isEmpty, destinations.count<=LayerLimits.maximumLayers, Set(destinations).count==destinations.count,
        clipboard.tracks.count==1 || clipboard.tracks.count==destinations.count else { throw CraftError.invalid("Choose one destination per copied layer, or destinations for one copied track set.") }
      // Admit the final key/metadata counts before allocating copies. A single
      // full track replicated across hundreds of layers must not build millions
      // of keys and rely on final document validation to reject them.
      let incomingCount=clipboard.tracks.count==1 ? clipboard.count*destinations.count : clipboard.count
      guard incomingCount<=65_536 else { throw CraftError.invalid("Pasted keyframes exceed the document key budget.") }
      var projectedCount=result.layers.reduce(0){$0+($1.videoKeyframes?.count ?? 0)}
      var projectedMetadata=result.layers.flatMap{$0.videoKeyframes ?? []}.reduce(0){$0+$1.metadataBytes}
      for (index,id) in destinations.enumerated() {
        guard let layer=result.layers.first(where:{$0.id==id}) else { throw CraftError.invalid("A keyframe destination no longer exists.") }
        let old=layer.videoKeyframes ?? [],incoming=clipboard.tracks[clipboard.tracks.count==1 ? 0:index].keys
        var count=old.count
        for key in incoming {
          let at=time+(key.time-clipboard.origin)
          if let replaced=old.first(where:{$0.property==key.property && abs($0.time-at)<1e-9}) {
            projectedMetadata-=replaced.metadataBytes
          } else { count+=1;projectedCount+=1 }
          projectedMetadata+=key.metadataBytes
        }
        guard count<=4096 else { throw CraftError.invalid("Pasted keyframes exceed a layer's key budget.") }
      }
      guard projectedCount<=65_536,projectedMetadata<=64*1024*1024 else { throw CraftError.invalid("Pasted keyframes exceed the document metadata budget.") }
      let hasColour=clipboard.tracks.flatMap(\.keys).contains{$0.property == .style || $0.property == .content}
      guard !hasColour || (clipboard.depth==result.depth && clipboard.colorSpace==result.colorSpace && clipboard.workingICC==result.workingICC && clipboard.profileIsUntagged==result.profileIsUntagged) else { throw CraftError.unsupported("Match document depth and working profile before pasting colour or content keyframes.") }
      for (index,id) in destinations.enumerated() {
        for value in clipboard.tracks[clipboard.tracks.count==1 ? 0:index].keys {
          try Task.checkCancellation()
          var key=value;key.id=UUID();key.time=time+(value.time-clipboard.origin)
          try insert(key,into:id,overwrite:true)
        }
      }
    case .delete(let selection), .interpolation(let selection,_), .move(let selection,_,_):
      let clipboard=try VideoKeyframeClipboard.capture(selection,in:result)
      for track in clipboard.tracks { for key in track.keys { _=try eligible(track.sourceLayerID,key.property,converted:key.frameComposition == true) } }
      switch self {
      case .delete:
        for i in result.layers.indices {
          let id=result.layers[i].id
          result.layers[i].videoKeyframes?.removeAll { selection.contains(.init(layerID:id,keyframeID:$0.id)) }
        }
      case .interpolation(_,let value):
        for i in result.layers.indices {
          guard var keys=result.layers[i].videoKeyframes else { continue }
          for j in keys.indices where selection.contains(.init(layerID:result.layers[i].id,keyframeID:keys[j].id)) {
            guard value == .hold || (keys[j].property != .content && keys[j].property != .visibility) else { throw CraftError.invalid("Content and Visibility use Hold interpolation.") }
            keys[j].interpolation=value
          }
          result.layers[i].videoKeyframes=keys
        }
      case .move(_,let delta,let duplicate):
        guard delta.isFinite, (-86_400...86_400).contains(delta) else { throw CraftError.invalid("Choose a finite keyframe time offset within one day.") }
        if duplicate {
          let existing=result.layers.flatMap{$0.videoKeyframes ?? []},copied=clipboard.tracks.flatMap(\.keys)
          guard existing.count+copied.count<=65_536,existing.reduce(0,{$0+$1.metadataBytes})+copied.reduce(0,{$0+$1.metadataBytes})<=64*1024*1024,
            clipboard.tracks.allSatisfy({track in (result.layers.first{$0.id==track.sourceLayerID}?.videoKeyframes?.count ?? 0)+track.keys.count<=4096}) else { throw CraftError.invalid("Duplicated keyframes exceed a Timeline key or metadata budget.") }
        }
        if !duplicate {
          for i in result.layers.indices {
            let id=result.layers[i].id
            result.layers[i].videoKeyframes?.removeAll { selection.contains(.init(layerID:id,keyframeID:$0.id)) }
          }
        }
        for track in clipboard.tracks { for value in track.keys {
          var key=value;key.time+=delta;if duplicate { key.id=UUID() }
          try insert(key,into:track.sourceLayerID,overwrite:false)
        } }
      case .paste: break
      }
    }
    for i in result.layers.indices {
      if result.layers[i].videoKeyframes?.isEmpty == true { result.layers[i].videoKeyframes=nil }
      result.layers[i].videoKeyframes?.sort { $0.time == $1.time ? $0.property.rawValue<$1.property.rawValue : $0.time<$1.time }
    }
    if let last=result.layers.flatMap({$0.videoKeyframes ?? []}).map(\.time).max() {
      timeline.durationFrames=max(timeline.durationFrames,Int(ceil(last*timeline.frameRate-1e-9))+1)
    }
    result.videoTimeline=timeline;try result.selectVideoFrame(timeline.currentFrame)
    try result.validate();try Task.checkCancellation();document=result
  }
}
