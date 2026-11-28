import Foundation
import PhotoCraftCore

extension RawSourceIO {
  struct RelatedXMP: Sendable, Equatable {
    let url: URL
    let data: Data
    let settings: RawDevelopment
  }

  /// Finder and Open grant access to the RAW file. File coordination uses the
  /// declared XMP related item to read just its matching sibling in the sandbox.
  public static func relatedSettings(for rawURL: URL) throws -> RawDevelopment? {
    try relatedXMP(for: rawURL)?.settings
  }

  static func relatedXMP(for rawURL: URL) throws -> RelatedXMP? {
    guard rawURL.isFileURL, rawURL.pathExtension.lowercased() != "xmp" else { return nil }
    let stem = rawURL.deletingPathExtension()
    for fileExtension in ["xmp", "XMP"] {
      try Task.checkCancellation()
      let sidecar = stem.appendingPathExtension(fileExtension)
      guard sidecar != rawURL else { continue }
      var result: RelatedXMP?
      try? coordinate(rawURL: rawURL, sidecar: sidecar) { coordinator in
        var error: NSError?
        coordinator.coordinate(readingItemAt: sidecar, options: .withoutChanges, error: &error) { url in
          guard let source = try? PSDFileSource(url, maximumBytes: CameraRawXMP.maximumBytes),
            let packet = try? source.bytes(at: 0, count: source.count),
            (try? source.validateUnchanged()) != nil,
            let settings = try? CameraRawXMP.read(packet, into: RawDevelopment()) else { return }
          result = RelatedXMP(url: url, data: packet, settings: settings)
        }
        if let error { throw error }
      }
      try Task.checkCancellation()
      if let result { return result }
    }
    return nil
  }

  static func coordinate<T>(rawURL: URL, sidecar: URL,
    perform: (NSFileCoordinator) throws -> T) rethrows -> T {
    let presenter = RawXMPPresenter(primary: rawURL, sidecar: sidecar)
    NSFileCoordinator.addFilePresenter(presenter)
    defer { NSFileCoordinator.removeFilePresenter(presenter) }
    return try perform(NSFileCoordinator(filePresenter: presenter))
  }
}

private final class RawXMPPresenter: NSObject, NSFilePresenter {
  let primaryPresentedItemURL: URL?
  let presentedItemURL: URL?
  let presentedItemOperationQueue = OperationQueue()

  init(primary: URL, sidecar: URL) {
    primaryPresentedItemURL = primary
    presentedItemURL = sidecar
  }
}
