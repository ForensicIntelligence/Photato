import Foundation
import ImageIO
import PhotoCraftCore
import UniformTypeIdentifiers

/// Native ImageIO import for a JPEG XL still image.
public enum JPEGXLInput {
  public static let typeIdentifier = "public.jpeg-xl"
  public static let mediaType = "image/jxl"
  public static let maximumDecodedPixels = 1_073_741_824 / MemoryLayout<Pixel>.stride
  public static let isAvailable = (CGImageSourceCopyTypeIdentifiers() as? [String])?
    .contains(typeIdentifier) == true

  public static var contentType: UTType {
    UTType(typeIdentifier) ?? UTType(filenameExtension: "jxl", conformingTo: .image)
      ?? UTType(importedAs: typeIdentifier, conformingTo: .image)
  }

  private static let codestreamSignature: [UInt8] = [0xff, 0x0a]
  private static let containerSignature: [UInt8] = [
    0x00, 0x00, 0x00, 0x0c, 0x4a, 0x58, 0x4c, 0x20, 0x0d, 0x0a, 0x87, 0x0a,
  ]

  public static func recognizes(_ data: Data) -> Bool {
    data.starts(with: codestreamSignature) || data.starts(with: containerSignature)
  }

  /// ImageIO can expose an animation as a single image. Inspect the codestream
  /// metadata before handing off decoding so a still import cannot lose frames.
  static func requireStill(_ data: Data) throws {
    let header = try codestreamPrefix(data)
    guard header.starts(with: codestreamSignature) else { throw invalidHeader }
    var bits = HeaderBits(bytes: header)
    try bits.skipSize(preview: false)
    let allDefault = try bits.read(1) == 1
    if allDefault { return }
    let hasExtraFields = try bits.read(1) == 1
    if !hasExtraFields { return }
    _ = try bits.read(3) // Orientation.
    if try bits.read(1) == 1 { try bits.skipSize(preview: false) }
    if try bits.read(1) == 1 { try bits.skipSize(preview: true) }
    if try bits.read(1) == 1 {
      throw CraftError.unsupported("Open a still JPEG XL image. Animated JPEG XL is not supported.")
    }
  }

  private static var invalidHeader: CraftError { .invalid("Invalid or incomplete JPEG XL header.") }

  // Container boxes carry either a whole codestream (jxlc) or ordered
  // fragments (jxlp). Read at most 32 codestream bytes for the metadata flags.
  private static func codestreamPrefix(_ data: Data) throws -> [UInt8] {
    let limit = 32
    if data.starts(with: codestreamSignature) { return Array(data.prefix(limit)) }
    guard data.starts(with: containerSignature) else { throw invalidHeader }
    func number(at offset: Int, length: Int) -> UInt64 {
      let start = data.startIndex + offset
      return data[start..<(start + length)].reduce(0) { ($0 << 8) | UInt64($1) }
    }
    var offset = containerSignature.count
    var expectedFragment: UInt64 = 0
    var prefix: [UInt8] = []
    while offset < data.count, prefix.count < limit {
      try Task.checkCancellation()
      let remaining = data.count - offset
      guard remaining >= 8 else { throw invalidHeader }
      let size32 = number(at: offset, length: 4)
      let kind = number(at: offset + 4, length: 4)
      let headerBytes = size32 == 1 ? 16 : 8
      guard remaining >= headerBytes else { throw invalidHeader }
      let size: UInt64
      switch size32 {
      case 0: size = UInt64(remaining)
      case 1: size = number(at: offset + 8, length: 8)
      default: size = size32
      }
      guard size >= headerBytes, size <= remaining else { throw invalidHeader }
      let end = offset + Int(size)
      var payload = offset + headerBytes
      switch kind {
      case 0x6A786C63: // jxlc
        guard expectedFragment == 0 else { throw invalidHeader }
        return Array(data.dropFirst(payload).prefix(min(limit, end - payload)))
      case 0x6A786C70: // jxlp
        guard end - payload >= 4 else { throw invalidHeader }
        let fragment = number(at: payload, length: 4)
        guard fragment & 0x7fff_ffff == expectedFragment else { throw invalidHeader }
        expectedFragment += 1
        payload += 4
        prefix.append(contentsOf: data.dropFirst(payload).prefix(min(limit - prefix.count, end - payload)))
        if fragment & 0x8000_0000 != 0 { return prefix }
      default: break
      }
      offset = end
    }
    return prefix
  }

  private struct HeaderBits {
    let bytes: [UInt8]
    var offset = 16 // The two-byte codestream signature.

    mutating func read(_ width: Int) throws -> Int {
      guard width <= bytes.count * 8 - offset else { throw invalidHeader }
      var value = 0
      for bit in 0..<width {
        value |= Int((bytes[offset / 8] >> (offset % 8)) & 1) << bit
        offset += 1
      }
      return value
    }

    mutating func skipSize(preview: Bool) throws {
      let small = try read(1) == 1
      try skipDimension(preview: preview, small: small)
      let aspectUsesExplicitWidth = try read(3) == 0
      if aspectUsesExplicitWidth { try skipDimension(preview: preview, small: small) }
    }

    private mutating func skipDimension(preview: Bool, small: Bool) throws {
      if small && !preview {
        _ = try read(5)
        return
      }
      let widths = preview ? (small ? [0, 0, 5, 9] : [6, 8, 10, 12]) : [9, 13, 18, 30]
      let choice = try read(2)
      _ = try read(widths[choice])
    }
  }
}
