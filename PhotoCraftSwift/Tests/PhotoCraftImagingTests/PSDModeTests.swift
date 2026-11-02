import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDModeTests: XCTestCase {
  func fixture(_ mode: DocumentColorMode, _ depth: PixelDepth) throws -> CraftDocument {
    var native = try NativeModeRaster(width: 4, height: 3, mode: mode, depth: depth)
    for i in 0..<12 {
      for c in 0..<mode.componentCount {
        let value = Float((i * 29 + c * 61) % 251) / 250
        try native.set(value, component: c, index: i)
      }
      try native.set([Float(0), 0.5, 1][i % 3], component: mode.componentCount, index: i)
    }
    if depth == .f32 { try native.set(2.5, component: 0, index: 2) }
    var document = try CraftDocument(width: 4, height: 3, depth: depth, name: "Mode fixture")
    document.modeDescriptor = try .init(mode: mode, depth: depth, profile: native.profile)
    var layer = Layer(name: "Original components", content: .raster(try native.surface())); layer.nativeMode = native
    document.layers = [layer]; document.activeLayerID = layer.id; try document.validate(); return document
  }
  func assertPlanes(_ restored: CraftDocument, _ source: CraftDocument, file: StaticString = #filePath, line: UInt = #line) throws {
    XCTAssertEqual(restored.colorMode, source.colorMode, file: file, line: line)
    XCTAssertEqual(restored.depth, source.depth, file: file, line: line)
    let original = try XCTUnwrap(source.layers[0].nativeMode)
    if source.colorMode != .rgb {
      XCTAssertEqual(restored.layers[0].nativeMode?.planes, original.planes, file: file, line: line)
      XCTAssertEqual(restored.modeDescriptor?.profile, original.profile, file: file, line: line)
    } else {
      guard case .raster(let pixels) = restored.layers[0].content else { return XCTFail("Expected raster") }
      for i in 0..<12 {
        let p = source.depth == .f32 ? pixels.linearPixel(x: i % 4, y: i / 4) : pixels.pixel(x: i % 4, y: i / 4)
        for (c, value) in [p.r, p.g, p.b, p.a].enumerated() {
          XCTAssertEqual(value.bitPattern, original.value(component: c, index: i).bitPattern, file: file, line: line)
        }
      }
    }
  }
  func testAllSupportedModeDepthCompressionAndContainerLayerPlanes() throws {
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      let document = try fixture(mode, depth)
      for format in PSDFileFormat.allCases { for compression in PSDCompression.allCases {
        let data = try PSDCodec.writeRasterLayers(document, compression: compression, format: format)
        let restored = try PSDCodec.read(data)
        try assertPlanes(restored, document)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(restored)), restored)
      } }
    } }
  }
  /// A standalone raw fixture assembled from literal file-layout fields. It does
  /// not call the production writer or the mode sample transformation helper.
  func flattened(mode: Int, depth: Int, planes: [[UInt8]], alpha: Bool = false, profile: Data? = nil) -> Data {
    var file = PSDWriter(); file.text("8BPS"); file.n(1, 2); file.n(0, 6)
    file.n(planes.count, 2); file.n(1, 4); file.n(2, 4); file.n(depth, 2); file.n(mode, 2); file.n(0, 4)
    var resources = PSDWriter()
    if let profile { resources.text("8BIM"); resources.n(1039, 2); resources.n(0, 2); resources.section(profile); if profile.count % 2 != 0 { resources.n(0, 1) } }
    file.section(resources.data)
    var layer = PSDWriter()
    if alpha {
      layer.n(0, 4); layer.n(0, 4); layer.text("8BIM"); layer.text(depth == 8 ? "Mtrn" : depth == 16 ? "Mt16" : "Mt32"); layer.n(0, 4)
    }
    file.section(layer.data); file.n(0, 2)
    for plane in planes { file.data.append(contentsOf: plane) }; return file.data
  }
  func testLiteralFlattenedSamplesUseActualModeChannelsAndCMYKInversion() throws {
    let cmyk = try PSDCodec.read(flattened(mode: 4, depth: 8, planes: [[0, 255], [255, 0], [128, 64], [13, 240], [128, 64]], alpha: true))
    let inks = try XCTUnwrap(cmyk.layers[0].nativeMode)
    XCTAssertEqual(inks.planes, [Data([255, 0]), Data([0, 255]), Data([127, 191]), Data([242, 15]), Data([128, 64])])
    let lab = try PSDCodec.read(flattened(mode: 9, depth: 8, planes: [[17, 241], [128, 64], [128, 192]]))
    XCTAssertEqual(lab.layers[0].nativeMode?.planes, [Data([17, 241]), Data([128, 64]), Data([128, 192]), Data([255, 255])])
    let gray = try PSDCodec.read(flattened(mode: 1, depth: 16, planes: [[0, 1, 128, 0]]))
    XCTAssertEqual(gray.layers[0].nativeMode?.planes, [Data([1, 0, 0, 128]), Data([255, 255, 255, 255])])
    let whiteMatted = try PSDCodec.read(flattened(mode: 1, depth: 8, planes: [[191, 255], [128, 0]], alpha: true))
    XCTAssertEqual(try XCTUnwrap(whiteMatted.layers[0].nativeMode).value(component: 0, index: 0), PixelDepth.u8.quantize(0.5), accuracy: 1 / 255)
    XCTAssertEqual(whiteMatted.layers[0].nativeMode?.value(component: 1, index: 1), 0)
  }
  func testLiteralGray32PreservesHDRAndLinearizesOriginalProfile() throws {
    let gamma = try NativeModeProfile.standard(.grayscale, depth: .u16)
    let document = try PSDCodec.read(flattened(mode: 1, depth: 32, planes: [[0x40, 0x20, 0, 0, 0xbe, 0x80, 0, 0]], profile: gamma))
    let native = try XCTUnwrap(document.layers[0].nativeMode)
    XCTAssertEqual(native.value(component: 0, index: 0), 2.5)
    XCTAssertEqual(native.value(component: 0, index: 1), -0.25)
    XCTAssertEqual(document.sourceICC, gamma)
    XCTAssertNoThrow(try NativeModeProfile.validate(native.profile, mode: .grayscale, depth: .f32))
  }
  func testRawCMYKOutputContainsInvertedInkPlanesAndStraightAlpha() throws {
    let document = try fixture(.cmyk, .u8), source = try XCTUnwrap(document.layers[0].nativeMode)
    var file = PSDReader(data: try PSDCodec.writeRasterLayers(document, compression: .raw))
    _ = try file.bytes(12); XCTAssertEqual(try file.u16(), 5)
    _ = try file.bytes(10); XCTAssertEqual(try file.u16(), 4)
    _ = try file.section(); _ = try file.section()
    var section = try file.section(), records = try section.section()
    XCTAssertEqual(try records.i16(), -1); _ = try records.bytes(16)
    XCTAssertEqual(try records.u16(), 5)
    var entries: [(Int, Int)] = []
    for _ in 0..<5 { entries.append((try records.i16(), try records.u32())) }
    XCTAssertEqual(entries.map(\.0), [0, 1, 2, 3, -1])
    _ = try records.bytes(12); _ = try records.section()
    for (c, entry) in entries.enumerated() {
      var data = try records.view(entry.1); XCTAssertEqual(try data.u16(), 0)
      let bytes = try data.bytes(data.remaining)
      XCTAssertEqual(bytes, c < 4 ? Data(source.planes[c].map { 255 - $0 }) : source.planes[c])
    }
  }
  func testGroupsMasksAndFileBackedRoundTripKeepSeparationBytes() throws {
    var document = try fixture(.cmyk, .u16)
    let group = Layer(name: "Ink group", content: .group(.init()))
    document.layers[0].parentID = group.id
    let coverage = PixelDepth.u16.quantize(0.7)
    document.layers[0].mask = try Surface(width: 4, height: 3, depth: .u16, fill: Pixel(coverage, coverage, coverage))
    document.layers.append(group); try document.validate()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for format in PSDFileFormat.allCases {
      let url = folder.appendingPathComponent("ink.\(format == .psd ? "psd" : "psb")")
      try PSDCodec.writeRasterLayers(document, to: url, compression: .rle, format: format)
      let read = try PSDCodec.read(url)
      let raster = try XCTUnwrap(read.layers.first { $0.nativeMode != nil })
      XCTAssertEqual(raster.nativeMode?.planes, document.layers[0].nativeMode?.planes)
      let mask = try XCTUnwrap(raster.mask), expected = try XCTUnwrap(document.layers[0].mask)
      XCTAssertEqual(mask.width, expected.width); XCTAssertEqual(mask.height, expected.height)
      for y in 0..<3 { for x in 0..<4 { XCTAssertEqual(mask.pixel(x: x, y: y), expected.pixel(x: x, y: y)) } }
      XCTAssertEqual(read.layers.first(where: { $0.id == raster.parentID })?.name, group.name)
    }
  }
  func testModeInputRejectsInvalidDepthMissingExtraAndNonFiniteSamples() throws {
    XCTAssertThrowsError(try PSDCodec.read(flattened(mode: 4, depth: 32, planes: Array(repeating: Array(repeating: 0, count: 8), count: 4))))
    XCTAssertThrowsError(try PSDCodec.read(flattened(mode: 4, depth: 8, planes: [[0, 0], [0, 0], [0, 0]])))
    // Two Lab auxiliary planes are supported since checkpoint329. Preserve the
    // missing-plane rejection with an actual truncated channel declaration.
    let extra = flattened(mode: 9, depth: 8, planes: Array(repeating: [0, 0], count: 5))
    let auxiliary = try PSDCodec.read(extra)
    XCTAssertEqual(auxiliary.alphaChannels?.count, 2)
    var missingExtra = extra; missingExtra[12] = 0; missingExtra[13] = 6
    XCTAssertThrowsError(try PSDCodec.read(missingExtra))
    XCTAssertThrowsError(try PSDCodec.read(flattened(mode: 1, depth: 32, planes: [[0x7f, 0xc0, 0, 0, 0, 0, 0, 0]])))
    XCTAssertThrowsError(try PSDCodec.read(flattened(mode: 4, depth: 8, planes: Array(repeating: [0, 0], count: 4), profile: NativeModeProfile.standard(.rgb, depth: .u8))))
    let valid = try PSDCodec.writeRasterLayers(fixture(.cmyk, .u16))
    XCTAssertThrowsError(try PSDCodec.read(valid.dropLast()))
    XCTAssertThrowsError(try PSDCodec.read(valid + Data([0])))
  }
  func testModeExportRejectsUnportedEditableRichContent() throws {
    var document = try fixture(.lab, .u8)
    document.layers.append(Layer(name: "Live fill", content: .fill(.white)))
    try document.validate()
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(document))
  }
  func testEmitModeFilesForIndependentInteroperabilityChecks() throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_PSD_MODE_EVIDENCE_DIR"] else { return }
    let folder = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var cases: [[String: Any]] = []
    for mode in [DocumentColorMode.grayscale, .cmyk, .lab] { for depth in mode.depths {
      let document = try fixture(mode, depth), native = try XCTUnwrap(document.layers[0].nativeMode)
      let name = "\(mode.rawValue)-\(depth == .u8 ? 8 : depth == .u16 ? 16 : 32).psd"
      try PSDCodec.writeRasterLayers(document, to: folder.appendingPathComponent(name), compression: .zipPrediction)
      cases.append(["file": name, "mode": mode.rawValue, "width": native.width, "height": native.height,
        "depth": depth == .u8 ? 8 : depth == .u16 ? 16 : 32, "components": native.mode.componentCount,
        "littleEndianNativePlanesBase64": native.planes.map { $0.base64EncodedString() }])
    } }
    try JSONSerialization.data(withJSONObject: cases, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("expected.json"))
  }
}
