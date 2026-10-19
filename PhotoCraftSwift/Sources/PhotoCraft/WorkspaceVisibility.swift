import AppKit

/// Temporary workspace visibility is presentation state, never document content or undo history.
struct WorkspaceVisibility: Codable, Equatable {
  var tools = true
  var options = true
  var color = true
  var properties = true
  var layers = true
  var rail = true
  var collapsedDock = false

  var hasInspector: Bool { color || properties || layers }
  var hasDock: Bool { rail || hasInspector }

  mutating func togglePanels(includingTools: Bool) {
    // A mixed state restores the complete workspace, as observed in Photoshop 2026.
    let show = !(color && properties && layers && rail && (!includingTools || (tools && options)))
    color = show
    properties = show
    layers = show
    rail = show
    if includingTools {
      tools = show
      options = show
    }
  }
}

@MainActor extension EditorStore {
  @discardableResult func handleWorkspaceKey(_ event: NSEvent) -> Bool {
    guard event.keyCode == 48,
      event.modifierFlags.intersection([.command, .option, .control, .function]).isEmpty
    else { return false }
    if !event.isARepeat {
      workspace.togglePanels(includingTools: !event.modifierFlags.contains(.shift))
    }
    return true
  }

  func reveal(_ tab: ColorPanelTab) {
    workspaceLibrary.selectPanel(WorkspacePanel(rawValue: tab.rawValue)!, reveal: true)
  }

  func reveal(_ tab: PropertiesTab) {
    workspaceLibrary.selectPanel(WorkspacePanel(rawValue: tab.rawValue)!, reveal: true)
  }

  func reveal(_ tab: LayersTab) {
    workspaceLibrary.selectPanel(WorkspacePanel(rawValue: tab.rawValue)!, reveal: true)
  }
}
