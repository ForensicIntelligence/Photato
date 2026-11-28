import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFPagedSelectionTests: XCTestCase {
  func testPagedImportMatchesPhotoshopSavedSelectionFixtures() throws {
    for name in ["photoshop-selection-le-fixture.tiff", "photoshop-transparent-be-fixture.tiff"] {
      let bytes = try TIFFLayerTests().fixture(name)
      let ordinary = try RasterIO.read(bytes)
      let paged = try XCTUnwrap(RasterIO.readPagedComponentTIFF(bytes, name: ordinary.name))
      XCTAssertEqual(paged.layers.map(\.name), ordinary.layers.map(\.name))
      XCTAssertEqual(paged.layers.map(\.content), ordinary.layers.map(\.content))
      XCTAssertEqual(paged.layers.map(\.mask), ordinary.layers.map(\.mask))
      let alpha = try XCTUnwrap(paged.alphaChannels?.first)
      XCTAssertEqual(paged.alphaChannels?.count, 1)
      XCTAssertEqual(alpha.name, "Alpha 1")
      XCTAssertEqual(alpha.psdIdentifier, 4)
      for y in 0..<48 { for x in 0..<64 {
        XCTAssertEqual(alpha.pixels.pixel(x: x, y: y).r, Float((13 * x + 7 * y) % 256) / 255)
      } }
      XCTAssertEqual(alpha.options, ordinary.alphaChannels?.first?.options)
    }
  }

  func testStreamedTIFFKeepsSavedSelectionAndTransparencyPackingAcrossLayouts() throws {
    var source = try RasterIO.read(TIFFLayerTests().fixture("photoshop-transparent-be-fixture.tiff"))
    source.alphaChannels?[0].options.indicates = .selectedAreas
    for order in RasterEncodingOptions.TIFFByteOrder.allCases {
      for layout in RasterEncodingOptions.TIFFPixelOrder.allCases {
        for transparent in [false, true] {
          let options = RasterEncodingOptions(tiffCompression: RasterEncodingOptions.TIFFCompression.none,
            tiffByteOrder: order, tiffPixelOrder: layout, tiffLayers: true, tiffTransparency: transparent)
          let baseline = try TIFFContainer(RasterIO.encoded(source, type: .tiff, options: options), metadata: false)
          let data = try TIFFComponentExport.encoded(source, options: options)
          let streamed = try TIFFContainer(data, metadata: false)
          XCTAssertEqual(try streamed.numbers(338), transparent ? [1, 0] : [0])
          XCTAssertEqual(try samples(streamed), try samples(baseline))
          let imported = try XCTUnwrap(RasterIO.readPagedComponentTIFF(data, name: source.name))
          XCTAssertEqual(imported.layers.map(\.mask), source.layers.map(\.mask))
          XCTAssertEqual(imported.alphaChannels?.first?.pixels, source.alphaChannels?.first?.pixels)
          XCTAssertEqual(imported.alphaChannels?.first?.options.indicates, .selectedAreas)
        }
      }
    }
  }

  func testLargeLayeredTIFFRetainsNamedMasksAndCanRestoreSavedSelection() throws {
    let width = 7200, height = 5400
    var source = try CraftDocument(width: width, height: height, depth: .u8)
    var pixels = try Surface(width: width, height: height, depth: .u8, fill: .clear)
    pixels.setPixel(x: 51, y: 60, Pixel(0.31, 0.37, 0.53, 0.64))
    source.layers[0].content = .raster(pixels)
    source.layers[0].name = "Base pixels"
    var edit = Layer(name: "Masked edit", content: .raster(try Surface(width: 40, height: 32, depth: .u8, fill: .white)))
    edit.x = 5; edit.y = 7
    var mask = try Surface(width: 40, height: 32, depth: .u8, fill: .white)
    mask.setPixel(x: 10, y: 20, Pixel(0.37, 0.37, 0.37))
    edit.mask = mask
    source.layers.append(edit)
    var first = try Surface(width: width, height: height, depth: .u8, fill: .black)
    first.setPixel(x: 17, y: 19, Pixel(0.75, 0.75, 0.75))
    first.setPixel(x: width - 1, y: height - 1, .white)
    var second = try Surface(width: width, height: height, depth: .u8, fill: .white)
    second.setPixel(x: 85, y: 140, .black)
    var selectionDisplay = ChannelDisplayOptions(); selectionDisplay.indicates = .selectedAreas
    source.alphaChannels = [AlphaChannel(name: "Retouch border", pixels: first, options: selectionDisplay),
      AlphaChannel(name: "Background protection", pixels: second)]
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let location = directory.appendingPathComponent("large-saved-selections.tiff")
    let options = RasterEncodingOptions(tiffCompression: .zip, tiffByteOrder: .littleEndian,
      tiffLayers: true, tiffTransparency: false, tiffLayerCompression: .zip)
    try RasterIO.write(source, to: location, type: .tiff, options: options)
    let opened = try RasterIO.read(location)
    XCTAssertEqual(opened.layers.map(\.name), source.layers.map(\.name))
    XCTAssertEqual(opened.layers.map(\.mask), source.layers.map(\.mask))
    XCTAssertEqual(opened.alphaChannels?.map(\.name), source.alphaChannels?.map(\.name))
    XCTAssertEqual(opened.alphaChannels?.first?.pixels, first)
    XCTAssertEqual(opened.alphaChannels?.last?.pixels, second)
    XCTAssertEqual(opened.alphaChannels?.first?.options.indicates, .selectedAreas)
    var selected = opened
    let restored = try XCTUnwrap(opened.alphaChannels?.first).selection()
    selected.setCoverageSelection(restored)
    XCTAssertEqual(try selected.coverageSelection()?.coverage(x: 17, y: 19), first.pixel(x: 17, y: 19).r)
    XCTAssertEqual(try selected.coverageSelection()?.coverage(x: width - 1, y: height - 1), 1)
    let bytes = try Data(contentsOf: location)
    XCTAssertEqual(try TIFFContainer(bytes, metadata: false).numbers(338), [0, 0])
  }

  private func samples(_ file: TIFFContainer) throws -> Data {
    let geometry = try XCTUnwrap(TIFFStorage.Geometry(file, allowAssociatedAlpha: true, allowSavedAlpha: true))
    XCTAssertEqual(geometry.compression, 1)
    return try zip(geometry.offsets, geometry.counts).reduce(into: Data()) { samples, strip in
      samples.append(try file.bytes(at: strip.0, count: strip.1))
    }
  }
}
