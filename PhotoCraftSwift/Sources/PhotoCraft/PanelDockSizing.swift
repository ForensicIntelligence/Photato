import Foundation

struct PanelDockSizing {
  struct Row: Identifiable {
    let group: PanelDockGroup
    let height: CGFloat
    let gap: CGFloat
    var id: String { group.id }
  }
  let rows: [Row]
  var heights: [String: Double] {
    Dictionary(uniqueKeysWithValues: rows.map { ($0.id, Double($0.height)) })
  }

  init(layout: WorkspaceLayout, height: CGFloat, columnID: String = PanelDockColumn.primaryID) {
    let dock = layout.panelDock ?? PanelDock(layout: layout)
    let groups = dock.groups(inColumn: columnID, visibility: layout.visibility)
    let height = height.isFinite ? max(0, height) : 0
    let legacy = WorkspacePanelLayout(
      height: height, visibility: layout.visibility,
      library: layout.colorTab == .gradients || layout.colorTab == .patterns,
      preferredProperties: layout.propertiesHeight)
    let factory = PanelDock(layout: layout)
    let unchanged =
      columnID == PanelDockColumn.primaryID
      && dock.groups.filter { $0.dockColumnID == columnID }
        == factory.groups.filter { $0.dockColumnID == columnID }
      && !dock.hidden.contains { $0 != .history && $0 != .cloneSource }
    let gaps = groups.indices.map { index -> CGFloat in
      guard index + 1 < groups.count else { return 0 }
      return groups[index].id == "color" ? 3 : 5
    }
    var values: [CGFloat]
    if unchanged {
      values = groups.map { group in
        group.id == "color"
          ? legacy.colorHeight
          : group.id == "properties" ? legacy.propertiesHeight : legacy.layersHeight
      }
    } else {
      let available = max(0, height - 12 - gaps.reduce(0, +))
      let filler = groups.lastIndex { !$0.collapsed }
      values = groups.map { group in
        if group.collapsed { return 29 }
        if let requested = group.preferredHeight { return CGFloat(requested) }
        let selected = dock.selectedPanel(in: group, visibility: layout.visibility)
        if selected == .gradients || selected == .patterns { return min(224, height * 0.29) }
        if selected == .color || selected == .swatches { return min(168, height * 0.23) }
        return group.panels.contains(.properties) ? CGFloat(layout.propertiesHeight) : 220
      }
      if let filler { values[filler] = min(220, available) }
      var deficit = max(0, values.reduce(0, +) - available)
      // Preserve dragged sizes where possible; automatic groups give way first.
      for pinned in [false, true] {
        for index in groups.indices.reversed()
        where index != filler && !groups[index].collapsed
          && (groups[index].preferredHeight != nil) == pinned
        {
          let give = min(deficit, max(0, values[index] - 80))
          values[index] -= give
          deficit -= give
        }
      }
      for index in groups.indices.reversed() where !groups[index].collapsed {
        let give = min(deficit, max(0, values[index] - 29))
        values[index] -= give
        deficit -= give
      }
      if deficit > 0 {
        let total = values.reduce(0, +)
        values = values.map { total > 0 ? $0 * available / total : 0 }
      }
      if let filler { values[filler] += max(0, available - values.reduce(0, +)) }
    }
    rows = groups.indices.map { Row(group: groups[$0], height: values[$0], gap: gaps[$0]) }
  }
}

@MainActor extension WorkspaceLibrary {
  func resizePanelGroup(_ id: String, startingHeights: [String: Double], by delta: Double) {
    guard delta.isFinite else { return }
    var dock = panelDock
    guard let column = dock.groups.first(where: { $0.id == id })?.dockColumnID else { return }
    let shown = dock.groups(inColumn: column, visibility: layout.visibility).filter {
      !$0.collapsed && startingHeights[$0.id] != nil
    }
    guard let index = shown.firstIndex(where: { $0.id == id }), index + 1 < shown.count,
      let first = startingHeights[id], let second = startingHeights[shown[index + 1].id],
      first.isFinite, second.isFinite, first >= 0, second >= 0
    else { return }
    let total = first + second
    let minimum = min(80, total / 2)
    let resized = min(total - minimum, max(minimum, first + delta))
    for group in shown.dropLast() {
      if let position = dock.groups.firstIndex(where: { $0.id == group.id }),
        let start = startingHeights[group.id]
      {
        let requested =
          group.id == id
          ? resized
          : group.id == shown[index + 1].id ? total - resized : start
        dock.groups[position].preferredHeight = min(4000, max(29, requested))
      }
    }
    layout.panelDock = dock
  }
}
