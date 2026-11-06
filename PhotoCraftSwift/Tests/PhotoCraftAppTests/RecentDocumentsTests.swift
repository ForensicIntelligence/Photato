import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class RecentDocumentsTests: XCTestCase {
  @MainActor func fixture() throws -> (URL, RecoveryPreferencesStore, CraftDocumentController) {
    _ = NSApplication.shared
    let folder = try DocumentPersistenceTests().directory()
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    let preferences = RecoveryPreferencesStore(url: folder.appendingPathComponent("FileHandling.json"))
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary(), recoveryPreferences: preferences)
    return (folder, preferences, controller)
  }
  func file(_ folder: URL, _ name: String) throws -> URL {
    try DocumentOpeningTests().fixture(folder, name: name)
  }
  @MainActor func testLegacyPreferencesMigrateWithoutChangingRecoveryValues() throws {
    let (folder, _, _) = try fixture()
    let url = folder.appendingPathComponent("legacy.json")
    try Data(#"{"version":1,"recovery":{"enabled":false,"intervalMinutes":30}}"#.utf8).write(to: url)
    let settings = RecoveryPreferencesStore(url: url)
    XCTAssertNil(settings.loadError)
    XCTAssertEqual(settings.value, .init(enabled: false, intervalMinutes: 30, recentFileLimit: 20))
    XCTAssertTrue(settings.recentDocuments.isEmpty)
    settings.remember(try file(folder, "one.photato"))
    let reloaded = RecoveryPreferencesStore(url: url)
    XCTAssertEqual(reloaded.value, settings.value)
    XCTAssertEqual(reloaded.recentDocuments, settings.recentDocuments)
    let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    XCTAssertEqual(raw["version"] as? Int, 4)
  }
  @MainActor func testOrderingDeduplicationTrimmingZeroAndClearPersistWithoutDeletingImages() throws {
    let (folder, settings, c) = try fixture()
    let files = try ["one.photato", "two.photato", "three.photato"].map { try file(folder, $0) }
    let before = try files.map { try Data(contentsOf: $0) }
    try c.setRecentFileLimit(2, revision: settings.recentRevision)
    files.forEach { settings.remember($0) }
    XCTAssertEqual(settings.recentDocuments.map(\.url), [files[2], files[1]].map { $0.resolvingSymlinksInPath() })
    let id = settings.recentDocuments[1].id
    settings.remember(files[1])
    XCTAssertEqual(settings.recentDocuments.first?.id, id)
    XCTAssertEqual(settings.recentDocuments.count, 2)
    let preferenceRevision = settings.revision
    try c.clearRecentFiles(revision: settings.recentRevision)
    XCTAssertEqual(settings.revision, preferenceRevision)
    XCTAssertEqual(settings.value.recentFileLimit, 2)
    settings.remember(files[0])
    try c.setRecentFileLimit(0, revision: settings.recentRevision)
    settings.remember(files[1])
    XCTAssertTrue(settings.recentDocuments.isEmpty)
    let loaded = RecoveryPreferencesStore(url: folder.appendingPathComponent("FileHandling.json"))
    XCTAssertEqual(loaded.value.recentFileLimit, 0)
    XCTAssertTrue(loaded.recentDocuments.isEmpty)
    for (index, url) in files.enumerated() { XCTAssertEqual(try Data(contentsOf: url), before[index]) }
  }
  @MainActor func testFailedAtomicPreferenceWriteKeepsHistoryLimitRevisionAndBytes() throws {
    let (folder, settings, _) = try fixture()
    settings.remember(try file(folder, "one.photato"))
    let url = folder.appendingPathComponent("FileHandling.json")
    let before = try Data(contentsOf: url)
    let failing = RecoveryPreferencesStore(url: url, writer: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
    let revision = failing.revision, recent = failing.recentRevision, records = failing.recentDocuments
    var value = failing.value; value.recentFileLimit = 0; value.enabled = false
    XCTAssertThrowsError(try failing.commit(value, revision: revision))
    XCTAssertEqual(failing.value, settings.value)
    XCTAssertEqual(failing.revision, revision)
    XCTAssertEqual(failing.recentRevision, recent)
    XCTAssertEqual(failing.recentDocuments, records)
    failing.remember(try file(folder, "two.photato"))
    XCTAssertNotNil(failing.recentWriteError)
    XCTAssertEqual(failing.recentDocuments, records)
    XCTAssertEqual(try Data(contentsOf: url), before)
  }
  @MainActor func testExternalAndInvalidRecentArchiveNeverOverwritePriorData() throws {
    let (folder, settings, _) = try fixture()
    settings.remember(try file(folder, "one.photato"))
    let url = folder.appendingPathComponent("FileHandling.json")
    let other = RecoveryPreferencesStore(url: url)
    other.remember(try file(folder, "two.photato"))
    let external = try Data(contentsOf: url)
    settings.remember(try file(folder, "three.photato"))
    XCTAssertNotNil(settings.recentWriteError)
    XCTAssertThrowsError(try settings.clearRecent(revision: settings.recentRevision))
    XCTAssertEqual(try Data(contentsOf: url), external)
    var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: external) as? [String: Any])
    let entries = try XCTUnwrap(raw["recentDocuments"] as? [[String: Any]])
    raw["recentDocuments"] = [entries[0], entries[0]]
    let bad = try JSONSerialization.data(withJSONObject: raw)
    try bad.write(to: url)
    let invalid = RecoveryPreferencesStore(url: url)
    XCTAssertNotNil(invalid.loadError)
    XCTAssertThrowsError(try invalid.clearRecent(revision: invalid.recentRevision))
    XCTAssertEqual(try Data(contentsOf: url), bad)
  }
  @MainActor func testFileHandlingDraftValidationCancelAndConcurrentHistory() throws {
    let (folder, settings, c) = try fixture()
    let draft = RecoveryPreferencesDraft(controller: c)
    draft.recentLimitText = "-1"
    XCTAssertFalse(draft.apply())
    draft.recentLimitText = "2.5"
    XCTAssertFalse(draft.apply())
    draft.recentLimitText = "100"
    settings.remember(try file(folder, "one.photato"))
    XCTAssertTrue(draft.apply(), "History updates must not stale unchanged settings")
    XCTAssertEqual(settings.value.recentFileLimit, 100)
    let cancelled = RecoveryPreferencesDraft(controller: c)
    cancelled.recentLimitText = "0"
    XCTAssertEqual(settings.recentDocuments.count, 1)
    try c.setRecentFileLimit(7, revision: settings.recentRevision)
    XCTAssertFalse(cancelled.apply())
    XCTAssertEqual(settings.value.recentFileLimit, 7)
  }
  @MainActor func testOpenSaveAsCopyRecoveryAndFailureRecordOnlySuccessfulAssociatedFiles() async throws {
    let (folder, settings, c) = try fixture()
    defer { for doc in c.documents { doc.close() } }
    let source = try file(folder, "one.photato")
    c.openDocument(withContentsOf: source, display: false) { _, _, error in XCTAssertNil(error) }
    await c.documentOpening.waitUntilIdle()
    let doc = try XCTUnwrap(c.document(for: source) as? CraftNSDocument)
    XCTAssertEqual(settings.recentDocuments.count, 1)
    try doc.store.executeEditorCommand(.renameLayer(doc.store.document.layers[0].id, "Edited"))
    let content = doc.store.document
    try await doc.copyDocument(to: folder.appendingPathComponent("copy.photato"), format: .native)
    try await doc.writeRecoverySnapshot()
    XCTAssertEqual(settings.recentDocuments.count, 1)
    let saved = folder.appendingPathComponent("saved.photato")
    try await DocumentSaveWorkflowTests().save(doc, to: saved, format: .native)
    XCTAssertEqual(settings.recentDocuments.count, 2)
    XCTAssertEqual(settings.recentDocuments.first?.url, saved.resolvingSymlinksInPath())
    XCTAssertEqual(doc.store.document, content)
    let prior = settings.recentDocuments
    c.openDocument(withContentsOf: folder.appendingPathComponent("missing"), display: false) { _, _, error in XCTAssertNotNil(error) }
    await c.documentOpening.waitUntilIdle()
    XCTAssertEqual(settings.recentDocuments, prior)
  }
  @MainActor func testMovedBookmarkRetainsRecentIdentityAndMissingFailureKeepsHistory() async throws {
    let (folder, settings, c) = try fixture()
    defer { for doc in c.documents { doc.close() } }
    let source = try file(folder, "original.photato").resolvingSymlinksInPath()
    settings.remember(source)
    let entry = try XCTUnwrap(settings.recentDocuments.first)
    XCTAssertNotNil(entry.bookmark)
    let moved = folder.appendingPathComponent("moved.photato").resolvingSymlinksInPath()
    try FileManager.default.moveItem(at: source, to: moved)
    XCTAssertEqual(try entry.resolvedURL().resolvingSymlinksInPath(), moved)
    try c.openRecentFile(entry.id, revision: settings.recentRevision, display: false)
    await c.documentOpening.waitUntilIdle()
    XCTAssertEqual(settings.recentDocuments.count, 1)
    XCTAssertEqual(settings.recentDocuments.first?.id, entry.id)
    XCTAssertEqual(settings.recentDocuments.first?.url, moved)
    c.document(for: moved)?.close()
    try FileManager.default.removeItem(at: moved)
    let prior = settings.recentDocuments
    try c.openRecentFile(entry.id, revision: settings.recentRevision, display: false)
    await c.documentOpening.waitUntilIdle()
    XCTAssertEqual(c.documentOpening.state?.failed, 1)
    XCTAssertEqual(settings.recentDocuments, prior)
  }
  @MainActor func testRecentMenuUsesExistingSubmenuStableIDsAndClearReferenceAction() throws {
    try PhotoshopMenuTests().withMenus { delegate, _ in
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder) }
      let file = try self.file(folder, "Menu fixture.photato")
      let settings = delegate.controller.recoveryPreferences
      settings.remember(file)
      let menu = try XCTUnwrap(delegate.recentDocumentsMenu)
      delegate.menuNeedsUpdate(menu)
      XCTAssertEqual(menu.items.map(\.title), ["Menu fixture.photato", "", "Clear Recent File List"])
      XCTAssertEqual(menu.items[0].representedObject as? UUID, settings.recentDocuments.first?.id)
      XCTAssertTrue(delegate.validateMenuItem(menu.items[0]))
      XCTAssertEqual(menu.items[0].keyEquivalent, "")
      delegate.clearRecentDocuments()
      delegate.menuNeedsUpdate(menu)
      XCTAssertEqual(menu.items.map(\.title), ["Clear Recent File List"])
      XCTAssertFalse(delegate.validateMenuItem(menu.items[0]))
      XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
  }
}
