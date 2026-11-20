import Foundation
import UniformTypeIdentifiers
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class InkModeInputTests: XCTestCase {
  func source(_ mode: DocumentColorMode, depth: PixelDepth = .u8, transparent: Bool = false) throws -> CraftDocument {
    var raster = try NativeModeRaster(width: 3, height: 1, mode: mode, depth: depth)
    for i in 0..<3 {
      for c in 0..<mode.componentCount { try raster.set(Float((i * 29 + c * 73) % 256) / 255, component: c, index: i) }
      try raster.set(transparent && i == 1 ? 0 : 1, component: mode.componentCount, index: i)
    }
    var document = try CraftDocument(width: 3, height: 1, depth: depth)
    document.modeDescriptor = try .init(mode: mode, depth: depth, profile: raster.profile)
    document.layers[0].nativeMode = raster; document.layers[0].content = .raster(try raster.surface())
    try document.validate(); return document
  }
  func testConversionsKeepEveryNativeComponentSampleIncludingCMYKBlack() throws {
    for mode in DocumentColorMode.componentModes { for depth in [PixelDepth.u8, .u16] {
      let original = try source(mode, depth: depth), before = try XCTUnwrap(original.layers[0].nativeMode)
      var session = EditorSession(document: original)
      try session.execute(InkModeInput.multichannel(in: original))
      guard case .multichannel(let converted) = session.document.inkMode else { return XCTFail() }
      XCTAssertTrue(session.document.layers.isEmpty); XCTAssertEqual(converted.plates.count, mode.componentCount)
      for (c, plate) in converted.plates.enumerated() {
        let raw = try InkPlane(width: 3, height: 1, depth: depth, bytes: try before.planes[c])
        XCTAssertEqual(try plate.samples.bytes, try raw.converted(to: depth, inverted: mode != .cmyk).bytes)
      }
      let restored = try session.document.convertingMode(.init(mode: mode, depth: depth))
      XCTAssertEqual(try restored.layers[0].nativeMode?.planes, try before.planes, "Round-trip component bytes must stay exact")
      try session.undo(); XCTAssertTrue(session.document == original)
    } }
  }
  func testLayeredCMYKAndLabRetainEveryNumericSeparationAndIgnoreHiddenArtwork() throws {
    for mode in [DocumentColorMode.cmyk, .lab] {
      for depth in [PixelDepth.u8, .u16] {
        var document = try source(mode, depth: depth)
        let bottom = try XCTUnwrap(document.layers[0].nativeMode)
        let maximum = depth == .u8 ? 255 : 65535
        let opacity = [maximum / 4, maximum, 0]
        let topWords = [11, 143, 209, 24].map { $0 * (maximum / 255) }
        var top = try NativeModeRaster(width: 3, height: 1, mode: mode, depth: depth, profile: bottom.profile)
        for pixel in 0..<3 {
          for index in 0..<mode.componentCount {
            try top.set(Float(topWords[index]) / Float(maximum), component: index, index: pixel)
          }
          try top.set(Float(opacity[pixel]) / Float(maximum), component: mode.componentCount, index: pixel)
        }
        var layer = Layer(name: "Partial coverage", content: .raster(try top.surface()))
        layer.nativeMode = top
        document.layers.append(layer)
        var hidden = Layer(name: "Hidden green fill", content: .fill(Pixel(0, 1, 0)))
        hidden.visible = false
        document.layers.append(hidden)
        document.activeLayerID = hidden.id

        var request = InkModeRequest(.multichannel, document: document)
        XCTAssertThrowsError(try request.command(in: document))
        request.mergeVisible = true
        var session = EditorSession(document: document)
        try session.execute(request.command(in: document))
        let plates = try session.document.multichannelRaster().plates
        XCTAssertEqual(plates.map(\.id), request.plateIDs)
        XCTAssertEqual(plates.count, mode.componentCount)
        XCTAssertTrue(session.document.layers.isEmpty)
        for component in plates.indices {
          for pixel in 0..<3 {
            let original = Int(bottom.rawWord(component: component, index: pixel))
            let numerator = original * (maximum - opacity[pixel]) + topWords[component] * opacity[pixel]
            let mixed = (numerator + maximum / 2) / maximum
            let expected = UInt32(mode == .cmyk ? mixed : maximum - mixed)
            XCTAssertEqual(plates[component].samples.rawWord(at: pixel), expected,
              "\(mode) \(depth), component \(component), sample \(pixel)")
          }
        }
        let deletion = ProcessChannelDeletion(mode: mode, components: [0], mergeVisible: true)
        var remaining = document
        try InkModeInput.deleteProcess(deletion, in: document).apply(to: &remaining)
        XCTAssertEqual(try remaining.multichannelRaster().plates.map(\.samples), Array(plates.dropFirst()).map(\.samples))
        try session.undo()
        XCTAssertEqual(session.document, document)
      }
    }
  }

  func testMaximumSparseLayeredCMYKRetainsFourPlatesAndDistantEdits() throws {
    let side = 300_000
    let baseWords: [UInt32] = [1400, 15300, 30000, 53000]
    let topWords: [UInt32] = [62000, 11200, 37000, 17100]
    let builder = try NativeModeRaster.RowBuilder(width: side, height: side, mode: .cmyk, depth: .u16)
    for index in baseWords.indices { try builder.fill(component: index, word: baseWords[index]) }
    try builder.fill(component: 4, word: 65535)
    let bottom = try builder.finish()
    let local = try NativeModeRaster.RowBuilder(width: 2, height: 1, mode: .cmyk, depth: .u16, profile: bottom.profile)
    for index in topWords.indices { try local.fill(component: index, word: topWords[index]) }
    try local.fill(component: 4, word: 65535)
    let top = try local.finish()
    var document = try CraftDocument(width: side, height: side, depth: .u16)
    document.modeDescriptor = try .init(mode: .cmyk, depth: .u16, profile: bottom.profile)
    document.layers[0].nativeMode = bottom; document.layers[0].content = .raster(try bottom.surface())
    var patch = Layer(name: "Far corner", content: .raster(try top.surface()))
    patch.nativeMode = top; patch.x = side - 2; patch.y = side - 1
    document.layers.append(patch)

    var converted = document
    try InkModeInput.multichannel(in: document, mergeVisible: true).apply(to: &converted)
    let plates = try converted.multichannelRaster().plates
    XCTAssertEqual(plates.map { $0.samples.rawWord(at: 0) }, baseWords)
    XCTAssertEqual(plates.map { $0.samples.rawWord(at: side * side - 3) }, baseWords)
    XCTAssertEqual(plates.map { $0.samples.rawWord(at: side * side - 1) }, topWords)
    let archive = try NativeArchive.encodeChunked(converted)
    XCTAssertLessThan(archive.count, 1_000_000)
    XCTAssertEqual(try NativeArchive.decodePaged(archive), converted)
  }

  func testDuotoneUsesRawGrayAndConvertsCurvesToSeparateInks() throws {
    let original = try source(.grayscale), native = try XCTUnwrap(original.layers[0].nativeMode)
    let settings = DuotoneSettings(inks: [.init(name: "Cyan", color: Pixel(0, 1, 1)),
      .init(name: "Warm", color: Pixel(1, 0.3, 0.1), curve: [.init(0, 0), .init(1, 0.5)])],
      overprints: [.init(mask: 3, color: Pixel(0.8, 0.6, 0.4))])
    var session = EditorSession(document: original)
    try session.execute(InkModeInput.duotone(settings, in: original))
    let duo = session.document
    guard case .duotone(let raster) = duo.inkMode else { return XCTFail() }
    XCTAssertEqual(try raster.gray.bytes, try native.planes[0])
    XCTAssertEqual(try Renderer.composite(duo).pixel(x: 0, y: 0), try duo.inkMode?.surface().pixel(x: 0, y: 0))
    try session.execute(InkModeInput.multichannel(in: duo))
    guard case .multichannel(let plates) = session.document.inkMode else { return XCTFail() }
    XCTAssertEqual(plates, try raster.separations())
    XCTAssertEqual(plates.plates.map(\.id), settings.inks.map(\.id))
    try session.undo(); XCTAssertTrue(session.document == duo)
    try session.undo(); XCTAssertTrue(session.document == original)
  }
  func testMergeConsentTransparencyAndAuxiliaryChannelsSurviveHistory() throws {
    var original = try source(.cmyk, depth: .u16, transparent: true)
    original.alphaChannels = [.init(name: "Saved selection", pixels: try Surface(width: 3, height: 1, depth: .u16, fill: .black))]
    var session = EditorSession(document: original)
    try session.execute(InkModeInput.multichannel(in: original))
    guard case .multichannel(let ink) = session.document.inkMode else { return XCTFail() }
    for plate in ink.plates { XCTAssertEqual(plate.samples.value(at: 1), 0, accuracy: 1 / 65535, "Transparent pixels become paper") }
    XCTAssertEqual(session.document.alphaChannels, original.alphaChannels)
    var hidden = Layer(name: "Hidden original", content: .fill(.black)); hidden.visible = false
    original.layers.append(hidden); try original.validate()
    XCTAssertTrue(InkModeInput.needsMerge(original))
    XCTAssertThrowsError(try InkModeInput.multichannel(in: original))
    var merged = EditorSession(document: original)
    try merged.execute(InkModeInput.multichannel(in: original, mergeVisible: true))
    XCTAssertEqual(merged.document.alphaChannels, original.alphaChannels)
    try merged.undo(); XCTAssertTrue(merged.document == original)
  }
  func testModePrerequisitesAndBoundsRejectBeforePreparingAnEdit() throws {
    let rgb = try source(.rgb), gray16 = try source(.grayscale, depth: .u16)
    XCTAssertThrowsError(try InkModeInput.duotone(.init(), in: rgb))
    XCTAssertThrowsError(try InkModeInput.duotone(.init(), in: gray16))
    let hdr = try source(.rgb, depth: .f32)
    XCTAssertThrowsError(try InkModeInput.multichannel(in: hdr))
    let bitmap = try CraftDocument(width: 3, height: 1).replacingRestrictedMode(.bitmap(.init(width: 3, height: 1, bits: Data([0]))))
    XCTAssertThrowsError(try InkModeInput.multichannel(in: bitmap))
    let indexed = try CraftDocument(width: 3, height: 1).replacingRestrictedMode(.indexed(.init(width: 3, height: 1, palette: [.init(0, 0, 0)], indices: Data([0, 0, 0]))))
    XCTAssertThrowsError(try InkModeInput.multichannel(in: indexed))
  }
  private func sparseSource(width: Int, height: Int, mode: DocumentColorMode, depth: PixelDepth,
    transparent: Bool = false) throws -> (CraftDocument, NativeModeRaster) {
    let builder = try NativeModeRaster.RowBuilder(width: width, height: height, mode: mode, depth: depth)
    let max: UInt32 = depth == .u8 ? 255 : 65535
    for c in 0..<mode.componentCount { try builder.fill(component: c, word: UInt32(11 + c * 31)) }
    try builder.fill(component: mode.componentCount, word: transparent ? max / 2 : max)
    var native = try builder.finish()
    for c in 0..<mode.componentCount {
      try native.set(Float(c + 1) / Float(max), component: c, index: 0)
      try native.set(Float(max - UInt32(c + 1)) / Float(max), component: c, index: width * height - 1)
    }
    if transparent {
      try native.set(0, component: mode.componentCount, index: 0)
      try native.set(1, component: mode.componentCount, index: width * height - 1)
    }
    var source = try CraftDocument(width: width, height: height, depth: depth)
    source.modeDescriptor = try .init(mode: mode, depth: depth, profile: native.profile)
    source.layers[0].nativeMode = native
    source.layers[0].content = .raster(try native.surface())
    return (source, native)
  }
  func testMaximumOpaqueProcessPlanesKeepWordsAtBothDepthsAndRoundTrip() throws {
    let side = 300_000
    for mode in DocumentColorMode.componentModes {
      for depth in [PixelDepth.u8, .u16] {
        var (original, native) = try sparseSource(width: side, height: side, mode: mode, depth: depth)
        original.alphaChannels = [AlphaChannel(name: "Saved mask",
          pixels: try Surface(width: side, height: side, depth: depth, fill: .white))]
        var session = EditorSession(document: original)
        try session.execute(InkModeRequest(.multichannel, document: original).command(in: original))
        let converted = session.document
        let plates = try converted.multichannelRaster().plates
        let max: UInt32 = depth == .u8 ? 255 : 65535
        XCTAssertEqual(converted.minimumArchiveVersion, 93)
        XCTAssertEqual(converted.alphaChannels, original.alphaChannels)
        for (c, plate) in plates.enumerated() {
          for index in [0, side, side * side - 1] {
            let word = native.rawWord(component: c, index: index)
            XCTAssertEqual(plate.samples.rawWord(at: index), mode == .cmyk ? word : max - word)
          }
          XCTAssertLessThan(plate.samples.estimatedBytes, 32 * 1024)
        }
        let reopened = try NativeArchive.decode(NativeArchive.encode(converted))
        XCTAssertEqual(reopened, converted)
        let restored = try reopened.convertingMode(.init(mode: mode, depth: depth, profile: native.profile))
        XCTAssertEqual(restored.layers[0].nativeMode, native, mode.rawValue)
        try session.undo()
        XCTAssertEqual(session.document, original)
      }
    }
  }
  func testPagedTransparencyAndSingleVisiblePlaneMatchDenseConversion() throws {
    let side = 300_000
    for mode in DocumentColorMode.componentModes {
      let (small, _) = try sparseSource(width: 3, height: 1, mode: mode, depth: .u16, transparent: true)
      var expected = small
      try InkModeInput.multichannel(in: small).apply(to: &expected)
      var (large, _) = try sparseSource(width: side, height: side, mode: mode, depth: .u16, transparent: true)
      var hidden = Layer(name: "Retained by Undo", content: .fill(.white))
      hidden.visible = false
      large.layers.append(hidden)
      XCTAssertThrowsError(try InkModeInput.multichannel(in: large))
      var session = EditorSession(document: large)
      try session.execute(InkModeInput.multichannel(in: large, mergeVisible: true))
      for (a, b) in zip(try session.document.multichannelRaster().plates, try expected.multichannelRaster().plates) {
        for (index, reference) in [0, 1, side * side - 1].enumerated() {
          XCTAssertEqual(a.samples.rawWord(at: reference), b.samples.rawWord(at: index), mode.rawValue)
        }
        XCTAssertLessThanOrEqual(a.samples.retainedSampleBytes, 2 * ComponentPlane.blockSamples * 2)
      }
      try session.undo()
      XCTAssertEqual(session.document, large)
    }
  }
  func testMaximumLayeredRGBMergeKeepsSparsePlateSamplesAndAlphaSelection() throws {
    let size = 300_000
    func fixture(_ side: Int) throws -> CraftDocument {
      var document = try CraftDocument(width: side, height: side, depth: .u16)
      document.layers[0].content = .raster(try Surface(width: side, height: side, depth: .u16,
        fill: Pixel(0.125, 0.5, 0.75, 0.6)))
      let swatch = try Surface(width: 1, height: 1, depth: .u16, fill: Pixel(1, 0, 0.25, 0.4))
      var top = Layer(name: "Red", content: .raster(swatch))
      top.x = 1
      top.y = 1
      document.layers.append(top)
      document.alphaChannels = [AlphaChannel(name: "Coverage",
        pixels: try Surface(width: side, height: side, depth: .u16, fill: .black))]
      return document
    }
    let dense = try fixture(3), sparse = try fixture(size)
    var expected = dense, result = sparse
    try InkModeInput.multichannel(in: dense, mergeVisible: true).apply(to: &expected)
    try InkModeInput.multichannel(in: sparse, mergeVisible: true).apply(to: &result)
    XCTAssertEqual(result.alphaChannels, sparse.alphaChannels)
    XCTAssertTrue(result.layers.isEmpty)
    for (large, small) in zip(try result.multichannelRaster().plates, try expected.multichannelRaster().plates) {
      XCTAssertEqual(large.samples.rawWord(at: 0), small.samples.rawWord(at: 0))
      XCTAssertEqual(large.samples.rawWord(at: size + 1), small.samples.rawWord(at: 4))
      XCTAssertEqual(large.samples.rawWord(at: size * size - 1), small.samples.rawWord(at: 8))
    }
  }
  func testRenderingAndRasterExportUseInkDisplayAndKeepOutsideRegionTransparent() throws {
    let gray = try InkPlane(width: 3, height: 1, bytes: Data([0, 128, 255]))
    let duo = try CraftDocument(width: 3, height: 1).replacingInkMode(.duotone(.init(gray: gray,
      settings: .init(inks: [.init(name: "Red", color: Pixel(1, 0, 0))]))))
    let rendered = try Renderer.composite(duo)
    XCTAssertEqual(rendered.pixel(x: 0, y: 0), Pixel(1, 0, 0)); XCTAssertEqual(rendered.pixel(x: 2, y: 0), .white)
    let region = try Renderer.composite(duo, region: .init(x: 1, y: 0, width: 1, height: 1))
    XCTAssertEqual(region.pixel(x: 0, y: 0).a, 0); XCTAssertEqual(region.pixel(x: 2, y: 0).a, 0)
    XCTAssertEqual(region.pixel(x: 1, y: 0), rendered.pixel(x: 1, y: 0))
    let flattened = try RasterIO.read(RasterIO.encoded(duo, type: .png))
    XCTAssertEqual(try Renderer.composite(flattened).pixel(x: 0, y: 0), Pixel(1, 0, 0))
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(duo))
    XCTAssertThrowsError(try RasterIO.encoded(duo, type: .tiff))
    var multi = duo; try InkModeInput.multichannel(in: duo).apply(to: &multi)
    XCTAssertEqual(try Renderer.composite(multi).pixel(x: 0, y: 0), Pixel(1, 0, 0))
    let request = DocumentModeRequest(.init(mode: .rgb, depth: .u8), mergeVisible: true)
    try DocumentModeInput.command(request, in: multi).apply(to: &multi)
    XCTAssertNil(multi.inkMode); XCTAssertEqual(multi.colorMode, .rgb)
    XCTAssertEqual(try Renderer.composite(multi).pixel(x: 0, y: 0), Pixel(1, 0, 0))
  }
}
