import AppKit
import PhotoCraftCore

struct RecentDocumentRecord: Codable, Equatable, Sendable {
  let id: UUID
  let url: URL
  let bookmark: Data?
  func validate() throws {
    guard url.isFileURL, !url.path.isEmpty, url.path.utf8.count <= 16384,
      (bookmark?.count ?? 0) <= 65536 else { throw CraftError.invalid("Invalid recent document.") }
  }
  static func capture(_ url: URL, id: UUID) throws -> Self {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let bookmark = (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
      ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
    let entry = Self(id: id, url: url, bookmark: bookmark.flatMap { $0.count <= 65536 ? $0 : nil })
    try entry.validate()
    return entry
  }
  func resolvedURL() throws -> URL {
    try validate()
    if let bookmark {
      var stale = false
      for options: URL.BookmarkResolutionOptions in [
        [.withoutUI, .withoutMounting, .withSecurityScope], [.withoutUI, .withoutMounting],
      ] {
        if let resolved = try? URL(resolvingBookmarkData: bookmark, options: options,
          relativeTo: nil, bookmarkDataIsStale: &stale), resolved.isFileURL { return resolved }
      }
    }
    return url
  }
}

@MainActor extension CraftDocumentController {
  var recentFilesBusy: Bool {
    recoveryPreferencesBusy || documentOpening.isActive || documentOpening.hasPendingRequests
      || documentClosing.isActive || documentOpenPanel != nil || recoveryIndex.isBusy
  }
  func setRecentFileLimit(_ limit: Int, revision: UUID) throws {
    try recoveryPreferences.validateRecentRevision(revision)
    var value = recoveryPreferences.value
    value.recentFileLimit = limit
    try setRecoveryPreferences(value, revision: recoveryPreferences.revision)
  }
  func clearRecentFiles(revision: UUID) throws {
    guard !recentFilesBusy else { throw RecoveryPreferencesFailure.busy }
    try recoveryPreferences.clearRecent(revision: revision)
  }
  @discardableResult func openRecentFile(_ id: UUID, revision: UUID, display: Bool,
    validate: @escaping () throws -> Void = {},
    completion: @escaping (NSDocument?, Bool, Error?) -> Void = { _, _, _ in },
    finished: @escaping (DocumentOpening.State) -> Void = { _ in }) throws -> UUID
  {
    try recoveryPreferences.validateRecentRevision(revision)
    guard let entry = recoveryPreferences.recentDocuments.first(where: { $0.id == id }) else {
      throw CraftError.invalid("This recent file is no longer listed.")
    }
    let url = try entry.resolvedURL()
    return try documentOpening.begin([url], display: display, showProgress: display, recentID: id,
      validate: { [weak self] in
        guard let self else { throw CancellationError() }
        try validate()
        try self.recoveryPreferences.validateRecentRevision(revision)
      }, completion: completion, finished: finished)
  }
}

@MainActor extension AppDelegate {
  func updateRecentDocumentsMenu(_ menu: NSMenu) {
    menu.removeAllItems()
    for entry in controller.recoveryPreferences.recentDocuments {
      let item = NSMenuItem(title: entry.url.lastPathComponent, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
      item.identifier = .init("recent-document:" + entry.id.uuidString)
      item.representedObject = entry.id; item.target = self
      item.toolTip = entry.url.path
      menu.addItem(item)
    }
    if !menu.items.isEmpty {
      let separator = NSMenuItem.separator(); separator.identifier = .init("recent-document:separator")
      menu.addItem(separator)
    }
    let clear = NSMenuItem(title: "Clear Recent File List", action: #selector(clearRecentDocuments), keyEquivalent: "")
    clear.identifier = .init("recent-document:clear"); clear.target = self
    menu.addItem(clear)
  }
  @objc func openRecentDocument(_ item: NSMenuItem) {
    guard let id = item.representedObject as? UUID else { return }
    do {
      try controller.openRecentFile(id, revision: controller.recoveryPreferences.recentRevision, display: true,
        completion: { _, _, error in
          if let error, (error as NSError).code != NSUserCancelledError {
            RunLoop.main.perform { MainActor.assumeIsolated { NSApp.presentError(error) } }
          }
        })
    } catch { NSApp.presentError(error) }
  }
  @objc func clearRecentDocuments() {
    do { try controller.clearRecentFiles(revision: controller.recoveryPreferences.recentRevision) }
    catch { NSApp.presentError(error) }
  }
  func validateRecentMenu(_ item: NSMenuItem) -> Bool? {
    if item.action == #selector(openRecentDocument(_:)) {
      return controller.documentOpening.canStart
        && controller.recoveryPreferences.recentDocuments.contains { $0.id == item.representedObject as? UUID }
    }
    if item.action == #selector(clearRecentDocuments) {
      return !controller.recentFilesBusy && !controller.recoveryPreferences.recentDocuments.isEmpty
        && controller.recoveryPreferences.loadError == nil
    }
    return nil
  }
}
