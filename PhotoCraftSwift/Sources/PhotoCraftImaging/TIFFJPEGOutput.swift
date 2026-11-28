import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import UniformTypeIdentifiers

/// One encoder per IFD. Each strip stores a complete baseline JPEG stream.
final class TIFFJPEGOutput {
  private let components: Int
  private let quality: Double
  private var sampling: [Int]?

  init(components: Int, quality: Int?) {
    self.components = components
    self.quality = quality.map { Double($0) / 12 } ?? 0.95
  }

  static func rowsPerStrip(height: Int, rowBytes: Int) -> Int {
    min(height, max(16, (65_536 / rowBytes / 16) * 16))
  }

  func encode(_ samples: [UInt8], width: Int) throws -> Data {
    try Task.checkCancellation()
    let rowBytes = width * components
    let rows = samples.count / rowBytes
    guard (components == 1 || components == 3), rows > 0, samples.count == rows * rowBytes,
      let provider = CGDataProvider(data: Data(samples) as CFData),
      let picture = CGImage(width: width, height: rows, bitsPerComponent: 8, bitsPerPixel: components * 8,
        bytesPerRow: rowBytes, space: components == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
        decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
      throw CraftError.invalid("Unable to assemble an opaque TIFF JPEG strip.")
    }

    let buffer = NSMutableData()
    guard let writer = CGImageDestinationCreateWithData(buffer, UTType.jpeg.identifier as CFString, 1, nil) else {
      throw CraftError.unavailable("The native JPEG encoder is unavailable.")
    }
    CGImageDestinationAddImage(writer, picture, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(writer) else { throw CraftError.invalid("TIFF JPEG compression failed.") }
    let data = buffer as Data
    let layout = try Self.samplingFactors(data, components: components, width: width, rows: rows)
    guard sampling == nil || sampling == layout else {
      throw CraftError.unsupported("TIFF JPEG strips must use the same chroma subsampling.")
    }
    sampling = layout
    return data
  }

  func setYCbCrFields(on node: TIFFContainer.Directory, order: TIFFContainer.Order) {
    guard components == 3, let sampling else { return }
    node.fields[262] = .init(tag: 262, type: 3, count: 1, data: order.bytes(6, 2))
    node.fields[530] = .init(tag: 530, type: 3, count: 2,
      data: order.bytes(sampling[0], 2) + order.bytes(sampling[1], 2))
    node.fields[531] = .init(tag: 531, type: 3, count: 1, data: order.bytes(1, 2))
  }

  // Chroma subsampling can change with quality. Read the emitted baseline frame
  // header so the directory describes the actual compressed samples.
  private static func samplingFactors(_ data: Data, components: Int, width: Int, rows: Int) throws -> [Int] {
    var offset = 2
    while offset + 4 <= data.count, data[offset] == 0xff {
      let marker = data[offset + 1], length = Int(data[offset + 2]) * 256 + Int(data[offset + 3])
      guard length >= 2, length <= data.count - offset - 2 else { break }
      if marker == 0xc0 {
        guard length == 8 + 3 * components, data[offset + 4] == 8, data[offset + 9] == components,
          Int(data[offset + 5]) * 256 + Int(data[offset + 6]) == rows,
          Int(data[offset + 7]) * 256 + Int(data[offset + 8]) == width else { break }
        if components == 1 { return [1, 1] }
        let first = data[offset + 11]
        guard data[offset + 10] == 1, data[offset + 13] == 2, data[offset + 16] == 3,
          data[offset + 14] == 0x11, data[offset + 17] == 0x11 else { break }
        let across = Int(first >> 4), down = Int(first & 15)
        if [1, 2, 4].contains(across), [1, 2, 4].contains(down) { return [across, down] }
        break
      }
      if marker == 0xda { break }
      offset += 2 + length
    }
    throw CraftError.invalid("Unexpected native JPEG frame layout for TIFF.")
  }
}
