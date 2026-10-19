import CoreGraphics
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class GradientFillRenderTests: XCTestCase {
  static var root: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
  }
  func fixture(_ depth: PixelDepth, aligned: Bool = true) throws -> CraftDocument {
    var doc = try CraftDocument(width: 128, height: 96, depth: depth)
    var fill = GradientFill(
      gradient: GradientDefinition(
        name: "Editable",
        colors: [
          .init(0, .rgb(.black)), .init(0.5, .rgb(Pixel(0.25, 0.5, 0.75)), midpoint: 0.3),
          .init(1, .rgb(.white), midpoint: 0.7),
        ], opacity: [.init(0, 0.2), .init(1, 1, midpoint: 0.4)], smoothness: 0.75, method: .classic),
      aligned: aligned)
    fill.placement.angle = 30
    fill.placement.scale = 0.75
    fill.placement.offsetX = 0.125
    var layer = Layer(name: "Gradient", content: .gradientFill(fill))
    layer.mask = try Surface(width: 80, height: 60, depth: depth, fill: .white)
    var mask = MaskProperties()
    mask.outside = 0
    mask.transform = .translation(12, 18)
    layer.maskProperties = mask
    try Command.addGradientFill(layer).apply(to: &doc)
    return doc
  }
  func testEditablePSDAtAllDepthsStylesMethodsAndIndependentMergedDecode() throws {
    for depth in PixelDepth.allCases {
      for style in GradientStyle.allCases {
        for method in GradientMethod.allCases {
          var doc = try fixture(depth)
          guard case .gradientFill(var fill) = doc.layers[1].content else { return XCTFail() }
          fill.gradient.method = method
          fill.placement.style = style
          doc.layers[1].content = .gradientFill(fill)
          let bytes = try PSDCodec.writeRasterLayers(doc)
          let restored = try PSDCodec.read(bytes)
          XCTAssertEqual(restored.layers[1].content, doc.layers[1].content)
          let before = try Renderer.composite(doc)
          let after = try Renderer.composite(restored)
          XCTAssertEqual(try before.rgbaData(depth: .f32), try after.rgbaData(depth: .f32))
          XCTAssertEqual(
            try PSDGradientFill.write(fill, original: restored.layers[1].sourceTags?["GdFl"]),
            restored.layers[1].sourceTags?["GdFl"])
          let image = try XCTUnwrap(
            CGImageSourceCreateImageAtIndex(
              XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil)), 0, nil))
          XCTAssertEqual(image.width, 128)
          let preview = try RasterIO.surface(image, depth: depth)
          XCTAssertEqual(
            preview.pixel(x: 43, y: 39).r, before.pixel(x: 43, y: 39).r, accuracy: 0.008)
          if style == .linear && method == .classic {
            try bytes.write(
              to: Self.root.appendingPathComponent(
                "artifacts/native-gradient-fill-\(depth.rawValue).psd"))
          }
        }
      }
    }
  }
  func testMaskFrameChangesInvalidateEntireFillWhileInteriorEditsStayRegional() throws {
    for aligned in [true, false] {
      var doc = try fixture(.f32, aligned: aligned)
      let first = try Renderer.render(doc)
      // Shrink the left edge, moving the reference center and changing colors elsewhere.
      for y in 0..<60 { doc.layers[1].mask?.setPixel(x: 0, y: y, .black) }
      let changed = try Renderer.render(doc, reusing: first)
      if aligned {
        XCTAssertEqual(changed.update, .full)
      } else {
        guard case .region = changed.update else {
          return XCTFail("Unaligned mask changes remain local")
        }
      }
      XCTAssertEqual(
        try changed.surface.rgbaData(depth: .f32), try Renderer.composite(doc).rgbaData(depth: .f32)
      )
      doc.layers[1].mask?.setPixel(x: 40, y: 30, Pixel(0.25, 0.25, 0.25))
      let interior = try Renderer.render(doc, reusing: changed)
      guard case .region = interior.update else {
        return XCTFail("Interior edit should reuse other pixels")
      }
      XCTAssertEqual(
        try interior.surface.rgbaData(depth: .f32),
        try Renderer.composite(doc).rgbaData(depth: .f32))
    }
  }
  func testCanvasCoverageGroupClippingPickingAndClipboard() throws {
    var doc = try fixture(.u16)
    let id = doc.layers[1].id
    doc.layers[1].x = 5
    doc.layers[1].y = 3
    guard case .gradientFill(let fill) = doc.layers[1].content else { return XCTFail() }
    let pixels = try Renderer.layerSurface(doc.layers[1], in: doc)
    let expected = try GradientRasterizer.render(
      fill.gradient, placement: fill.placement,
      frame: fill.frame(for: doc.layers[1], width: doc.width, height: doc.height),
      region: .init(x: 0, y: 0, width: doc.width, height: doc.height), dither: fill.dither)
    XCTAssertEqual(pixels, expected)
    for y in stride(from: 0, to: doc.height, by: 7) {
      for x in stride(from: 0, to: doc.width, by: 5) {
        XCTAssertEqual(
          try Renderer.gradientPixel(doc.layers[1], in: doc, x: x, y: y), pixels.pixel(x: x, y: y))
      }
    }
    let sample = try Renderer.cloneSample(in: doc, layerID: id, sampling: .current)
    XCTAssertEqual(sample.transform, .identity)
    XCTAssertEqual(sample.surface, pixels)
    let clipboard = try ClipboardRenderer.copy(doc, layerIDs: [id], merged: false)
    XCTAssertEqual(clipboard.bounds, .init(x: 0, y: 0, width: 128, height: 96))
    XCTAssertEqual(clipboard.document.layers[0].content, doc.layers[1].content)
    let original = try Renderer.composite(doc)
    try Command.groupLayers(doc.layers.map(\.id), "Group").apply(to: &doc)
    XCTAssertEqual(
      try Renderer.composite(doc).rgbaData(depth: .f32), try original.rgbaData(depth: .f32))
    try Command.clipping(id, true).apply(to: &doc)
    XCTAssertEqual(
      try Renderer.composite(doc).rgbaData(depth: .f32), try original.rgbaData(depth: .f32))
    let before = try Renderer.render(doc)
    let index = try XCTUnwrap(doc.layers.firstIndex { $0.id == id })
    doc.layers[index].mask?.setPixel(x: 15, y: 15, .black)
    XCTAssertEqual(
      try Renderer.render(doc, reusing: before).surface.rgbaData(depth: .f32),
      try Renderer.composite(doc).rgbaData(depth: .f32))
  }
  func testDescriptorBoundsUnsupportedSettingsAndRasterizationDropsStaleTag() throws {
    let doc = try fixture(.u8)
    guard case .gradientFill(let fill) = doc.layers[1].content else { return XCTFail() }
    let bytes = try PSDGradientFill.write(fill)
    for i in 0..<bytes.count {
      XCTAssertThrowsError(try PSDGradientFill.read(Data(bytes.prefix(i))))
    }
    var d = try PSDDescriptor.read(bytes)
    PSDGradient.set(&d, "Type", .enumerated(PSDID("GrdT"), PSDID("unknown")))
    XCTAssertThrowsError(try PSDGradientFill.read(d.encoded()))
    d = try PSDDescriptor.read(bytes)
    PSDGradient.set(&d, "Dthr", .integer(1))
    XCTAssertThrowsError(try PSDGradientFill.read(d.encoded()))
    d = try PSDDescriptor.read(bytes)
    PSDGradient.set(&d, "Scl ", .unit(Data("#Ang".utf8), Double(100).bitPattern))
    XCTAssertThrowsError(try PSDGradientFill.read(d.encoded()))
    d = try PSDDescriptor.read(bytes)
    d.items.append(d.items[0])
    XCTAssertThrowsError(try PSDGradientFill.read(d.encoded()))
    var reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(doc))
    let layer = reopened.layers[1]
    try Command.rasterize(layer.id, Renderer.layerSurface(layer, in: reopened)).apply(to: &reopened)
    let rasterized = try PSDCodec.read(PSDCodec.writeRasterLayers(reopened))
    XCTAssertNil(rasterized.layers[1].sourceTags?["GdFl"])
    guard case .raster = rasterized.layers[1].content else {
      return XCTFail("Gradient tag survived rasterization")
    }
  }
  func storedMerged(_ data: Data) throws -> Surface {
    var reader = PSDReader(data: data)
    _ = try reader.bytes(12)
    let channels = try reader.u16()
    let height = try reader.u32()
    let width = try reader.u32()
    let depth = try reader.u16()
    XCTAssertEqual(depth, 8)
    _ = try reader.u16()
    for _ in 0..<3 { _ = try reader.section() }
    let bytes = try PSDChannelCodec.decode(
      reader.bytes(reader.remaining), width: width, height: height, depth: depth, channels: channels
    )
    var result = try Surface(width: width, height: height)
    let n = width * height
    for y in 0..<height {
      for x in 0..<width {
        let i = y * width + x
        result.setPixel(
          x: x, y: y,
          try Pixel(
            PSDChannelCodec.sample(bytes, i, depth: depth),
            PSDChannelCodec.sample(bytes, n + i, depth: depth),
            PSDChannelCodec.sample(bytes, 2 * n + i, depth: depth),
            channels == 4 ? PSDChannelCodec.sample(bytes, 3 * n + i, depth: depth) : 1))
      }
    }
    return result
  }
  func testPinnedSavedReferencesRecordActualPixelDifferences() throws {
    var report: [[String: Any]] = []
    var referencePixels: [Data] = []
    for name in [
      "reference-gradient-fill", "reference-gradient-sizes", "reference-gradient-styles",
      "reference-layers-gradient-fill", "reference-layers-minimal-gradient-fill",
    ] {
      let url = try XCTUnwrap(
        Bundle.module.url(forResource: name, withExtension: "psd", subdirectory: "Fixtures"))
      let data = try Data(contentsOf: url)
      var row: [String: Any] = ["name": name]
      do {
        let doc = try PSDCodec.read(data)
        XCTAssertTrue(
          name.hasPrefix("reference-layers"),
          "Unexpectedly supported reference: qualify its behavior explicitly")
        let actual = try Renderer.composite(doc)
        let expected = try storedMerged(data)
        var changed = 0
        var visible = 0
        var maximum: Float = 0
        for y in 0..<doc.height {
          for x in 0..<doc.width {
            let a = PSDMergedSample.encode(actual.pixel(x: x, y: y), depth: 8).quantized(.u8)
            let b = expected.pixel(x: x, y: y)
            if a != b { changed += 1 }
            if b.a > 0 { visible += 1 }
            maximum = max(maximum, abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b), abs(a.a - b.a))
          }
        }
        referencePixels.append(try actual.rgbaData(depth: .f32))
        if name == "reference-layers-gradient-fill" {
          XCTAssertEqual(changed, 0)
          XCTAssertEqual(try storedMerged(PSDCodec.writeRasterLayers(doc)), expected)
        } else {
          XCTAssertEqual(changed, 1024)
          for y in 0..<32 { for x in 0..<32 { XCTAssertEqual(expected.pixel(x: x, y: y), .white) } }
        }
        let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(doc))
        XCTAssertEqual(
          try Renderer.composite(reopened).rgbaData(depth: .f32), try actual.rgbaData(depth: .f32))
        for (a, b) in zip(doc.layers, reopened.layers) {
          XCTAssertEqual(a.sourceTags?["GdFl"], b.sourceTags?["GdFl"])
        }
        row.merge([
          "imported": true, "width": doc.width, "height": doc.height, "changed_pixels": changed,
          "maximum_channel_error": maximum, "visible_reference_pixels": visible,
          "usable_merged_pixel_reference": name == "reference-layers-gradient-fill",
          "byte_identical": changed == 0,
        ]) { _, v in v }
      } catch {
        let expectedError = name == "reference-gradient-fill" ? "sRGB document profile" : "artd"
        XCTAssertFalse(name.hasPrefix("reference-layers"), "Supported fixture failed: \(error)")
        XCTAssertTrue(
          error.localizedDescription.contains(expectedError), "Unexpected rejection: \(error)")
        row["imported"] = false
        row["error"] = error.localizedDescription
      }
      print("Gradient saved reference: \(row)")
      report.append(row)
    }
    XCTAssertEqual(referencePixels.count, 2)
    if referencePixels.count == 2 { XCTAssertEqual(referencePixels[0], referencePixels[1]) }
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: Self.root.appendingPathComponent("artifacts/gradient-fill-reference.json"))
  }
}
