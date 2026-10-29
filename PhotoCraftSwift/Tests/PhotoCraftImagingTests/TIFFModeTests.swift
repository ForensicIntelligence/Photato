import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFModeTests: XCTestCase {
  func testNativeRGBUsesAuthoritativeSamplesAndGrayHDRSpansPredictedStrips() throws {
    for depth in PixelDepth.allCases {
      let original = try PSDModeTests().fixture(.rgb, depth)
      let bytes = try RasterIO.encoded(original, type: .tiff,
        options: .init(tiffCompression: .zip, tiffPixelOrder: .perChannel, tiffPredictor: depth == .f32))
      try PSDModeTests().assertPlanes(RasterIO.read(bytes), original)
    }
    var n = try NativeModeRaster(width: 257, height: 73, mode: .grayscale, depth: .f32)
    for i in 0..<257 * 73 {
      try n.set(Float(i % 43) * 0.125 - 1, component: 0, index: i)
      try n.set(Float(i % 5) / 4, component: 1, index: i)
    }
    var document = try CraftDocument(width: 257, height: 73, depth: .f32)
    document.modeDescriptor = try .init(mode: .grayscale, depth: .f32, profile: n.profile)
    document.layers[0].content = .raster(try n.surface()); document.layers[0].nativeMode = n
    for order in RasterEncodingOptions.TIFFByteOrder.allCases {
      for layout in RasterEncodingOptions.TIFFPixelOrder.allCases {
        let bytes = try RasterIO.encoded(document, type: .tiff,
          options: .init(tiffCompression: .lzw, tiffByteOrder: order, tiffPixelOrder: layout, tiffPredictor: true))
        XCTAssertLessThan(try TIFFContainer(bytes, metadata: false).scalar(278), 73)
        XCTAssertEqual(try RasterIO.read(bytes).layers[0].nativeMode?.planes, n.planes)
      }
    }
  }
  func testModeDepthByteOrderLayoutAndCompressionPreserveComponents() throws {
    for mode in [DocumentColorMode.grayscale, .cmyk, .lab] { for depth in mode.depths {
      var document = try PSDModeTests().fixture(mode, depth); document.resolution = 144
      let original = try XCTUnwrap(document.layers[0].nativeMode)
      for order in RasterEncodingOptions.TIFFByteOrder.allCases {
        for layout in RasterEncodingOptions.TIFFPixelOrder.allCases {
          for compression in RasterEncodingOptions.TIFFCompression.allCases {
            let options = RasterEncodingOptions(tiffCompression: compression, tiffByteOrder: order,
              tiffPixelOrder: layout, tiffPredictor: depth == .f32 && compression != .none)
            let bytes = try RasterIO.encoded(document, type: .tiff, options: options)
            let file = try TIFFContainer(bytes, metadata: true), read = try RasterIO.read(bytes)
            let actual = try XCTUnwrap(read.layers[0].nativeMode)
            XCTAssertEqual(actual.mode, mode); XCTAssertEqual(actual.depth, depth)
            XCTAssertEqual(actual.profile, original.profile); XCTAssertEqual(read.pixelsPerInch, 144)
            XCTAssertEqual(try file.scalar(277), mode.componentCount + 1)
            XCTAssertEqual(try file.scalar(338), 2)
            if mode == .lab && depth == .u16 {
              for c in 0...3 { for i in 0..<12 {
                XCTAssertEqual(actual.value(component: c, index: i), original.value(component: c, index: i), accuracy: 1.01 / 65535)
              } }
            } else { XCTAssertEqual(actual.planes, original.planes) }
          }
        }
      }
      XCTAssertEqual(document.layers[0].nativeMode, original)
    } }
  }
  func testLayeredModesRetainExactPlanesGroupsAndMasksAcrossEndianAndCompression() throws {
    for mode in [DocumentColorMode.grayscale, .cmyk, .lab] { for depth in mode.depths {
      var document = try PSDModeTests().fixture(mode, depth)
      let group = Layer(name: "Native group", content: .group(.init()))
      document.layers[0].parentID = group.id
      document.layers[0].mask = try Surface(width: 4, height: 3, depth: depth, fill: Pixel(depth.quantize(0.5), depth.quantize(0.5), depth.quantize(0.5), 1))
      document.layers.append(group)
      for order in RasterEncodingOptions.TIFFByteOrder.allCases {
        for compression in RasterEncodingOptions.TIFFLayerCompression.allCases {
          let bytes = try RasterIO.encoded(document, type: .tiff,
            options: .init(tiffCompression: .zip, tiffByteOrder: order,
              tiffPixelOrder: .perChannel, tiffLayers: true, tiffLayerCompression: compression))
          let result = try RasterIO.read(bytes)
          let layer = try XCTUnwrap(result.layers.first { $0.nativeMode != nil })
          XCTAssertEqual(layer.nativeMode, document.layers[0].nativeMode)
          XCTAssertEqual(result.layers.first { $0.id == layer.parentID }?.name, group.name)
          let mask = try XCTUnwrap(layer.mask), source = try XCTUnwrap(document.layers[0].mask)
          for y in 0..<3 { for x in 0..<4 { XCTAssertEqual(mask.pixel(x: x, y: y), source.pixel(x: x, y: y)) } }
        }
      }
    } }
  }
  // Literal little-endian TIFF fixture: fields and samples are independent of
  // the production serializers and color sample mapping helpers.
  func literal(photo: Int, bits: Int = 8, channels: Int, samples: [UInt8], extra: Int? = nil,
    orientation: Int = 1, format: Int = 1) -> Data {
    func le(_ value: Int, _ n: Int) -> [UInt8] { (0..<n).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
    var fields: [(Int, Int, [Int])] = [(256, 4, [2]), (257, 4, [1]), (258, 3, [bits]),
      (259, 3, [1]), (262, 3, [photo]), (273, 4, [8]), (274, 3, [orientation]),
      (277, 3, [channels]), (278, 4, [1]), (279, 4, [samples.count]), (284, 3, [1]), (339, 3, [format])]
    if let extra { fields.append((338, 3, [extra])) }
    fields.sort { $0.0 < $1.0 }
    let start = 8 + samples.count + samples.count % 2
    var bytes: [UInt8] = [73, 73, 42, 0] + le(start, 4) + samples
    if bytes.count % 2 != 0 { bytes.append(0) }
    bytes += le(fields.count, 2)
    for (tag, type, values) in fields {
      let value = le(values[0], type == 3 ? 2 : 4)
      bytes += le(tag, 2) + le(type, 2) + le(1, 4) + value + Array(repeating: 0, count: 4 - value.count)
    }
    bytes += [0, 0, 0, 0]; return Data(bytes)
  }
  func testLiteralInkGrayAndLabEncodingsAndOrientation() throws {
    let cmyk = try RasterIO.read(literal(photo: 5, channels: 5, samples: [0, 255, 128, 64, 0, 255, 0, 64, 128, 255], extra: 2))
    XCTAssertEqual(cmyk.layers[0].nativeMode?.planes, [Data([0, 255]), Data([255, 0]), Data([128, 64]), Data([64, 128]), Data([0, 255])])
    let white = try RasterIO.read(literal(photo: 0, channels: 1, samples: [0, 255], orientation: 6))
    XCTAssertEqual(white.width, 1); XCTAssertEqual(white.height, 2)
    XCTAssertEqual(white.layers[0].nativeMode?.planes, [Data([255, 0]), Data([255, 255])])
    let lab8 = try RasterIO.read(literal(photo: 8, channels: 3, samples: [64, 128, 127, 192, 0, 255]))
    XCTAssertEqual(lab8.layers[0].nativeMode?.planes, [Data([64, 192]), Data([0, 128]), Data([255, 127]), Data([255, 255])])
    let lab16 = try RasterIO.read(literal(photo: 8, bits: 16, channels: 3,
      samples: [0, 0, 0, 128, 0, 127, 255, 255, 0, 0, 0, 255]))
    let n = try XCTUnwrap(lab16.layers[0].nativeMode)
    XCTAssertEqual(n.value(component: 0, index: 1), 1)
    XCTAssertEqual(n.value(component: 1, index: 0), 0)
    XCTAssertEqual(n.value(component: 2, index: 0), 1)
    XCTAssertEqual(n.value(component: 1, index: 1), Float(128) / 255, accuracy: 1 / 65535)
    XCTAssertEqual(n.value(component: 2, index: 1), Float(127) / 255, accuracy: 1 / 65535)
    let icc = try RasterIO.read(literal(photo: 9, bits: 16, channels: 3,
      samples: [0, 255, 0, 128, 0, 128, 0, 0, 0, 0, 0, 255]))
    XCTAssertEqual(icc.layers[0].nativeMode?.value(component: 0, index: 0), 1)
    XCTAssertEqual(icc.layers[0].nativeMode?.value(component: 1, index: 0), Float(128) / 255)
  }
  func testAssociatedAlphaAndFloatHDR() throws {
    let gray = try RasterIO.read(literal(photo: 1, channels: 2, samples: [64, 128, 17, 0], extra: 1))
    XCTAssertEqual(gray.layers[0].nativeMode?.planes, [Data([128, 0]), Data([128, 0])])
    let hdr = try RasterIO.read(literal(photo: 1, bits: 32, channels: 1,
      samples: [0, 0, 32, 64, 0, 0, 128, 190], format: 3))
    XCTAssertEqual(hdr.layers[0].nativeMode?.value(component: 0, index: 0), 2.5)
    XCTAssertEqual(hdr.layers[0].nativeMode?.value(component: 0, index: 1), -0.25)
  }
  func testMalformedModeSamplesRejectWithoutRGBFallback() throws {
    XCTAssertThrowsError(try RasterIO.read(literal(photo: 5, channels: 3, samples: [0, 0, 0, 0, 0, 0])))
    XCTAssertThrowsError(try RasterIO.read(literal(photo: 1, channels: 2, samples: [0, 0, 0, 0], extra: 0)))
    XCTAssertThrowsError(try RasterIO.read(literal(photo: 1, bits: 32, channels: 1,
      samples: [0, 0, 192, 127, 0, 0, 0, 0], format: 3)))
    XCTAssertThrowsError(try RasterIO.read(literal(photo: 8, channels: 3, samples: [0, 0])))
    XCTAssertThrowsError(try RasterIO.read(literal(photo: 1, channels: 1, samples: [0, 255], orientation: 9)))
  }
  func testMetadataAndSingleSurfaceExportDoNotSubstituteDocumentPixels() throws {
    var document = try PSDModeTests().fixture(.cmyk, .u16)
    document.sourceMetadata = try RasterIO.read(MetadataPreservationTests().source()).sourceMetadata
    let data = try RasterIO.encoded(document, type: .tiff)
    let result = try RasterIO.read(data)
    XCTAssertTrue(String(decoding: try XCTUnwrap(RasterMetadata.xmpData(result.sourceMetadata)), as: UTF8.self).contains("original-value"))
    let properties = try MetadataPreservationTests().properties(data)
    XCTAssertEqual((properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifFNumber] as? Double, 2.8)
    let empty = try Surface(width: 4, height: 3, depth: .u16)
    let rendered = try RasterIO.read(RasterIO.encoded(empty, type: .tiff, workingDocument: document))
    XCTAssertNotEqual(rendered.layers[0].nativeMode?.planes, document.layers[0].nativeMode?.planes)
    XCTAssertEqual(rendered.layers[0].nativeMode?.value(component: 4, index: 0), 0)
  }
  func testEmitNativeTIFFsForIndependentReaders() throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_TIFF_MODE_EVIDENCE_DIR"] else { return }
    let folder = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var cases: [[String: Any]] = []
    for mode in [DocumentColorMode.grayscale, .cmyk, .lab] { for depth in mode.depths {
      let document = try PSDModeTests().fixture(mode, depth), native = try XCTUnwrap(document.layers[0].nativeMode)
      for layered in [false, true] {
        let name = "\(mode.rawValue)-\(native.bytesPerSample * 8)-\(layered).tiff"
        let bytes = try RasterIO.encoded(document, type: .tiff, options: .init(tiffCompression: .zip,
          tiffByteOrder: .bigEndian, tiffPixelOrder: .perChannel, tiffPredictor: depth == .f32,
          tiffLayers: layered))
        try bytes.write(to: folder.appendingPathComponent(name))
        cases.append(["file": name, "mode": mode.rawValue, "depth": native.bytesPerSample * 8,
          "width": native.width, "height": native.height, "layered": layered,
          "nativePlanesBase64": native.planes.map { $0.base64EncodedString() }])
      }
    } }
    try JSONSerialization.data(withJSONObject: cases, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("expected.json"))
  }
}
