import Foundation

/// Component numbers are zero-based in the captured color mode. Recording the
/// mode prevents a replay from deleting a different plate in another color model.
public struct ProcessChannelDeletion: Codable, Equatable, Sendable {
  public let mode: DocumentColorMode
  public let components: [Int]
  public let mergeVisible: Bool

  public init(mode: DocumentColorMode, components: [Int], mergeVisible: Bool) {
    self.mode = mode
    self.components = components
    self.mergeVisible = mergeVisible
  }

  public static func unavailableReason(_ document: CraftDocument) -> String? {
    guard [.rgb, .cmyk, .lab].contains(document.colorMode), document.depth != .f32,
      !document.layers.isEmpty else {
      return "Process channel deletion requires an 8- or 16-bit RGB, CMYK or Lab image."
    }
    guard !document.hasArtboards, !document.hasFrames, document.animation == nil, document.videoTimeline == nil else {
      return "Prepare a single still canvas before deleting process channels."
    }
    guard document.quickMask == nil else { return "Exit Quick Mask before deleting process channels." }
    return nil
  }

  public func retainedComponents(in document: CraftDocument) throws -> [Int] {
    if let reason = Self.unavailableReason(document) { throw CraftError.unsupported(reason) }
    let available = 0..<document.colorMode.componentCount
    let dropping = Set(components)
    guard mode == document.colorMode, !components.isEmpty, components.count == dropping.count,
      components.count < available.count, components.allSatisfy(available.contains) else {
      throw CraftError.invalid("Select valid process channels and leave at least one channel.")
    }
    return available.filter { !dropping.contains($0) }
  }
}
