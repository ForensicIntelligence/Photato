import AppKit

/// Keep the delivered mouse/tablet samples while drawing. Rendering may combine
/// frames; stroke geometry must not lose the intermediate input that defines a curve.
@MainActor final class DrawingEventCapture {
  private static var owners: Set<UUID> = []
  private static var previous = true
  private let id = UUID()
  isolated deinit { end() }
  func begin() {
    guard !Self.owners.contains(id) else { return }
    if Self.owners.isEmpty { Self.previous = NSEvent.isMouseCoalescingEnabled }
    Self.owners.insert(id); NSEvent.isMouseCoalescingEnabled = false
  }
  func end() {
    guard Self.owners.remove(id) != nil else { return }
    if Self.owners.isEmpty { NSEvent.isMouseCoalescingEnabled = Self.previous }
  }
}
