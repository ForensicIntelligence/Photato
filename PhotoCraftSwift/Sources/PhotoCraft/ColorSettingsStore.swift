import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

enum ColorSettingsFailure: Error, LocalizedError, Equatable {
  case changed, unreadable
  var errorDescription: String? {
    switch self {
    case .changed: "Color Settings changed. Reopen this dialog or refresh the API; restart Photato if the settings file changed externally."
    case .unreadable: "The Color Settings file could not be loaded. Repair it before saving changes."
    }
  }
}

@MainActor @Observable final class ColorSettingsStore {
  private struct Archive: Codable { let version: Int; let settings: ColorSettings }
  static let maximumBytes = ColorSettings.maximumArchiveBytes
  static let shared = ColorSettingsStore(url: FileManager.default.urls(for: .applicationSupportDirectory,
    in: .userDomainMask).first?.appendingPathComponent("Photato/ColorSettings.json"))
  private(set) var value = ColorSettings()
  private(set) var revision = UUID()
  private(set) var loadError: String?
  var isPersistent: Bool { url != nil }
  @ObservationIgnored private let url: URL?
  @ObservationIgnored private var originalBytes: Data?
  @ObservationIgnored private let writer: (Data, URL) throws -> Void
  init(url: URL? = nil, writer: ((Data, URL) throws -> Void)? = nil) {
    self.url = url
    self.writer = writer ?? { data, url in
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let output = try AtomicFileWriter(to: url, maximumBytes: Self.maximumBytes)
      defer { output.discard() }
      try output.append(data); try output.commit()
    }
    guard let url else { return }
    do {
      originalBytes = try Self.read(url)
      if let originalBytes {
        let archive = try JSONDecoder().decode(Archive.self, from: originalBytes)
        guard (1...2).contains(archive.version) else { throw CraftError.invalid("Unsupported Color Settings version.") }
        try archive.settings.validate(); value = archive.settings
      }
    } catch { loadError = error.localizedDescription }
  }
  private static func read(_ url: URL) throws -> Data? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, (0...maximumBytes).contains(size) else {
      throw CraftError.invalid("Color Settings file exceeds the supported size.")
    }
    let bytes = try Data(contentsOf: url)
    guard bytes.count <= maximumBytes else { throw CraftError.invalid("Color Settings file exceeds the supported size.") }
    return bytes
  }
  func commit(_ next: ColorSettings, revision expected: UUID) throws {
    try next.validate()
    guard loadError == nil else { throw ColorSettingsFailure.unreadable }
    guard expected == revision else { throw ColorSettingsFailure.changed }
    if let url, try Self.read(url) != originalBytes { throw ColorSettingsFailure.changed }
    guard next != value else { return }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let bytes = try encoder.encode(Archive(version: 2, settings: next))
    guard bytes.count <= Self.maximumBytes else { throw CraftError.invalid("Color Settings file exceeds the supported size.") }
    if let url { try writer(bytes, url) }
    originalBytes = bytes; value = next; revision = UUID()
  }
}

@MainActor @Observable final class ColorSettingsDraft {
  var value: ColorSettings
  var error: String?
  private let store: ColorSettingsStore
  private let revision: UUID
  init(store: ColorSettingsStore) {
    self.store = store; value = store.value; revision = store.revision; error = store.loadError
  }
  func apply() -> Bool {
    do { try store.commit(value, revision: revision); error = nil; return true }
    catch { self.error = error.localizedDescription; return false }
  }
}

extension EditorStore {
  var workingColorSettings: ColorSettings { documentController?.colorSettings.value ?? ColorSettings() }
}
