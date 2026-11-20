import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// File output state is attached to a save snapshot, outside pixel edits and Undo.
struct SavedDocumentPrintSettings: Codable {
  static let key = "photato.printSettings.v1"
  // Two base64-encoded ICC profiles plus the bounded settings fields.
  static let maximumBytes = 12 * 1024 * 1024
  var settings: PrintSettings
  var proof: ProofSettings?

  init(settings: PrintSettings, proof: ProofSettings?) {
    self.settings = settings
    self.proof = proof
  }

  init?(_ document: CraftDocument) {
    guard let bytes = document.sourceMetadata?[Self.key], bytes.count <= Self.maximumBytes,
      let value = try? JSONDecoder().decode(Self.self, from: bytes),
      (try? value.settings.validate()) != nil else { return nil }
    self = value
    if settings.selectedArea, document.selection == nil { settings.selectedArea = false }
    if let proof, settings.content != .hardProof || (try? SoftProof.validate(proof, in: document)) == nil {
      self.proof = nil
    }
  }

  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let bytes = try encoder.encode(self)
    guard bytes.count <= Self.maximumBytes else { throw CraftError.invalid("Saved print options exceed 12 MiB.") }
    return bytes
  }
}

extension EditorStore {
  func documentWithPrintSettings(_ document: CraftDocument, format: DocumentIO.Format) throws -> CraftDocument {
    guard var settings = printOverride else { return document }
    var result = document
    var metadata = document.sourceMetadata ?? [:]
    switch format {
    case .native:
      if document.selection == nil { settings.selectedArea = false }
      var proof: ProofSettings?
      if settings.content == .hardProof {
        var value = proofSettings
        value.enabled = false
        value.gamutWarning = false
        value.plate = .composite
        proof = value
      }
      metadata[SavedDocumentPrintSettings.key] = try SavedDocumentPrintSettings(settings: settings, proof: proof).encoded()
    case .psd, .psb:
      metadata["psdResources"] = try PhotoshopPrintSettings.writing(settings, to: metadata["psdResources"] ?? Data())
    default:
      return document
    }
    result.sourceMetadata = metadata
    return result
  }
}
