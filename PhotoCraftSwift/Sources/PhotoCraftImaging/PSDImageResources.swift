import Foundation
import PhotoCraftCore

/// Opaque PSD image resources retain their original names, padding and payload.
/// Pixel/profile/path and layer-index resources must be regenerated or omitted.
enum PSDImageResources {
  struct Block {
    let id: Int
    let data: Data
    let raw: Data
  }
  static let maximumBytes = 16 * 1024 * 1024
  static let replacedIDs: Set<Int> = [1005, 1025, 1039, 1041, 1046, 1047, 1060,
    1006, 1007, 1045, 1053, 1066, 1067, 1077]
  static let staleIDs: Set<Int> = [
    1000, 1022, 1024, 1026, 1033, 1036, 1044, 1057, 1069, 1072, 1086, 1087, 1088,
  ]
  static func blocks(_ data: Data) throws -> [Block] {
    guard data.count <= maximumBytes else {
      throw CraftError.invalid("PSD image metadata exceeds the 16 MiB limit.")
    }
    var reader = PSDReader(data: data)
    var result: [Block] = []
    while reader.remaining > 0 {
      try Task.checkCancellation()
      let start = reader.offset
      guard try reader.string(4) == "8BIM" else {
        throw CraftError.invalid("Invalid PSD image resource signature.")
      }
      let id = try reader.u16()
      let nameLength = Int(try reader.u8())
      _ = try reader.bytes(nameLength)
      if (nameLength + 1) % 2 != 0 { _ = try reader.bytes(1) }
      let content = try reader.bytes(reader.u32())
      if content.count % 2 != 0 { _ = try reader.bytes(1) }
      result.append(Block(id: id, data: content, raw: data.subdata(in: start..<reader.offset)))
    }
    return result
  }
  static func preserved(_ data: Data, preservingLayerLinks:Bool=false) throws -> Data {
    var output = Data()
    for block in try blocks(data)
    where !replacedIDs.contains(block.id) && (!staleIDs.contains(block.id) || (preservingLayerLinks && [1026,1072].contains(block.id)))
      && !(2000...2997).contains(block.id)
    {
      output.append(block.raw)
    }
    return output
  }
  static func block(_ id: Int, data: Data) -> Data {
    var writer = PSDWriter()
    writer.text("8BIM")
    writer.n(id, 2)
    writer.n(0, 2)
    writer.section(data)
    if data.count % 2 != 0 { writer.n(0, 1) }
    return writer.data
  }
}
