import Foundation
import PhotoCraftCore

enum WorkspacePanel: String, Codable, CaseIterable, Hashable {
  case color = "Color"
  case swatches = "Swatches"
  case gradients = "Gradients"
  case patterns = "Patterns"
  case properties = "Properties"
  case adjustments = "Adjustments"
  case libraries = "Libraries"
  case layers = "Layers"
  case channels = "Channels"
  case paths = "Paths"
  case history = "History"
  case cloneSource = "Clone Source"

  func isVisible(in visibility: WorkspaceVisibility) -> Bool {
    if self == .history || self == .cloneSource { return visibility.rail }
    if ColorPanelTab(rawValue: rawValue) != nil { return visibility.color }
    if PropertiesTab(rawValue: rawValue) != nil { return visibility.properties }
    return visibility.layers
  }
}

struct PanelDockGroup: Codable, Equatable, Identifiable {
  var id: String
  var panels: [WorkspacePanel]
  var selected: WorkspacePanel
  var collapsed = false
  var preferredHeight: Double?
  var floatingFrame: FloatingPanelFrame?
  var columnID: String?
  var floatingStack: String?
  var floatingHostID: String { floatingStack.map { "stack:\($0)" } ?? id }
}

enum PanelDockSource: Codable, Equatable {
  case panel(WorkspacePanel)
  case group(String)
}

enum PanelDockDestination: Equatable {
  case group(String, before: WorkspacePanel?)
  case beforeGroup(String?)
  case column(String, beforeGroup: String?)
  case newColumn(PanelDockSide, before: String?)
}

/// Presentation topology only. Every supported panel has exactly one retained location,
/// including closed panels, so Window commands restore a panel without duplicating it.
struct PanelDock: Codable, Equatable {
  var catalogVersion = 2
  var groups: [PanelDockGroup]
  var hidden: Set<WorkspacePanel> = []
  var columns: [PanelDockColumn]?

  init(layout: WorkspaceLayout) {
    groups = [
      .init(
        id: "color", panels: [.color, .swatches, .gradients, .patterns],
        selected: WorkspacePanel(rawValue: layout.colorTab.rawValue)!),
      .init(
        id: "properties", panels: [.properties, .adjustments, .libraries],
        selected: WorkspacePanel(rawValue: layout.propertiesTab.rawValue)!),
      .init(
        id: "layers", panels: [.layers, .channels, .paths],
        selected: WorkspacePanel(rawValue: layout.layersTab.rawValue)!),
    ]
    addUtilityPanels()
  }

  func validate() throws {
    guard catalogVersion == 2 else { throw CraftError.invalid("Unsupported panel catalog.") }
    try validatePanels(Set(WorkspacePanel.allCases))
  }

  func validatePanels(_ required: Set<WorkspacePanel>) throws {
    let panels = groups.flatMap(\.panels)
    guard !groups.isEmpty, groups.count <= required.count,
      Set(groups.map(\.id)).count == groups.count,
      panels.count == required.count, Set(panels) == required,
      hidden.isSubset(of: required),
      groups.allSatisfy({ group in
        !group.id.isEmpty && group.id.utf8.count <= 64 && !group.panels.isEmpty
          && group.panels.contains(group.selected)
          && (group.preferredHeight.map { $0.isFinite && (29...4000).contains($0) } ?? true)
          && (group.floatingFrame?.isValid ?? true)
      })
    else { throw CraftError.invalid("Invalid workspace panel layout.") }
    try validateColumns(panelCount: required.count)
    for group in groups where group.floatingStack != nil {
      guard let stack = group.floatingStack, !stack.isEmpty, stack.utf8.count <= 64,
        group.floatingFrame != nil,
        !groups.contains(where: { $0.floatingStack == nil && $0.id == group.floatingHostID }),
        groups.filter({ $0.floatingStack == stack }).allSatisfy({
          $0.floatingFrame == group.floatingFrame
        })
      else { throw CraftError.invalid("Invalid floating panel stack.") }
    }
  }

  func visiblePanels(in group: PanelDockGroup, visibility: WorkspaceVisibility) -> [WorkspacePanel]
  {
    group.panels.filter { !hidden.contains($0) && $0.isVisible(in: visibility) }
  }

  func visibleGroups(_ visibility: WorkspaceVisibility) -> [PanelDockGroup] {
    groups.filter { !visiblePanels(in: $0, visibility: visibility).isEmpty }
  }

  func dockedGroups(_ visibility: WorkspaceVisibility) -> [PanelDockGroup] {
    visibleGroups(visibility).filter { $0.floatingFrame == nil }
  }

  func selectedPanel(in group: PanelDockGroup, visibility: WorkspaceVisibility) -> WorkspacePanel? {
    let visible = visiblePanels(in: group, visibility: visibility)
    return visible.contains(group.selected) ? group.selected : visible.first
  }

  func panels(for source: PanelDockSource) -> [WorkspacePanel]? {
    switch source {
    case .panel(let panel): return groups.contains { $0.panels.contains(panel) } ? [panel] : nil
    case .group(let id): return groups.first { $0.id == id }?.panels
    }
  }

  @discardableResult mutating func move(
    _ source: PanelDockSource, to destination: PanelDockDestination,
    floatingTitlebarHeight: Double = 22
  ) -> Bool {
    guard let moving = panels(for: source), !moving.isEmpty,
      let origin = groups.first(where: { $0.panels.contains(moving[0]) })
    else { return false }
    // Normalize legacy placement while retaining a floated group's previous dock column.
    if case .beforeGroup(let before) = destination {
      let column =
        before.flatMap { id in groups.first { $0.id == id }?.dockColumnID }
        ?? origin.dockColumnID
      return move(
        source, to: .column(column, beforeGroup: before),
        floatingTitlebarHeight: floatingTitlebarHeight)
    }
    if case .newColumn(let side, let before) = destination {
      guard before == nil || orderedColumns.contains(where: { $0.id == before && $0.side == side })
      else { return false }
      var next = self
      var values = orderedColumns
      let column = PanelDockColumn(id: UUID().uuidString, side: side, width: 322, collapsed: false)
      let insertion =
        before.flatMap { target in values.firstIndex { $0.id == target } }
        ?? ((values.lastIndex { $0.side == side } ?? -1) + 1)
      values.insert(column, at: insertion)
      next.columns = values
      guard
        next.move(
          source, to: .column(column.id, beforeGroup: nil),
          floatingTitlebarHeight: floatingTitlebarHeight)
      else { return false }
      self = next
      return true
    }
    switch destination {
    case .group(let id, let before):
      guard let target = groups.first(where: { $0.id == id }),
        before == nil || target.panels.contains(before!),
        before == nil || !moving.contains(before!),
        id != origin.id || moving.count < origin.panels.count
      else { return false }
    case .column(let column, let id):
      guard orderedColumns.contains(where: { $0.id == column }),
        id == nil
          || groups.contains(where: {
            $0.id == id && $0.dockColumnID == column && $0.floatingFrame == nil
          })
      else { return false }
      if id == origin.id && moving.count == origin.panels.count { return false }
    case .beforeGroup, .newColumn: return false
    }
    var next = self
    for index in next.groups.indices {
      next.groups[index].panels.removeAll { moving.contains($0) }
      if !next.groups[index].panels.contains(next.groups[index].selected),
        let first = next.groups[index].panels.first
      {
        next.groups[index].selected = first
      }
    }
    next.groups.removeAll { $0.panels.isEmpty }
    switch destination {
    case .group(let id, let before):
      guard let index = next.groups.firstIndex(where: { $0.id == id }) else { return false }
      let insertion =
        before.flatMap { next.groups[index].panels.firstIndex(of: $0) }
        ?? next.groups[index].panels.count
      next.groups[index].panels.insert(contentsOf: moving, at: insertion)
      next.groups[index].selected = moving.contains(origin.selected) ? origin.selected : moving[0]
    case .column(let column, let id):
      let insertion =
        id.flatMap { value in next.groups.firstIndex { $0.id == value } }
        ?? ((next.groups.lastIndex { $0.dockColumnID == column && $0.floatingFrame == nil } ?? -1)
          + 1)
      var group =
        moving.count == origin.panels.count
        ? origin
        : PanelDockGroup(
          id: UUID().uuidString, panels: moving, selected: moving[0])
      group.floatingFrame = nil
      group.floatingStack = nil
      group.columnID = column == PanelDockColumn.primaryID ? nil : column
      next.groups.insert(group, at: insertion)
    case .beforeGroup, .newColumn: return false
    }
    next.shrinkDepartedStacks(from: self, titlebarHeight: floatingTitlebarHeight)
    next.removeUnusedColumns()
    guard next != self else { return false }
    self = next
    return true
  }
}

@MainActor extension WorkspaceLibrary {
  var panelDock: PanelDock { layout.panelDock ?? PanelDock(layout: layout) }
  var workspaceLocked: Bool { state.workspaceLocked ?? false }

  func selectPanel(_ panel: WorkspacePanel, reveal: Bool = false) {
    var next = layout
    if let tab = ColorPanelTab(rawValue: panel.rawValue) { next.colorTab = tab }
    if let tab = PropertiesTab(rawValue: panel.rawValue) { next.propertiesTab = tab }
    if let tab = LayersTab(rawValue: panel.rawValue) { next.layersTab = tab }
    if next.panelDock != nil || reveal {
      var dock = panelDock
      if let index = dock.groups.firstIndex(where: { $0.panels.contains(panel) }) {
        dock.groups[index].selected = panel
        if reveal {
          dock.groups[index].collapsed = false
          dock.hidden.remove(panel)
        }
      }
      next.panelDock = dock
    }
    if reveal {
      if panel == .history || panel == .cloneSource {
        next.visibility.rail = true
      } else if ColorPanelTab(rawValue: panel.rawValue) != nil {
        next.visibility.color = true
      } else if PropertiesTab(rawValue: panel.rawValue) != nil {
        next.visibility.properties = true
      } else {
        next.visibility.layers = true
      }
      let floating =
        next.panelDock?.groups.first { $0.panels.contains(panel) }?.floatingFrame != nil
      if !floating, let group = next.panelDock?.groups.first(where: { $0.panels.contains(panel) }) {
        if group.dockColumnID == PanelDockColumn.primaryID {
          next.visibility.collapsedDock = false
        } else if let index = next.panelDock?.columns?.firstIndex(where: {
          $0.id == group.dockColumnID
        }) {
          next.panelDock?.columns?[index].collapsed = false
        }
      }
    }
    layout = next
    if reveal, let group = panelDock.groups.first(where: { $0.panels.contains(panel) }),
      group.floatingFrame == nil
    {
      expandedDockColumnID = group.dockColumnID
    }
  }

  @discardableResult func movePanels(
    _ source: PanelDockSource, to destination: PanelDockDestination
  ) -> Bool {
    guard !workspaceLocked else { return false }
    var dock = panelDock
    let movingPanel = dock.panels(for: source)?.first
    if case .group(let id) = source,
      let index = dock.groups.firstIndex(where: { $0.id == id }),
      let selected = dock.selectedPanel(in: dock.groups[index], visibility: layout.visibility)
    {
      dock.groups[index].selected = selected
    }
    guard
      dock.move(source, to: destination, floatingTitlebarHeight: FloatingPanelWindow.titlebarHeight)
    else { return false }
    layout.panelDock = dock
    if let movingPanel, let group = dock.groups.first(where: { $0.panels.contains(movingPanel) }),
      group.floatingFrame == nil
    {
      expandedDockColumnID = group.dockColumnID
    }
    return true
  }

  func togglePanelGroup(_ id: String) {
    var dock = panelDock
    guard let index = dock.groups.firstIndex(where: { $0.id == id }) else { return }
    dock.groups[index].collapsed.toggle()
    layout.panelDock = dock
  }

  func closePanels(_ panels: [WorkspacePanel]) {
    var dock = panelDock
    dock.hidden.formUnion(panels)
    layout.panelDock = dock
  }
}
