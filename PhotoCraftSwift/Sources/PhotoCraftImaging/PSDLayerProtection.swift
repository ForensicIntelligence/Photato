import Foundation
import PhotoCraftCore

/// Protection record codec shared by PSD, PSB and embedded TIFF layer records.
enum PSDLayerProtection {
  static func decode(layerFlags: UInt8, record: Data?) throws -> LayerProtection {
    var value: UInt32 = layerFlags & 1 == 0 ? 0 : 1
    if let record {
      guard record.count == 4 else {
        throw CraftError.invalid("PSD layer protection must contain exactly four bytes.")
      }
      let stored = record.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
      value |= stored
    }
    let result = LayerProtection(rawValue: value)
    try result.validate()
    return result
  }

  static func encode(_ protection: LayerProtection) throws -> Data {
    try protection.validate()
    let value = protection.rawValue
    return Data([
      UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
      UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value),
    ])
  }

  /// Only the legacy transparency bit belongs in the layer record's flags byte.
  static func layerFlags(_ flags: UInt8, protection: LayerProtection) throws -> UInt8 {
    try protection.validate()
    return (flags & ~1) | (protection.locksTransparency ? 1 : 0)
  }
}
