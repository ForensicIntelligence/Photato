import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFLayerOutputTests: XCTestCase {
  func testIndependentInputLayerSamplesSurviveOutputMatrixAndCompositeRemainsReadable() throws {
    let helper = TIFFLayerTests()
    for depth in [8, 16, 32] {
      let model = try RasterIO.read(helper.fixture("\(depth)-little-marker.tiff"))
      for order in RasterEncodingOptions.TIFFByteOrder.allCases {
        for compression in RasterEncodingOptions.TIFFLayerCompression.allCases {
          for image in RasterEncodingOptions.TIFFCompression.allCases {
            let options = RasterEncodingOptions(tiffCompression: image, tiffByteOrder: order,
              tiffPixelOrder: .perChannel, tiffPredictor: depth == 32 && image != .none,
              tiffLayers: true, tiffLayerCompression: compression)
            let bytes = try RasterIO.encoded(model, type: .tiff, options: options)
            let reopened = try RasterIO.read(bytes)
            try helper.check(reopened, depth: depth)
            XCTAssertEqual(reopened.sourceMetadata?["tiffGlobal_MTrn"], Data())
            let file = try TIFFContainer(bytes, metadata: false, additionalTags: [37724])
            XCTAssertEqual(file.order, order == .bigEndian ? .big : .little)
            XCTAssertEqual(try file.scalar(259), image.tag)
            var flatOptions = options
            flatOptions.tiffLayers = nil; flatOptions.tiffLayerCompression = nil
            let expected = try RasterIO.read(RasterIO.encoded(model, type: .tiff, options: flatOptions))
            let cache = try helper.replacing(bytes) { $0.root.fields.removeValue(forKey: 37724) }
            XCTAssertEqual(try helper.raw(helper.raster(RasterIO.read(cache).layers[0])),
              try helper.raw(helper.raster(expected.layers[0])))
            if let folder = ProcessInfo.processInfo.environment["PHOTATO_TIFF_LAYER_WRITE_OUTPUT_DIR"] {
              try bytes.write(to: URL(fileURLWithPath: folder)
                .appendingPathComponent("\(depth)-\(order.rawValue)-\(compression.rawValue)-\(image.rawValue).tiff"))
            }
          }
        }
      }
    }
  }
  func testBothEndianRichOutputsAndExtendedMaskParameters() throws {
    for depth in PixelDepth.allCases {
      var model = try CraftDocument(width: 4, height: 3, depth: depth)
      var layer = Layer(name: "Levels 🥔", content: .adjustment(.levels(PSDLevelsTests().levels)))
      layer.mask = try Surface(width: 4, height: 3, depth: depth, fill: .white)
      layer.maskProperties = .init()
      layer.maskProperties?.density = Float(128) / 255; layer.maskProperties?.feather = 1.25
      model.layers.append(layer)
      let expected = try PSDCodec.read(PSDCodec.writeRasterLayers(model))
      let bytes = try RasterIO.encoded(model, type: .tiff, options: .init(tiffLayers: true))
      let actual = try RasterIO.read(bytes)
      XCTAssertEqual(actual.layers.map(\.content), expected.layers.map(\.content))
      XCTAssertEqual(actual.layers.map(\.name), expected.layers.map(\.name))
      XCTAssertEqual(actual.layers.map(\.maskProperties), expected.layers.map(\.maskProperties))
      XCTAssertEqual(try TIFFContainer(bytes, metadata: false).order, .big)
      let richLittle = try RasterIO.read(RasterIO.encoded(model, type: .tiff,
        options: .init(tiffByteOrder: .littleEndian, tiffLayers: true)))
      XCTAssertEqual(richLittle.layers.map(\.content), expected.layers.map(\.content))
      XCTAssertEqual(richLittle.layers.map(\.name), expected.layers.map(\.name))
      XCTAssertEqual(richLittle.layers.map(\.maskProperties), expected.layers.map(\.maskProperties))
      // Extended mask parameters also convert for ordinary raster layers.
      model.layers[1].content = .raster(try Surface(width: 4, height: 3, depth: depth, fill: .white))
      let little = try RasterIO.read(RasterIO.encoded(model, type: .tiff,
        options: .init(tiffByteOrder: .littleEndian, tiffLayers: true, tiffLayerCompression: .rle)))
      XCTAssertEqual(little.layers.map(\.name), model.layers.map(\.name))
      XCTAssertEqual(little.layers.map(\.maskProperties), model.layers.map(\.maskProperties))
    }
  }
  func testInvalidLayerOptionsAndGlobalBlockBudgetRejectBeforePublication() throws {
    let model = try CraftDocument(width: 2, height: 2)
    for options in [
      RasterEncodingOptions(tiffLayerCompression: .rle),
      .init(tiffLayers: false, tiffLayerCompression: .zip),
    ] { XCTAssertThrowsError(try RasterIO.encoded(model, type: .tiff, options: options)) }
    XCTAssertThrowsError(try RasterIO.encoded(model, type: .png, options: .init(tiffLayers: true)))
    let helper = TIFFLayerTests()
    let input = try helper.fixture("8-big-marker.tiff")
    let excessive = try helper.replacing(input) { tiff in
      var field = tiff.root.fields[37724]!
      for i in 0..<4096 {
        field.data.append(Data("8BIM".utf8))
        field.data.append(Data(String(format: "%04X", i).utf8))
        field.data.append(Data(repeating: 0, count: 4))
      }
      field.count = field.data.count; tiff.root.fields[37724] = field
    }
    XCTAssertThrowsError(try RasterIO.read(excessive)) {
      XCTAssertTrue($0.localizedDescription.contains("Too many TIFF Photoshop blocks"))
    }
  }
  func testCancelledOutputDoesNotReturnCompositeOnly() async throws {
    let model = try RasterIO.read(TIFFLayerTests().fixture())
    let task = Task {
      while !Task.isCancelled { await Task.yield() }
      return try RasterIO.encoded(model, type: .tiff, options: .init(tiffLayers: true))
    }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled output returned bytes") }
    catch { XCTAssertTrue(error is CancellationError) }
  }
}
