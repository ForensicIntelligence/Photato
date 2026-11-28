// This product includes DNG technology under license by Adobe.
import Foundation
import ImageIO
import PhotoCraftCore

extension RawSourceIO {
  /// Reject reduced decoder output for an unscaled DNG whose default crop is
  /// the entire declared CFA image. Other DNGs can legitimately use a crop,
  /// non-square samples, or a preview IFD in their metadata.
  static func validateDNGCanvas(_ properties: [AnyHashable: Any], decoded: CGSize) throws {
    guard let dng = properties[kCGImagePropertyDNGDictionary as String] as? [String: Any],
      let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
      let interpretation = tiff[kCGImagePropertyTIFFPhotometricInterpretation as String] as? Int,
      [32_803, 34_892].contains(interpretation),
      let w = properties[kCGImagePropertyPixelWidth as String] as? Int,
      let h = properties[kCGImagePropertyPixelHeight as String] as? Int, w > 0, h > 0,
      let crop = dng[kCGImagePropertyDNGDefaultCropSize as String] as? [Double], crop == [Double(w), Double(h)],
      let area = dng[kCGImagePropertyDNGActiveArea as String] as? [Int], area == [0, 0, h, w],
      let scale = dng[kCGImagePropertyDNGDefaultScale as String] as? [Double], scale == [1, 1],
      let origin = dng[kCGImagePropertyDNGDefaultCropOrigin as String] as? [Double], origin == [0, 0] else { return }
    guard w <= maximumDimension, h <= maximumDimension, w <= maximumPixels / h else {
      throw CraftError.unsupported("The DNG declares dimensions above 65,000 pixels per side or 512 megapixels.")
    }
    let declared = CGSize(width: w, height: h)
    let rotated = CGSize(width: h, height: w)
    guard decoded == declared || decoded == rotated else {
      throw CraftError.unsupported("This Mac’s RAW decoder could not render the DNG at its declared size of \(w) × \(h) pixels.")
    }
  }

  static func embeddedDNGXMP(_ data: Data) throws -> Data? {
    guard TIFFContainer.isClassic(data) else { return nil }
    let container = try TIFFContainer(data, metadata: false, additionalTags: [700], maximumBytes: SmartObject.maximumCameraRawSourceBytes)
    guard let packet = container.root.fields[700], packet.type == 1 || packet.type == 7,
      (1...CameraRawXMP.maximumBytes).contains(packet.count) else { return nil }
    return packet.data
  }

  /// Reuse the original TIFF addresses for all sensor, preview and metadata data.
  /// Only the first directory pointer changes in the copy of the original bytes.
  public static func dngWithSettings(_ data: Data, settings: RawDevelopment) throws -> Data {
    try dngWithSettings(data, settings: settings, including: nil)
  }

  static func dngWithSettings(_ data: Data, settings: RawDevelopment, including sidecar: Data?,
    marking: RawPhotoMarking? = nil) throws -> Data {
    try replacingDNGXMP(data) { packet in
      try CameraRawXMP.writeStored(settings, replacing: packet, including: sidecar, marking: marking)
    }
  }

  static func replacingDNGXMP(_ data: Data, packet makePacket: (Data?) throws -> Data) throws -> Data {
    try Task.checkCancellation()
    guard data.count <= SmartObject.maximumCameraRawSourceBytes, TIFFContainer.isClassic(data) else {
      throw CraftError.unsupported("Choose a classic DNG file under 2 GiB.")
    }
    let container = try TIFFContainer(data, metadata: false, additionalTags: [700, 50706], maximumBytes: SmartObject.maximumCameraRawSourceBytes)
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
    let packet = try makePacket(existing?.data)
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
    guard entries.count <= 4096, newLength <= SmartObject.maximumCameraRawSourceBytes else {
      throw CraftError.invalid("The DNG with embedded settings exceeds the 2 GiB local RAW source limit.")
    }
    try Task.checkCancellation()
    var tail = Data()
    if original.count % 2 != 0 { tail.append(0) }
    tail.append(packet)
    if packet.count % 2 != 0 { tail.append(0) }
    tail.append(order.bytes(entries.count, 2))
    for entry in entries.sorted(by: { $0.tag < $1.tag }) { tail.append(entry.bytes) }
    tail.append(followingDirectory)
    let pointer = order.bytes(newDirectory, 4)
    if newLength > SmartObject.maximumSourceBytes {
      return try FileBackedSource.writing(maximumBytes: SmartObject.maximumCameraRawSourceBytes) { destination in
        let writer = try AtomicFileWriter(to: destination, maximumBytes: newLength)
        try writer.append(Data(original.prefix(4)))
        try writer.append(pointer)
        for offset in stride(from: 8, to: original.count, by: 64 * 1024) {
          try Task.checkCancellation()
          try writer.append(original.subdata(in: offset..<min(original.count, offset + 64 * 1024)))
        }
        try writer.append(tail)
        try writer.commit()
      }.data
    }
    var result = original
    result.reserveCapacity(newLength)
    result.append(tail)
    result.replaceSubrange(4..<8, with: pointer)
    return result
  }
}
