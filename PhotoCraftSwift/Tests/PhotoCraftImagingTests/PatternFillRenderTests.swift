import CoreGraphics
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PatternFillRenderTests: XCTestCase {
  static var root: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
  }
  func fixture(_ depth: PixelDepth) throws -> CraftDocument {
    var doc = try CraftDocument(width: 80, height: 64, depth: depth)
    let pattern = try PatternPresets.make()[4]
    var fill = PatternFill(patternID: pattern.id)
    fill.placement.scale = 137
    fill.placement.angle = 17
    fill.placement.phaseX = 3.25
    fill.placement.phaseY = -2.5
    var layer = Layer(name: "Pattern Fill", content: .patternFill(fill))
    layer.mask = try Surface(width: 80, height: 64, depth: depth, fill: .white)
    layer.opacity = Float(179) / 255
    try Command.addPatternFill(layer, pattern).apply(to: &doc)
    return doc
  }
  func testEditablePatternPSDAtAllDepthsAndIndependentMergedPreview() throws {
    for depth in PixelDepth.allCases {
      let doc = try fixture(depth)
      let before = try Renderer.composite(doc)
      let data = try PSDCodec.writeRasterLayers(doc)
      let restored = try PSDCodec.read(data)
      XCTAssertEqual(restored.patterns, doc.patterns)
      XCTAssertEqual(restored.layers.last?.content, doc.layers.last?.content)
      let after = try Renderer.composite(restored)
      XCTAssertEqual(try before.rgbaData(depth: .f32), try after.rgbaData(depth: .f32))
      let image = try XCTUnwrap(
        CGImageSourceCreateImageAtIndex(
          XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil)), 0, nil))
      XCTAssertEqual(image.width, 80)
      let preview = try RasterIO.surface(image, depth: depth)
      XCTAssertEqual(preview.pixel(x: 20, y: 15).r, before.pixel(x: 20, y: 15).r, accuracy: 0.005)
      try data.write(
        to: Self.root.appendingPathComponent("artifacts/native-pattern-fill-\(depth.rawValue).psd"))
    }
  }
  func testPinnedPatternReferencesMeasurePixelAgreementAndIdentifyBlankMergedPreview() throws {
    var report: [[String: Any]] = []
    var renderedReferences: [Data] = []
    for name in ["reference-layers-minimal-pattern-fill", "reference-layers-pattern-fill"] {
      let url = try XCTUnwrap(
        Bundle.module.url(forResource: name, withExtension: "psd", subdirectory: "Fixtures"))
      let data = try Data(contentsOf: url)
      let doc = try PSDCodec.read(data)
      XCTAssertFalse((doc.patterns ?? []).isEmpty)
      XCTAssertTrue(
        doc.layers.contains {
          if case .patternFill = $0.content { return true }
          return false
        })
      let actual = try Renderer.composite(doc)
      let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
      let expected = try RasterIO.surface(
        XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)), depth: doc.depth)
      var maximum: Float = 0
      var changed = 0
      var nonzeroMergedPixels = 0
      for y in 0..<doc.height {
        for x in 0..<doc.width {
          let a = actual.pixel(x: x, y: y)
          let b = expected.pixel(x: x, y: y)
          maximum = max(maximum, abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b), abs(a.a - b.a))
          if a.quantized(doc.depth) != b.quantized(doc.depth) { changed += 1 }
          if b != .clear { nonzeroMergedPixels += 1 }
        }
      }
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(doc))
      for key in PSDPatterns.keys where doc.sourceMetadata?["psdGlobal_" + key] != nil {
        XCTAssertEqual(
          reopened.sourceMetadata?["psdGlobal_" + key], doc.sourceMetadata?["psdGlobal_" + key])
      }
      report.append([
        "name": name, "width": doc.width, "height": doc.height, "maximum_channel_error": maximum,
        "changed_pixels_at_document_depth": changed, "byte_identical_pixels": changed == 0,
        "embedded_patterns": doc.patterns?.count ?? 0,
        "merged_preview_nonzero_pixels": nonzeroMergedPixels,
        "usable_merged_pixel_reference": nonzeroMergedPixels > 0,
      ])
      renderedReferences.append(try actual.rgbaData(depth: .f32))
      print(
        "Pattern Fill saved reference \(name): \(changed) differing pixels; max error \(maximum)")
      if name == "reference-layers-pattern-fill" {
        XCTAssertEqual(changed, 0)
      } else {
        XCTAssertEqual(
          nonzeroMergedPixels, 0, "The minimal fixture deliberately has no usable merged preview.")
      }
    }
    XCTAssertEqual(
      renderedReferences[0], renderedReferences[1],
      "Both fixtures describe the same editable pattern content.")
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: Self.root.appendingPathComponent("artifacts/pattern-fill-reference.json"))
    let unsupported = try XCTUnwrap(
      Bundle.module.url(
        forResource: "reference-patterns", withExtension: "psd", subdirectory: "Fixtures"))
    XCTAssertThrowsError(try PSDCodec.read(Data(contentsOf: unsupported))) { error in
      XCTAssertTrue(error.localizedDescription.contains("vogk"), "\(error)")
    }
  }
  func testMaskedPatternRegionalRenderAndRegistryChangeInvalidatesCache() throws {
    for depth in PixelDepth.allCases {
      var doc = try fixture(depth)
      let first = try Renderer.render(doc)
      let index = doc.layers.count - 1
      doc.layers[index].mask?.setPixel(x: 12, y: 13, Pixel(0.25, 0.25, 0.25))
      let regional = try Renderer.render(doc, reusing: first)
      XCTAssertEqual(
        try regional.surface.rgbaData(depth: .f32),
        try Renderer.composite(doc).rgbaData(depth: .f32))
      guard case .region = regional.update else { return XCTFail("Expected regional mask update") }
      let prior = doc.patterns![0]
      var pixels = prior.surface
      pixels.setPixel(x: 0, y: 0, .black)
      doc.patterns![0] = try RasterPattern(name: prior.name, surface: pixels, id: prior.id)
      let changed = try Renderer.render(doc, reusing: regional)
      XCTAssertEqual(changed.update, .full)
      XCTAssertEqual(
        try changed.surface.rgbaData(depth: .f32), try Renderer.composite(doc).rgbaData(depth: .f32)
      )
    }
  }
  func testMaskedAndMovedPSDUsesRelativePhaseAndReopensAtSameDocumentPosition() throws {
    for linked in [true, false] {
      var doc = try fixture(.u8)
      let index = doc.layers.count - 1
      var fill = try XCTUnwrap(
        {
          if case .patternFill(let f) = doc.layers[index].content { return f }
          return nil
        }())
      fill.linked = linked
      doc.layers[index].content = .patternFill(fill)
      doc.layers[index].mask = try Surface(width: 14, height: 9, fill: .white)
      var properties = MaskProperties()
      properties.transform = .translation(11, 7)
      doc.layers[index].maskProperties = properties
      try Command.move(doc.layers[index].id, 3, 2).apply(to: &doc)
      let expected = try Renderer.composite(doc)
      let encoded = try PSDCodec.writeRasterLayers(doc)
      let reopened = try PSDCodec.read(encoded)
      XCTAssertEqual(
        try expected.rgbaData(depth: .f32), try Renderer.composite(reopened).rgbaData(depth: .f32))
      let descriptor = try PSDPatternFill.read(
        XCTUnwrap(reopened.layers[index].sourceTags?["PtFl"]))
      XCTAssertEqual(descriptor.fill.placement.phaseX, linked ? 3.25 + 3 - 14 : 3.25)
      XCTAssertEqual(descriptor.fill.placement.phaseY, linked ? -2.5 + 2 - 9 : -2.5)
      XCTAssertEqual(
        try PSDPatternFill.exportPlacement(
          reopened.layers[index], width: doc.width, height: doc.height), descriptor.fill)
    }
  }
  func testFillFrameFollowsEnabledMasksControlBoundsAndCanvasIntersection() throws {
    var layer = Layer(name: "Pattern", content: .patternFill(PatternFill(patternID: "test")))
    var mask = try Surface(width: 30, height: 20, fill: .black)
    for y in 3..<15 { for x in 4..<20 { mask.setPixel(x: x, y: y, .white) } }
    layer.mask = mask
    var properties = MaskProperties()
    properties.transform = .translation(-2, 5)
    layer.maskProperties = properties
    var origin = try PSDPatternFill.frameOrigin(layer, width: 32, height: 24)
    XCTAssertEqual(origin.x, 2)
    XCTAssertEqual(origin.y, 8)
    layer.vectorMask = VectorMask(
      path: VectorPath(components: [
        PathComponent(
          knots: [
            PathKnot(.init(6.5, 10.5)), PathKnot(.init(18.5, 10.5)), PathKnot(.init(18.5, 21.5)),
          ], closed: true)
      ]))
    origin = try PSDPatternFill.frameOrigin(layer, width: 32, height: 24)
    XCTAssertEqual(origin.x, 6)
    XCTAssertEqual(origin.y, 10)
    layer.vectorMask?.path.inverted = true
    layer.maskProperties?.enabled = false
    origin = try PSDPatternFill.frameOrigin(layer, width: 32, height: 24)
    XCTAssertEqual(origin.x, 0)
    XCTAssertEqual(origin.y, 0)
  }
  func testInvalidPatternDescriptorAndEmbeddedTileBudgetRejectBeforeImport() throws {
    let pattern = try PatternPresets.make()[4]
    let valid = try PSDPatternFill.write(PatternFill(patternID: pattern.id), pattern: pattern)
    var descriptor = try PSDDescriptor.read(valid)
    descriptor.items.append(.init("unknown", .number(1)))
    XCTAssertThrowsError(try PSDPatternFill.read(descriptor.encoded()))
    descriptor = try PSDDescriptor.read(valid)
    descriptor.items.append(descriptor.items[0])
    XCTAssertThrowsError(try PSDPatternFill.read(descriptor.encoded()))
    for count in stride(from: 0, to: valid.count, by: 11) {
      XCTAssertThrowsError(try PSDPatternFill.read(valid.prefix(count)))
    }
    let block = try PSDPatterns.write([pattern])
    XCTAssertThrowsError(try PSDPatterns.read(block, tileBudget: 1))
    for count in stride(from: 5, to: block.count - 3, by: 97) {
      XCTAssertThrowsError(try PSDPatterns.read(block.prefix(count)))
    }
    var reflected = PatternFill(patternID: pattern.id)
    reflected.geometry = .scale(-1, 1)
    XCTAssertThrowsError(try PSDPatternFill.write(reflected, pattern: pattern))
  }
  func testRasterizingMovedCanvasFillsPreservesMaskCoordinatesAndPixels() throws {
    for isPattern in [true, false] {
      var doc = try fixture(.u8)
      let index = doc.layers.count - 1
      if !isPattern { doc.layers[index].content = .fill(Pixel(0.37, 0.64, 0.19)) }
      doc.layers[index].mask = try Surface(width: 30, height: 24, fill: .white)
      try Command.move(doc.layers[index].id, 11, 7).apply(to: &doc)
      let before = try Renderer.composite(doc)
      let maskTransform = doc.layers[index].maskCoordinateTransform
      let pixels = try Renderer.layerSurface(doc.layers[index], in: doc)
      try Command.rasterize(doc.layers[index].id, pixels).apply(to: &doc)
      XCTAssertEqual(doc.layers[index].coordinateTransform, .identity)
      XCTAssertEqual(doc.layers[index].maskCoordinateTransform, maskTransform)
      let after = try Renderer.composite(doc)
      // Rasterization commits interpolation to the document's integer depth.
      for y in 0..<doc.height {
        for x in 0..<doc.width {
          XCTAssertEqual(before.pixel(x: x, y: y).a, after.pixel(x: x, y: y).a, accuracy: 1 / 255)
          XCTAssertEqual(before.pixel(x: x, y: y).r, after.pixel(x: x, y: y).r, accuracy: 1 / 255)
        }
      }
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(doc))
      XCTAssertNil(reopened.layers[index].sourceTags?["PtFl"])
      guard case .raster = reopened.layers[index].content else {
        return XCTFail("Expected rasterized layer")
      }
    }
  }
  func testPatternInMaskedGroupsAndClippingMatchesFullPrecisionRasterReference() throws {
    for depth in PixelDepth.allCases {
      for passThrough in [true, false] {
        var doc = try fixture(depth)
        let patternIndex = doc.layers.count - 1
        let id = doc.layers[patternIndex].id
        let base = Layer(
          name: "Base",
          content: .raster(
            try Surface(width: 80, height: 64, depth: depth, fill: Pixel(0.2, 0.4, 0.7, 0.4))))
        doc.layers.insert(base, at: 1)
        try Command.groupLayers([base.id, id], "Pattern group").apply(to: &doc)
        let groupIndex = try XCTUnwrap(doc.layers.firstIndex { $0.isGroup })
        doc.layers[groupIndex].content = .group(GroupContent(passThrough: passThrough))
        doc.layers[groupIndex].opacity = 0.6
        doc.layers[groupIndex].mask = try Surface(
          width: 80, height: 64, depth: depth, fill: Pixel(0.7, 0.7, 0.7))
        let fillIndex = try XCTUnwrap(doc.layers.firstIndex { $0.id == id })
        doc.layers[fillIndex].blendMode = .screen
        doc.layers[fillIndex].clipped = true
        let actual = try Renderer.composite(doc)
        var reference = doc
        reference.layers[fillIndex].content = .raster(
          try Renderer.layerSurface(doc.layers[fillIndex], in: doc))
        XCTAssertEqual(
          try actual.rgbaData(depth: .f32), try Renderer.composite(reference).rgbaData(depth: .f32))
      }
    }
  }
  func testWholeCanvasRotationAndReflectionKeepUnlinkedPatternPixelsAttachedToImage() throws {
    for turn in [CanvasTurn.clockwise, .horizontal] {
      var doc = try CraftDocument(width: 9, height: 7)
      let preset = try PatternPresets.make()[4]
      let layer = Layer(
        name: "Pattern", content: .patternFill(PatternFill(patternID: preset.id, linked: false)))
      try Command.addPatternFill(layer, preset).apply(to: &doc)
      let before = try Renderer.composite(doc)
      try Command.rotateCanvas(turn).apply(to: &doc)
      let after = try Renderer.composite(doc)
      for y in 0..<after.height {
        for x in 0..<after.width {
          let expected =
            turn == .clockwise ? before.pixel(x: y, y: 6 - x) : before.pixel(x: 8 - x, y: y)
          XCTAssertEqual(after.pixel(x: x, y: y), expected)
        }
      }
    }
  }
}
