import Foundation
import PhotoCraftCore

extension RestrictedModeRequest {
  public func command(in document: CraftDocument, masters: [CraftDocument] = []) throws -> Command {
    switch kind {
    case .indexed: return try RestrictedModeInput.indexed(indexed, in: document, mergeVisible: mergeVisible, masterDocuments: [.masterPerceptual, .masterSelective, .masterAdaptive].contains(indexed.palette) ? masters : [], previousPalette: previousPalette)
    case .bitmap: return try RestrictedModeInput.bitmap(bitmap, in: document, mergeVisible: mergeVisible)
    case .colorTable: return try RestrictedModeInput.colorTable(colors, transparentIndex: transparentIndex, in: document)
    }
  }
}

/// Adobe Color Table files contain 256 RGB triplets, optionally followed by
/// big-endian palette count and transparent index (65535 means none).
public struct ColorTableFile: Equatable, Sendable {
  public var colors: [PaletteColor]
  public var transparentIndex: Int?
  public init(colors: [PaletteColor], transparentIndex: Int? = nil) throws {
    guard (1...256).contains(colors.count), transparentIndex == nil || colors.indices.contains(transparentIndex!) else { throw CraftError.invalid("Invalid color table or transparency entry.") }
    self.colors = colors; self.transparentIndex = transparentIndex
  }
  public init(data: Data) throws {
    let bytes = [UInt8](data)
    guard [768, 772].contains(bytes.count) else { throw CraftError.invalid("An ACT file must contain 768 or 772 bytes.") }
    let count = bytes.count == 772 ? Int(bytes[768]) * 256 + Int(bytes[769]) : 256
    let countValue = count == 0 ? 256 : count
    let transparent = bytes.count == 772 ? Int(bytes[770]) * 256 + Int(bytes[771]) : 65535
    guard countValue <= 256 else { throw CraftError.invalid("ACT palette exceeds 256 entries.") }
    try self.init(colors: (0..<countValue).map { .init(bytes[$0 * 3], bytes[$0 * 3 + 1], bytes[$0 * 3 + 2]) }, transparentIndex: transparent == 65535 ? nil : transparent)
  }
  public func encoded() throws -> Data {
    _ = try Self(colors: colors, transparentIndex: transparentIndex)
    var bytes = [UInt8](repeating: 0, count: 772)
    for (i, c) in colors.enumerated() { bytes[i * 3] = c.red; bytes[i * 3 + 1] = c.green; bytes[i * 3 + 2] = c.blue }
    bytes[768] = UInt8(colors.count >> 8); bytes[769] = UInt8(colors.count & 255)
    let transparent = transparentIndex ?? 65535
    bytes[770] = UInt8(transparent >> 8); bytes[771] = UInt8(transparent & 255)
    return Data(bytes)
  }
}
