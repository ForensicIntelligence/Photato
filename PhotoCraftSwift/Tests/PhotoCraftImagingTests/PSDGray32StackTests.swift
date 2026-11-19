import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDGray32StackTests: XCTestCase {
  private struct Reference: Decodable {
    let name: String
    let channels: Int
    let armMergedSHA256: String
    let intelMergedSHA256: String
  }

  private let width = 16
  private let height = 10
  private let coverage: [Float] = [0, 0.25, 0.5, 0.75, 1]

  private func fixture(_ name: String) throws -> CraftDocument {
    let hasBackground = name.hasPrefix("opaque-")
    let levels: [Float] = [-0.375, -0.125, 0, 0.0625, 0.125, 0.3, 0.5, 0.85, 1, 1.5, 2.5]
    let mode = try DocumentModeDescriptor(mode: .grayscale, depth: .f32)
    var document = try CraftDocument(width: width, height: height, depth: .f32, name: "Owned Gray32 stack")
    document.modeDescriptor = mode
    document.layers = try (0...1).map { index in
      let isBackground = index == 0 && hasBackground
      var raster = try NativeModeRaster(width: width, height: height, mode: .grayscale,
        depth: .f32, profile: mode.profile)
      for y in 0..<height {
        for x in 0..<width {
          let gray = levels[(3 * x + 7 * y + index * (x + y + 2)) % levels.count]
          let alpha = coverage[(11 * x + 3 * y + index * (x + y + 3)) % coverage.count]
          try raster.set(gray, component: 0, index: y * width + x)
          try raster.set(isBackground ? 1 : alpha, component: 1, index: y * width + x)
        }
      }
      var layer = Layer(name: isBackground ? "Background" : index == 0 ? "Owned base" : "Owned top",
        content: .raster(try raster.surface()))
      layer.nativeMode = raster
      layer.background = isBackground ? true : nil
      return layer
    }
    document.activeLayerID = document.layers[1].id
    switch name {
    case "opaque-layer-opacity":
      document.layers[1].opacity = 128 / 255
    case "transparent-normal":
      document.layers[1].opacity = 192 / 255
    case "opaque-multiply":
      document.layers[1].blendMode = .multiply
    case "opaque-masked":
      var mask = try Surface(width: width, height: height, depth: .f32, fill: .white)
      for y in 0..<height {
        for x in 0..<width {
          let alpha = coverage[(2 * x + y) % coverage.count]
          mask.setPixel(x: x, y: y, Pixel(alpha, alpha, alpha))
        }
      }
      document.layers[1].mask = mask
    default: break
    }
    try document.validate()
    return document
  }

  private func mergedPlanes(_ data: Data, format: PSDFileFormat) throws -> (Int, Data) {
    var reader = PSDReader(data: data)
    _ = try reader.view(12)
    let channels = try reader.u16()
    _ = try reader.view(12)
    _ = try reader.section()
    _ = try reader.section()
    _ = try reader.section(lengthBytes: format.sectionLengthBytes)
    let rows = try PSDChannelReader(reader, width: width, height: height, depth: 32,
      channels: channels, format: format)
    var samples = Data()
    for _ in 0..<(channels * height) { samples.append(contentsOf: try rows.nextRow()) }
    return (channels, samples)
  }

  func testGray32PSDAndPSBStacksMatchSavedPhotoshopMergedSamples() throws {
    let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "gray32-stack-references",
      withExtension: "json", subdirectory: "Fixtures/gray32"))
    let references = try JSONDecoder().decode([Reference].self, from: Data(contentsOf: fixtureURL))
    XCTAssertEqual(Set(references.map(\.name)), Set(["opaque-layer-opacity", "opaque-normal",
      "opaque-masked", "opaque-multiply", "transparent-normal"]))
    for row in references {
      let document = try fixture(row.name)
      #if arch(x86_64)
      let expected = row.intelMergedSHA256
      #else
      let expected = row.armMergedSHA256
      #endif
      for format in PSDFileFormat.allCases {
        for compression in PSDCompression.allCases {
          let data = try PSDCodec.writeRasterLayers(document, compression: compression,
            format: format, compositeCompression: compression)
          let (channels, samples) = try mergedPlanes(data, format: format)
          XCTAssertEqual(channels, row.channels, row.name)
          XCTAssertEqual(SHA256.hash(data: samples).map { String(format: "%02x", $0) }.joined(),
            expected, row.name)
          let result = try PSDCodec.read(data)
          XCTAssertEqual(result.layers.count, document.layers.count)
          XCTAssertEqual(result.layers.map(\.isBackground), document.layers.map(\.isBackground), row.name)
          for (original, restored) in zip(document.layers, result.layers) {
            XCTAssertEqual(try restored.nativeMode?.planes, try original.nativeMode?.planes, row.name)
            XCTAssertEqual(restored.blendMode, original.blendMode, row.name)
            XCTAssertEqual(restored.opacity, original.opacity, row.name)
            if let mask = original.mask {
              let restoredMask = try XCTUnwrap(restored.mask)
              for y in 0..<height {
                for x in 0..<width {
                  XCTAssertEqual(restoredMask.pixel(x: x, y: y).r, mask.pixel(x: x, y: y).r, row.name)
                }
              }
            }
          }
          if let capture = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
            let ext = format == .psd ? "psd" : "psb"
            try data.write(to: URL(fileURLWithPath: capture)
              .appendingPathComponent("gray32-\(row.name)-\(compression.rawValue).\(ext)"))
          }
        }
      }
    }
  }

  func testSparseGray32MergedRowsMatchOrdinaryRowsWithNormalAndMultiply() throws {
    let width = 4_097, height = 300_000
    for opaque in [false, true] {
      let descriptor = try DocumentModeDescriptor(mode: .grayscale, depth: .f32)
      var document = try CraftDocument(width: width, height: height, depth: .f32)
      document.modeDescriptor = descriptor
      var layers: [Layer] = []
      for index in 0...1 {
        let builder = try NativeModeRaster.RowBuilder(width: width, height: height, mode: .grayscale,
          depth: .f32, profile: descriptor.profile)
        try builder.fill(component: 0, word: Float(index == 0 ? 0.375 : 0.75).bitPattern)
        try builder.fill(component: 1, word: Float(index == 0 && opaque ? 1 : 0.5).bitPattern)
        var source = try builder.finish()
        try source.set(index == 0 ? -0.0 : 1.5, component: 0, index: index + 1)
        try source.set(index == 0 ? -0.25 : 1.25, component: 0, index: width * height - 1 - index)
        if index == 1 { try source.set(0.75, component: 1, index: width * height - 1) }
        var layer = Layer(name: index == 0 && opaque ? "Background" : "Owned pixels", content: .raster(try source.surface()))
        layer.nativeMode = source
        if index == 0 && opaque { layer.background = true }
        if index == 1 {
          layer.opacity = 191 / 255
          if opaque { layer.blendMode = .multiply }
        }
        layers.append(layer)
      }
      document.layers = layers
      document.activeLayerID = layers[1].id
      let sparse = try XCTUnwrap(PSDGray32CompositeRows(document))
      XCTAssertTrue(sparse.usesSparseRows)
      XCTAssertEqual(sparse.repeatedRows(from: height / 2), height - 1 - height / 2)
      XCTAssertEqual(sparse.repeatedRows(from: height - 1), 1)
      for y in [0, height / 2, height - 1] {
        var small = try CraftDocument(width: width, height: 1, depth: .f32)
        small.modeDescriptor = descriptor
        small.layers = try layers.map { layer in
          let source = try XCTUnwrap(layer.nativeMode).cropped(to: .init(x: 0, y: y, width: width, height: 1))
          var cropped = layer
          cropped.nativeMode = source
          cropped.content = .raster(try source.surface())
          return cropped
        }
        small.activeLayerID = layers[1].id
        let ordinary = try XCTUnwrap(PSDGray32CompositeRows(small))
        XCTAssertFalse(ordinary.usesSparseRows)
        for channel in 0...1 {
          XCTAssertEqual(try sparse.row(y, channel: channel, transparency: !opaque),
            try ordinary.row(0, channel: channel, transparency: !opaque))
        }
      }
    }
  }

  func testNamedGray32RasterKeepsItsAlphaWhenItsLocksResembleBackground() throws {
    var document = try fixture("opaque-normal")
    document.layers[0].background = nil
    document.layers[0].protection = [.position, .transparency]
    for format in PSDFileFormat.allCases {
      let data = try PSDCodec.writeRasterLayers(document, format: format)
      let rebuilt = try PSDCodec.read(data)
      XCTAssertFalse(rebuilt.layers[0].isBackground)
      XCTAssertEqual(rebuilt.layers[0].name, "Background")
      XCTAssertEqual(rebuilt.layers[0].protection, [.position, .transparency])
      XCTAssertEqual(try mergedPlanes(data, format: format).0, 2)
    }
  }

  func testStackWithSavedAlphaKeepsItsChannelAfterMergedTransparency() throws {
    for name in ["opaque-normal", "transparent-normal"] {
      var document = try fixture(name)
      for format in PSDFileFormat.allCases {
        let initial = try PSDCodec.writeRasterLayers(document, format: format, compositeCompression: .raw)
        let (channels, merged) = try mergedPlanes(initial, format: format)
        let mask = try Surface(width: width, height: height, depth: .f32, fill: Pixel(0.375, 0.375, 0.375))
        document.alphaChannels = [AlphaChannel(name: "Saved detail", pixels: mask)]
        let output = try PSDCodec.writeRasterLayers(document, format: format, compositeCompression: .raw)
        let (withAlpha, samples) = try mergedPlanes(output, format: format)
        XCTAssertEqual(withAlpha, channels + 1)
        XCTAssertEqual(samples.prefix(merged.count), merged)
        let reopened = try PSDCodec.read(output)
        XCTAssertEqual(reopened.alphaChannels?.map(\.name), ["Saved detail"])
        XCTAssertEqual(reopened.alphaChannels?.first?.pixels.pixel(x: 0, y: 0).r, 0.375)
        document.alphaChannels = nil
      }
    }
  }
}
