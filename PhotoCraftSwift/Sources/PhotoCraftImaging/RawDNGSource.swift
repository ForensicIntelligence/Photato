import CryptoKit
import Foundation
import PhotoCraftCore

/// An original DNG and the sidecar actually used to open it. Kept only for the
/// selected local source, outside the editable Photato document and its archive.
public struct RawDNGSource: Sendable {
  public let url: URL
  let original: Data
  let sidecar: RawSourceIO.RelatedXMP?
  private let ignoresSidecar: Bool

  init(url: URL, original: Data, sidecar: RawSourceIO.RelatedXMP?, ignoresSidecar: Bool = false) {
    self.url = url
    self.original = original
    self.sidecar = sidecar
    self.ignoresSidecar = ignoresSidecar
  }

  public var hasSidecar: Bool { sidecar != nil }
  public var matchingSidecarURL: URL? { sidecar?.url }

  public static var sidecarBackupDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Photato", isDirectory: true)
      .appendingPathComponent("Camera Raw Sidecars", isDirectory: true)
  }

  public enum SaveError: LocalizedError {
    case sourceChanged
    case multipleSidecars
    case sidecarAccessNeeded
    case rollbackFailed

    public var errorDescription: String? {
      switch self {
      case .sourceChanged:
        "The RAW file or its sidecar has changed. Reopen the source before saving its settings."
      case .multipleSidecars:
        "The RAW file has two sidecars with different filename casing. Keep the intended sidecar and reopen the source."
      case .sidecarAccessNeeded:
        "Allow access to the source folder to finish saving the Camera Raw settings."
      case .rollbackFailed:
        "The DNG was written, but its sidecar could not be retired and the DNG could not be restored. Review the DNG and sidecar before trying again."
      }
    }
  }

  public func save(settings: RawDevelopment, authorizedFolder: URL? = nil) throws -> RawDNGSource {
    try save(settings: settings, marking: nil, authorizedFolder: authorizedFolder)
  }

  func save(settings: RawDevelopment?, marking: RawPhotoMarking?, authorizedFolder: URL?) throws -> RawDNGSource {
    let access = try Self.accessSourceFolder(authorizedFolder, source: url)
    defer { if access { authorizedFolder?.stopAccessingSecurityScopedResource() } }
    return try save(settings: settings, marking: marking) { url in
      let files = FileManager.default
      do {
        try files.trashItem(at: url, resultingItemURL: nil)
      } catch {
        // A user-selected file grant can permit deleting the sibling while
        // the Trash itself remains outside the application's sandbox.
        guard let sidecar else { throw error }
        _ = try Self.unchanged(url, expected: sidecar.data)
        let folder = Self.sidecarBackupDirectory
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let stem = String(decoding: url.deletingPathExtension().lastPathComponent.utf8.prefix(80), as: UTF8.self)
        let hash = SHA256.hash(data: sidecar.data).map { String(format: "%02x", $0) }.joined()
        let backup = folder.appendingPathComponent("\(stem)-\(hash).xmp")
        try sidecar.data.write(to: backup, options: .atomic)
        _ = try Self.unchanged(url, expected: sidecar.data)
        do {
          try files.removeItem(at: url)
        } catch let failure as CocoaError where failure.code == .fileWriteNoPermission {
          throw SaveError.sidecarAccessNeeded
        } catch let failure as POSIXError where failure.code == .EACCES || failure.code == .EPERM {
          throw SaveError.sidecarAccessNeeded
        }
      }
    }
  }

  func save(settings: RawDevelopment?, marking: RawPhotoMarking? = nil,
    retireSidecar: (URL) throws -> Void) throws -> RawDNGSource {
    try Task.checkCancellation()
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }

    if !ignoresSidecar, try RawSourceIO.relatedXMP(for: url, includeMarking: true) != sidecar { throw SaveError.sourceChanged }
    let updated: Data
    if let settings {
      updated = try RawSourceIO.dngWithSettings(original, settings: settings, including: sidecar?.data, marking: marking)
    } else if let marking {
      updated = try RawSourceIO.replacingDNGXMP(original) { packet in
        try CameraRawXMP.writeMarking(marking, replacing: packet, including: sidecar?.data)
      }
    } else { return self }
    var coordinationError: NSError?
    var operation: Result<Void, Error>?
    if let sidecar {
      RawSourceIO.coordinate(rawURL: url, sidecar: sidecar.url) { coordinator in
        coordinator.coordinate(writingItemAt: url, options: .forReplacing,
          writingItemAt: sidecar.url, options: .forDeleting, error: &coordinationError) { raw, packet in
          operation = Result {
            guard raw.standardizedFileURL == url.standardizedFileURL,
              packet.standardizedFileURL == sidecar.url.standardizedFileURL else { throw SaveError.sourceChanged }
            let rawFile = try Self.unchanged(raw, expected: original)
            let xmpFile = try Self.unchanged(packet, expected: sidecar.data)
            try Self.validateSidecarCasing(packet)
            try rawFile.validateUnchanged()
            try xmpFile.validateUnchanged()
            if updated != original { try updated.write(to: raw, options: .atomic) }
            do {
              try xmpFile.validateUnchanged()
              try retireSidecar(packet)
            } catch {
              if updated != original {
                do {
                  // Do not undo an unrelated replacement that happened
                  // outside this coordination after writing our DNG.
                  guard try raw.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false else {
                    throw SaveError.sourceChanged
                  }
                  let file = try FileHandle(forReadingFrom: raw)
                  defer { try? file.close() }
                  guard try file.read(upToCount: updated.count + 1) == updated else {
                    throw SaveError.sourceChanged
                  }
                  try original.write(to: raw, options: .atomic)
                } catch { throw SaveError.rollbackFailed }
              }
              throw error
            }
          }
        }
      }
    } else {
      NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url,
        options: .forReplacing, error: &coordinationError) { raw in
        operation = Result {
          guard raw.standardizedFileURL == url.standardizedFileURL else { throw SaveError.sourceChanged }
          let source = try Self.unchanged(raw, expected: original)
          try source.validateUnchanged()
          if updated != original { try updated.write(to: raw, options: .atomic) }
        }
      }
    }
    guard let operation else {
      if let coordinationError { throw coordinationError }
      throw SaveError.sourceChanged
    }
    try operation.get()
    return RawDNGSource(url: url, original: updated, sidecar: nil, ignoresSidecar: ignoresSidecar)
  }

  static func accessSourceFolder(_ folder: URL?, source: URL) throws -> Bool {
    guard let folder else { return false }
    guard folder.standardizedFileURL.resolvingSymlinksInPath()
      == source.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath() else {
      throw SaveError.sidecarAccessNeeded
    }
    return folder.startAccessingSecurityScopedResource()
  }

  static func validateSidecarCasing(_ packet: URL) throws {
    let oppositeExtension = packet.pathExtension == "xmp" ? "XMP" : "xmp"
    let alternate = packet.deletingPathExtension().appendingPathExtension(oppositeExtension)
    if let other = try? alternate.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
      let selected = try packet.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
      !other.isEqual(selected) {
      throw SaveError.multipleSidecars
    }
  }

  static func unchanged(_ location: URL, expected: Data) throws -> PSDFileSource {
    guard try location.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false,
      let source = try? PSDFileSource(location, maximumBytes: expected.count),
      source.count == expected.count else { throw SaveError.sourceChanged }
    let base = expected.startIndex
    let chunkBytes = PSDFileSource.pageBytes
    for offset in stride(from: 0, to: expected.count, by: chunkBytes) {
      try Task.checkCancellation()
      let count = min(chunkBytes, expected.count - offset)
      let original = expected[(base + offset)..<(base + offset + count)]
      guard try source.bytes(at: offset, count: count) == original else { throw SaveError.sourceChanged }
    }
    try source.validateUnchanged()
    return source
  }
}
