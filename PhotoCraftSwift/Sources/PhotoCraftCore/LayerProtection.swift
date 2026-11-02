import Foundation

/// Independent protection flags shared by native editing and format/API adapters.
public struct LayerProtection: OptionSet, Codable, Equatable, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  public static let transparency = Self(rawValue: 1)
  public static let image = Self(rawValue: 2)
  public static let position = Self(rawValue: 4)
  public static let autoNest = Self(rawValue: 8)
  public static let all = Self(rawValue: 0x8000_0000)
  public static let partial: Self = [.transparency, .image, .position, .autoNest]
  public static let fullyLocked: Self = [.partial, .all]
  public static let known: Self = .fullyLocked

  public var fullyLocks: Bool { contains(.all) }
  public var locksTransparency: Bool {
    !intersection([.transparency, .image, .all]).isEmpty
  }
  public var locksImage: Bool { !intersection([.image, .all]).isEmpty }
  public var locksPosition: Bool { !intersection([.position, .all]).isEmpty }
  public var preventsAutoNesting: Bool { !intersection([.autoNest, .all]).isEmpty }
  public var unknownBits: UInt32 { rawValue & ~Self.known.rawValue }

  public func validate() throws {
    guard unknownBits == 0 else {
      throw CraftError.unsupported("Unknown layer protection flags cannot be edited.")
    }
  }

  /// Observed single-layer Command-/ behavior: clear everything or enable everything.
  public func togglingAll() throws -> Self {
    try validate()
    return fullyLocks ? [] : .fullyLocked
  }

  /// Lock Layers dialog behavior. Clearing All leaves its four subordinate settings
  /// checked; clearing Image leaves Transparency checked. Disabled choices do nothing.
  public func setting(_ option: Self, enabled: Bool) throws -> Self {
    try validate()
    guard [.transparency, .image, .position, .autoNest, .all].contains(option) else {
      throw CraftError.invalid("Choose one layer protection setting.")
    }
    if option == .all {
      return enabled ? .fullyLocked : (fullyLocks ? .partial : self)
    }
    if fullyLocks || (option == .transparency && locksImage) { return self }
    var result = enabled ? union(option) : subtracting(option)
    if option == .image && (enabled || contains(.image)) { result.insert(.transparency) }
    return result
  }

  /// Preserve exact bits when archiving; semantic/format validation is explicit.
  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(UInt32.self)
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

extension Layer {
  public var protection: LayerProtection {
    get {
      var value=protectionFlags ?? (locked ? .fullyLocked:[])
      if locked {value.insert(.all)}
      if isBackground {value.formUnion([.transparency,.position])}
      return value
    }
    set {
      locked = newValue.fullyLocks
      let partial = newValue.subtracting(.all)
      protectionFlags = (locked && partial == .partial) || (!locked && partial.isEmpty)
        ? nil : partial
    }
  }
}

extension CraftDocument {
  public func effectiveProtection(_ id: UUID) -> LayerProtection {
    ancestors(of: id).reduce(layers.first { $0.id == id }?.protection ?? []) {
      $0.union($1.protection)
    }
  }
  public func isImageLocked(_ id: UUID) -> Bool { effectiveProtection(id).locksImage }
  public func isPositionLocked(_ id: UUID) -> Bool { effectiveProtection(id).locksPosition }
  public func isTransparencyLocked(_ id: UUID) -> Bool {
    effectiveProtection(id).locksTransparency
  }
}

extension CraftDocument {
  /// Older readers only understand the legacy full-lock Bool. Require version12
  /// whenever the optional partial flags carry information those readers lose.
  public var requiresPartialProtectionArchive: Bool { layers.contains { $0.protectionFlags != nil } }
}
