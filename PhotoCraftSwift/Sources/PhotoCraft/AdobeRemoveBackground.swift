import CoreFoundation
import Foundation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging

/// The published remove-background envelope is distinct from execute-actions.
struct AdobeRemoveBackgroundRequest: Sendable {
  enum Mode: String, Sendable { case cutout, mask, psd }
  let input: URL
  let mode: Mode
  let mediaType: AdobeActionsRequest.MediaType?
  let trim: Bool
  let background: Pixel?
  let decontamination: Float

  init(data: Data) throws {
    guard data.count <= AdobeActionsRequest.maximumBodyBytes else {
      throw AdobeAPIError(status: 413, code: "validation_error", message: "Request exceeds the local 4 MiB limit.")
    }
    let raw: Any
    do { raw = try JSONSerialization.jsonObject(with: data) }
    catch { throw AdobeAPIError(status: 400, code: "invalid_json", message: "Expected a JSON object.") }
    let root = try AdobeActionsRequest.Object(raw, at: "request",
      allowed: ["image", "mode", "output", "trim", "backgroundColor", "colorDecontamination"])
    let source = try root.object("image", allowed: ["source"]).object("source", allowed: ["url"])
    input = try AdobeActionsRequest.url(source.string("url"), path: "image.source.url", httpsOnly: false)
    guard let mode = Mode(rawValue: try root.fields["mode"] == nil ? "cutout" : root.string("mode")) else {
      throw AdobeAPIError.invalid("mode must be cutout, mask or psd.")
    }
    self.mode = mode
    if root.fields["output"] != nil {
      let output = try root.object("output", allowed: ["mediaType"])
      if output.fields["mediaType"] == nil { mediaType = nil }
      else {
      let name = try output.string("mediaType")
      guard ["image/png", "image/jpeg", "image/webp", "image/vnd.adobe.photoshop"].contains(name) else {
        throw AdobeAPIError.invalid("Invalid output.mediaType.")
      }
      guard let type = AdobeActionsRequest.MediaType(rawValue: name) else {
        throw AdobeAPIError.unsupported("Native WebP output is not implemented; request PNG, JPEG or PSD.")
      }
      mediaType = type
      }
    } else { mediaType = nil }
    if mode == .psd, let mediaType, mediaType != .psd {
      throw AdobeAPIError.invalid("PSD mode requires PSD output.")
    }
    trim = try root.optionalBool("trim") ?? false
    if let raw = root.fields["backgroundColor"] {
      let color = try AdobeActionsRequest.Object(raw, at: "backgroundColor", allowed: ["red", "green", "blue", "alpha"])
      background = try Pixel(Self.number(color.fields, "red", 0...255) / 255,
        Self.number(color.fields, "green", 0...255) / 255,
        Self.number(color.fields, "blue", 0...255) / 255,
        Self.number(color.fields, "alpha", 0...1))
    } else { background = nil }
    decontamination = try root.fields["colorDecontamination"] == nil ? 1 : Self.number(root.fields, "colorDecontamination", 0...1)
  }
  private static func number(_ fields: [String: Any], _ key: String, _ range: ClosedRange<Float>) throws -> Float {
    guard let number = fields[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      number.doubleValue.isFinite, Double(range.lowerBound)...Double(range.upperBound) ~= number.doubleValue else {
      throw AdobeAPIError.invalid("Invalid \(key).")
    }
    return number.floatValue
  }

  func execute(input data: Data, detector: any ForegroundDetecting) async throws -> [AdobeActionAssets.Encoded] {
    try Task.checkCancellation()
    guard data.count <= AdobeActionAssets.maximumResourceBytes,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let uti = CGImageSourceGetType(source) as String?,
      ["public.jpeg", "public.png", "public.tiff", "org.webmproject.webp"].contains(uti),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int else {
      throw AdobeAPIError.invalid("Input must be a JPEG, PNG, TIFF or WebP image within 64 MiB.")
    }
    try ForegroundSelection.checkSize(width, height)
    let outputType: AdobeActionsRequest.MediaType
    if mode == .psd { outputType = .psd }
    else if let mediaType { outputType = mediaType }
    else if uti == "public.png" { outputType = .png }
    else if uti == "public.jpeg" { outputType = .jpeg }
    else { throw AdobeAPIError.unsupported("Request explicit PNG, JPEG or PSD output for TIFF/WebP input.") }
    // Import only the published image input, including EXIF orientation and profile handling.
    let decoded = try RasterIO.read(data, name: "Foreground")
    guard decoded.layers.count <= 64, decoded.estimatedBytes <= 128 * 1_024 * 1_024 else {
      throw AdobeAPIError.invalid("Decoded input exceeds the local 64-layer or 128 MiB document limit.")
    }
    let original = try Renderer.composite(decoded)
    var document = try CraftDocument(width: decoded.width, height: decoded.height, depth: decoded.depth)
    document.workingICC = decoded.workingICC
    document.layers[0].name = "Foreground"
    document.layers[0].content = .raster(original)
    let command = try await ForegroundSelection.command(document: document, layerID: document.layers[0].id,
      removeBackground: true, detector: detector)
    try command.apply(to: &document)
    guard case .removeBackground(_, let mask) = command, let bounds = mask.bounds else {
      throw AdobeAPIError.invalid("No foreground subject was found.")
    }
    if mode == .mask {
      var surface = try Surface(width: document.width, height: document.height, depth: .u8, fill: .black)
      for y in 0..<document.height {
        try Task.checkCancellation()
        for x in 0..<document.width {
          let value = mask.coverage(x: x, y: y) * original.pixel(x: x, y: y).a
          surface.setPixel(x: x, y: y, Pixel(value, value, value))
        }
      }
      document = try CraftDocument(width: document.width, height: document.height)
      document.layers[0].name = "Foreground Mask"
      document.layers[0].content = .raster(surface)
    } else {
      document.layers[0].content = .raster(try Self.decontaminate(original, mask: mask, amount: decontamination))
      if let background {
        let layer = Layer(name: "Background", content: .raster(try Surface(
          width: document.width, height: document.height, depth: document.depth, fill: background)))
        document.layers.insert(layer, at: 0)
      }
    }
    if trim { try Command.crop(bounds).apply(to: &document) }
    try Task.checkCancellation()
    guard let format = outputType.format else { throw AdobeAPIError.unsupported("Background removal requires an image output.") }
    let encoded = try DocumentIO.encode(document, format: format)
    guard encoded.count <= AdobeActionAssets.maximumResourceBytes else {
      throw AdobeAPIError.invalid("Output exceeds the local 64 MiB resource limit.")
    }
    return [.init(output: .init(mediaType: outputType, destination: .hosted(validityPeriod: 3600), shouldOverwrite: nil), data: encoded)]
  }

  /// Bounded local edge unmixing; an explicit approximation, not Adobe's model.
  static func decontaminate(_ source: Surface, mask: SelectionMask, amount: Float) throws -> Surface {
    guard amount > 0 else { return source }
    var output = source
    for y in 0..<source.height {
      try Task.checkCancellation()
      for x in 0..<source.width {
        let coverage = mask.coverage(x: x, y: y)
        guard coverage > 0.05, coverage < 0.98 else { continue }
        var red: Float = 0, green: Float = 0, blue: Float = 0, weight: Float = 0
        for sy in max(0, y - 3)...min(source.height - 1, y + 3) {
          for sx in max(0, x - 3)...min(source.width - 1, x + 3) {
            let q = source.pixel(x: sx, y: sy)
            let w = max(0, 0.1 - mask.coverage(x: sx, y: sy)) * q.a
            red += q.r * w; green += q.g * w; blue += q.b * w; weight += w
          }
        }
        guard weight > 0 else { continue }
        var p = source.pixel(x: x, y: y)
        func corrected(_ c: Float, _ bg: Float) -> Float {
          let unmixed = min(1, max(0, (c - (1 - coverage) * bg / weight) / coverage))
          return c + amount * (unmixed - c)
        }
        p.r = corrected(p.r, red); p.g = corrected(p.g, green); p.b = corrected(p.b, blue)
        output.setPixel(x: x, y: y, p)
      }
    }
    return output
  }
}
