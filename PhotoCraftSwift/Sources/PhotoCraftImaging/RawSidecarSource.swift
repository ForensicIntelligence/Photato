import Darwin
import Foundation
import PhotoCraftCore

/// The settings destination for an original opened from a local file.
public enum RawSettingsSource: Sendable {
  case embeddedDNG(RawDNGSource)
  case sidecar(RawSidecarSource)

  public var url: URL {
    switch self {
    case .embeddedDNG(let source): source.url
    case .sidecar(let source): source.url
    }
  }

  public var sidecarURL: URL? {
    switch self {
    case .embeddedDNG(let source): source.matchingSidecarURL
    case .sidecar(let source): source.sidecarURL
    }
  }

  public var savesInsideDNG: Bool {
    if case .embeddedDNG = self { return true }
    return false
  }

  public func save(settings: RawDevelopment, authorizedFolder: URL? = nil) throws -> RawSettingsSource {
    switch self {
    case .embeddedDNG(let source):
      return .embeddedDNG(try source.save(settings: settings, authorizedFolder: authorizedFolder))
    case .sidecar(let source):
      return .sidecar(try source.save(settings: settings, authorizedFolder: authorizedFolder))
    }
  }
}

/// Writes the sibling of a vendor RAW without changing the original file.
public struct RawSidecarSource: Sendable {
  public let url: URL
  let original: Data
  let existing: RawSourceIO.RelatedXMP?
  public var sidecarURL: URL {
    existing?.url ?? url.deletingPathExtension().appendingPathExtension("xmp")
  }

  public func save(settings: RawDevelopment, authorizedFolder: URL? = nil) throws -> RawSidecarSource {
    let folderAccess = try RawDNGSource.accessSourceFolder(authorizedFolder, source: url)
    defer { if folderAccess { authorizedFolder?.stopAccessingSecurityScopedResource() } }
    let sourceAccess = url.startAccessingSecurityScopedResource()
    defer { if sourceAccess { url.stopAccessingSecurityScopedResource() } }

    let data = try CameraRawXMP.writeStoredSidecar(settings, replacing: existing)
    let destination = sidecarURL
    var coordinationError: NSError?
    var operation: Result<Void, Error>?
    RawSourceIO.coordinate(rawURL: url, sidecar: destination) { coordinator in
      coordinator.coordinate(readingItemAt: url, options: .withoutChanges,
        writingItemAt: destination, options: .forReplacing, error: &coordinationError) { raw, packet in
        operation = Result {
          guard raw.standardizedFileURL == url.standardizedFileURL,
            packet.standardizedFileURL == destination.standardizedFileURL else {
            throw RawDNGSource.SaveError.sourceChanged
          }
          let source = try RawDNGSource.unchanged(raw, expected: original)
          let physicalParent = try Self.physicalDirectory(packet.deletingLastPathComponent())
          let physicalPacket = physicalParent.appendingPathComponent(packet.lastPathComponent)
          let writer = try AtomicFileWriter(to: physicalPacket, maximumBytes: CameraRawXMP.maximumBytes,
            followSymbolicLinks: false)
          let alternateExtension = physicalPacket.pathExtension == "xmp" ? "XMP" : "xmp"
          let alternate = physicalPacket.deletingPathExtension().appendingPathExtension(alternateExtension)
          let selected = try Self.fileStatus(physicalPacket)
          let other = try Self.fileStatus(alternate)
          if let existing {
            guard let selected else { throw RawDNGSource.SaveError.sourceChanged }
            if let other, other.st_dev != selected.st_dev || other.st_ino != selected.st_ino {
              throw RawDNGSource.SaveError.multipleSidecars
            }
            let previous = try RawDNGSource.unchanged(physicalPacket, expected: existing.data)
            try previous.validateUnchanged()
          } else {
            guard selected == nil, other == nil else { throw RawDNGSource.SaveError.sourceChanged }
          }
          try writer.append(data)
          try source.validateUnchanged()
          try writer.commit()
        }
      }
    }
    do {
      if let operation { try operation.get() }
      else if let coordinationError { throw coordinationError }
      else { throw RawDNGSource.SaveError.sourceChanged }
    } catch {
      let error = error as NSError
      if (error.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(error.code))
        || (error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileWriteNoPermission.rawValue) {
        throw RawDNGSource.SaveError.sidecarAccessNeeded
      }
      throw error
    }
    let refreshed = RawSourceIO.RelatedXMP(url: destination, data: data, settings: settings)
    return RawSidecarSource(url: url, original: original, existing: refreshed)
  }

  private static func physicalDirectory(_ url: URL) throws -> URL {
    try url.withUnsafeFileSystemRepresentation { path in
      guard let path, let resolved = Darwin.realpath(path, nil) else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
      }
      defer { free(resolved) }
      return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }
  }

  private static func fileStatus(_ url: URL) throws -> stat? {
    var record = stat()
    let result = url.withUnsafeFileSystemRepresentation { pointer in
      pointer.map { Darwin.lstat($0, &record) } ?? -1
    }
    if result == 0 { return record }
    let code = errno
    if code == ENOENT { return nil }
    throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
  }
}
