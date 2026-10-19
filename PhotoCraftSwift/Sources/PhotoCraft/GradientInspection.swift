import CoreGraphics
import CoreText
import CryptoKit
import Foundation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

extension Benchmark {
  static func gradientAtlas(to output: URL) throws {
    let width = 1100
    let height = 680
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
      throw CraftError.invalid("Cannot create gradient atlas.")
    }
    context.setFillColor(CGColor(gray: 0.08, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat) {
      let string = NSAttributedString(
        string: text,
        attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
            "Helvetica" as CFString, size, nil),
          NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
            gray: 0.92, alpha: 1),
        ])
      context.textPosition = CGPoint(x: x, y: y)
      CTLineDraw(CTLineCreateWithAttributedString(string), context)
    }
    label("Photato • Native gradient renderer", x: 24, y: 640, size: 24)
    label(
      "Retained color stops • 100% smoothness • 35° • 80% scale • no dither", x: 24, y: 612,
      size: 14)
    let frame = IntRect(x: 0, y: 0, width: 196, height: 138)
    for (row, method) in [GradientMethod.classic, .linear, .perceptual].enumerated() {
      let top = 578 - row * 188
      label(method.rawValue, x: 24, y: CGFloat(top), size: 16)
      for (column, style) in GradientStyle.allCases.enumerated() {
        var placement = GradientPlacement()
        placement.style = style
        placement.angle = 35
        placement.scale = 0.8
        let gradient = GradientDefinition(
          colors: [
            .init(0, .rgb(Pixel(0.04, 0.19, 0.75))),
            .init(0.45, .rgb(Pixel(0.95, 0.2, 0.42))), .init(1, .rgb(Pixel(1, 0.82, 0.12))),
          ], method: method)
        let surface = try GradientRasterizer.render(
          gradient, placement: placement, frame: frame, depth: .u8)
        let x = 24 + column * 214
        context.draw(
          try RasterIO.cgImage(surface), in: CGRect(x: x, y: top - 148, width: 196, height: 138))
        label(style.rawValue, x: CGFloat(x), y: CGFloat(top - 168), size: 12)
      }
    }
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        output as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CraftError.invalid("Cannot save gradient atlas.") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw CraftError.invalid("Cannot finish gradient atlas.")
    }
  }
  static func inspectGradients(at url: URL, to output: URL) throws {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    let library = try GRDCodec.read(data)
    guard try GRDCodec.write(library) == data else {
      throw CraftError.invalid("GRD byte preservation failed.")
    }
    let supported = library.presets.compactMap(\.gradient)
    var exactSamples = 0
    if !supported.isEmpty {
      let rebuilt = try GRDCodec.read(GRDCodec.write(GRDLibrary(supported)))
      guard rebuilt.presets.count == supported.count else {
        throw CraftError.invalid("GRD preset count changed.")
      }
      for (original, preset) in zip(supported, rebuilt.presets) {
        guard let roundTrip = preset.gradient else {
          throw CraftError.invalid("GRD native export cannot be read.")
        }
        let a = try GradientRamp(original)
        let b = try GradientRamp(roundTrip)
        for i in 0...256 {
          guard a.sample(Float(i) / 256).hasSameBits(as: b.sample(Float(i) / 256)) else {
            throw CraftError.invalid(
              "GRD rendered round trip changed preset \(original.name), sample \(i).")
          }
          exactSamples += 1
        }
      }
    }
    func folders(_ nodes: [GRDPresetNode]) -> Int {
      nodes.reduce(0) { count, node in
        if case .group(_, let children) = node { return count + 1 + folders(children) }
        return count
      }
    }
    let report: [String: Any] = [
      "folder_count": folders(library.hierarchy),
      "path": url.path, "bytes": data.count,
      "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
      "preset_count": library.presets.count, "renderable_presets": supported.count,
      "unavailable_presets": library.presets.filter { $0.gradient == nil }.map {
        ["name": $0.name, "reason": $0.unavailableReason ?? "Unknown"]
      },
      "unchanged_export_byte_identical": true, "rebuilt_export_exact_rgba_samples": exactSamples,
      "scope":
        "Read-only installed preset inspection. Native rebuilt GRD ramps are compared at 257 locations per supported preset. Unavailable entries retain their original descriptors. No Adobe presets are copied into the app or test resources. Live Photoshop rendering/import remains unverified.",
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: output)
  }
}
