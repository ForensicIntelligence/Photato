import Foundation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging

/// Native resource processing shared with desktop import/export. These limits
/// describe the local preview, not Adobe's hosted service limits.
enum AdobeActionAssets {
  static let maximumResourceBytes = 64 * 1_024 * 1_024
  static let maximumOutputBytes = 128 * 1_024 * 1_024
  static let maximumCanvasPixels = 4_194_304

  struct Encoded: Sendable {
    let output: AdobeActionsRequest.Output
    let data: Data
  }

  static func decode(_ data: Data) throws -> CraftDocument {
    try Task.checkCancellation()
    guard data.count <= maximumResourceBytes else {
      throw AdobeAPIError.invalid("Input exceeds the local 64 MiB resource limit.")
    }
    let width: Int
    let height: Int
    if data.starts(with: Data("8BPS".utf8)) {
      guard data.count >= 26 else { throw AdobeAPIError.invalid("Truncated PSD header.") }
      func number(_ start: Int, _ count: Int) -> Int {
        data[start..<(start + count)].reduce(0) { ($0 << 8) | Int($1) }
      }
      guard number(4, 2) == 1, [8, 16, 32].contains(number(22, 2)), number(24, 2) == 3 else {
        throw AdobeAPIError.unsupported("Actions require a supported RGB8/16/32 PSD or RGB8 PNG.")
      }
      width = number(18, 4)
      height = number(14, 4)
    } else {
      guard data.starts(with: Data([137, 80, 78, 71, 13, 10, 26, 10])),
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let w = properties[kCGImagePropertyPixelWidth] as? Int,
        let h = properties[kCGImagePropertyPixelHeight] as? Int
      else {
        throw AdobeAPIError.unsupported("The input must contain a supported PSD or PNG image.")
      }
      width = w
      height = h
    }
    guard width > 0, height > 0, width <= maximumCanvasPixels / height else {
      throw AdobeAPIError.invalid("Input exceeds the local 4,194,304 pixel canvas limit.")
    }
    let document = try RasterIO.read(data, name: "Action Input")
    if !data.starts(with: Data("8BPS".utf8)), document.depth != .u8 {
      throw AdobeAPIError.unsupported("PNG action input currently requires RGB8.")
    }
    try check(document)
    return document
  }

  static func check(_ document: CraftDocument) throws {
    try document.validate()
    guard document.width <= maximumCanvasPixels / document.height,
      document.layers.count <= 64, document.estimatedBytes <= 128 * 1_024 * 1_024
    else {
      throw AdobeAPIError.invalid(
        "Input exceeds the local canvas, 64-layer or 128 MiB document limit.")
    }
  }

  /// Encode every output before publishing any of them. This prevents an invalid
  /// later output from exposing a misleading partial successful result.
  static func execute(_ request: AdobeActionsRequest, input: Data) throws -> [Encoded] {
    let document = try decode(input)
    let edited = try request.applying(to: document).session.document
    try check(edited)
    var cache: [AdobeActionsRequest.MediaType: Data] = [:]
    var total = 0
    return try request.outputs.map { output in
      try Task.checkCancellation()
      let data: Data
      if let existing = cache[output.mediaType] {
        data = existing
      } else {
        switch output.mediaType {
        case .psd: data = try PSDCodec.writeRasterLayers(edited)
        case .png:
          guard edited.depth != .f32 else {
            throw AdobeAPIError.unsupported("PNG cannot retain RGB32 action output; request PSD.")
          }
          data = try RasterIO.encoded(edited)
        }
        guard data.count <= maximumResourceBytes else {
          throw AdobeAPIError.invalid("Encoded output exceeds the local 64 MiB resource limit.")
        }
        cache[output.mediaType] = data
      }
      total += data.count
      guard total <= maximumOutputBytes else {
        throw AdobeAPIError.invalid("Outputs exceed the local 128 MiB aggregate limit.")
      }
      return Encoded(output: output, data: data)
    }
  }
}
