import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class QuickMaskGraySemanticsTests: XCTestCase {
  func fixture(_ name: String) throws -> CraftDocument {
    let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/quick-mask-semantics484/" + name + ".psd")
    return try PSDCodec.read(Data(contentsOf: url))
  }
  func testIndependentPhotoshopEntryAndExitPlanesDistinguishNoneAndExplicitFull() throws {
    let cases: [(String, Float, Bool, Bool)] = [
      ("ps-masked-no-selection-entry", 1, true, false),
      ("ps-masked-explicit-full-entry", 1, false, true),
      ("ps-no-selection-switched-selected", 1, true, true),
      ("ps-selected-no-selection-entry", 0, true, false),
      ("ps-selected-no-selection-black-dialog", 1, true, true)
    ]
    for (name, coverage, initiallyEmpty, full) in cases {
      var d = try fixture(name)
      let mask = try XCTUnwrap(d.quickMask), layers = d.layers
      XCTAssertEqual(mask.psdQuickMaskInitiallyEmpty, initiallyEmpty, name)
      for y in 0..<8 { for x in 0..<8 {
        XCTAssertEqual(mask.pixels.pixel(x: x, y: y).r, coverage, name)
      } }
      try Command.channel(.quickMask(false, mask.options)).apply(to: &d)
      if full { XCTAssertTrue(try XCTUnwrap(d.coverageSelection(), name).isFullCoverage) }
      else { XCTAssertNil(try d.coverageSelection(), name) }
      XCTAssertEqual(d.layers, layers, name)
    }
  }
  func testIndependentPartialSelectedAreaPlaneNormalizesAndExitsUnchanged() throws {
    var d = try fixture("ps-selected-entry")
    let mask = try XCTUnwrap(d.quickMask)
    XCTAssertEqual(mask.options.indicates, .selectedAreas)
    let expected = Array(repeating: [UInt8](repeating: 255, count: 5) + [UInt8](repeating: 0, count: 3), count: 8).flatMap { $0 }
    XCTAssertEqual(try mask.selection().denseBytes(), expected)
    try Command.channel(.quickMask(false, mask.options)).apply(to: &d)
    XCTAssertEqual(try d.coverageSelection()?.denseBytes(), expected)
    XCTAssertEqual(try fixture("ps-selected-exit").alphaChannels?.first?.selection().denseBytes(), expected)
  }
  // Read only the public raw merged-plane framing. No channel normalization or
  // display logic is shared with the implementation under test.
  func rawLastPlane(_ data: Data, width: Int, height: Int, bytesPerSample: Int) throws -> Data {
    func number(_ at: Int, _ count: Int) -> Int { data[at..<(at + count)].reduce(0) { ($0 << 8) | Int($1) } }
    XCTAssertEqual(data.prefix(4), Data("8BPS".utf8))
    var at = 26
    for _ in 0..<3 { let length = number(at, 4); at += 4 + length }
    XCTAssertEqual(number(at, 2), 0)
    let count = width * height * bytesPerSample
    XCTAssertGreaterThanOrEqual(data.count - at - 2, count)
    return data.suffix(count)
  }
  func testSelectedAreaWriterMatchesIndependentEditingGray() throws {
    var d = try CraftDocument(width: 8, height: 8)
    d.selection = .init(x: 0, y: 0, width: 5, height: 8)
    var options = ChannelDisplayOptions(); options.indicates = .selectedAreas
    try Command.channel(.quickMask(true, options)).apply(to: &d)
    let bytes = try PSDCodec.writeRasterLayers(d, compression: .raw)
    let expected = Data(Array(repeating: [UInt8](repeating: 0, count: 5) + [UInt8](repeating: 255, count: 3), count: 8).flatMap { $0 })
    XCTAssertEqual(try rawLastPlane(bytes, width: 8, height: 8, bytesPerSample: 1), expected)
    let reopened = try PSDCodec.read(bytes)
    XCTAssertEqual(try reopened.quickMask?.selection().denseBytes(), try d.quickMask?.selection().denseBytes())
    XCTAssertEqual(reopened.quickMask?.psdQuickMaskInitiallyEmpty, false)
  }
  func testImportedSelectedFloat32RawWordsSurviveNativeAndPSDRoundTrips() throws {
    var d = try CraftDocument(width: 8, height: 1, depth: .f32)
    let words: [Float] = [-0.0, 0, Float(bitPattern: 1), 0.1234567, 0.4, 1, 1.1, -0.2]
    var gray = try Surface(width: 8, height: 1, depth: .f32)
    for (x, v) in words.enumerated() { gray.setPixel(x: x, y: 0, Pixel(v, v, v)) }
    d.alphaChannels = [AlphaChannel(name: "Literal editing gray", pixels: gray)]
    // Produce raw gray in masked mode, then change only the public display-kind
    // byte. The source words are independent of selected-gray writer inversion.
    var bytes = try PSDCodec.writeRasterLayers(d, compression: .raw)
    func number(_ at: Int, _ count: Int) -> Int { bytes[at..<(at + count)].reduce(0) { ($0 << 8) | Int($1) } }
    var at = 26; at += 4 + number(at, 4)
    let end = at + 4 + number(at, 4); at += 4
    var found = false
    while at < end {
      let id = number(at + 4, 2); at += 6
      let name = number(at, 1); at += 1 + name; if (1 + name) % 2 != 0 { at += 1 }
      let length = number(at, 4); at += 4
      if id == 1077 { bytes[at + 4 + 12] = 0; found = true }
      at += length + length % 2
    }
    XCTAssertTrue(found)
    let sourceRaw = try rawLastPlane(bytes, width: 8, height: 1, bytesPerSample: 4)
    let imported = try PSDCodec.read(bytes), channel = try XCTUnwrap(imported.alphaChannels?.first)
    XCTAssertEqual(imported.minimumArchiveVersion, 91)
    for (x, raw) in words.enumerated() {
      XCTAssertEqual(channel.psdSelectedGray?.pixel(x: x, y: 0).r.bitPattern, raw.bitPattern)
      XCTAssertEqual(channel.pixels.pixel(x: x, y: 0).r.bitPattern, (1 - raw).bitPattern)
    }
    let restored = try NativeArchive.decode(NativeArchive.encodeChunked(imported))
    let encoded = try PSDCodec.writeRasterLayers(restored, compression: .raw)
    XCTAssertEqual(try rawLastPlane(encoded, width: 8, height: 1, bytesPerSample: 4), sourceRaw)
    if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let url = URL(fileURLWithPath: path).appendingPathComponent("selected-gray-float32-" + UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try sourceRaw.write(to: url.appendingPathComponent("source.words"))
      try rawLastPlane(encoded, width: 8, height: 1, bytesPerSample: 4).write(to: url.appendingPathComponent("output.words"))
    }
  }
  func testSelectedQuickMaskOrdinaryAndMultichannelRoundTripsAtAllDepths() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 8, height: 8, depth: depth)
      d.selection = .init(x: 0, y: 0, width: 5, height: 8)
      var options = ChannelDisplayOptions(); options.indicates = .selectedAreas
      try Command.channel(.quickMask(true, options)).apply(to: &d)
      let expected = try XCTUnwrap(d.quickMask).selection().denseBytes()
      for standalone in [false, true] where !standalone || depth != .f32 {
        var model = d
        if standalone {
          model.alphaChannels = [AlphaChannel(name: "Saved", pixels: try XCTUnwrap(d.quickMask).pixels, options: options)]
          model.channelOnly = true; model.layers = []; model.activeLayerID = nil
        }
        for format: PSDFileFormat in [.psd, .psb] { for compression: PSDCompression in [.raw, .rle, .zip, .zipPrediction] {
          let bytes = try PSDCodec.writeRasterLayers(model, compression: compression, format: format)
          let reopened = try PSDCodec.read(bytes)
          XCTAssertEqual(try reopened.quickMask?.selection().denseBytes(), expected)
          XCTAssertEqual(reopened.quickMask?.psdQuickMaskInitiallyEmpty, false)
          if standalone { XCTAssertEqual(try reopened.alphaChannels?.first?.selection().denseBytes(), expected) }
        } }
      }
    }
  }
}
