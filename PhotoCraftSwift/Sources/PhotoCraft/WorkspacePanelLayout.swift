import Foundation

/// Allocates visible dock groups without allowing a divider to push Layers offscreen.
/// Preferred Properties height is retained separately, so shrinking the window is reversible.
struct WorkspacePanelLayout {
  let colorHeight: CGFloat
  let propertiesHeight: CGFloat
  let layersHeight: CGFloat
  let propertiesRange: ClosedRange<CGFloat>

  init(
    height: CGFloat, visibility: WorkspaceVisibility, library: Bool, preferredProperties: CGFloat
  ) {
    let height = height.isFinite ? max(0, height) : 0
    let separators: CGFloat =
      (visibility.color && (visibility.properties || visibility.layers) ? 3 : 0)
      + (visibility.properties && visibility.layers ? 5 : 0)
    let available = max(0, height - 12 - separators)
    colorHeight =
      visibility.color
      ? min(available, library ? min(224, height * 0.29) : min(168, height * 0.23)) : 0
    let remaining = max(0, available - colorHeight)
    let maximum = visibility.layers ? max(0, remaining - 220) : remaining
    propertiesRange = min(160, maximum)...maximum
    let preferred = preferredProperties.isFinite ? preferredProperties : 360
    propertiesHeight =
      visibility.properties
      ? (visibility.layers ? min(maximum, max(propertiesRange.lowerBound, preferred)) : remaining)
      : 0
    layersHeight = visibility.layers ? max(0, remaining - propertiesHeight) : 0
  }
}
