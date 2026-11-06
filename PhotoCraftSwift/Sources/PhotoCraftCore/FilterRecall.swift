import Foundation

extension Command {
  /// Settings from a successfully applied filter, independent of its original target.
  public func filterRecallValue(in source: CraftDocument) -> RasterFilter? {
    switch self {
    case .applyFilter(_, let filter), .channel(.filter(_, let filter)),
      .inkChannel(.edit(_, .filter(let filter))):
      return filter
    case .modeComponents(let edit):
      if case .filter(let filter) = edit.operation { return filter }
    case .blurGalleryMask(let edit):return edit.filter
    case .smartFilters(let id, let stack):
      guard let stack, stack.enabled else { return nil }
      let previous = source.layers.first { $0.id == id }?.smartFilters?.filters ?? []
      return stack.filters.last { item in
        item.enabled && previous.first { $0.id == item.id }?.filter != item.filter
      }?.filter
    default: break
    }
    return nil
  }
}

extension PreparedEdit {
  public var filterRecallValue: RasterFilter? {
    recordingCommand?.filterRecallValue(in: original)
  }
}
