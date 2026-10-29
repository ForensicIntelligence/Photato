import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSBTests: XCTestCase {
  func testExternalUnsupportedShapeContentRemainsExplicitForPSDAndPSB() throws {
    for ext in ["psd", "psb"] {
      let url = try XCTUnwrap(
        Bundle.module.url(
          forResource: "semi-transparent-layers", withExtension: ext,
          subdirectory: "Fixtures/psb-corpus"))
      XCTAssertThrowsError(try PSDCodec.read(Data(contentsOf: url))) { error in
        guard case CraftError.unsupported(let message) = error else {
          return XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(message.contains("sn2P"), message)
        XCTAssertTrue(message.contains("Import cancelled to preserve its contents"), message)
      }
    }
  }

  func testPinnedExternalPSDAndPSBPairSamplesAndStructureAgree() throws {
    for name in [
      "0layers", "1layer", "2layers", "group", "16bit5x5", "32bit5x5", "hidden-layer",
      "300dpi", "transparentbg",
    ] {
      func read(_ ext: String) throws -> CraftDocument {
        let url = try XCTUnwrap(
          Bundle.module.url(
            forResource: name, withExtension: ext, subdirectory: "Fixtures/psb-corpus"))
        return try PSDCodec.read(Data(contentsOf: url))
      }
      do {
        let psd = try read("psd")
        let psb = try read("psb")
        print(
          "PSB external pair \(name): \(psb.width)x\(psb.height), \(psb.depth), \(psb.layers.count) layers"
        )
        XCTAssertEqual(psb.width, psd.width, name)
        XCTAssertEqual(psb.height, psd.height, name)
        XCTAssertEqual(psb.depth, psd.depth, name)
        XCTAssertEqual(psb.pixelsPerInch, psd.pixelsPerInch, name)
        XCTAssertEqual(psb.workingICC, psd.workingICC, name)
        XCTAssertEqual(psb.layers.count, psd.layers.count, name)
        for (a, b) in zip(psb.layers, psd.layers) {
          XCTAssertEqual(a.name, b.name, name)
          XCTAssertEqual(a.visible, b.visible, name)
          XCTAssertEqual(a.opacity, b.opacity, name)
          XCTAssertEqual(a.blendMode, b.blendMode, name)
          XCTAssertEqual(a.isClipped, b.isClipped, name)
          XCTAssertEqual(a.group, b.group, name)
          XCTAssertEqual(
            psb.layers.firstIndex(where: { $0.id == a.parentID }),
            psd.layers.firstIndex(where: { $0.id == b.parentID }), name)
          switch (a.content, b.content) {
          case (.raster(let x), .raster(let y)):
            let encoding: SurfaceColorEncoding = psb.depth == .f32 ? .linearRGB : .sRGB
            XCTAssertEqual(
              try x.rgbaData(depth: .f32, colorEncoding: encoding),
              try y.rgbaData(depth: .f32, colorEncoding: encoding), name)
          case (.group, .group): break
          default: XCTAssertEqual(a.content, b.content, name)
          }
          XCTAssertEqual(try a.mask?.rgbaData(depth: .f32), try b.mask?.rgbaData(depth: .f32), name)
        }
        let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(psb, format: .psb))
        XCTAssertEqual(reopened.layers.map(\.name), psb.layers.map(\.name), name)
        XCTAssertEqual(
          try Renderer.composite(reopened).rgbaData(depth: psb.depth),
          try Renderer.composite(psb).rgbaData(depth: psb.depth), name)
      } catch { XCTFail("Corpus \(name): \(error)") }
    }
  }

  struct Manifest: Decodable {
    struct Fixture: Decodable {
      var file: String
      var depth: Int
      var compression: Int
      var width: Int
      var height: Int
      var planes: [String]
      var mask: String
    }
    var cases: [Fixture]
  }
  func fixtureURL(_ name: String) throws -> URL {
    try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/psb"))
  }
  func fixtures() throws -> [Manifest.Fixture] {
    try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: fixtureURL("provenance.json")))
      .cases
  }
  func bytes(_ hex: String) -> [UInt8] {
    stride(from: 0, to: hex.count, by: 2).map {
      let start = hex.index(hex.startIndex, offsetBy: $0)
      return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    }
  }
  func sample(_ plane: [UInt8], _ i: Int, depth: Int) -> Float {
    let count = depth / 8
    let bits = plane[(i * count)..<((i + 1) * count)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    return depth == 32 ? Float(bitPattern: bits) : Float(bits) / (depth == 16 ? 65535 : 255)
  }
  func assertSamples(
    _ doc: CraftDocument, fixture: Manifest.Fixture, file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    XCTAssertEqual(doc.width, fixture.width, file: file, line: line)
    XCTAssertEqual(doc.height, fixture.height, file: file, line: line)
    XCTAssertEqual(doc.layers.count, 2, file: file, line: line)
    let layer = try XCTUnwrap(doc.layers.first(where: { !$0.isGroup }))
    let group = try XCTUnwrap(doc.layers.first(where: \.isGroup))
    XCTAssertEqual(layer.name, "PSB pixels Ω", file: file, line: line)
    XCTAssertEqual(layer.parentID, group.id, file: file, line: line)
    XCTAssertEqual(group.group?.passThrough, true, file: file, line: line)
    guard case .raster(let surface) = layer.content else {
      return XCTFail("Raster missing", file: file, line: line)
    }
    let planes = fixture.planes.map(bytes)
    for y in 0..<fixture.height {
      for x in 0..<fixture.width {
        let pixel =
          fixture.depth == 32 ? surface.linearPixel(x: x, y: y) : surface.pixel(x: x, y: y)
        for (c, actual) in [pixel.r, pixel.g, pixel.b, pixel.a].enumerated() {
          XCTAssertEqual(
            actual.bitPattern,
            sample(planes[c], y * fixture.width + x, depth: fixture.depth).bitPattern, file: file,
            line: line)
        }
      }
    }
    let mask = try XCTUnwrap(layer.mask)
    let expectedMask = bytes(fixture.mask)
    for y in 0..<2 {
      for x in 0..<2 {
        XCTAssertEqual(
          mask.pixel(x: x, y: y).r, sample(expectedMask, y * 2 + x, depth: fixture.depth),
          file: file, line: line)
      }
    }
  }
  func testIndependentPSBAllDepthsAndFourCompressionMethods() throws {
    for fixture in try fixtures() {
      let doc = try PSDCodec.read(Data(contentsOf: fixtureURL(fixture.file)))
      try assertSamples(doc, fixture: fixture)
      XCTAssertEqual(doc.sourceMetadata?["psdGlobal_cinf"], Data("original!".utf8))
    }
  }
  func testPSBExportAllDepthsCompressionAndNativeArchiveRetainsEditableStructure() throws {
    for fixture in try fixtures() where fixture.compression == 1 {
      var doc = try PSDCodec.read(Data(contentsOf: fixtureURL(fixture.file)))
      // The pths block is another64bit PSB tag, despite its omission in Adobe's key list.
      let component = PathComponent(
        knots: [PathKnot(PathPoint(0, 0)), PathKnot(PathPoint(2, 0)), PathKnot(PathPoint(2, 2))],
        closed: true)
      doc.paths = [
        NamedPath(name: "Saved Ω", path: VectorPath(components: [component]), isWorkPath: false)
      ]
      let archived = try NativeArchive.encode(doc)
      for compression in [PSDCompression.raw, .zip, .zipPrediction] {
        let output = try PSDCodec.writeRasterLayers(doc, compression: compression, format: .psb)
        XCTAssertEqual(Array(output[4..<6]), [0, 2])
        // Independently locate the8byte outer length (resources remain4byte).
        var at = 26
        for _ in 0..<2 {
          let length = output[at..<(at + 4)].reduce(0) { ($0 << 8) | Int($1) }
          at += 4 + length
        }
        let layerBytes = output[at..<(at + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        XCTAssertGreaterThan(layerBytes, 0)
        XCTAssertLessThan(layerBytes, UInt64(output.count - at - 8))
        let reopened = try PSDCodec.read(output)
        try assertSamples(reopened, fixture: fixture)
        XCTAssertEqual(reopened.paths?.first?.name, "Saved Ω")
        XCTAssertEqual(try NativeArchive.encode(doc), archived)
        if let directory = ProcessInfo.processInfo.environment["PHOTATO_PSB_OUTPUT_DIR"] {
          let url = URL(fileURLWithPath: directory).appendingPathComponent(
            "rgb\(fixture.depth)-compression\(compression.rawValue).psb")
          try output.write(to: url)
        }
      }
    }
  }
  func testPSBSupportsDimensionBeyondPSDLimitWithoutChangingPSDContract() throws {
    let doc = try CraftDocument(width: 30_001, height: 1, depth: .u8)
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(doc, format: .psd))
    let bytes = try PSDCodec.writeRasterLayers(doc, format: .psb)
    let reopened = try PSDCodec.read(bytes)
    XCTAssertEqual(reopened.width, 30_001)
    XCTAssertEqual(reopened.height, 1)
    var invalidPSD = bytes
    invalidPSD[5] = 1
    XCTAssertThrowsError(try PSDCodec.read(invalidPSD)) { error in
      XCTAssertTrue(error.localizedDescription.contains("format limit"))
    }
  }
  func testPSBTruncationUnsignedLengthsAndUnknownVersionsRejectWithoutTrap() throws {
    let fixture = try Data(contentsOf: fixtureURL("rgb8-compression1.psb"))
    for length in 0..<fixture.count {
      XCTAssertThrowsError(try PSDCodec.read(fixture.prefix(length)), "truncation at \(length)")
    }
    for value in [UInt64.max, UInt64(Int.max), 0x1_0000_0000] {
      var reader = PSDReader(data: withUnsafeBytes(of: value.bigEndian) { Data($0) })
      XCTAssertThrowsError(try reader.section(lengthBytes: 8))
      var bad = fixture
      // Empty color/resources put the outer8byte length at34.
      bad.replaceSubrange(34..<42, with: withUnsafeBytes(of: value.bigEndian) { Data($0) })
      XCTAssertThrowsError(try PSDCodec.read(bad))
    }
    var badVersion = fixture
    badVersion[5] = 3
    XCTAssertThrowsError(try PSDCodec.read(badVersion))
    var oversized = fixture
    oversized.replaceSubrange(18..<22, with: [0, 4, 147, 225])  //300001
    XCTAssertThrowsError(try PSDCodec.read(oversized))
  }
  func testPSBRLERowsUse32BitsIncludingRowsLargerThanUInt16() throws {
    let width = 20_000
    let raw = [UInt8](repeating: 123, count: width * 4)
    var packed = Data()
    for start in stride(from: 0, to: raw.count, by: 128) {
      let count = min(128, raw.count - start)
      packed.append(UInt8(count - 1))
      packed.append(contentsOf: raw[start..<(start + count)])
    }
    XCTAssertGreaterThan(packed.count, Int(UInt16.max))
    var writer = PSDWriter()
    writer.n(1, 2)
    writer.n(packed.count, 4)
    writer.data.append(packed)
    XCTAssertEqual(
      try PSDChannelCodec.decode(writer.data, width: width, height: 1, depth: 32, format: .psb), raw
    )
    XCTAssertThrowsError(
      try PSDChannelCodec.decode(writer.data, width: width, height: 1, depth: 32, format: .psd))
  }
}
