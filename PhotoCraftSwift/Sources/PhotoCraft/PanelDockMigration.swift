import Foundation
import PhotoCraftCore

extension PanelDock {
  enum CodingKeys: String, CodingKey { case catalogVersion, groups, hidden, columns }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    catalogVersion = try values.decodeIfPresent(Int.self, forKey: .catalogVersion) ?? 1
    groups = try values.decode([PanelDockGroup].self, forKey: .groups)
    hidden = try values.decodeIfPresent(Set<WorkspacePanel>.self, forKey: .hidden) ?? []
    columns = try values.decodeIfPresent([PanelDockColumn].self, forKey: .columns)
    if catalogVersion == 1 {
      // Validate before migration: a missing old panel is corruption, not an upgrade.
      try validatePanels(Set(WorkspacePanel.allCases).subtracting([.history, .cloneSource, .character, .paragraph]))
      addUtilityPanels()
      catalogVersion = 2
    }
    if catalogVersion == 2 {
      try validatePanels(Set(WorkspacePanel.allCases).subtracting([.character, .paragraph]))
      addTypographyPanels()
      catalogVersion = 3
    }
    try validate()
  }

  mutating func addUtilityPanels() {
    var values = orderedColumns
    let columnID = values.contains { $0.id == "utility" } ? UUID().uuidString : "utility"
    let insertion = values.firstIndex { $0.side == .right } ?? values.count
    values.insert(.init(id: columnID, width: 322, collapsed: true), at: insertion)
    columns = values
    for (panel, preferredID) in [
      (WorkspacePanel.history, "history"), (.cloneSource, "cloneSource"),
    ] {
      let id = groups.contains { $0.id == preferredID } ? UUID().uuidString : preferredID
      groups.append(.init(id: id, panels: [panel], selected: panel, columnID: columnID))
    }
    hidden.insert(.cloneSource)
  }
  mutating func addTypographyPanels() {
    let column = groups.first { $0.panels.contains(.history) }?.dockColumnID
      ?? PanelDockColumn.primaryID
    let id = groups.contains { $0.id == "typography" } ? UUID().uuidString : "typography"
    groups.append(.init(id: id, panels: [.character, .paragraph], selected: .character,
      preferredHeight: 360, columnID: column == PanelDockColumn.primaryID ? nil : column))
    hidden.formUnion([.character, .paragraph])
  }

}
