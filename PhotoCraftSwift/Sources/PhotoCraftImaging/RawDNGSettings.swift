// This product includes DNG technology under license by Adobe.
import Foundation
import PhotoCraftCore

extension RawSourceIO {
  /// Reuse the original TIFF addresses for all sensor, preview and metadata data.
  /// Only the first directory pointer changes in the copy of the original bytes.
  public static func dngWithSettings(_ data: Data, settings: RawDevelopment) throws -> Data {
    try Task.checkCancellation()
    guard data.count <= SmartObject.maximumSourceBytes, TIFFContainer.isClassic(data) else {
      throw CraftError.unsupported("Choose a classic DNG file under 64 MiB.")
    }
    let container = try TIFFContainer(data, metadata: false, additionalTags: [700, 50706])
    guard let version = container.root.fields[50706], version.type == 1,
      version.count == 4, version.data.first == 1 else {
      throw CraftError.unsupported("Camera Raw settings can be embedded only in DNG sources.")
    }
    let existing = container.root.fields[700]
    if let existing {
      guard existing.type == 1 || existing.type == 7,
        (1...CameraRawXMP.maximumBytes).contains(existing.count) else {
        throw CraftError.invalid("The DNG’s existing XMP tag cannot be updated safely.")
      }
    }
    let packet = try CameraRawXMP.write(settings, replacing: existing?.data)
    if packet == existing?.data { return data }

    let order = container.order
    let original = Data(data)
    let directory = order.number(original, 4, 4)
    let count = order.number(original, directory, 2)
    var entries: [(tag: Int, bytes: Data)] = []
    var tags: Set<Int> = []
    for index in 0..<count {
      let start = directory + 2 + index * 12
      let tag = order.number(original, start, 2)
      guard tags.insert(tag).inserted else {
        throw CraftError.invalid("The DNG contains a duplicate TIFF tag.")
      }
      if tag != 700 { entries.append((tag, original.subdata(in: start..<start + 12))) }
    }
    let next = directory + 2 + count * 12
    let followingDirectory = original.subdata(in: next..<next + 4)
    let xmpOffset = original.count + original.count % 2
    var entry = order.bytes(700, 2)
    entry.append(order.bytes(1, 2))
    entry.append(order.bytes(packet.count, 4))
    entry.append(order.bytes(xmpOffset, 4))
    entries.append((700, entry))

    let newDirectory = xmpOffset + packet.count + packet.count % 2
    let newLength = newDirectory + 2 + entries.count * 12 + 4
    guard entries.count <= 4096, newLength <= SmartObject.maximumSourceBytes else {
      throw CraftError.invalid("The DNG with embedded settings exceeds Photato’s 64 MiB source limit.")
    }
    try Task.checkCancellation()
    var result = original
    result.reserveCapacity(newLength)
    if original.count % 2 != 0 { result.append(0) }
    result.append(packet)
    if packet.count % 2 != 0 { result.append(0) }
    result.append(order.bytes(entries.count, 2))
    for entry in entries.sorted(by: { $0.tag < $1.tag }) { result.append(entry.bytes) }
    result.append(followingDirectory)
    result.replaceSubrange(4..<8, with: order.bytes(newDirectory, 4))
    return result
  }
}
