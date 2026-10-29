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
        let raw = try InkPlane(width: 3, height: 1, depth: depth, bytes: before.planes[c])
        XCTAssertEqual(plate.samples.bytes, try raw.converted(to: depth, inverted: mode != .cmyk).bytes)
      }
      let restored = try session.document.convertingMode(.init(mode: mode, depth: depth))
      XCTAssertEqual(restored.layers[0].nativeMode?.planes, before.planes, "Round-trip component bytes must stay exact")
      try session.undo(); XCTAssertTrue(session.document == original)
    } }
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
    XCTAssertEqual(raster.gray.bytes, native.planes[0])
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
