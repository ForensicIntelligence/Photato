import Foundation
import PhotoCraftAI
import PhotoCraftCore

/// A requested system strategy, not an attestation of the provider's final input.
enum ImageReferenceUse: String, CaseIterable, Codable, Sendable {
  case inspiration, editExisting
  var title: String { self == .inspiration ? "Inspiration" : "Image to edit" }
  static func supportsEditing(majorVersion: Int, isAppleSilicon: Bool) -> Bool {
    majorVersion >= 27 && isAppleSilicon
  }
  static var editingSupported: Bool {
    ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 && LocalAI.platform.available
  }
  func validate(hasReference: Bool, editingSupported: Bool = Self.editingSupported) throws {
    guard self == .editExisting else { return }
    guard hasReference else { throw CraftError.invalid("Choose an image before requesting a reference-image edit.") }
    guard editingSupported else {
      throw CraftError.unsupported("Editing a reference image requires macOS 27 or later on eligible Apple Silicon. Inspiration remains available on supported macOS 26 systems.")
    }
  }
}
