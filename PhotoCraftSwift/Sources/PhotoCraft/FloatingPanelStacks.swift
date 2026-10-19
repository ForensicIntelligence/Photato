import AppKit

extension PanelDock {
  func floatingGroups(_ hostID: String) -> [PanelDockGroup] {
    groups.filter { $0.floatingFrame != nil && $0.floatingHostID == hostID }
  }

  /// A stack keeps its identity even after its original first group leaves.
  mutating func shrinkDepartedStacks(from previous: PanelDock, titlebarHeight: Double) {
    for hostID in Set(previous.groups.filter { $0.floatingStack != nil }.map(\.floatingHostID)) {
      let old = previous.floatingGroups(hostID)
      let remaining = floatingGroups(hostID)
      guard !remaining.isEmpty, remaining.count < old.count,
        var frame = old.first?.floatingFrame
      else { continue }
      let sizes = FloatingPanelStackSizing.expandedHeights(
        old, height: frame.height - titlebarHeight)
      let removed = old.filter { group in !remaining.contains { $0.id == group.id } }
      let reduction = removed.reduce(0) { $0 + (sizes[$1.id] ?? 0) + 4 }
      let top = frame.rect.maxY
      frame.height = max(120, frame.height - reduction)
      frame.y = top - frame.height
      for index in groups.indices where groups[index].floatingHostID == hostID {
        groups[index].floatingFrame = frame
        groups[index].preferredHeight = sizes[groups[index].id]
      }
    }
  }
}

/// Expanded row sizes are retained independently from collapsed and hidden presentation.
struct FloatingPanelStackSizing {
  struct Row: Identifiable {
    let group: PanelDockGroup
    var height: CGFloat
    let gap: CGFloat
    var id: String { group.id }
  }
  let rows: [Row]
  let naturalHeight: CGFloat
  let expanded: [String: Double]
  var heights: [String: Double] {
    Dictionary(uniqueKeysWithValues: rows.map { ($0.id, Double($0.height)) })
  }

  static func expandedHeights(_ groups: [PanelDockGroup], height: Double) -> [String: Double] {
    let available = max(0, height - Double(max(0, groups.count - 1)) * 4)
    let weights = groups.map { max(80, $0.preferredHeight ?? 280) }
    let values = allocate(weights, available: available, minimum: 80)
    return Dictionary(uniqueKeysWithValues: zip(groups.map(\.id), values))
  }

  static func allocate(_ weights: [Double], available: Double, minimum: Double) -> [Double] {
    guard !weights.isEmpty else { return [] }
    let base = min(minimum, available / Double(weights.count))
    let extra = max(0, available - base * Double(weights.count))
    let excess = weights.map { max(0, $0 - base) }
    let sum = excess.reduce(0, +)
    return excess.map { base + (sum > 0 ? extra * $0 / sum : extra / Double(weights.count)) }
  }

  init(
    dock: PanelDock, hostID: String, visibility: WorkspaceVisibility,
    expandedHeight: Double, visibleHeight: Double? = nil
  ) {
    let groups = dock.floatingGroups(hostID)
    let expanded = Self.expandedHeights(groups, height: max(0, expandedHeight))
    self.expanded = expanded
    let shown = groups.filter { !dock.visiblePanels(in: $0, visibility: visibility).isEmpty }
    var values = shown.map { $0.collapsed ? 29 : expanded[$0.id] ?? 80 }
    let gaps = Double(max(0, shown.count - 1)) * 4
    naturalHeight = values.reduce(0, +) + gaps
    if let visibleHeight, visibleHeight.isFinite {
      let available = max(0, visibleHeight - gaps)
      let open = shown.indices.filter { !shown[$0].collapsed }
      if open.isEmpty {
        values = values.map { _ in min(29, available / Double(max(1, shown.count))) }
      } else {
        let closedHeight = Double(shown.count - open.count) * 29
        let resized = Self.allocate(
          open.map { values[$0] }, available: max(0, available - closedHeight), minimum: 80)
        for (offset, index) in open.enumerated() { values[index] = resized[offset] }
        if available < closedHeight {
          for index in shown.indices where shown[index].collapsed {
            values[index] = available / Double(shown.count - open.count)
          }
        }
      }
    }
    rows = shown.indices.map {
      Row(group: shown[$0], height: values[$0], gap: $0 + 1 < shown.count ? 4 : 0)
    }
  }
}

@MainActor extension WorkspaceLibrary {
  @discardableResult func stackPanels(_ source: PanelDockSource, hostID: String, before: String?)
    -> Bool
  {
    guard !workspaceLocked else { return false }
    let previous = panelDock
    let target = previous.floatingGroups(hostID)
    guard let firstTarget = target.first, var frame = firstTarget.floatingFrame,
      before == nil || target.contains(where: { $0.id == before }),
      let moving = previous.panels(for: source), let first = moving.first,
      let origin = previous.groups.first(where: { $0.panels.contains(first) })
    else { return false }
    let wholeGroup = moving.count == origin.panels.count
    let sameStack = origin.floatingFrame != nil && origin.floatingHostID == hostID
    if wholeGroup && sameStack && (target.count == 1 || before == origin.id) { return false }
    var dock = previous
    if wholeGroup && sameStack {
      dock.groups.removeAll { $0.id == origin.id }
      let insertion =
        before.flatMap { id in dock.groups.firstIndex { $0.id == id } }
        ?? ((dock.groups.lastIndex { $0.floatingHostID == hostID } ?? -1) + 1)
      dock.groups.insert(origin, at: insertion)
    } else {
      var group: PanelDockGroup
      if wholeGroup {
        group = origin
        dock.groups.removeAll { $0.id == origin.id }
        dock.shrinkDepartedStacks(
          from: previous, titlebarHeight: FloatingPanelWindow.titlebarHeight)
      } else {
        guard
          dock.move(
            source, to: .beforeGroup(nil),
            floatingTitlebarHeight: FloatingPanelWindow.titlebarHeight),
          let index = dock.groups.firstIndex(where: { $0.panels.contains(first) })
        else { return false }
        group = dock.groups.remove(at: index)
      }
      let stack = firstTarget.floatingStack ?? UUID().uuidString
      let heights = FloatingPanelStackSizing.expandedHeights(
        target, height: frame.height - FloatingPanelWindow.titlebarHeight)
      let desired =
        origin.floatingFrame.map { old in
          FloatingPanelStackSizing.expandedHeights(
            previous.floatingGroups(origin.floatingHostID),
            height: old.height - FloatingPanelWindow.titlebarHeight)[origin.id] ?? 280
        } ?? origin.preferredHeight ?? 280
      let top = frame.rect.maxY
      frame.height = min(4000, frame.height + max(80, desired) + 4)
      frame.y = top - frame.height
      for targetIndex in dock.groups.indices
      where target.contains(where: { $0.id == dock.groups[targetIndex].id }) {
        dock.groups[targetIndex].floatingStack = stack
        dock.groups[targetIndex].floatingFrame = frame
        dock.groups[targetIndex].preferredHeight = heights[dock.groups[targetIndex].id]
      }
      group.floatingStack = stack
      group.floatingFrame = frame
      group.preferredHeight = max(80, desired)
      if let selected = previous.selectedPanel(in: origin, visibility: layout.visibility),
        moving.contains(selected)
      {
        group.selected = selected
      }
      let insertion =
        before.flatMap { id in dock.groups.firstIndex { $0.id == id } }
        ?? ((dock.groups.lastIndex { $0.floatingStack == stack } ?? -1) + 1)
      dock.groups.insert(group, at: insertion)
    }
    guard dock != previous, (try? dock.validate()) != nil else { return false }
    layout.panelDock = dock
    return true
  }

  func recordFloatingStackFrame(
    _ hostID: String, frame: NSRect, hiddenHeight: Double, expandedRows: [String: Double]? = nil
  ) {
    var dock = panelDock
    let groups = dock.floatingGroups(hostID)
    guard let old = groups.first?.floatingFrame, hiddenHeight.isFinite else { return }
    var next = FloatingPanelFrame(frame)
    next.height += max(0, hiddenHeight)
    next.y = frame.maxY - next.height
    if workspaceLocked {
      next.x = old.x
      next.y = old.rect.maxY - next.height
    }
    guard next.isValid, next != old else { return }
    let previous =
      expandedRows
      ?? FloatingPanelStackSizing.expandedHeights(
        groups, height: old.height - FloatingPanelWindow.titlebarHeight)
    let open = groups.filter {
      !$0.collapsed && !dock.visiblePanels(in: $0, visibility: layout.visibility).isEmpty
    }
    let retained = groups.filter { group in !open.contains { $0.id == group.id } }
      .reduce(0.0) { $0 + (previous[$1.id] ?? 80) }
    let available = max(
      0,
      next.height - FloatingPanelWindow.titlebarHeight
        - Double(max(0, groups.count - 1)) * 4 - retained)
    let heights = FloatingPanelStackSizing.allocate(
      open.map { previous[$0.id] ?? 80 },
      available: available, minimum: 80)
    var updated = previous
    for (offset, group) in open.enumerated() { updated[group.id] = heights[offset] }
    for index in dock.groups.indices where dock.groups[index].floatingHostID == hostID {
      dock.groups[index].floatingFrame = next
      dock.groups[index].preferredHeight = min(4000, max(29, updated[dock.groups[index].id] ?? 80))
    }
    layout.panelDock = dock
  }

  func resizeFloatingGroup(
    _ id: String, hostID: String, startingHeights: [String: Double], by delta: Double
  ) {
    guard delta.isFinite else { return }
    var dock = panelDock
    let groups = dock.floatingGroups(hostID).filter {
      !$0.collapsed && startingHeights[$0.id] != nil
    }
    guard let index = groups.firstIndex(where: { $0.id == id }), index + 1 < groups.count,
      let first = startingHeights[id], let second = startingHeights[groups[index + 1].id],
      first.isFinite, second.isFinite, first >= 0, second >= 0
    else { return }
    let total = first + second
    let minimum = min(80, total / 2)
    let value = min(total - minimum, max(minimum, first + delta))
    for position in dock.groups.indices {
      let group = dock.groups[position]
      guard group.floatingHostID == hostID, let start = startingHeights[group.id], !group.collapsed
      else { continue }
      let height = group.id == id ? value : group.id == groups[index + 1].id ? total - value : start
      dock.groups[position].preferredHeight = min(4000, max(29, height))
    }
    layout.panelDock = dock
  }
}
