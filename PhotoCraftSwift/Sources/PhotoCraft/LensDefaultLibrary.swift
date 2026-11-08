import CryptoKit
import Foundation
import Observation
import PhotoCraftCore
import PhotoCraftImaging

/// Individual bounded records avoid imposing a limit on the number of lenses.
@MainActor @Observable final class LensDefaultLibrary {
  static let maximumBytes = 32768
  static let shared = LensDefaultLibrary(directory: FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask).first?
    .appendingPathComponent("Photato/LensDefaults", isDirectory: true))
  private(set) var previous: LensCorrectionSettings?
  private(set) var previousError: String?
  private(set) var revision = UUID()
  @ObservationIgnored let directory: URL?
  @ObservationIgnored private var entries = [CameraLensIdentity: Entry]()
  @ObservationIgnored private var order = [CameraLensIdentity]()
  @ObservationIgnored private var preserveUnreadablePrevious = false
  struct Entry {
    var settings: LensCorrectionSettings?
    var error: String?
    var exists: Bool
  }
  private struct Record: Codable {
    var version = 1
    var identity: CameraLensIdentity?
    var settings: LensCorrectionSettings
  }
  init(directory: URL? = nil) {
    self.directory = directory
    guard let file = directory?.appendingPathComponent("PreviousConversion.json"),
      FileManager.default.fileExists(atPath: file.path) else { return }
    do { previous = try read(file, identity: nil) }
    catch { preserveUnreadablePrevious = true; previousError = "Previous Conversion could not be read. The saved file was preserved." }
  }
  func fileURL(for identity: CameraLensIdentity) -> URL? {
    directory?.appendingPathComponent(SHA256.hash(data: identity.matchingKey)
      .map { String(format: "%02x", $0) }.joined() + ".json")
  }
  func lookup(_ identity: CameraLensIdentity) -> Entry {
    _ = revision // Make native menu availability observe preference changes.
    if let value = entries[identity] { return value }
    guard let file = fileURL(for: identity) else { return .init(exists: false) }
    let value: Entry
    if !FileManager.default.fileExists(atPath: file.path) { value = .init(exists: false) }
    else {
      do { value = .init(settings: try read(file, identity: identity), exists: true) }
      catch { value = .init(error: "The saved lens default could not be read. Remove it to preserve a backup and start again.", exists: true) }
    }
    cache(value, for: identity); return value
  }
  func set(_ settings: LensCorrectionSettings, for rawIdentity: CameraLensIdentity) throws {
    let identity = try rawIdentity.validated()
    try settings.validate()
    let old = lookup(identity)
    guard old.error == nil else { throw CraftError.invalid(old.error!) }
    if let file = fileURL(for: identity) {
      do { try write(settings, identity: identity, to: file) }
      catch { throw CraftError.invalid("The lens default could not be saved. Previous settings were preserved.") }
    }
    cache(.init(settings: settings, exists: true), for: identity); revision = UUID()
  }
  func remove(_ identity: CameraLensIdentity) throws {
    if let file = fileURL(for: identity), FileManager.default.fileExists(atPath: file.path) {
      // Retire rather than overwrite an unreadable default; also preserves valid prior values.
      let retired = file.deletingLastPathComponent().appendingPathComponent("Retired", isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: retired, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: file, to: retired.appendingPathComponent(UUID().uuidString + ".json"))
      } catch { throw CraftError.invalid("The saved lens default could not be removed. It was preserved.") }
    }
    cache(.init(exists: false), for: identity); revision = UUID()
  }
  func remember(_ settings: LensCorrectionSettings) {
    guard (try? settings.validate()) != nil else { return }
    let changed = previous != settings, oldError = previousError
    previous = settings
    if !preserveUnreadablePrevious, let file = directory?.appendingPathComponent("PreviousConversion.json") {
      do { try write(settings, identity: nil, to: file); previousError = nil }
      catch { previousError = "Previous Conversion is available for this session but could not be saved." }
    }
    if changed || oldError != previousError { revision = UUID() }
  }
  func detachedCopy(including identity: CameraLensIdentity?) -> LensDefaultLibrary {
    if let identity { _ = lookup(identity) }
    let copy = LensDefaultLibrary(); copy.entries = entries; copy.order = order
    copy.previous = previous; copy.previousError = previousError
    return copy
  }
  private func cache(_ value: Entry, for identity: CameraLensIdentity) {
    entries[identity] = value; order.removeAll { $0 == identity }; order.append(identity)
    // Memory-only libraries are intentional test/detached snapshots, not a capped database.
    if directory != nil, order.count > 64 { entries.removeValue(forKey: order.removeFirst()) }
  }
  private func read(_ file: URL, identity: CameraLensIdentity?) throws -> LensCorrectionSettings {
    let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
    let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
    guard data.count <= Self.maximumBytes, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(root.keys).isSubset(of: ["version", "identity", "settings"]), root["settings"] is [String: Any]
    else { throw CraftError.invalid("Invalid lens-default record.") }
    let record = try JSONDecoder().decode(Record.self, from: data)
    guard record.version == 1, record.identity == identity else { throw CraftError.invalid("Mismatched lens-default record.") }
    if let camera = record.identity { _ = try camera.validated() }
    return try LensCorrectionSettings.decodeJSON(JSONSerialization.data(withJSONObject: root["settings"]!))
  }
  private func write(_ settings: LensCorrectionSettings, identity: CameraLensIdentity?, to file: URL) throws {
    let data = try JSONEncoder().encode(Record(identity: identity, settings: settings))
    guard data.count <= Self.maximumBytes else { throw CraftError.invalid("Lens settings exceed 32 KiB.") }
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: file, options: .atomic)
  }
}

@MainActor final class CameraLensMetadataCache {
  private var source: [String: Data]?
  private var loaded = false
  private var identity: CameraLensIdentity?
  private(set) var error: String?
  func read(_ metadata: [String: Data]?) -> CameraLensIdentity? {
    let relevant = metadata?.filter { ["imageIOProperties", "imageIOXMP", "psdResources", "pcraft.exif"].contains($0.key) }
    if loaded && source == relevant { return identity }
    loaded = true; source = relevant; identity = nil; error = nil
    do { identity = try CameraLensIdentity.read(from: relevant) }
    catch { self.error = "Camera metadata could not be read. Automatic lens defaults are unavailable." }
    return identity
  }
}

@MainActor extension EditorStore {
  var cameraLensIdentity: CameraLensIdentity? { cameraLensMetadataCache.read(document.sourceMetadata) }
  func setLensDefault(_ settings: LensCorrectionSettings) throws {
    guard let identity = cameraLensIdentity else { throw CraftError.invalid("This image needs camera, lens, focal length and aperture metadata to save a lens default.") }
    try filterRecall.lensDefaults.set(settings, for: identity)
  }
  func removeLensDefault() throws {
    guard let identity = cameraLensIdentity else { throw CraftError.invalid("No complete camera metadata is available.") }
    try filterRecall.lensDefaults.remove(identity)
  }
}
