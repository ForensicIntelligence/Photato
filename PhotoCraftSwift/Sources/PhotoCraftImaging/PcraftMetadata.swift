import Foundation
import PhotoCraftCore

/// Retains source metadata independently of regenerated editing records.
enum PcraftMetadata {
  static func read(_ node: PcraftNode, project: PcraftProject) throws -> [String: Data] {
    try node.keys("xmp exif psd_resources psd_global_blocks")
    var result: [String: Data] = [:], resources = Data()
    func blob(_ node: PcraftNode) throws -> Data {
      guard let value = project.blobs[try node.string()] else { throw node.invalid }; return value
    }
    if let xmp = node.optional("xmp") {
      let bytes = Data(try xmp.string().utf8)
      guard bytes.count <= FileInfoMetadata.maximumPacketBytes else { throw xmp.invalid }
      result[RasterMetadata.xmpKey] = bytes
    }
    if let exif = node.optional("exif") {
      let bytes = try blob(exif); result["pcraft.exif"] = bytes
      resources.append(PSDImageResources.block(1058, data: bytes))
    }
    for entry in try node.field("psd_resources").array() {
      let values = try entry.array(); guard values.count == 3 else { throw entry.invalid }
      let id = try values[0].integer(), name = Data(try values[1].string().utf8), bytes = try blob(values[2])
      guard (0...65535).contains(id), name.count <= 255 else { throw entry.invalid }
      var writer = PSDWriter(); writer.text("8BIM"); writer.n(id, 2); writer.n(name.count, 1); writer.data.append(name)
      if (name.count + 1) % 2 != 0 { writer.n(0, 1) }; writer.section(bytes); if bytes.count % 2 != 0 { writer.n(0, 1) }
      resources.append(writer.data)
      guard resources.count <= PSDImageResources.maximumBytes else { throw entry.invalid }
    }
    if !resources.isEmpty { guard resources.count <= PSDImageResources.maximumBytes else { throw node.invalid }; result["psdResources"] = resources }
    for (index, entry) in try node.field("psd_global_blocks").array().enumerated() {
      let values = try entry.array(); guard values.count == 3 else { throw entry.invalid }
      let signature = try values[0].string(), key = try values[1].string()
      guard signature.count == 8, key.count == 8, (signature + key).utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { throw entry.invalid }
      // Opaque source globals do not become trusted native rendering programs.
      result["pcraft.psdGlobal.\(index).\(signature).\(key)"] = try blob(values[2])
    }
    return result
  }
}
