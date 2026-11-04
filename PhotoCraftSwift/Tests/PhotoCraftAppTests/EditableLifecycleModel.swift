import Foundation
import PhotoCraftCore
@testable import PhotoCraft

/// Generic lifecycle fixtures need an editable layer, not File/New Background
/// semantics. Retain the factory pixels, dimensions, depth, profile and identity.
@MainActor enum EditableLifecycleModel {
  static func make(
    width: Int = 1200, height: Int = 800, depth: PixelDepth = .u8,
    background: Pixel = .white, name: String = "Untitled-1",
    mode: DocumentColorMode? = nil, profile: Data? = nil, resolution: Double? = nil
  ) throws -> CraftDocument {
    var model = try CraftNSDocument.blankModel(width: width, height: height,
      depth: depth, background: background, name: name, mode: mode,
      profile: profile, resolution: resolution)
    model.layers[0].background = nil
    return model
  }
}
