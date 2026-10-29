import AppKit

@MainActor extension AppDelegate: NSMenuDelegate {
  func menuNeedsUpdate(_ menu: NSMenu) {
    if menu === recentDocumentsMenu { updateRecentDocumentsMenu(menu); return }
    if menu === workspaceMenu {
      updateWorkspaceMenu(menu)
      return
    }
    guard menu === documentWindowMenu else { return }
    for item in menu.items where item.identifier?.rawValue.hasPrefix("document-window:") == true {
      menu.removeItem(item)
    }
    let documents = controller.documents.compactMap { $0 as? CraftNSDocument }
    guard !documents.isEmpty else { return }
    let separator = NSMenuItem.separator()
    separator.identifier = NSUserInterfaceItemIdentifier("document-window:separator")
    menu.addItem(separator)
    for document in documents {
      let item = NSMenuItem(
        title: document.displayName, action: #selector(selectDocumentWindow(_:)), keyEquivalent: "")
      item.identifier = NSUserInterfaceItemIdentifier(
        "document-window:" + document.store.identity.uuidString)
      item.representedObject = document.store.identity
      item.target = self
      item.state = controller.currentDocument === document ? .on : .off
      menu.addItem(item)
    }
  }

  @objc func selectDocumentWindow(_ item: NSMenuItem) {
    guard let id = item.representedObject as? UUID,
      let document = controller.documents.compactMap({ $0 as? CraftNSDocument }).first(where: {
        $0.store.identity == id
      })
    else { return }
    document.showWindows()
  }

  @objc func consolidateDocumentWindows() { controller.documentWindows.consolidate() }
  @objc func floatDocumentWindow() {
    if let document = controller.currentDocument as? CraftNSDocument {
      controller.documentWindows.float(document)
    }
  }
  @objc func floatAllDocumentWindows() { controller.documentWindows.floatAll() }
  @objc func minimizeDocumentWindow() {
    controller.documentWindows.current?.window?.miniaturize(nil)
  }
  @objc func bringDocumentWindowsToFront() {
    let windows = controller.documentWindows
    let active = windows.current
    for group in windows.groups { group.window?.orderFront(nil) }
    active?.window?.makeKeyAndOrderFront(nil)
  }

  func validateDocumentWindowMenuItem(_ item: NSMenuItem) -> Bool? {
    let windows = controller.documentWindows
    let available =
      !windows.groups.isEmpty && windows.canChangeDocument
    switch item.action {
    case #selector(selectDocumentWindow(_:)):
      guard let id = item.representedObject as? UUID else { return false }
      return available
        && controller.documents.compactMap { $0 as? CraftNSDocument }.contains {
          $0.store.identity == id
        }
    case #selector(consolidateDocumentWindows), #selector(bringDocumentWindowsToFront):
      return available
    case #selector(floatDocumentWindow):
      return available && windows.current?.workspace.floating == false
        && windows.activeDocument != nil
    case #selector(floatAllDocumentWindows):
      return available && windows.applicationFrame?.workspace.documents.isEmpty == false
    case #selector(minimizeDocumentWindow):
      return available && windows.current?.window?.isMiniaturized == false
    default: return nil
    }
  }
}
