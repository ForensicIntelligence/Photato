import AppKit
import SwiftUI

struct TypographyPanel: View {
  let store: EditorStore
  let panel: WorkspacePanel
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        if store.editableType == nil {
          Text("Select a type layer to edit its formatting.")
            .font(.caption).foregroundStyle(.secondary)
        }
        TypeControls(store: store, scope: panel == .paragraph ? .paragraph : .character)
      }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
    }.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity).clipped()
      .accessibilityLabel(panel.rawValue + " formatting")
  }
}

@MainActor extension AppDelegate {
  private func showTypographyPanel(_ panel: WorkspacePanel) {
    guard controller.documentWindows.canUseTypographyPanels, store != nil,
      controller.workspaces.error == nil else { return }
    do { try controller.workspaces.setPanelVisible(panel, true) }
    catch { reportWorkspaceError(error) }
  }
  @objc func characterPanel() { showTypographyPanel(.character) }
  @objc func paragraphPanel() { showTypographyPanel(.paragraph) }
  func validateTypographyPanel(_ item: NSMenuItem) -> Bool? {
    let panel: WorkspacePanel
    if item.action == #selector(characterPanel) { panel = .character }
    else if item.action == #selector(paragraphPanel) { panel = .paragraph }
    else { return nil }
    let library = controller.workspaces
    item.state = library.panelDock.groups.contains {
      library.panelDock.visiblePanels(in: $0, visibility: library.layout.visibility).contains(panel)
    } ? .on : .off
    return store != nil && controller.documentWindows.canUseTypographyPanels && library.error == nil
  }
}
