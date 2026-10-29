import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFLayerTests: XCTestCase {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/tiff-layers")
  func fixture(_ name: String = "8-little-3.tiff") throws -> Data {
    try Data(contentsOf: root.appendingPathComponent(name))
  }
  func raster(_ layer: Layer) throws -> Surface {
    guard case .raster(let s) = layer.content else { throw CraftError.invalid("Expected raster") }
    return s
  }
  func raw(_ s: Surface) throws -> Data {
    try s.rgbaData(depth: s.depth, colorEncoding: s.depth == .f32 ? .linearRGB : .sRGB)
  }
  func replacing(_ input: Data, _ body: (TIFFContainer) throws -> Void) throws -> Data {
    let tiff = try TIFFContainer(input, metadata: true, additionalTags: [37724])
    try body(tiff)
    var output = input
    try tiff.appendDirectories(to: &output, order: tiff.order)
    return output
  }
  func check(_ d: CraftDocument, depth: Int) throws {
    XCTAssertEqual(d.layers.count, 3); XCTAssertEqual(d.width, 5); XCTAssertEqual(d.height, 4)
    XCTAssertEqual(d.pixelsPerInch, 144)
    XCTAssertEqual(d.layers.map(\.name), ["Base Ω", "Crème 层", "Layers"])
    XCTAssertNil(d.layers[0].parentID)
    XCTAssertEqual(d.layers[1].parentID, d.layers[2].id)
    XCTAssertTrue(try XCTUnwrap(d.layers[2].group).passThrough)
    XCTAssertTrue(try XCTUnwrap(d.layers[2].group).expanded)
    let layer = d.layers[1]
    XCTAssertEqual(layer.x, -1); XCTAssertEqual(layer.y, 1)
    XCTAssertFalse(layer.visible); XCTAssertFalse(layer.locked)
    XCTAssertEqual(layer.protection, .transparency, "Independent TIFF lspf is1, not full protection")
    XCTAssertEqual(layer.opacity, Float(153) / 255)
    XCTAssertEqual(layer.blendMode, .multiply)
    XCTAssertEqual(try raw(raster(d.layers[0])), try Data(contentsOf: root.appendingPathComponent("\(depth)-base.raw")))
    XCTAssertEqual(try raw(raster(layer)), try Data(contentsOf: root.appendingPathComponent("\(depth)-top.raw")))
    let mask = try XCTUnwrap(layer.mask)
    for y in 0..<2 { for x in 0..<3 {
      XCTAssertEqual(mask.pixel(x: x, y: y).r, (y == 0 && x == 0) || (y == 1 && x == 2) ? 0 : 1)
    } }
    XCTAssertEqual(layer.effectiveMaskProperties.outside, 1)
    XCTAssertEqual(layer.maskCoordinateTransform, .translation(-1, 1))
  }
  func testIndependentDepthEndianCompressionMatrixKeepsEditableContentInsteadOfCache() throws {
    for depth in [8, 16, 32] {
      for order in ["big", "little"] {
        for compression in 0...3 {
          let bytes = try fixture("\(depth)-\(order)-\(compression).tiff")
          let d = try RasterIO.read(bytes)
          try check(d, depth: depth)
          XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)), d)
          let output = try PSDCodec.writeRasterLayers(d)
          let reopened = try PSDCodec.read(output)
          try check(reopened, depth: depth)
          if let folder = ProcessInfo.processInfo.environment["PHOTATO_TIFF_LAYER_OUTPUT_DIR"] {
            try output.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(depth)-\(order)-\(compression).psd"))
          }
        }
      }
    }
  }
  func testBigEndianRichRecordsSharePSDDecoderIncludingUnicodeAndMaskParameters() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 4, height: 3, depth: depth)
      var layer = Layer(name: "Levels 🥔", content: .adjustment(.levels(PSDLevelsTests().levels)))
      layer.mask = try Surface(width: 4, height: 3, depth: depth, fill: .white)
      layer.maskProperties = .init(); layer.maskProperties?.density = Float(128) / 255
      layer.maskProperties?.feather = 1.25
      d.layers.append(layer)
      let psd = try PSDCodec.writeRasterLayers(d), expected = try PSDCodec.read(psd)
      var reader = PSDReader(data: psd, offset: 26)
      _ = try reader.section()
      let resources = try reader.section().data
      var section = try reader.section()
      let info = try section.section().data
      _ = try section.section()
      var blocks = PSDWriter()
      if !info.isEmpty { blocks.text("8BIM"); blocks.text("Layr"); blocks.section(info) }
      blocks.data.append(try section.bytes(section.remaining))
      let cache = try RasterIO.encoded(d, type: .tiff, options: .init(tiffByteOrder: .bigEndian))
      let bytes = try replacing(cache) { t in
        let payload = TIFFLayers.signature + blocks.data
        t.root.fields[37724] = .init(tag: 37724, type: 7, count: payload.count, data: payload)
        t.root.fields[34377] = .init(tag: 34377, type: 1, count: resources.count, data: resources)
      }
      let actual = try RasterIO.read(bytes)
      XCTAssertEqual(actual.layers[1].name, layer.name)
      XCTAssertEqual(actual.layers[1].content, expected.layers[1].content)
      XCTAssertEqual(actual.layers[1].mask, expected.layers[1].mask)
      XCTAssertEqual(actual.layers[1].maskProperties, expected.layers[1].maskProperties)
    }
  }
  func testMalformedLayerContainersRejectDespiteReadableComposite() throws {
    let input = try fixture("8-little-0.tiff")
    let mutations: [(TIFFContainer) throws -> Void] = [
      { $0.root.fields[37724]!.data[0] = 0 },
      { $0.root.fields[37724]!.data[36] = 0 },
      { $0.root.fields[37724]!.data.replaceSubrange(40..<44, with: Data("61rL".utf8)) },
      { $0.root.fields[37724]!.data.replaceSubrange(44..<48, with: Data(repeating: 255, count: 4)) },
      { $0.root.fields[37724]!.data.replaceSubrange(48..<50, with: Data([255, 127])) },
      { t in
        var f = t.root.fields[37724]!
        f.data = Data(f.data.dropLast(7)); f.count = f.data.count; t.root.fields[37724] = f
      },
      { t in
        var f = t.root.fields[37724]!
        f.data.append(Data("MIB8zzzz".utf8) + Data([0, 0, 0, 0])); f.count = f.data.count
        t.root.fields[37724] = f
      },
      { t in
        var f = t.root.fields[37724]!
        f.data.append(f.data.dropFirst(36)); f.count = f.data.count; t.root.fields[37724] = f
      },
      { $0.set(274, [3]) },
      { $0.root.fields[37724]!.type = 2 },
    ]
    for (index, mutate) in mutations.enumerated() {
      let broken = try replacing(input, mutate)
      let source = try XCTUnwrap(CGImageSourceCreateWithData(broken as CFData, nil))
      XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil), "\(index)")
      XCTAssertThrowsError(try RasterIO.read(broken), "\(index)")
    }
    let ordinary = try replacing(input) { $0.root.fields.removeValue(forKey: 37724) }
    XCTAssertEqual(try RasterIO.read(ordinary).layers.count, 1)
    XCTAssertEqual(try raster(RasterIO.read(ordinary).layers[0]).pixel(x: 0, y: 0), .white)
  }
  func testLayerProfileDisagreementIsNotFlattenedOrReinterpreted() throws {
    let input = try fixture("8-big-0.tiff")
    let a = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData() as Data?)
    let b = try XCTUnwrap(CGColorSpace(name: CGColorSpace.adobeRGB1998)?.copyICCData() as Data?)
    let bytes = try replacing(input) { t in
      let resources = PSDImageResources.block(1039, data: b)
      t.root.fields[34377] = .init(tag: 34377, type: 1, count: resources.count, data: resources)
      t.root.fields[34675] = .init(tag: 34675, type: 7, count: a.count, data: a)
    }
    XCTAssertThrowsError(try RasterIO.read(bytes))
  }
  func testIndependentTIFFSpecificTransparencyMarkerAndExtraChannels() throws {
    for depth in [8, 16, 32] { for order in ["big", "little"] {
      let bytes = try fixture("\(depth)-\(order)-marker.tiff")
      let d = try RasterIO.read(bytes)
      try check(d, depth: depth)
      XCTAssertEqual(d.sourceMetadata?["tiffGlobal_MTrn"], Data())
      XCTAssertNil(d.sourceMetadata?["psdGlobal_Mtrn"])
      for extra in [0, 3] {
        let invalid = try replacing(bytes) { $0.set(338, [extra]) }
        XCTAssertThrowsError(try RasterIO.read(invalid))
      }
      let tooMany = try replacing(bytes) { $0.set(277, [5]); $0.set(258, [depth, depth, depth, depth, depth]); $0.set(338, [2, 0]) }
      XCTAssertThrowsError(try RasterIO.read(tooMany))
    } }
  }
  func testLittleEndianMaskParametersAndUnsupportedRichTags() throws {
    var bytes = Data()
    let order = TIFFContainer.Order.little
    for n in [0, 0, 2, 3] { bytes.append(order.bytes(n, 4)) }
    bytes.append(contentsOf: [255, 16, 3, 128])
    bytes.append(order.bytes(Int(truncatingIfNeeded: Double(1.25).bitPattern), 8))
    var framed = order.bytes(bytes.count, 4) + bytes
    var c = TIFFLayerEndian.Cursor(framed)
    let mask = try XCTUnwrap(c.mask())
    XCTAssertEqual(mask.density, 128); XCTAssertEqual(mask.feather, 1.25)
    XCTAssertEqual(mask.bounds.width, 3); XCTAssertEqual(mask.bounds.height, 2)
    framed.removeLast()
    XCTAssertThrowsError(try { var c = TIFFLayerEndian.Cursor(framed); return try c.mask() }())
    XCTAssertThrowsError(try TIFFLayerEndian.payload(Data(repeating: 0, count: 4), tag: "SoCo", global: false))
  }
  func testCancelledLayerImportDoesNotReturnFlattenedPixels() async throws {
    let bytes = try fixture()
    let task = Task {
      while !Task.isCancelled { await Task.yield() }
      return try RasterIO.read(bytes)
    }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled import returned content") }
    catch { XCTAssertTrue(error is CancellationError) }
  }
}
