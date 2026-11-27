import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFLayerOutputTests: XCTestCase {
  func testPhotoshopTIFFSavedSelectionAndMergedTransparencyMetadata() throws {
    let helper = TIFFLayerTests()
    for (name, order, extras) in [
      ("photoshop-selection-le-fixture.tiff", TIFFContainer.Order.little, [0]),
      ("photoshop-transparent-be-fixture.tiff", .big, [1, 0]),
    ] {
      let bytes = try helper.fixture(name)
      let header = try TIFFContainer(bytes, metadata: false)
      XCTAssertEqual(header.order, order)
      XCTAssertEqual(try header.numbers(338), extras)
      let document = try RasterIO.read(bytes)
      XCTAssertEqual(document.layers.map(\.name), ["Base pixels", "Masked coating"])
      XCTAssertNotNil(document.layers.last?.mask)
      XCTAssertEqual(document.alphaChannels?.map(\.name), ["Alpha 1"])
      let selection = try XCTUnwrap(document.alphaChannels?.first)
      XCTAssertEqual(selection.psdIdentifier, 4)
      for y in 0..<48 {
        for x in 0..<64 {
          XCTAssertEqual(selection.pixels.pixel(x: x, y: y).r, Float((13*x+7*y)%256)/255)
        }
      }
      let layerMetadata = try PSDLayerComps.metadata(document.layers[0].sourceTags?["shmd"])
      XCTAssertEqual(layerMetadata.map(\.key), ["cust"])
      let descriptor = try PSDDescriptor.read(XCTUnwrap(layerMetadata.first).data, padding: true)
      XCTAssertNotNil(descriptor["layerTime"]?.number)
      let preserved = try RasterIO.encoded(document, type: .tiff,
        options: .init(tiffByteOrder: .littleEndian, tiffLayers: true))
      let reopened = try RasterIO.read(preserved)
      XCTAssertEqual(reopened.alphaChannels?.first?.pixels, selection.pixels)
      XCTAssertEqual(reopened.layers[0].sourceTags?["shmd"], document.layers[0].sourceTags?["shmd"])
    }
  }

  func testRGB8TIFFRetainsNamedSelectionAlongsideLayerMasks() throws {
    var document = try RasterIO.read(TIFFLayerTests().fixture("8-big-marker.tiff"))
    var pixels = try Surface(width:document.width,height:document.height,fill:.black)
    for y in 0..<pixels.height {
      for x in 0..<pixels.width {
        let value = Float(13*x+7*y)/255
        pixels.setPixel(x:x,y:y,Pixel(value,value,value))
      }
    }
    var options = ChannelDisplayOptions()
    options.indicates = .selectedAreas
    document.alphaChannels = [AlphaChannel(name:"Saved selection",pixels:pixels,options:options)]
    for order in RasterEncodingOptions.TIFFByteOrder.allCases {
      for pixelOrder in RasterEncodingOptions.TIFFPixelOrder.allCases {
        let writeOptions = RasterEncodingOptions(tiffCompression:.zip,tiffByteOrder:order,tiffPixelOrder:pixelOrder,
          tiffLayers:true)
        let bytes = try RasterIO.encoded(document,type:.tiff,options:writeOptions)
        let metadata = try TIFFContainer(bytes,metadata:false)
        XCTAssertEqual(try metadata.numbers(338).last,0)
        let imported = try RasterIO.read(bytes)
        let saved = try XCTUnwrap(imported.alphaChannels?.first)
        XCTAssertEqual(imported.alphaChannels?.count,1)
        XCTAssertEqual(saved.name,"Saved selection")
        XCTAssertEqual(saved.pixels,pixels)
        XCTAssertEqual(saved.options.indicates,.selectedAreas)
        try TIFFLayerTests().check(imported,depth:8)
        let undeclared = try TIFFLayerTests().replacing(bytes) {
          $0.root.fields.removeValue(forKey: 338)
        }
        XCTAssertThrowsError(try RasterIO.read(undeclared))
      }
    }
  }

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
