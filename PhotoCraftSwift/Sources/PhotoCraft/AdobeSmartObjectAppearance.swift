import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

struct AdobeSmartObjectAppearance: Sendable {
  private static let blendModes = Dictionary(uniqueKeysWithValues: BlendMode.allCases
    .filter { $0 != .linearLight && $0 != .subtract }
    .map { ($0.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"), $0) })

  static var capabilities: [String: Any] {
    [
      "route": "POST /v2/create-composite",
      "layerType": "smart_object_layer",
      "operations": ["add", "edit"],
      "blendOptions": ["blendModes": blendModes.keys.sorted(), "opacityPercentRange": [0, 100]],
      "pixelMask": [
        "sourceFormats": ["grayscale PNG", "grayscale JPEG", "grayscale PSD", "grayscale PSB"],
        "fields": ["source", "isEnabled", "isLinked", "offset", "delete"],
        "offsetOrigin": "Layer origin, measured in document pixels",
        "deleteOnEditOnly": true,
        "maximumUnpagedSourcePixels": AdobeActionAssets.maximumUnpagedInputPixels,
      ],
    ]
  }

  let blendMode: BlendMode?
  let opacity: Float?
  let pixelMask: AdobeTemplatePixelMask?

  init(_ object: AdobeActionsRequest.Object, adding: Bool) throws {
    if object.fields["blendOptions"] != nil {
      let blend = try object.object("blendOptions", allowed: ["blendMode", "opacity"])
      if blend.fields["blendMode"] != nil {
        let name = try blend.string("blendMode")
        guard let mode = Self.blendModes[name] else {
          throw AdobeAPIError.invalid("Unknown \(blend.path).blendMode.")
        }
        blendMode = mode
      } else {
        blendMode = nil
      }
      opacity = try blend.fields["opacity"].map { _ in Float(try blend.integer("opacity", range: 0...100)) / 100 }
    } else {
      blendMode = nil
      opacity = nil
    }
    if object.fields["pixelMask"] != nil {
      let mask = try object.object("pixelMask", allowed: ["delete", "isEnabled", "isLinked", "source", "offset"])
      pixelMask = try AdobeTemplatePixelMask(mask, adding: adding)
    } else {
      pixelMask = nil
    }
  }

  func apply(to session: inout EditorSession, layerID: UUID, resources: [URL: Data]) throws {
    if let blendMode { try session.execute(.blend(layerID, blendMode)) }
    if let opacity { try session.execute(.opacity(layerID, opacity)) }
    if let pixelMask { try pixelMask.apply(to: &session, layerID: layerID, resources: resources) }
  }
}

struct AdobeTemplatePixelMask: Sendable {
  let source: URL?
  private let delete: Bool
  private let enabled: Bool?
  private let linked: Bool?
  private let horizontal: Int?
  private let vertical: Int?
  private let adding: Bool

  init(_ object: AdobeActionsRequest.Object, adding: Bool) throws {
    self.adding = adding
    if adding, object.fields["delete"] != nil {
      throw AdobeAPIError.invalid("\(object.path).delete is only supported for edits.")
    }
    delete = try object.optionalBool("delete") ?? false
    // A deleted mask ignores its other settings and never fetches its old source.
    if delete {
      source = nil
      enabled = nil
      linked = nil
      horizontal = nil
      vertical = nil
      return
    }
    enabled = try object.optionalBool("isEnabled")
    linked = try object.optionalBool("isLinked")
    if object.fields["source"] != nil {
      let resource = try object.object("source", allowed: ["url"])
      source = try AdobeActionsRequest.url(resource.string("url"), path: resource.path + ".url", httpsOnly: false)
    } else {
      source = nil
    }
    if object.fields["offset"] != nil {
      let offset = try object.object("offset", allowed: ["horizontal", "vertical"])
      let signed32 = Int(Int32.min)...Int(Int32.max)
      horizontal = try offset.fields["horizontal"].map { _ in try offset.integer("horizontal", range: signed32) }
      vertical = try offset.fields["vertical"].map { _ in try offset.integer("vertical", range: signed32) }
    } else {
      horizontal = nil
      vertical = nil
    }
  }

  func apply(to session: inout EditorSession, layerID: UUID, resources: [URL: Data]) throws {
    guard let layer = session.document.layers.first(where: { $0.id == layerID }) else {
      throw AdobeAPIError.invalid("The pixel mask layer is unavailable.")
    }
    if delete {
      if layer.mask != nil { try session.execute(.deleteMask(layerID)) }
      return
    }
    guard source != nil || enabled != nil || linked != nil || horizontal != nil || vertical != nil else { return }

    var properties = layer.effectiveMaskProperties
    let origin = layer.coordinateTransform
    if let source {
      guard let data = resources[source] else { throw AdobeAPIError.invalid("Missing pixel mask resource.") }
      let coverage = try Self.decode(data, depth: session.document.depth)
      // The replacement changes samples. Existing placement and mask settings
      // are preserved unless the edit supplies new values.
      try session.execute(.mask(layerID, coverage))
    } else if layer.mask == nil {
      guard adding else { throw AdobeAPIError.invalid("A pixel mask source is required to create a mask on this layer.") }
      try session.execute(.createMask(layerID, .revealAll))
      guard let created = session.document.layers.first(where: { $0.id == layerID }) else {
        throw AdobeAPIError.invalid("The pixel mask layer is unavailable.")
      }
      properties = created.effectiveMaskProperties
    }

    if layer.mask == nil {
      let placement = Transform2D.translation(origin.tx + Double(horizontal ?? 0), origin.ty + Double(vertical ?? 0))
      properties.transform = try origin.inverted() * placement
    } else if horizontal != nil || vertical != nil {
      let previous = layer.maskCoordinateTransform
      let targetX = horizontal.map { origin.tx + Double($0) } ?? previous.tx
      let targetY = vertical.map { origin.ty + Double($0) } ?? previous.ty
      let local = try origin.inverted().point(targetX, targetY)
      properties.transform.tx = local.x
      properties.transform.ty = local.y
    }
    if let enabled { properties.enabled = enabled }
    if let linked { properties.linked = linked }
    try session.execute(.maskProperties(layerID, properties))
  }

  private static func decode(_ data: Data, depth: PixelDepth) throws -> Surface {
    guard data.count <= AdobeActionAssets.maximumResourceBytes else {
      throw AdobeAPIError.invalid("The pixel mask exceeds the local resource size limit.")
    }
    let maxPixels = AdobeActionAssets.maximumUnpagedInputPixels
    if data.starts(with: Data("8BPS".utf8)) {
      let document = try AdobeActionAssets.decode(data)
      guard document.colorMode == .grayscale else {
        throw AdobeAPIError.invalid("A Photoshop mask resource must be grayscale.")
      }
      let samples = try ModeChannelPresentation.singleComponent(document, component: 0)
      let sourceEncoding = samples.colorEncoding
      return try samples.mappedStoredSamples(encoding: .sRGB) { stored in
        let sample = sourceEncoding == .linearRGB ? SRGBTransfer.encoded(stored) : stored
        let gray = unit(sample.r) * sample.a
        return Pixel(gray, gray, gray)
      }.quantizedStoredDepth(depth)
    }

    guard let decoder = CGImageSourceCreateWithData(data as CFData, nil),
      let type = CGImageSourceGetType(decoder) as String?,
      [UTType.png.identifier, UTType.jpeg.identifier].contains(type),
      CGImageSourceGetCount(decoder) == 1,
      let metadata = CGImageSourceCopyPropertiesAtIndex(decoder, 0, nil) as? [CFString: Any],
      let width = metadata[kCGImagePropertyPixelWidth] as? Int,
      let height = metadata[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
    else { throw AdobeAPIError.invalid("A pixel mask source must be a grayscale PNG, JPEG or PSD.") }

    try AdobeActionAssets.checkDimensions(width: width, height: height)
    guard width <= maxPixels / height else {
      throw AdobeAPIError.invalid("A pixel mask source may contain at most \(maxPixels) pixels.")
    }
    guard let image = CGImageSourceCreateImageAtIndex(decoder, 0, nil),
      CGImageSourceGetStatusAtIndex(decoder, 0) == .statusComplete,
      image.width == width, image.height == height,
      let space = image.colorSpace, space.model == .monochrome
    else { throw AdobeAPIError.invalid("The PNG or JPEG mask must contain complete grayscale samples.") }

    // Use the source's gray space to preserve numeric coverage without an RGB
    // color conversion. A transparent source contributes its gray over black.
    let wide = image.bitsPerComponent > 8
    let bits = wide ? 16 : 8
    let stride = width * (wide ? 2 : 1)
    var raw = Data(count: stride * height)
    try raw.withUnsafeMutableBytes { buffer in
      let format = CGImageAlphaInfo.none.rawValue | (wide ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
      guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
        bitsPerComponent: bits, bytesPerRow: stride, space: space, bitmapInfo: format)
      else { throw AdobeAPIError.invalid("The grayscale mask sample layout could not be decoded.") }
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    var mask = try Surface(width: width, height: height, depth: depth, fill: .black)
    try raw.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
      for y in 0..<height {
        try Task.checkCancellation()
        for x in 0..<width {
          let offset = y * stride + x * (wide ? 2 : 1)
          let gray = wide
            ? Float(UInt16(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))) / 65_535
            : Float(buffer[offset]) / 255
          if gray > 0 { mask.setPixel(x: x, y: y, Pixel(gray, gray, gray)) }
        }
      }
    }
    return try RasterIO.oriented(mask, orientation: metadata[kCGImagePropertyOrientation] as? Int ?? 1)
  }
}
