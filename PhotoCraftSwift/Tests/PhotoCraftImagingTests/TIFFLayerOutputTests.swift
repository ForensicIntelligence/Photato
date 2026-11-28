import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFLayerOutputTests: XCTestCase {
  func testTIFFProfileChoicePreservesCompositeAndEditableLayerSamples() throws {
    for mode in [DocumentColorMode.rgb, .grayscale, .cmyk, .lab] {
      let profile = try NativeModeProfile.standard(mode, depth: .u8)
      var document = try CraftDocument(width: 3, height: 2)
      if mode != .rgb { document.modeDescriptor = try .init(mode: mode, depth: .u8, profile: profile) }
      document.layers = try (0..<2).map { ordinal in
        var raster = try NativeModeRaster(width: 3, height: 2, mode: mode, depth: .u8, profile: profile)
        for i in 0..<6 {
          for component in 0...mode.componentCount {
            let word = (19 + 51 * ordinal + 32 * i + 67 * component) % 256
            try raster.set(Float(word) / 255, component: component, index: i)
          }
        }
        var layer = Layer(name: "Layer \(ordinal + 1)", content: .raster(try raster.surface()))
        if mode != .rgb { layer.nativeMode = raster }
        return layer
      }
      document.activeLayerID = document.layers.last?.id
      for layered in [false, true] {
        var samples: Data?, layerBytes: Data?
        let choices: [(sourceUntagged: Bool, override: Bool?, embedsProfile: Bool)] = [
          (false, nil, true), (true, nil, false), (false, false, false), (true, true, true),
        ]
        for (sourceUntagged, override, embedsProfile) in choices {
          document.profileIsUntagged = sourceUntagged ? true : nil
          let options = RasterEncodingOptions(tiffCompression: RasterEncodingOptions.TIFFCompression.none,
            tiffByteOrder: .bigEndian, tiffLayers: layered, tiffTransparency: false, tiffEmbedProfile: override)
          let bytes = try RasterIO.encoded(document, type: .tiff, options: options)
          let container = try TIFFContainer(bytes, metadata: false, additionalTags: [34377, 34675, 37724])
          XCTAssertEqual(container.root.fields[34675] != nil, embedsProfile, "\(mode), layered: \(layered)")
          let resources = try PSDImageResources.blocks(container.root.fields[34377]?.data ?? Data())
          if !embedsProfile { XCTAssertFalse(resources.contains(where: { $0.id == 1039 })) }
          let offsets = try container.numbers(273), counts = try container.numbers(279)
          let merged = zip(offsets, counts).reduce(into: Data()) { result, strip in
            result.append(bytes[strip.0..<(strip.0 + strip.1)])
          }
          if let samples { XCTAssertEqual(merged, samples) } else { samples = merged }
          if layered {
            let pixels = try XCTUnwrap(container.root.fields[37724]?.data)
            if let layerBytes { XCTAssertEqual(pixels, layerBytes) } else { layerBytes = pixels }
          }
          let reopened = try RasterIO.read(bytes)
          XCTAssertEqual(reopened.profileIsUntagged == true, !embedsProfile)
          XCTAssertEqual(reopened.layers.count, layered ? 2 : 1)
          XCTAssertEqual(document.profileIsUntagged == true, sourceUntagged)
        }
      }
    }
  }

  func testPhotoshopTIFFNormalCompositeMatchesMergedSamples() throws {
    let fixtures = TIFFLayerTests()
    let transparentReference = try fixtures.fixture("photoshop-transparent-be-fixture.tiff")
    let source = try RasterIO.read(transparentReference)
    XCTAssertTrue(Renderer.usesIntegerNormalRasterComposite(source))

    func samplePlanes(_ bytes: Data) throws -> [[UInt8]] {
      let file = try TIFFContainer(bytes, metadata: false)
      let layout = try XCTUnwrap(TIFFStorage.Geometry(file, allowAssociatedAlpha: true, allowSavedAlpha: true))
      XCTAssertEqual(layout.compression, 1)
      XCTAssertEqual(layout.bits, 8)
      let strips = zip(layout.offsets, layout.counts).map { offset, count in
        Array(file.data[offset..<offset + count])
      }
      if layout.planar {
        let stripsPerPlane = strips.count / layout.channels
        return (0..<layout.channels).map { channel in
          let start = channel * stripsPerPlane
          return strips[start..<start + stripsPerPlane].flatMap { $0 }
        }
      }
      let samples = strips.flatMap { $0 }
      return (0..<layout.channels).map { channel in
        stride(from: channel, to: samples.count, by: layout.channels).map { samples[$0] }
      }
    }

    let dense = try Renderer.composite(source).rgbaData(depth: .u8)
    XCTAssertEqual(try Renderer.compositePaged(source).rgbaData(depth: .u8), dense)
    let sparse = try XCTUnwrap(SparseCanvasRenderer.composite(source))
    XCTAssertEqual(try sparse.rgbaData(depth: .u8), dense)

    for (keepTransparency, order, layout, reference) in [
      (true, RasterEncodingOptions.TIFFByteOrder.bigEndian, RasterEncodingOptions.TIFFPixelOrder.interleaved, transparentReference),
      (false, .littleEndian, .perChannel, try fixtures.fixture("photoshop-selection-le-fixture.tiff")),
    ] {
      let options = RasterEncodingOptions(tiffCompression: RasterEncodingOptions.TIFFCompression.none,
        tiffByteOrder: order, tiffPixelOrder: layout, tiffLayers: true, tiffTransparency: keepTransparency)
      let actual = try samplePlanes(RasterIO.encoded(source, type: .tiff, options: options))
      let expected = try samplePlanes(reference)
      XCTAssertEqual(actual.count, expected.count)
      for (channel, samples) in zip(actual, expected).enumerated() {
        XCTAssertEqual(samples.0.count, source.width * source.height)
        XCTAssertEqual(samples.1.count, samples.0.count)
        let differences = zip(samples.0, samples.1).filter { $0 != $1 }.count
        XCTAssertEqual(differences, 0, "Channel \(channel), Save Transparency \(keepTransparency)")
      }
    }
  }

  func testTIFFSaveTransparencyMattesOnlyMergedImage() throws {
    let source = try RasterIO.read(TIFFLayerTests().fixture("photoshop-transparent-be-fixture.tiff"))
    for layout in RasterEncodingOptions.TIFFPixelOrder.allCases {
      var options = RasterEncodingOptions(tiffCompression: RasterEncodingOptions.TIFFCompression.none,
        tiffByteOrder: .littleEndian, tiffPixelOrder: layout, tiffLayers: true, tiffTransparency: true)
      let transparent = try RasterIO.encoded(source, type: .tiff, options: options)
      options.tiffTransparency = false
      let matted = try RasterIO.encoded(source, type: .tiff, options: options)
      let a = try TIFFContainer(transparent, metadata: false)
      let b = try TIFFContainer(matted, metadata: false, additionalTags: [37724])
      XCTAssertEqual(try a.numbers(338), [1, 0])
      XCTAssertEqual(try b.numbers(338), [0])
      XCTAssertNil(try XCTUnwrap(b.root.fields[37724]).data.range(of: Data("nrTM".utf8)))
      let offsetsA = try a.numbers(273), offsetsB = try b.numbers(273)
      let planar = layout == .perChannel
      func sample(_ file: TIFFContainer, _ offsets: [Int], _ pixel: Int, _ channel: Int, _ count: Int) -> Int {
        Int(file.data[planar ? offsets[channel] + pixel : offsets[0] + pixel * count + channel])
      }
      for pixel in 0..<source.width * source.height {
        let opacity = sample(a, offsetsA, pixel, 3, 5)
        for color in 0..<3 {
          XCTAssertEqual(sample(b, offsetsB, pixel, color, 4), sample(a, offsetsA, pixel, color, 5) + 255 - opacity)
        }
        XCTAssertEqual(sample(b, offsetsB, pixel, 3, 4), sample(a, offsetsA, pixel, 4, 5))
      }
      let reopened = try RasterIO.read(matted)
      XCTAssertEqual(reopened.layers.map(\.content), source.layers.map(\.content))
      XCTAssertEqual(reopened.layers.map(\.mask), source.layers.map(\.mask))
      XCTAssertEqual(reopened.alphaChannels?.first?.pixels, source.alphaChannels?.first?.pixels)
      XCTAssertEqual(reopened.alphaChannels?.first?.name, source.alphaChannels?.first?.name)
    }
  }

  func testFlatTIFFOmitsOpacityAtEachRGBDepth() throws {
    for depth in PixelDepth.allCases {
      let surface = try Surface(width: 4, height: 3, depth: depth, fill: .clear)
      let options = RasterEncodingOptions(tiffCompression: .zip, tiffByteOrder: .bigEndian,
        tiffPixelOrder: .perChannel, tiffPredictor: depth == .f32, tiffTransparency: false)
      let bytes = try RasterIO.encoded(surface, type: .tiff, options: options)
      let file = try TIFFContainer(bytes, metadata: false)
      XCTAssertEqual(try file.scalar(277), 3)
      XCTAssertNil(file.root.fields[338])
      let imported = try TIFFLayerTests().raster(RasterIO.read(bytes).layers[0])
      XCTAssertEqual(imported.pixel(x: 0, y: 0), .white)
    }
  }

  func testTIFFWhiteMatteUsesNativeLightInkAndPaletteSamples() throws {
    for mode in [DocumentColorMode.grayscale, .cmyk, .lab] {
      for depth in mode.depths {
        var raster = try NativeModeRaster(width: 2, height: 1, mode: mode, depth: depth)
        for channel in 0..<mode.componentCount {
          try raster.set(0.25, component: channel, index: 0)
          try raster.set(0.25, component: channel, index: 1)
        }
        try raster.set(0, component: mode.componentCount, index: 0)
        try raster.set(1, component: mode.componentCount, index: 1)
        var document = try CraftDocument(width: 2, height: 1, depth: depth)
        document.modeDescriptor = try .init(mode: mode, depth: depth, profile: raster.profile)
        document.layers[0].content = .raster(try raster.surface())
        document.layers[0].nativeMode = raster
        let bytes = try RasterIO.encoded(document, type: .tiff, options: .init(tiffTransparency: false))
        let result = try XCTUnwrap(RasterIO.read(bytes).layers[0].nativeMode)
        XCTAssertEqual(result.value(component: mode.componentCount, index: 0), 1)
        for channel in 0..<mode.componentCount {
          let white: Float = mode == .cmyk ? 0 : (mode == .lab && channel > 0 ? 128 / 255 : 1)
          let tolerance: Float = depth == .u8 ? 1.01 / 255 : (depth == .u16 ? 1.01 / 65535 : 0)
          XCTAssertEqual(result.value(component: channel, index: 0), white, accuracy: tolerance)
          XCTAssertEqual(result.value(component: channel, index: 1),
            raster.value(component: channel, index: 1), accuracy: tolerance)
        }
      }
    }
    let indexed = try IndexedRaster(width: 2, height: 1, palette: [.init(0,0,0), .init(40,80,120)],
      indices: Data([0,1]), transparentIndex: 0)
    let source = try CraftDocument(width: 2, height: 1).replacingRestrictedMode(.indexed(indexed))
    let encoded = try RasterIO.encoded(source, type: .tiff, options: .init(tiffTransparency: false))
    guard case .indexed(let result) = try RasterIO.read(encoded).restrictedMode else {
      return XCTFail("Save Transparency changed the indexed color mode.")
    }
    XCTAssertEqual(result.indices, indexed.indices)
    XCTAssertEqual(result.palette, [.init(255,255,255), .init(40,80,120)])
    XCTAssertNil(result.transparentIndex)
    XCTAssertEqual(source.restrictedMode, .indexed(indexed))
  }

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
