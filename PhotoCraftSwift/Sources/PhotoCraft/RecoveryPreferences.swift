import AppKit
import Observation
import PhotoCraftCore

struct RecoveryPreferences: Codable, Equatable {
  static let intervals = [5, 10, 15, 30, 60]
  var enabled = true
  var intervalMinutes = 10
  var recentFileLimit = 20
  var disablePSDCompression = false
  var saveDialogFormats = SaveDialogFormats.defaults
  init(enabled: Bool = true, intervalMinutes: Int = 10, recentFileLimit: Int = 20,
    disablePSDCompression: Bool = false, saveDialogFormats: Set<DocumentIO.Format> = SaveDialogFormats.defaults) {
    self.enabled = enabled; self.intervalMinutes = intervalMinutes; self.recentFileLimit = recentFileLimit
    self.disablePSDCompression = disablePSDCompression
    self.saveDialogFormats = saveDialogFormats
  }
  private enum CodingKeys: String, CodingKey {
    case enabled, intervalMinutes, recentFileLimit, disablePSDCompression, saveDialogFormats
  }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try values.decode(Bool.self, forKey: .enabled)
    intervalMinutes = try values.decode(Int.self, forKey: .intervalMinutes)
    recentFileLimit = try values.decodeIfPresent(Int.self, forKey: .recentFileLimit) ?? 20
    disablePSDCompression = try values.decodeIfPresent(Bool.self, forKey: .disablePSDCompression) ?? false
    if let formats = try values.decodeIfPresent([String].self, forKey: .saveDialogFormats) {
      saveDialogFormats = try SaveDialogFormats.parse(formats)
    }
  }
  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(enabled, forKey: .enabled)
    try values.encode(intervalMinutes, forKey: .intervalMinutes)
    try values.encode(recentFileLimit, forKey: .recentFileLimit)
    try values.encode(disablePSDCompression, forKey: .disablePSDCompression)
    try values.encode(SaveDialogFormats.ordered(saveDialogFormats).map(\.rawValue), forKey: .saveDialogFormats)
  }
  var delay: TimeInterval { enabled ? TimeInterval(intervalMinutes * 60) : 0 }
  func validate() throws {
    guard Self.intervals.contains(intervalMinutes) else {
      throw CraftError.invalid("Choose a supported recovery interval.")
    }
    guard (0...100).contains(recentFileLimit) else {
      throw CraftError.invalid("Recent File List Contains must be between 0 and 100.")
    }
  }
}

enum RecoveryPreferencesFailure: Error, LocalizedError, Equatable {
  case changed, busy, unreadable
  var errorDescription: String? {
    switch self {
    case .changed: "File Handling settings changed. Refresh the API or reopen File Handling; restart Photato if the settings file changed externally."
    case .busy: "Wait for the current file operation before changing File Handling settings."
    case .unreadable:
      "The File Handling settings file could not be loaded. Repair it before saving changes."
    }
  }
}

@MainActor @Observable final class RecoveryPreferencesStore {
  private struct Archive: Codable {
    let version: Int
    let recovery: RecoveryPreferences
    var recentDocuments: [RecentDocumentRecord]?
    private enum CodingKeys: String, CodingKey { case version, recovery, recentDocuments }
    private enum FormatKey: String, CodingKey { case saveDialogFormats }
    init(version: Int, recovery: RecoveryPreferences, recentDocuments: [RecentDocumentRecord]?) {
      self.version = version; self.recovery = recovery; self.recentDocuments = recentDocuments
    }
    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      version = try values.decode(Int.self, forKey: .version)
      guard (1...4).contains(version) else { throw CraftError.invalid("Unsupported recovery settings version.") }
      let settings = try values.superDecoder(forKey: .recovery)
      recovery = try RecoveryPreferences(from: settings)
      if version == 4 {
        // Legacy settings may omit the list; a v4 archive must carry it explicitly.
        let required = try settings.container(keyedBy: FormatKey.self)
        _ = try required.decode([String].self, forKey: .saveDialogFormats)
      }
      recentDocuments = try values.decodeIfPresent([RecentDocumentRecord].self, forKey: .recentDocuments)
    }
  }
  static let maximumBytes = 8 * 1024 * 1024
  static let shared = RecoveryPreferencesStore(
    url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first?.appendingPathComponent("Photato/RecoverySettings.json"))
  private(set) var value = RecoveryPreferences()
  private(set) var revision = UUID()
  private(set) var recentRevision = UUID()
  private(set) var recentDocuments: [RecentDocumentRecord] = []
  private(set) var recentWriteError: String?
  var isPersistent: Bool { url != nil }
  private(set) var loadError: String?
  @ObservationIgnored private let url: URL?
  @ObservationIgnored private var originalBytes: Data?
  @ObservationIgnored private let writer: (Data, URL) throws -> Void

  init(url: URL? = nil, writer: ((Data, URL) throws -> Void)? = nil) {
    self.url = url
    self.writer =
      writer ?? { data, url in
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let output = try AtomicFileWriter(to: url, maximumBytes: Self.maximumBytes)
        defer { output.discard() }
        try output.append(data)
        try output.commit()
      }
    guard let url else { return }
    do {
      originalBytes = try Self.read(url)
      if let originalBytes {
        let archive = try JSONDecoder().decode(Archive.self, from: originalBytes)
        guard (1...4).contains(archive.version) else {
          throw CraftError.invalid("Unsupported recovery settings version.")
        }
        try archive.recovery.validate()
        try Self.validateRecent(archive.recentDocuments ?? [], limit: archive.recovery.recentFileLimit)
        value = archive.recovery
        recentDocuments = archive.recentDocuments ?? []
      }
    } catch { loadError = error.localizedDescription }
  }
  private static func read(_ url: URL) throws -> Data? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    guard let size, (0...maximumBytes).contains(size) else {
      throw CraftError.invalid("Recovery settings file is too large.")
    }
    let data = try Data(contentsOf: url)
    guard data.count <= maximumBytes else {
      throw CraftError.invalid("Recovery settings file is too large.")
    }
    return data
  }
  func commit(_ next: RecoveryPreferences, revision expected: UUID) throws {
    try next.validate()
    guard loadError == nil else { throw RecoveryPreferencesFailure.unreadable }
    guard expected == revision else { throw RecoveryPreferencesFailure.changed }
    if let url, try Self.read(url) != originalBytes { throw RecoveryPreferencesFailure.changed }
    guard next != value else { return }
    let entries = Array(recentDocuments.prefix(next.recentFileLimit))
    try persist(next, entries: entries)
    if next.recentFileLimit != value.recentFileLimit || entries != recentDocuments {
      recentRevision = UUID()
    }
    recentDocuments = entries
    value = next
    revision = UUID()
  }
  private static func validateRecent(_ entries: [RecentDocumentRecord], limit: Int) throws {
    guard entries.count <= limit, Set(entries.map(\.id)).count == entries.count,
      Set(entries.map(\.url)).count == entries.count else {
      throw CraftError.invalid("Invalid recent-file list.")
    }
    try entries.forEach { try $0.validate() }
  }
  private func persist(_ next: RecoveryPreferences, entries: [RecentDocumentRecord]) throws {
    try Self.validateRecent(entries, limit: next.recentFileLimit)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(Archive(version: 4, recovery: next, recentDocuments: entries))
    guard data.count <= Self.maximumBytes else { throw CraftError.invalid("Recent-file list is too large.") }
    if let url { try writer(data, url) }
    originalBytes = data
    recentWriteError = nil
  }
  func validateRecentRevision(_ expected: UUID) throws {
    guard loadError == nil else { throw RecoveryPreferencesFailure.unreadable }
    guard recentRevision == expected else { throw RecoveryPreferencesFailure.changed }
    if let url, try Self.read(url) != originalBytes { throw RecoveryPreferencesFailure.changed }
  }
  func remember(_ url: URL, replacing id: UUID? = nil) {
    guard value.recentFileLimit > 0 else { return }
    do {
      try validateRecentRevision(recentRevision)
      let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
      let prior = recentDocuments.first { $0.id == id || $0.url == canonical }
      let entry = try RecentDocumentRecord.capture(canonical, id: prior?.id ?? UUID())
      var entries = recentDocuments.filter { $0.id != entry.id && $0.url != canonical }
      entries.insert(entry, at: 0)
      entries = Array(entries.prefix(value.recentFileLimit))
      if entries != recentDocuments {
        try persist(value, entries: entries)
        recentDocuments = entries; recentRevision = UUID()
      }
    } catch is AtomicFileWriter.PublicationFailure {
      recentWriteError = "Recent-file history could not be confirmed. The file may already contain the new history. Restart Photato before updating it again."
    } catch { recentWriteError = "Recent-file history could not be saved. Existing history is preserved." }
  }
  func clearRecent(revision expected: UUID) throws {
    try validateRecentRevision(expected)
    guard !recentDocuments.isEmpty else { return }
    try persist(value, entries: [])
    recentDocuments = []; recentRevision = UUID()
  }
}

extension CraftDocumentController {
  var recoveryPreferencesBusy: Bool {
    recoveryIndex.isMaintaining || documents.contains {
      guard let document = $0 as? CraftNSDocument else { return false }
      return document.recoveryWriteBusy || document.fileOperationBusy
        || document.copyPanel != nil || document.windowForSheet?.attachedSheet != nil
    }
  }
  func setRecoveryPreferences(_ value: RecoveryPreferences, revision: UUID) throws {
    guard !recoveryPreferencesBusy else { throw RecoveryPreferencesFailure.busy }
    if value.recentFileLimit != recoveryPreferences.value.recentFileLimit, recentFilesBusy {
      throw RecoveryPreferencesFailure.busy
    }
    let previousDelay = recoveryPreferences.value.delay
    try recoveryPreferences.commit(value, revision: revision)
    guard previousDelay != recoveryPreferences.value.delay else { return }
    autosavingDelay = recoveryPreferences.value.delay
    // Updating the controller delay does not notify already-dirty documents.
    // Reschedule through AppKit without inventing a content/history change.
    for case let document as CraftNSDocument in documents {
      document.scheduleAutosaving()
    }
  }
}

@MainActor @Observable final class RecoveryPreferencesDraft {
  var value: RecoveryPreferences
  var recentLimitText: String
  var error: String?
  let revision: UUID
  let controller: CraftDocumentController
  init(controller: CraftDocumentController) {
    self.controller = controller
    value = controller.recoveryPreferences.value
    recentLimitText = String(controller.recoveryPreferences.value.recentFileLimit)
    revision = controller.recoveryPreferences.revision
    error = controller.recoveryPreferences.loadError
  }
  func apply() -> Bool {
    do {
      guard let limit = Int(recentLimitText.trimmingCharacters(in: .whitespacesAndNewlines)),
        (0...100).contains(limit) else {
        throw CraftError.invalid("Recent File List Contains must be a whole number from 0 to 100.")
      }
      value.recentFileLimit = limit
      try controller.setRecoveryPreferences(value, revision: revision)
      error = nil
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
}
