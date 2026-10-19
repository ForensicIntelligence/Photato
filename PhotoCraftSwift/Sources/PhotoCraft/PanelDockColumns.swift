import AppKit
import PhotoCraftCore

enum PanelDockSide: String, Codable, CaseIterable { case left, right }

struct PanelDockColumn: Codable, Equatable, Identifiable {
  static let primaryID = "main"
  var id: String
  var side: PanelDockSide = .right
  var width: Double? = nil
  var collapsed: Bool? = nil
  var iconWidth: Double? = nil
}

extension PanelDockGroup {
  var dockColumnID: String { columnID ?? PanelDockColumn.primaryID }
}

extension PanelDock {
  var orderedColumns: [PanelDockColumn] { columns ?? [.init(id: PanelDockColumn.primaryID)] }

  func groups(inColumn id: String, visibility: WorkspaceVisibility) -> [PanelDockGroup] {
    dockedGroups(visibility).filter { $0.dockColumnID == id }
  }

  func visibleColumns(_ visibility: WorkspaceVisibility) -> [PanelDockColumn] {
    orderedColumns.filter { !groups(inColumn: $0.id, visibility: visibility).isEmpty }
  }

  mutating func removeUnusedColumns() {
    guard columns != nil else { return }
    // Floating and closed groups retain their dock destination.
    let used = Set(groups.map(\.dockColumnID)).union([PanelDockColumn.primaryID])
    columns?.removeAll { !used.contains($0.id) }
  }

  func validateColumns(panelCount: Int = WorkspacePanel.allCases.count) throws {
    let values = orderedColumns
    guard !values.isEmpty, values.count <= panelCount + 1,
      Set(values.map(\.id)).count == values.count,
      values.contains(where: { $0.id == PanelDockColumn.primaryID }),
      values.allSatisfy({
        !$0.id.isEmpty && $0.id.utf8.count <= 64
          && ($0.width.map { $0.isFinite && (275...600).contains($0) } ?? true)
          && ($0.iconWidth.map { $0.isFinite && (34...240).contains($0) } ?? true)
      }), groups.allSatisfy({ group in values.contains { $0.id == group.dockColumnID } })
    else { throw CraftError.invalid("Invalid workspace dock columns.") }
  }
}

/// Compact presentation retains the saved widths; temporary icon presentation is reversible.
/// Exact Photoshop behavior under extreme width pressure still requires live qualification.
struct PanelDockColumnSizing {
  struct Column: Identifiable {
    let column: PanelDockColumn
    var width: Double
    var icons: Bool
    var id: String { column.id }
  }
  let columns: [Column]
  init(layout: WorkspaceLayout, availableWidth: Double, preferredColumn: String? = nil) {
    let dock = layout.panelDock ?? PanelDock(layout: layout)
    var columns = dock.visibleColumns(layout.visibility).map { column in
      let primary = column.id == PanelDockColumn.primaryID
      let icons = primary ? layout.visibility.collapsedDock : column.collapsed ?? false
      return Column(
        column: column,
        width: icons ? column.iconWidth ?? 34 : primary ? layout.dockWidth : column.width ?? 322,
        icons: icons)
    }
    let available = availableWidth.isFinite ? max(0, availableWidth) : 0
    var total = columns.reduce(0) { $0 + $1.width + 4 }
    let preferred =
      columns.contains(where: { $0.id == preferredColumn })
      ? preferredColumn
      : columns.contains(where: { $0.id == PanelDockColumn.primaryID })
        ? PanelDockColumn.primaryID : columns.last?.id
    let priority = columns.indices.sorted {
      if (columns[$0].id == preferred) != (columns[$1].id == preferred) {
        return columns[$0].id != preferred
      }
      return $0 < $1
    }
    for index in priority
    where total > available && !columns[index].icons && columns[index].id != preferred {
      let width = columns[index].column.iconWidth ?? 34
      total -= columns[index].width - width
      columns[index].width = width
      columns[index].icons = true
    }
    for index in priority
    where total > available && columns[index].icons && columns[index].width > 34 {
      total -= columns[index].width - 34
      columns[index].width = 34
    }
    if total > available, let index = columns.firstIndex(where: { $0.id == preferred && !$0.icons })
    {
      let width = max(275, columns[index].width - (total - available))
      total -= columns[index].width - width
      columns[index].width = width
      if total > available {
        columns[index].icons = true
        columns[index].width = 34
      }
    }
    self.columns = columns
  }
}

@MainActor extension WorkspaceLibrary {
  func columnWidth(_ id: String, icons: Bool = false) -> Double {
    guard let column = panelDock.orderedColumns.first(where: { $0.id == id }) else { return 322 }
    if icons { return column.iconWidth ?? 34 }
    return id == PanelDockColumn.primaryID ? layout.dockWidth : column.width ?? 322
  }

  func resizeColumn(_ id: String, width: Double, icons: Bool = false) {
    guard width.isFinite else { return }
    if id == PanelDockColumn.primaryID && !icons {
      resizeDock(to: width)
      return
    }
    var dock = panelDock
    var columns = dock.orderedColumns
    guard let index = columns.firstIndex(where: { $0.id == id }) else { return }
    if icons {
      columns[index].iconWidth = min(240, max(34, width))
    } else {
      columns[index].width = min(600, max(275, width))
    }
    dock.columns = columns
    layout.panelDock = dock
  }

  func setColumnCollapsed(_ id: String, _ collapsed: Bool) {
    guard panelDock.orderedColumns.contains(where: { $0.id == id }) else { return }
    if !collapsed {
      expandedDockColumnID = id
    } else if expandedDockColumnID == id {
      expandedDockColumnID = nil
    }
    if id == PanelDockColumn.primaryID {
      layout.visibility.collapsedDock = collapsed
      return
    }
    var dock = panelDock
    guard var columns = dock.columns, let index = columns.firstIndex(where: { $0.id == id }) else {
      return
    }
    columns[index].collapsed = collapsed
    dock.columns = columns
    layout.panelDock = dock
  }

  @discardableResult func moveColumn(_ id: String, side: PanelDockSide, before: String?) -> Bool {
    guard !workspaceLocked else { return false }
    var dock = panelDock
    var columns = dock.orderedColumns
    guard let index = columns.firstIndex(where: { $0.id == id }), id != before,
      before == nil || columns.contains(where: { $0.id == before && $0.side == side })
    else { return false }
    var column = columns.remove(at: index)
    column.side = side
    let insertion =
      before.flatMap { target in columns.firstIndex { $0.id == target } }
      ?? ((columns.lastIndex { $0.side == side } ?? -1) + 1)
    columns.insert(column, at: insertion)
    guard columns != dock.orderedColumns else { return false }
    dock.columns = columns
    layout.panelDock = dock
    expandedDockColumnID = id
    return true
  }
}
