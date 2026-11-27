import CryptoKit
import Foundation
import ImageIO
import PhotoCraftCore
import XCTest
import zlib
@testable import PhotoCraftImaging

final class RasterEncodingOptionsTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var model = try CraftDocument(width: 129, height: 73, depth: depth)
    var pixels = try Surface(width: 129, height: 73, depth: depth)
    for y in 0..<73 {
      for x in 0..<129 {
        pixels.setPixel(x: x, y: y, Pixel(Float(x % 23) / 22, Float(y % 17) / 16,
          Float((x * y) % 31) / 30, x % 4 == 0 ? 0.5 : 1))
      }
    }
    model.layers[0].content = .raster(pixels)
    model.resolution = 144
    return model
  }
  func image(_ data: Data) throws -> CGImage {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }
  func properties(_ data: Data) throws -> [CFString: Any] {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
  }
  func samples(_ data: Data) throws -> Data {
    let image = try image(data)
    return try XCTUnwrap(image.dataProvider?.data) as Data
  }
  func testPNGAllCompressionLevelsAndAdam7RetainDecoded8And16BitSamples() throws {
    for depth in [PixelDepth.u8, .u16] {
      let model = try fixture(depth), baseline = try RasterIO.encoded(model)
      for interlaced in [false, true] {
        for level in 0...9 {
          let bytes = try RasterIO.encoded(model,
            options: .init(pngCompression: level, pngInterlaced: interlaced))
          XCTAssertEqual(try samples(bytes), try samples(baseline))
          XCTAssertEqual(try image(bytes).bitsPerComponent, depth == .u8 ? 8 : 16)
          let props = try properties(bytes)
          XCTAssertEqual((props[kCGImagePropertyPNGDictionary] as? [CFString: Any])?[kCGImagePropertyPNGInterlaceType] as? Int, interlaced ? 1 : 0)
          XCTAssertEqual(props[kCGImagePropertyDPIWidth] as? Double,
            try properties(baseline)[kCGImagePropertyDPIWidth] as? Double)
        }
      }
      XCTAssertEqual(try RasterIO.encoded(model, options: .init()), baseline)
    }
  }
  func testPhotoshopPNGPreservesStraightRGBAndHiddenColor() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/png-straight-alpha")
    for fixture in ["rgb8", "rgb16", "offset"] {
      let source = try RasterIO.read(root.appendingPathComponent("\(fixture).psd"))
      let expected = try Data(contentsOf: root.appendingPathComponent("\(fixture).rgba"))
      for interlaced in [false, true] {
        let png = try RasterIO.encoded(source, type: .png,
          options: .init(pngCompression: 9, pngInterlaced: interlaced))
        XCTAssertEqual(try straightPNGSamples(png), expected, "\(fixture), Adam7 \(interlaced)")
      }
    }
  }

  func testDirectPNGEncodingKeepsStraightSurfaceSamplesAtZeroAndLowOpacity() throws {
    for depth in [PixelDepth.u8, .u16] {
      let maximum = depth == .u8 ? Float(255) : Float(65535)
      var surface = try Surface(width: 4, height: 1, depth: depth)
      for (index, alpha) in [0, 1, 2, 7].enumerated() {
        surface.setPixel(x: index, y: 0, Pixel(206 / 255, 173 / 255, 204 / 255, Float(alpha) / maximum))
      }
      let direct = try surface.rgbaData(depth: depth)
      var expected = direct
      if depth == .u16 {
        for offset in stride(from: 0, to: direct.count, by: 2) {
          expected[offset] = direct[offset + 1]
          expected[offset + 1] = direct[offset]
        }
      }
      XCTAssertEqual(try straightPNGSamples(RasterIO.encoded(surface)), expected)
    }
  }

  func testPNGImportAndNativeArchiveKeepPhotoshopStraightSamples() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/png-straight-alpha")
    for fixture in ["rgb8", "rgb16", "offset"] {
      let source = try RasterIO.read(root.appendingPathComponent("\(fixture).psd"))
      let expected = try Data(contentsOf: root.appendingPathComponent("\(fixture).rgba"))
      for interlaced in [false, true] {
        let png = try RasterIO.encoded(source, options: .init(pngInterlaced: interlaced))
        let imported = try RasterIO.read(png)
        XCTAssertEqual(imported.depth, source.depth)
        XCTAssertEqual(imported.layers.count, 1)
        let restored = try NativeArchive.decode(NativeArchive.encode(imported))
        for model in [imported, restored] {
          guard case .raster(let pixels) = try XCTUnwrap(model.layers.first).content else {
            XCTFail("Expected one editable raster layer.")
            continue
          }
          var bytes = try pixels.rgbaData(depth: model.depth)
          if model.depth == .u16 {
            for offset in stride(from: 0, to: bytes.count, by: 2) {
              let low = bytes[offset]
              bytes[offset] = bytes[offset + 1]
              bytes[offset + 1] = low
            }
          }
          XCTAssertEqual(bytes, expected, "\(fixture), Adam7 \(interlaced)")
        }
        XCTAssertEqual(try straightPNGSamples(RasterIO.encoded(restored)), expected)
      }
    }
  }

  func testGrayscalePNGKeepsGrayAndOpacityThroughOpenArchiveAndSave() throws {
    let controls: [(bits: UInt8, type: UInt8, input: [UInt8], transparent: [UInt8]?,
      saved: [UInt8], savedType: UInt8)] = [
      (2, 0, [0b11011000], nil, [255, 85, 170], 0),
      (4, 0, [0x81, 0xa0], [0, 8], [136, 0, 17, 255, 170, 255], 4),
      (8, 4, [195, 0, 113, 1, 9, 255], nil, [195, 0, 113, 1, 9, 255], 4),
      (16, 0, [0xc3, 0x81, 0x11, 0x59, 0xd4, 0xff], nil,
        [0xc3, 0x81, 0x11, 0x59, 0xd4, 0xff], 0),
      (16, 4, [0xc3, 0x81, 0, 0, 0x11, 0x59, 0, 1, 0xd4, 0xff, 255, 255], nil,
        [0xc3, 0x81, 0, 0, 0x11, 0x59, 0, 1, 0xd4, 0xff, 255, 255], 4),
    ]
    for control in controls {
      let header = PNGRestrictedStorage.number(3) + PNGRestrictedStorage.number(1)
        + Data([control.bits, control.type, 0, 0, 0])
      let pixels = try RestrictedRasterCompression.deflate(Data([0] + control.input))
      var png = PNGRestrictedStorage.signature + PNGRestrictedStorage.chunk("IHDR", header)
      if let transparent = control.transparent { png += PNGRestrictedStorage.chunk("tRNS", Data(transparent)) }
      png += PNGRestrictedStorage.chunk("IDAT", pixels) + PNGRestrictedStorage.chunk("IEND", Data())

      let source = try RasterIO.read(png)
      XCTAssertEqual(source.colorMode, .grayscale)
      XCTAssertEqual(source.depth, control.bits == 16 ? .u16 : .u8)
      XCTAssertEqual(source.profileIsUntagged, true)
      let raster = try XCTUnwrap(source.layers.first?.nativeMode)
      let saved = try NativeArchive.decode(NativeArchive.encodeChunked(source))
      XCTAssertEqual(saved.layers.first?.nativeMode, raster)
      for interlaced in [false, true] {
        let encoded = try RasterIO.encoded(saved, options: .init(pngCompression: 9, pngInterlaced: interlaced))
        XCTAssertEqual(try straightPNGSamples(encoded, colorType: control.savedType), Data(control.saved))
        XCTAssertEqual(try UntaggedOutput.hasProfile(encoded), false)
        let reopened = try RasterIO.read(encoded)
        XCTAssertEqual(reopened.layers.first?.nativeMode, raster)
      }
    }
  }

  func testGrayscalePNGPreservesItsDeclaredTransferCurve() throws {
    let header = PNGRestrictedStorage.number(3) + PNGRestrictedStorage.number(1)
      + Data([8, 0, 0, 0, 0])
    let pixels = try RestrictedRasterCompression.deflate(Data([0, 83, 127, 200]))
    var profiles = Set<Data>()
    for storedGamma in [45_455, 60_000, 100_000] {
      let png = PNGRestrictedStorage.signature
        + PNGRestrictedStorage.chunk("IHDR", header)
        + PNGRestrictedStorage.chunk("gAMA", PNGRestrictedStorage.number(storedGamma))
        + PNGRestrictedStorage.chunk("IDAT", pixels)
        + PNGRestrictedStorage.chunk("IEND", Data())
      let expected = try XCTUnwrap(image(png).colorSpace?.copyICCData()) as Data
      let source = try RasterIO.read(png)
      XCTAssertEqual(source.modeDescriptor?.profile, expected)
      XCTAssertEqual(source.sourceICC, expected)
      XCTAssertNil(source.profileIsUntagged)
      profiles.insert(expected)

      let exported = try RasterIO.encoded(source)
      XCTAssertEqual(try UntaggedOutput.hasProfile(exported), true)
      XCTAssertEqual(try straightPNGSamples(exported, colorType: 0), Data([83, 127, 200]))
      let reloaded = try RasterIO.read(exported)
      XCTAssertEqual(reloaded.modeDescriptor?.profile, expected)
    }
    XCTAssertEqual(profiles.count, 3)
  }

  func testPhotoshopGrayscalePNGMatchesLayeredNormalSamples() throws {
    // Digests cover the independently decoded network-order samples of four
    // Photoshop 27.2.0 Save a Copy controls made from this owned layer stack.
    let captures: [(PixelDepth, Bool, String)] = [
      (.u8, true, "91ab665bb16769839a3515252004406ec740fd48ec07f02d4ad43b7cac540a9f"),
      (.u8, false, "56f3228751a665f48d2ff36f81355c3ac09dec87432b4d3f5732e38b8f6b5420"),
      (.u16, true, "c26e1b74df7b07dd8d4a6af235b91588d903e950b658695dc66011c06f17af07"),
      (.u16, false, "5e0fc9ada4dd822d1f6874189b87bac952fc1802af37e8099e0468b4d6f7b4de"),
    ]
    let width = 64, height = 32
    for (depth, opaqueBase, expected) in captures {
      let profile = try ColorSettings().profile(.grayscale, depth: depth)
      let maximum: UInt32 = depth == .u8 ? 255 : 65_535
      var document = try CraftDocument(width: width, height: height, depth: depth)
      document.modeDescriptor = try .init(mode: .grayscale, depth: depth, profile: profile)
      document.layers = try [255, 149, 217].enumerated().map { stage, opacity in
        let builder = try NativeModeRaster.RowBuilder(width: width, height: height, mode: .grayscale,
          depth: depth, profile: profile)
        for y in 0..<height {
          let gray = (0..<width).map { x -> UInt32 in
            UInt32((y * width + x) * (511 + stage * 149) + 113 + stage * 17) & maximum
          }
          let alpha = (0..<width).map { x -> UInt32 in
            if opaqueBase && stage == 0 { return maximum }
            if x % (stage + 3) == 0 { return 0 }
            return UInt32((y * width + x) * (989 + stage * 201) + 137 + stage * 34) & maximum
          }
          try builder.appendRow(gray, component: 0)
          try builder.appendRow(alpha, component: 1)
        }
        let native = try builder.finish()
        var layer = Layer(name: "Gray layer \(stage + 1)", content: .raster(try native.surface()))
        layer.nativeMode = native
        layer.opacity = Float(opacity) / 255
        return layer
      }
      document.activeLayerID = document.layers.last?.id
      document.resolution = 300
      let reopened = try RasterIO.read(PSDCodec.writeRasterLayers(document))
      XCTAssertEqual(reopened.layers.count, 3)
      for interlaced in [false, true] {
        let png = try RasterIO.encoded(reopened, options: .init(pngInterlaced: interlaced))
        let words = try straightPNGSamples(png, colorType: opaqueBase ? 0 : 4)
        let actual = SHA256.hash(data: words).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actual, expected, "\(depth), opaque base: \(opaqueBase), Adam7: \(interlaced)")
      }
    }
  }

  private func straightPNGSamples(_ png: Data, colorType: UInt8 = 6) throws -> Data {
    let blocks = try PNGRestrictedStorage.chunks(png)
    let header = try XCTUnwrap(blocks.first).data
    let width = PNGRestrictedStorage.integer(header, 0)
    let height = PNGRestrictedStorage.integer(header, 4)
    XCTAssertEqual(header[9], colorType)
    XCTAssertTrue([8, 16].contains(header[8]))
    let channels = colorType == 6 ? 4 : colorType == 4 ? 2 : 1
    let pixelBytes = Int(header[8]) / 8 * channels
    let passes = PNGRestrictedStorage.passes(header[12] == 1)
      .filter { width > $0.0 && height > $0.1 }
    let size = passes.reduce(0) { total, pass in
      let (x, y, dx, dy) = pass
      return total + (((width - x + dx - 1) / dx) * pixelBytes + 1) * ((height - y + dy - 1) / dy)
    }
    let packed = blocks.filter { $0.type == "IDAT" }.reduce(into: Data()) { $0.append($1.data) }
    let data = try RestrictedRasterCompression.inflate(packed, limit: size, expected: size)
    var result = Data(count: width * height * pixelBytes)
    var offset = 0
    for (x, y, dx, dy) in passes {
      let columns = (width - x + dx - 1) / dx
      let rowBytes = columns * pixelBytes
      var previous = [UInt8](repeating: 0, count: rowBytes)
      for row in stride(from: y, to: height, by: dy) {
        let filter = data[offset]
        XCTAssertLessThanOrEqual(filter, 4)
        var restored = Array(data[offset + 1..<offset + 1 + rowBytes])
        offset += rowBytes + 1
        for index in restored.indices {
          let left = index < pixelBytes ? 0 : restored[index - pixelBytes]
          let upperLeft = index < pixelBytes ? 0 : previous[index - pixelBytes]
          switch filter {
          case 1: restored[index] &+= left
          case 2: restored[index] &+= previous[index]
          case 3: restored[index] &+= UInt8((Int(left) + Int(previous[index])) / 2)
          case 4: restored[index] &+= PNGRestrictedStorage.paeth(left, previous[index], upperLeft)
          default: break
          }
        }
        for column in 0..<columns {
          let destination = (row * width + x + column * dx) * pixelBytes
          let sample = column * pixelBytes
          result.replaceSubrange(destination..<destination + pixelBytes, with: restored[sample..<sample + pixelBytes])
        }
        previous = restored
      }
    }
    return result
  }

  func testTIFFCompressionTagsDepthAndSamplesMatchUnmodifiedEncoder() throws {
    for depth in [PixelDepth.u8, .u16] {
      let model = try fixture(depth), baseline = try RasterIO.encoded(model, type: .tiff)
      for compression in RasterEncodingOptions.TIFFCompression.allCases {
        let bytes = try RasterIO.encoded(model, type: .tiff, options: .init(tiffCompression: compression))
        XCTAssertEqual(try samples(bytes), try samples(baseline))
        XCTAssertEqual(try image(bytes).bitsPerComponent, depth == .u8 ? 8 : 16)
        XCTAssertEqual((try properties(bytes)[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFCompression] as? Int, compression.tag)
      }
      XCTAssertEqual(try RasterIO.encoded(model, type: .tiff, options: .init()), baseline)
    }
  }
  func chunks(_ data: Data) throws -> [(String, Data)] {
    var offset = 8, result: [(String, Data)] = []
    while offset < data.count {
      let count = data[offset..<(offset+4)].reduce(0) { ($0 << 8) | Int($1) }
      let type = String(decoding: data[(offset+4)..<(offset+8)], as: UTF8.self)
      result.append((type, Data(data[(offset+8)..<(offset+8+count)])))
      offset += count + 12
    }
    return result
  }
  func chunk(_ type: String, _ data: Data) -> Data {
    func be(_ x: UInt32) -> Data { var v = x.bigEndian; return withUnsafeBytes(of: &v) { Data($0) } }
    let body = Data(type.utf8) + data
    let crc = body.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) }
    return be(UInt32(data.count)) + body + be(UInt32(crc))
  }
  func testFragmentedIDATAndAncillaryChunksArePreserved() throws {
    let baseline = try RasterIO.encoded(fixture(.u16), options: .init(pngInterlaced: true))
    let pieces = try chunks(baseline)
    var fragmented = Data(baseline.prefix(8))
    let note = Data("Photato test\0independent original fixture".utf8)
    for (type, bytes) in pieces {
      if type == "IDAT" {
        fragmented.append(chunk(type, Data()))
        for i in stride(from: 0, to: bytes.count, by: 2) {
          fragmented.append(chunk(type, Data(bytes[i..<min(bytes.count, i+2)])))
        }
      } else {
        if type == "IEND" { fragmented.append(chunk("tEXt", note)) }
        fragmented.append(chunk(type, bytes))
      }
    }
    let output = try PNGCompression.rewrite(fragmented, level: 9)
    XCTAssertEqual(try samples(output), try samples(baseline))
    let before = try chunks(fragmented).filter { $0.0 != "IDAT" }.map { chunk($0.0, $0.1) }
    let after = try chunks(output).filter { $0.0 != "IDAT" }.map { chunk($0.0, $0.1) }
    XCTAssertEqual(before, after)
  }
  func testInvalidOptionsDamagedStreamsAndWrongGeometryReject() throws {
    let original = try RasterIO.encoded(fixture())
    for level in [-1, 10] { XCTAssertThrowsError(try PNGCompression.rewrite(original, level: level)) }
    var damaged = original; damaged[20] ^= 1
    XCTAssertThrowsError(try PNGCompression.rewrite(damaged, level: 5))
    XCTAssertThrowsError(try PNGCompression.rewrite(Data(original.dropLast()), level: 5))
    var rebuilt = Data(original.prefix(8))
    for (type, value) in try chunks(original) {
      var bytes = value
      if type == "IHDR" { bytes[3] += 1 }
      rebuilt.append(chunk(type, bytes))
    }
    XCTAssertThrowsError(try PNGCompression.rewrite(rebuilt, level: 5))
    XCTAssertThrowsError(try RasterIO.encoded(fixture(), type: .jpeg, options: .init(pngCompression: 4)))
    XCTAssertThrowsError(try RasterIO.encoded(fixture(), options: .init(tiffCompression: .zip)))
    XCTAssertThrowsError(try RasterIO.encoded(fixture(), options: .init(pngCompression: 10)))
  }
  func testCancelledRecompressionReturnsNoOutput() async throws {
    let bytes = try RasterIO.encoded(fixture())
    let task = Task {
      while !Task.isCancelled { await Task.yield() }
      return try PNGCompression.rewrite(bytes, level: 9)
    }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled compression returned data") }
    catch { XCTAssertTrue(error is CancellationError) }
  }
}
