import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import UniformTypeIdentifiers

/// Native ImageIO interchange. Decoded frames are editable raster layers whose
/// visibility is captured by the Timeline; exported frames are rendered copies.
public enum AnimationGIF {
  public static let maximumImportFrames = 256 // N frames × N editable layers ≤ 65,536 states.
  public static let maximumOutputBytes = 128 * 1_024 * 1_024
  public static func recognizes(_ data: Data) -> Bool {
    data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8))
  }
  public static func read(_ data: Data, name: String, rasterByteLimit: Int = 1_073_741_824) throws -> CraftDocument {
    try Task.checkCancellation()
    guard recognizes(data), data.count <= 512 * 1_024 * 1_024,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetStatus(source) == .statusComplete else { throw CraftError.invalid("Incomplete or invalid GIF.") }
    let data = Data(data) // Normalize indices when callers supply a Data slice.
    let count = CGImageSourceGetCount(source)
    guard (1...maximumImportFrames).contains(count), data.count >= 13 else { throw CraftError.unsupported("GIF import supports up to 256 editable frames.") }
    let w = Int(data[6]) | Int(data[7]) << 8, h = Int(data[8]) | Int(data[9]) << 8
    // Account for tiled float storage and frame states before allocating any decoded images.
    guard w > 0, h > 0, w <= Surface.maxDimension, h <= Surface.maxDimension,
      w <= Surface.maximumDensePixels / h else { throw CraftError.invalid("GIF canvas exceeds the image limits.") }
    let perFrame = ((w + 63) / 64) * ((h + 63) / 64) * 65_536
    guard rasterByteLimit > 0, perFrame * count + count * count * 256 <= rasterByteLimit else {
      throw CraftError.invalid("Decoded GIF frames exceed the document memory limit.")
    }
    var document = try CraftDocument(width: w, height: h, name: name)
    var layers: [Layer] = [], delays: [Double] = []
    for i in 0..<count {
      try Task.checkCancellation()
      guard let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
        let image = CGImageSourceCreateImageAtIndex(source, i, [kCGImageSourceShouldCache: false] as CFDictionary),
        image.width == w, image.height == h,
        CGImageSourceGetStatusAtIndex(source, i) == .statusComplete else {
        throw CraftError.invalid("GIF frame could not be reconstructed on its canvas.")
      }
      let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
      let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
        ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0
      guard delay.isFinite, (0...655.35).contains(delay) else { throw CraftError.invalid("Invalid GIF frame delay.") }
      var layer = Layer(name: count == 1 ? name : "Frame \(i + 1)", content: .raster(try RasterIO.surface(image)))
      layer.visible = i == 0; layers.append(layer); delays.append(delay)
    }
    // First frame is the lowest layer, as with Make Frames From Layers.
    document.layers = layers.reversed(); document.activeLayerID = layers[0].id
    if count > 1 {
      let root = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] ?? [:]
      let gif = root[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
      // ImageIO exposes total passes (Netscape repeat count + 1); zero means forever.
      let loops = (gif[kCGImagePropertyGIFLoopCount] as? Int) ?? 1
      guard (0...65_535).contains(loops) else { throw CraftError.unsupported("GIF loop count exceeds the Timeline limit.") }
      let frames = layers.enumerated().map { i, layer in
        var frame = AnimationFrame(layers: document.layers, delay: delays[i])
        for j in frame.layers.indices { frame.layers[j].visible = frame.layers[j].layerID == layer.id }
        return frame
      }
      var animation = FrameAnimation(layers: document.layers)
      animation.frames = frames; animation.selectedFrameID = frames[0].id; animation.loopCount = loops
      document.animation = animation
    }
    try document.validate(); return document
  }

  /// ImageIO drops sufficiently large finite counts when writing. Replace its
  /// known Netscape application block using the public repetition-count encoding.
  /// Walk extension subblocks; never search compressed image bytes for a signature.
  static func settingLoops(_ loops: Int, in encoded: Data) throws -> Data {
    var bytes = Data(encoded)
    guard bytes.count >= 13 else { throw CraftError.invalid("Incomplete GIF export header.") }
    var at = 13 + (bytes[10] & 0x80 == 0 ? 0 : 3 * (1 << (Int(bytes[10] & 7) + 1)))
    while at + 2 < bytes.count, bytes[at] == 0x21 {
      let start = at, label = bytes[at + 1]; at += 2
      while at < bytes.count {
        let length = Int(bytes[at]); at += 1
        guard length <= bytes.count - at else { throw CraftError.invalid("Truncated GIF extension.") }
        at += length
        if length == 0 { break }
      }
      if label == 0xff, at - start == 19,
        bytes[start + 2] == 11,
        bytes[(start + 3)..<(start + 14)] == Data("NETSCAPE2.0".utf8),
        bytes[start + 14] == 3, bytes[start + 15] == 1, bytes[start + 18] == 0 {
        if loops == 1 { bytes.removeSubrange(start..<at) }
        else {
          let repeats = loops == 0 ? 0 : loops - 1
          bytes[start + 16] = UInt8(repeats & 255); bytes[start + 17] = UInt8(repeats >> 8)
        }
        bytes.replaceSubrange(0..<6, with: Data("GIF89a".utf8))
        return bytes
      }
    }
    throw CraftError.invalid("Native GIF encoder did not provide the expected loop extension.")
  }

  public static func encode(_ document: CraftDocument, alphaThreshold: Double = 0.5) throws -> Data {
    try Task.checkCancellation(); try document.validate()
    guard alphaThreshold.isFinite, (0...1).contains(alphaThreshold), let animation = document.animation else {
      throw CraftError.invalid("Create frame animation before exporting a GIF; alpha threshold must be from 0 to 1.")
    }
    guard document.width <= 65_535, document.height <= 65_535,
      animation.frames.allSatisfy({ $0.delay <= 655.35 }) else {
      throw CraftError.unsupported("GIF supports delays up to 655.35 seconds per frame and a 65,535-pixel canvas.")
    }
    let bytes = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(bytes, UTType.gif.identifier as CFString, animation.frames.count, nil) else {
      throw CraftError.unavailable("Native GIF export is unavailable.")
    }
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let srgb = try CraftDocument(width: 1, height: 1)
    for frame in animation.frames {
      try Task.checkCancellation()
      let composition = try document.animationDocument(at: frame.id)
      var surface = try ColorManagement.converted(Renderer.composite(composition), from: composition, to: srgb)
      // GIF has one-bit alpha. Explicit thresholding avoids an undocumented matte.
      surface.mapPixels { _, _, p in p.a > 0 && Double(p.a) >= alphaThreshold ? Pixel(p.r, p.g, p.b, 1) : .clear }
      let delay = (frame.delay * 100).rounded() / 100
      CGImageDestinationAddImage(destination, try RasterIO.displayImage(surface), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
      guard bytes.length <= maximumOutputBytes else { throw CraftError.invalid("GIF export exceeds 128 MiB.") }
    }
    try Task.checkCancellation()
    guard CGImageDestinationFinalize(destination), bytes.length <= maximumOutputBytes else { throw CraftError.invalid("GIF encoding failed or exceeded 128 MiB.") }
    try Task.checkCancellation(); return try settingLoops(animation.loopCount, in: bytes as Data)
  }
}
