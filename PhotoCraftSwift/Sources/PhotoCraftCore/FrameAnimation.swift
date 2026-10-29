import Foundation

/// Ordinary frame animation shares layer pixels. Sampled video frames may retain
/// independent content payloads as well as composition properties.
public struct AnimationLayerState: Codable, Equatable, Sendable {
  public var payload: AnimationLayerPayload?
  public var layerID: UUID
  public var visible: Bool
  public var opacity: Float
  public var x: Int
  public var y: Int
  public var affine: Transform2D?
  public var style: LayerStyle?
  public init(_ layer: Layer, capturingPayload: Bool = false) {
    payload = capturingPayload ? AnimationLayerPayload(layer):nil
    layerID = layer.id; visible = layer.visible; opacity = layer.opacity
    x = layer.x; y = layer.y; affine = layer.affine; style = layer.style
  }
  func apply(to layer: inout Layer) {
    payload?.apply(to:&layer)
    layer.visible = visible; layer.opacity = opacity; layer.x = x; layer.y = y
    layer.affine = affine; layer.style = style
  }
}
public struct AnimationFrame: Codable, Equatable, Identifiable, Sendable {
  public var id = UUID()
  public var sourceVideoFrame: Int?
  public var transitions: [AnimationTransitionState]?
  public var delay: Double
  public var layers: [AnimationLayerState]
  public init(layers: [Layer], delay: Double = 0.1) {
    self.layers = layers.map { AnimationLayerState($0) }; self.delay = delay
  }
}
public struct FrameAnimation: Codable, Equatable, Sendable {
  public var retainedVideoSource: FrameVideoSource?
  public var sampledTimeline:FrameSampledTimeline?
  public static let maximumFrames = 512
  public static let maximumLayerStates = 65_536
  public var frames: [AnimationFrame]
  public var selectedFrameID: UUID
  /// Zero repeats indefinitely; positive values specify total passes.
  public var loopCount = 0
  public init(layers: [Layer]) {
    let frame = AnimationFrame(layers: layers); frames = [frame]; selectedFrameID = frame.id
  }
  public var selectedIndex: Int { frames.firstIndex { $0.id == selectedFrameID } ?? 0 }
  public var metadataBytes: Int {
    frames.reduce(0) { $0 + 128 + ($1.transitions?.count ?? 0)*256 + $1.layers.reduce(0) { $0 + 192 + ($1.style?.estimatedBytes ?? 0) + ($1.payload?.metadataBytes ?? 0) } }
  }
  public var estimatedBytes: Int {
    metadataBytes + (sampledTimeline?.estimatedBytes ?? 0) + (retainedVideoSource?.estimatedBytes ?? 0) + frames.reduce(0){$0+$1.layers.reduce(0){$0+($1.payload?.rasterBytes ?? 0)}}
  }
  public func validate(in document: CraftDocument) throws {
    guard !document.hasArtboards, !frames.isEmpty, frames.count <= Self.maximumFrames,
      Set(frames.map(\.id)).count == frames.count, frames.contains(where: { $0.id == selectedFrameID }),
      (0...65_535).contains(loopCount), frames.count * document.layers.count <= Self.maximumLayerStates,
      metadataBytes <= 64 * 1024 * 1024 else { throw CraftError.invalid("Invalid or oversized frame animation.") }
    if let retainedVideoSource {try retainedVideoSource.document(in:document).validate()}
    try sampledTimeline?.validate(in:document)
    let ids = Set(document.layers.map(\.id))
    for frame in frames {
      if let index=frame.sourceVideoFrame {guard index>=0,index<20_736_001 else{throw CraftError.invalid("Invalid original video frame index.")}}
      guard (frame.transitions?.count ?? 0)<=1024 else{throw CraftError.invalid("Too many sampled transitions.")}
      for transition in frame.transitions ?? [] {try transition.validate(in:document)}
      guard frame.delay.isFinite, (0...3600).contains(frame.delay), frame.layers.count == ids.count,
        Set(frame.layers.map(\.layerID)) == ids else { throw CraftError.invalid("Animation frame layers or delay are invalid.") }
      for state in frame.layers {
        guard state.opacity.isFinite, (0...1).contains(state.opacity),
          (-1_000_000...1_000_000).contains(state.x), (-1_000_000...1_000_000).contains(state.y)
        else { throw CraftError.invalid("Invalid animated layer properties.") }
        if let affine = state.affine { try affine.validated() }
        try state.style?.validate()
        if let payload=state.payload,let layer=document.layers.first(where:{$0.id==state.layerID}) {try payload.validate(layer:layer,in:document)}
      }
    }
    let current = Dictionary(uniqueKeysWithValues: frames[selectedIndex].layers.map { ($0.layerID, $0) })
    guard document.layers.allSatisfy({ current[$0.id] == AnimationLayerState($0,capturingPayload:current[$0.id]?.payload != nil) }) else {
      throw CraftError.invalid("The selected frame does not match the layer composition.")
    }
  }
  public func playbackDelay(at index:Int)->Double {
    let frame=frames[index]
    return frame.sourceVideoFrame != nil && frame.delay>0 ? frame.delay:max(0.02,frame.delay)
  }
  /// Deterministic playback clock, independent of display refresh and render latency.
  public func playbackFrame(elapsed: Double, startingAt index: Int) throws -> (index: Int, finished: Bool) {
    guard frames.indices.contains(index), elapsed.isFinite, elapsed >= 0 else { throw CraftError.invalid("Invalid animation clock.") }
    let order = Array(index..<frames.count) + Array(0..<index)
    let duration = order.reduce(0.0) { $0 + playbackDelay(at:$1) }
    if loopCount > 0, elapsed >= duration * Double(loopCount) { return (order.last!, true) }
    var time = elapsed.truncatingRemainder(dividingBy: duration)
    for i in order { let delay = playbackDelay(at:i); if time < delay { return (i, false) }; time -= delay }
    return (order.last!, false)
  }
}

extension CraftDocument {
  public mutating func selectAnimationFrame(_ id: UUID) throws {
    guard var animation, let frame = animation.frames.first(where: { $0.id == id }) else {
      throw CraftError.invalid("Animation frame no longer exists.")
    }
    guard frame.layers.count == layers.count, Set(frame.layers.map(\.layerID)).count == frame.layers.count else { throw CraftError.invalid("Invalid frame layer identifiers.") }
    let states = Dictionary(uniqueKeysWithValues: frame.layers.map { ($0.layerID, $0) })
    guard Set(states.keys) == Set(layers.map(\.id)) else { throw CraftError.invalid("Animation layers changed.") }
    for i in layers.indices { states[layers[i].id]!.apply(to: &layers[i]) }
    animation.selectedFrameID = id; self.animation = animation
  }
  public func animationDocument(at id: UUID) throws -> CraftDocument {
    var result = self; try result.selectAnimationFrame(id); return result
  }
  /// Layer pixels and structure are shared. Composition changes belong to the selected frame.
  mutating func captureAnimationChanges() throws {
    guard var animation else { return }
    let ids = Set(layers.map(\.id))
    let current=Dictionary(uniqueKeysWithValues:animation.frames[animation.selectedIndex].layers.map{($0.layerID,$0)})
    let snapshot = layers.map { AnimationLayerState($0,capturingPayload:current[$0.id]?.payload != nil) }
    for i in animation.frames.indices {
      animation.frames[i].transitions?.removeAll{!$0.transition.participants.isSubset(of:ids)}
      if animation.frames[i].id == animation.selectedFrameID { animation.frames[i].layers = snapshot }
      else {
        animation.frames[i].layers.removeAll { !ids.contains($0.layerID) }
        let existing = Set(animation.frames[i].layers.map(\.layerID))
        animation.frames[i].layers += snapshot.filter { !existing.contains($0.layerID) }
      }
    }
    self.animation = animation
  }
}
public enum AnimationCommand: Sendable {
  case convertToVideo(Double)
  case convertFromVideo, restoreVideoSource
  case create, remove, fromLayers, duplicate, delete, reverse
  case reorder(Int), delay(Double), loop(Int)
  case tween(count: Int, position: Bool, opacity: Bool)
  public var label: String {
    switch self {
    case .convertToVideo: "Convert to Video Timeline"
    case .convertFromVideo: "Convert to Frame Animation"
    case .restoreVideoSource: "Restore Original Video Timeline"
    case .create: "Create Frame Animation"
    case .remove: "Delete Animation"
    case .fromLayers: "Make Frames From Layers"
    case .duplicate: "Duplicate Selected Frames"
    case .delete: "Delete Selected Frames"
    case .reverse: "Reverse Frames"
    case .reorder: "Move Frame"
    case .delay: "Frame Delay"
    case .loop: "Animation Looping"
    case .tween: "Tween Animation Frames"
    }
  }
  public func apply(to document: inout CraftDocument) throws {
    try document.validate()
    if case .convertFromVideo=self {document=try document.convertingVideoToFrameAnimation();return}
    if case .restoreVideoSource=self {document=try document.restoringFrameVideoSource();return}
    if case .convertToVideo(let rate)=self {document=try document.convertingFrameAnimation(frameRate:rate);return}
    var result = document
    switch self {
    case .create, .fromLayers:
      guard result.animation == nil, !result.hasArtboards else { throw CraftError.invalid("Create animation in a document without an existing timeline or artboards.") }
      var animation = FrameAnimation(layers: result.layers)
      if case .fromLayers = self {
        let roots = result.layers.filter { $0.parentID == nil }
        guard !roots.isEmpty else { throw CraftError.invalid("Create layers first.") }
        animation.frames = roots.map { root in
          var frame = AnimationFrame(layers: result.layers)
          let rootIDs = Set(roots.map(\.id))
          for i in frame.layers.indices where rootIDs.contains(frame.layers[i].layerID) { frame.layers[i].visible = frame.layers[i].layerID == root.id }
          return frame
        }
        animation.selectedFrameID = animation.frames[0].id
      }
      result.animation = animation; try result.selectAnimationFrame(animation.selectedFrameID)
    case .remove:
      guard result.animation != nil else { throw CraftError.invalid("No frame animation.") }
      result.animation = nil
    default:
      guard var animation = result.animation else { throw CraftError.invalid("Create a frame animation first.") }
      let i = animation.selectedIndex
      switch self {
      case .duplicate:
        var frame = animation.frames[i]; frame.id = UUID(); animation.frames.insert(frame, at: i + 1); animation.selectedFrameID = frame.id
      case .delete:
        guard animation.frames.count > 1 else { throw CraftError.invalid("Keep at least one frame, or delete the animation.") }
        animation.frames.remove(at: i); animation.selectedFrameID = animation.frames[min(i, animation.frames.count - 1)].id
      case .reverse: animation.frames.reverse()
      case .reorder(let destination):
        guard animation.frames.indices.contains(destination) else { throw CraftError.invalid("Invalid destination frame index.") }
        let frame = animation.frames.remove(at: i); animation.frames.insert(frame, at: destination)
      case .delay(let value): animation.frames[i].delay = value
      case .loop(let count): animation.loopCount = count
      case .tween(let count, let position, let opacity):
        guard animation.frames.count > 1, (1...100).contains(count), position || opacity,
          animation.frames.count + count <= FrameAnimation.maximumFrames else { throw CraftError.invalid("Tween needs two frames, 1–100 additions and an animated property.") }
        let next = animation.frames[(i + 1) % animation.frames.count]
        let targets = Dictionary(uniqueKeysWithValues: next.layers.map { ($0.layerID, $0) })
        var additions: [AnimationFrame] = []
        for n in 1...count {
          try Task.checkCancellation()
          let amount = Double(n) / Double(count + 1)
          var frame = animation.frames[i]; frame.id = UUID()
          for j in frame.layers.indices {
            let start = frame.layers[j], end = targets[start.layerID]!
            if position {
              let a = start.affine ?? .identity, b = end.affine ?? .identity
              guard a.a == b.a, a.b == b.b, a.c == b.c, a.d == b.d else { throw CraftError.unsupported("Frame tween supports position; differing affine rotation/scale needs timeline keyframes.") }
              func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * amount }
              frame.layers[j].x = Int(mix(Double(start.x), Double(end.x)).rounded())
              frame.layers[j].y = Int(mix(Double(start.y), Double(end.y)).rounded())
              if start.affine != nil || end.affine != nil { frame.layers[j].affine = .init(a:a.a,b:a.b,c:a.c,d:a.d,tx:mix(a.tx,b.tx),ty:mix(a.ty,b.ty)) }
            }
            if opacity { frame.layers[j].opacity = start.opacity + (end.opacity - start.opacity) * Float(amount) }
          }
          additions.append(frame)
        }
        animation.frames.insert(contentsOf: additions, at: i + 1)
      default: break
      }
      result.animation = animation; try result.selectAnimationFrame(animation.selectedFrameID)
    }
    try result.validate(); document = result
  }
}
extension Command {
  func validateAnimationContext(in document: CraftDocument) throws {
    guard document.animation != nil else { return }
    switch self {
    case .crop, .cropDocument, .canvasSize, .imageSize, .rotateCanvas, .mergeLayers,
      .documentMode, .preparedDocumentMode, .preparedColorProfile, .artboard:
      throw CraftError.unsupported("This operation does not yet transform all animation frames. Keep the animated original and prepare a still copy first.")
    default: break
    }
  }
}
extension EditorSession {
  /// Selection changes neither undo/redo nor action recording; stale prepared edits still reject.
  public mutating func selectAnimationFrame(_ id: UUID) throws {
    var candidate = document; try candidate.selectAnimationFrame(id); try candidate.validate()
    endCoalescing(); setAnimationSelection(candidate)
  }
}
