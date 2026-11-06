import Foundation
import PhotoCraftCore

/// A Save panel authorizes its selected item, not arbitrary sibling temporary files.
/// Use Foundation's coordinated atomic publication for these small preset payloads.
enum CustomKernelPresetFile {
  static func write(_ data:Data,to url:URL)throws {
    try Task.checkCancellation()
    guard url.isFileURL,data.count<=CustomKernelPreset.maximumBytes else {
      throw CraftError.invalid("Choose a local preset destination, up to 16 KiB.")
    }
    let accessing=url.startAccessingSecurityScopedResource()
    defer{if accessing{url.stopAccessingSecurityScopedResource()}}
    var coordinationError:NSError?,operationError:Error?
    NSFileCoordinator(filePresenter:nil).coordinate(writingItemAt:url,options:.forReplacing,error:&coordinationError) {destination in
      do {
        try Task.checkCancellation()
        guard (try? destination.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) != true else {
          throw CraftError.invalid("Choose a preset file, not a directory.")
        }
        try data.write(to:destination,options:.atomic)
      }catch{operationError=error}
    }
    if let error=operationError ?? coordinationError{throw error}
  }
}
