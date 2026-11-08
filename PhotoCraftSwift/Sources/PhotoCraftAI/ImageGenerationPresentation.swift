import Foundation

/// Configuration choices, separate from device eligibility and model readiness.
public struct ImageGenerationPresentation: Equatable, Sendable {
  public enum Style: String, Sendable {
    case any, illustration, animation, sketch
  }

  public let styles: [Style]
  public let usesCanvasSizeHint: Bool
  public var defaultStyle: Style? { styles.first }
  public static var current: Self {
    .init(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
  }

  public init(majorVersion: Int) {
    if majorVersion >= 27 {
      styles = [.any, .illustration, .animation, .sketch]
      usesCanvasSizeHint = true
    } else if majorVersion == 26 {
      styles = [.illustration, .animation, .sketch]
      usesCanvasSizeHint = false
    } else {
      styles = []
      usesCanvasSizeHint = false
    }
  }
}
