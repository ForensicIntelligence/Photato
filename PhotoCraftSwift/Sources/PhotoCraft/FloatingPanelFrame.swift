import AppKit

/// Expanded outer window frame in AppKit screen coordinates. Optional in old workspace files.
struct FloatingPanelFrame: Codable, Equatable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double

  init(_ rect: NSRect) {
    x = rect.minX
    y = rect.minY
    width = rect.width
    height = rect.height
  }
  var rect: NSRect { NSRect(x: x, y: y, width: width, height: height) }
  var isValid: Bool {
    [x, y, width, height].allSatisfy(\.isFinite)
      && abs(x) <= 100000 && abs(y) <= 100000
      && (275...4000).contains(width) && (120...4000).contains(height)
  }

  /// Keep the entire title bar reachable after display removal or workspace transfer.
  /// The saved frame is retained until the user actually moves/resizes the recovered window.
  func fitted(to screens: [NSRect]) -> NSRect {
    let usable = screens.filter {
      !$0.isEmpty && [$0.minX, $0.minY, $0.width, $0.height].allSatisfy(\.isFinite)
    }
    guard
      let screen = usable.max(by: { first, second in
        func area(_ screen: NSRect) -> CGFloat {
          let intersection = rect.intersection(screen)
          return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        return area(first) < area(second)
      })
    else { return rect }
    let width = min(rect.width, screen.width)
    let height = min(rect.height, screen.height)
    return NSRect(
      x: min(max(rect.minX, screen.minX), screen.maxX - width),
      y: min(max(rect.minY, screen.minY), screen.maxY - height),
      width: width, height: height)
  }
}

@MainActor extension WorkspaceLibrary {
  @discardableResult func floatPanels(_ source: PanelDockSource, frame: FloatingPanelFrame) -> Bool
  {
    guard !workspaceLocked, frame.isValid else { return false }
    var dock = panelDock
    guard let panels = dock.panels(for: source), let first = panels.first,
      let origin = dock.groups.firstIndex(where: { $0.panels.contains(first) })
    else { return false }
    if let selected = dock.selectedPanel(in: dock.groups[origin], visibility: layout.visibility) {
      dock.groups[origin].selected = selected
    }
    if panels.count < dock.groups[origin].panels.count {
      guard
        dock.move(
          source, to: .beforeGroup(nil), floatingTitlebarHeight: FloatingPanelWindow.titlebarHeight)
      else { return false }
    }
    guard let index = dock.groups.firstIndex(where: { $0.panels.contains(first) }) else {
      return false
    }
    let previous = dock
    dock.groups[index].floatingStack = nil
    dock.groups[index].floatingFrame = frame
    dock.shrinkDepartedStacks(from: previous, titlebarHeight: FloatingPanelWindow.titlebarHeight)
    guard dock != panelDock else { return false }
    layout.panelDock = dock
    return true
  }

  func recordFloatingPanelFrame(_ id: String, frame: NSRect) {
    var dock = panelDock
    guard let index = dock.groups.firstIndex(where: { $0.id == id }),
      let old = dock.groups[index].floatingFrame
    else { return }
    var next = FloatingPanelFrame(frame)
    if dock.groups[index].collapsed {
      next.height = old.height
      next.y = frame.maxY - old.height
    }
    if workspaceLocked {
      // Resize stays available while Lock Workspace prevents title-bar movement.
      next.x = old.x
      next.y = old.rect.maxY - next.height
    }
    guard next.isValid, next != old else { return }
    for position in dock.groups.indices
    where dock.groups[position].floatingHostID == dock.groups[index].floatingHostID {
      dock.groups[position].floatingFrame = next
    }
    layout.panelDock = dock
  }
}
