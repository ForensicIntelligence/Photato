import AppKit

@MainActor extension AppDelegate {
  func updateWorkspaceMenu(_ menu: NSMenu) {
    for item in menu.items where item.identifier?.rawValue.hasPrefix("workspace-custom:") == true {
      menu.removeItem(item)
    }
    let library = controller.workspaces
    let insertion =
      menu.items.firstIndex { $0.action == #selector(resetWorkspace) } ?? menu.items.count
    for (offset, name) in library.customNames.enumerated() {
      let item = NSMenuItem(
        title: name, action: #selector(selectSavedWorkspace(_:)), keyEquivalent: "")
      item.identifier = NSUserInterfaceItemIdentifier("workspace-custom:" + name)
      item.representedObject = name
      item.target = self
      item.state = name == library.activeName ? .on : .off
      menu.insertItem(item, at: insertion + offset)
    }
    menu.items.first { $0.action == #selector(resetWorkspace) }?.title =
      "Reset " + library.activeName
  }

  func validateWorkspaceMenuItem(_ item: NSMenuItem) -> Bool? {
    let library = controller.workspaces
    let available = controller.documentWindows.canChangeDocument
    switch item.action {
    case #selector(selectEssentialsWorkspace):
      item.state = library.activeName == "Essentials" ? .on : .off
      return available
    case #selector(selectSavedWorkspace(_:)):
      guard let name = item.representedObject as? String else { return false }
      item.state = name == library.activeName ? .on : .off
      return available && library.customNames.contains(name)
    case #selector(resetWorkspace):
      item.title = "Reset " + library.activeName
      return available
    case #selector(newWorkspace): return available
    case #selector(lockWorkspace):
      item.state = library.workspaceLocked ? .on : .off
      return available
    case #selector(deleteWorkspace): return available && !library.deletableNames.isEmpty
    default: return nil
    }
  }

  func performWorkspaceChange(_ change: (WorkspaceLibrary) throws -> Void) {
    guard controller.documentWindows.canChangeDocument else { return }
    do { try change(controller.workspaces) } catch {
      reportWorkspaceError(error)
    }
  }

  func reportWorkspaceError(_ error: Error) {
    if controller.documents.isEmpty {
      NSApp.presentError(error)
    } else {
      controller.workspaces.error = error.localizedDescription
    }
  }

  @objc func selectEssentialsWorkspace() {
    performWorkspaceChange { try $0.select("Essentials") }
  }

  @objc func selectSavedWorkspace(_ item: NSMenuItem) {
    guard let name = item.representedObject as? String,
      controller.workspaces.customNames.contains(name)
    else { return }
    performWorkspaceChange { try $0.select(name) }
  }

  @objc func resetWorkspace() { performWorkspaceChange { try $0.reset() } }
  @objc func lockWorkspace() {
    performWorkspaceChange { try $0.setWorkspaceLocked(!$0.workspaceLocked) }
  }

  func makeNewWorkspaceAlert() -> (NSAlert, NSTextField) {
    let alert = NSAlert()
    alert.messageText = "New Workspace"
    alert.informativeText = "Save the current panel layout."
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    let name = NSTextField(string: "")
    name.placeholderString = "Workspace name"
    name.setAccessibilityLabel("Workspace name")
    let stack = NSStackView(views: [
      NSTextField(labelWithString: "Name:"), name,
      NSTextField(labelWithString: "Capture"),
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    for title in ["Panel Locations", "Keyboard Shortcuts", "Menus", "Toolbar"] {
      let checkbox = NSButton(checkboxWithTitle: title, target: nil, action: nil)
      checkbox.state = title == "Panel Locations" ? .on : .off
      checkbox.isEnabled = false
      if title != "Panel Locations" { checkbox.toolTip = "Customization is not available yet." }
      stack.addArrangedSubview(checkbox)
    }
    stack.frame = NSRect(x: 0, y: 0, width: 290, height: 194)
    name.widthAnchor.constraint(equalToConstant: 290).isActive = true
    alert.accessoryView = stack
    alert.window.initialFirstResponder = name
    return (alert, name)
  }

  @objc func newWorkspace() {
    guard controller.documentWindows.canChangeDocument else { return }
    let (alert, field) = makeNewWorkspaceAlert()
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let name: String
    do { name = try WorkspaceState.normalizedName(field.stringValue) } catch {
      reportWorkspaceError(error)
      return
    }
    let replacing = controller.workspaces.customNames.contains { WorkspaceState.sameName($0, name) }
    if replacing {
      let confirm = NSAlert()
      confirm.messageText = "Replace Workspace?"
      confirm.informativeText =
        "A workspace named “\(name)” already exists. Replace its saved layout?"
      confirm.addButton(withTitle: "Replace")
      confirm.addButton(withTitle: "Cancel")
      guard confirm.runModal() == .alertFirstButtonReturn else { return }
    }
    performWorkspaceChange { try $0.save(name: name, replacing: replacing) }
  }

  func makeDeleteWorkspaceAlert() -> (NSAlert, NSPopUpButton) {
    let alert = NSAlert()
    alert.messageText = "Delete Workspace"
    alert.informativeText =
      "Select a saved workspace to delete. Switch workspaces first to delete the current one."
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")
    let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 290, height: 28))
    picker.addItems(withTitles: controller.workspaces.deletableNames)
    picker.setAccessibilityLabel("Workspace")
    alert.accessoryView = picker
    alert.buttons.first?.isEnabled = !controller.workspaces.deletableNames.isEmpty
    return (alert, picker)
  }

  @objc func deleteWorkspace() {
    guard controller.documentWindows.canChangeDocument,
      !controller.workspaces.deletableNames.isEmpty
    else { return }
    let (alert, picker) = makeDeleteWorkspaceAlert()
    guard alert.runModal() == .alertFirstButtonReturn, let name = picker.titleOfSelectedItem else {
      return
    }
    performWorkspaceChange { try $0.delete(name) }
  }
}
