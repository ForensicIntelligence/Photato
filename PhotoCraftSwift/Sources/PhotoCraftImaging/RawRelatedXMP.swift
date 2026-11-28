import Foundation
import PhotoCraftCore

extension RawSourceIO {
  /// Finder and Open grant access to the RAW file. File coordination uses the
  /// declared XMP related item to read just its matching sibling in the sandbox.
  public static func relatedSettings(for rawURL: URL) throws -> RawDevelopment? {
    guard rawURL.isFileURL, rawURL.pathExtension.lowercased() != "xmp" else { return nil }
    let stem = rawURL.deletingPathExtension()
    for fileExtension in ["xmp", "XMP"] {
      try Task.checkCancellation()
      let sidecar = stem.appendingPathExtension(fileExtension)
      guard sidecar != rawURL else { continue }
      let presenter = RawXMPPresenter(primary: rawURL, sidecar: sidecar)
      let coordinator = NSFileCoordinator(filePresenter: presenter)
      NSFileCoordinator.addFilePresenter(presenter)
      defer { NSFileCoordinator.removeFilePresenter(presenter) }
      var error: NSError?
      var settings: RawDevelopment?
      coordinator.coordinate(readingItemAt: sidecar, options: .withoutChanges, error: &error) { url in
        guard let source = try? PSDFileSource(url, maximumBytes: CameraRawXMP.maximumBytes),
          let packet = try? source.bytes(at: 0, count: source.count),
          (try? source.validateUnchanged()) != nil else { return }
        settings = try? CameraRawXMP.read(packet, into: RawDevelopment())
      }
      try Task.checkCancellation()
      if let settings { return settings }
    }
    return nil
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
