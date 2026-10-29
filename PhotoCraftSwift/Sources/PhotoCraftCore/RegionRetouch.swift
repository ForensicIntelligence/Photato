import Foundation

public struct RegionRetouchRequest: Equatable, Sendable {
  public enum Kind: String, Sendable { case patch, move, redEye }
  public enum PatchMode: String, CaseIterable, Sendable { case source, destination }
  public enum PatchType: String, CaseIterable, Sendable { case normal, contentAware }
  public enum MoveMode: String, CaseIterable, Sendable { case move, extend }
  public var kind: Kind
  public var patchMode = PatchMode.source
  public var patchType = PatchType.normal
  public var moveMode = MoveMode.move
  public var dx = 0.0
  public var dy = 0.0
  public var scaleX = 100.0
  public var scaleY = 100.0
  public var angle = 0.0
  public var diffusion = 5
  public var structure = 4
  public var color = 0
  public var sampleAllLayers = false
  public var transparent = false
  public var seed: UInt32 = 1
  public var region: IntRect?
  public var pupilSize = 50.0
  public var darken = 50.0
  public init(kind: Kind) { self.kind = kind }
  public var label: String {
    switch kind {
    case .patch: patchMode == .source ? "Patch" : "Patch (Destination)"
    case .move: moveMode == .move ? "Content-Aware Move" : "Content-Aware Extend"
    case .redEye: "Red Eye"
    }
  }
  public func validate() throws {
    guard dx.isFinite, dy.isFinite, abs(dx) <= 1_000_000, abs(dy) <= 1_000_000,
      scaleX.isFinite, scaleY.isFinite, (1...1000).contains(scaleX), (1...1000).contains(scaleY),
      angle.isFinite, (-360...360).contains(angle), (1...7).contains(diffusion),
      (1...7).contains(structure), (0...10).contains(color),
      pupilSize.isFinite, darken.isFinite, (1...100).contains(pupilSize), (0...100).contains(darken)
    else { throw CraftError.invalid("Invalid retouching settings.") }
    if kind == .patch && (dx != dx.rounded() || dy != dy.rounded() || scaleX != 100 || scaleY != 100 || angle != 0) {
      throw CraftError.invalid("Patch requires a whole-pixel offset without scaling or rotation.")
    }
    if kind == .redEye {
      guard let region, (-1_000_000...1_000_000).contains(region.x), (-1_000_000...1_000_000).contains(region.y),
        region.width > 0, region.height > 0, region.width <= 60000, region.height <= 60000
      else { throw CraftError.invalid("Draw a region around the red eye.") }
    }
  }
  public func transform(bounds: IntRect) -> Transform2D {
    let x = Double(bounds.x) + Double(bounds.width)/2, y = Double(bounds.y) + Double(bounds.height)/2
    return .translation(x+dx,y+dy) * .rotation(angle) * .scale(scaleX/100,scaleY/100) * .translation(-x,-y)
  }
}

/// Immutable prepared edit keeps preview, API and history commits on the same source revision.
public struct RegionRetouchEdit: Sendable {
  public let source: CraftDocument
  public let result: CraftDocument
  public let label: String
  public init(source: CraftDocument, result: CraftDocument, label: String) {
    self.source = source; self.result = result; self.label = label
  }
  public func applied(to original: CraftDocument) throws -> CraftDocument {
    try Task.checkCancellation()
    guard original == source else { throw CraftError.invalid("Document changed during retouching.") }
    try result.validate()
    return result
  }
}
