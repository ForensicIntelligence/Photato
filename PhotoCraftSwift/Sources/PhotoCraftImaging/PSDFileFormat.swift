import Foundation

/// PSD/PSB framing from Adobe's public specification and PhotoCraft's
/// crates/psd/src/{header,tagged,compression}.rs (MIT OR Apache-2.0).
/// Container support does not remove the engine's decoded-memory limits.
public enum PSDFileFormat: Int, Sendable, CaseIterable {
  case psd = 1
  case psb = 2

  public var maximumDimension: Int { self == .psd ? 30_000 : 300_000 }
  var sectionLengthBytes: Int { self == .psd ? 4 : 8 }
  var rowLengthBytes: Int { self == .psd ? 2 : 4 }

  /// Photoshop requires the64-bit signature for these wide PSB blocks.
  /// A wide length preceded by8BIM can round-trip locally but is rejected by Photoshop.
  func tagSignature(_ key: String) -> String {
    tagLengthBytes(key) == 8 ? "8B64" : "8BIM"
  }

  func tagLengthBytes(_ key: String) -> Int {
    // The Rust source includes eight additional observed Photoshop keys beyond
    // the thirteen listed by Adobe. In particular, pths/cinf must not shift the
    // following blocks by interpreting their high length word as a zero size.
    let wideKeys: Set<String> = [
      "LMsk", "Lr16", "Lr32", "Layr", "Mt16", "Mt32", "Mtrn", "Alph", "FMsk",
      "lnk2", "FEid", "FXid", "PxSD", "lnk3", "lnkE", "pths", "extd", "extn",
      "FELS", "cinf", "artd",
    ]
    return self == .psb && wideKeys.contains(key) ? 8 : 4
  }
}
