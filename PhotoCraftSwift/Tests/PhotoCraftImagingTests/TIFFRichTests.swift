import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFRichTests: XCTestCase {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/tiff-rich")
  func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: root.appendingPathComponent(name))
  }
  let tags = ["levl", "curv", "hue2", "blnc", "thrs", "post", "grdm", "vmsk", "vsms",
    "levl-extension", "curv-extension"]
  func testIndependentBinaryPayloadsMatchBothDirectionsIncludingSignedAndUnicodeFields() throws {
    for name in tags {
      let tag = String(name.prefix(4))
      let big = try fixture("\(name)-big.bin"), little = try fixture("\(name)-little.bin")
      XCTAssertEqual(try TIFFLayerEndian.payload(little, tag: tag, global: false), big, name)
      XCTAssertEqual(try TIFFLayerEndian.payload(big, tag: tag, global: false, order: .big), little, name)
    }
    XCTAssertEqual(try PSDLevels.read(fixture("levl-extension-big.bin")).rgb.gamma, 1.25)
    XCTAssertEqual(try PSDCurves.read(fixture("curv-extension-big.bin")).rgb.points[1], .init(127, 115))
  }
  func check(_ d: CraftDocument) throws {
    XCTAssertEqual(d.layers.count, d.depth == .f32 ? 7 : 8)
    XCTAssertEqual(d.sourceMetadata?["psdGlobal_LMsk"],
      Data([0, 0, 4, 210, 91, 160, 221, 213, 0, 0, 0, 37, 128, 0]))
    let adjustmentTags = ["levl", "curv", "hue2", "blnc", "thrs", "post"] + (d.depth == .f32 ? [] : ["grdm"])
    for (index, tag) in adjustmentTags.enumerated() {
      XCTAssertEqual(d.layers[index + 1].sourceTags?[tag], try fixture("\(tag)-big.bin"))
    }
    guard case .adjustment(.levels(let levels)) = d.layers[1].content,
      case .adjustment(.curves(let curves)) = d.layers[2].content,
      case .adjustment(.hueSaturation(let hue)) = d.layers[3].content,
      case .adjustment(.colorBalance(let balance)) = d.layers[4].content,
      case .adjustment(.tonalSteps(let threshold)) = d.layers[5].content,
      case .adjustment(.tonalSteps(let posterize)) = d.layers[6].content
    else { return XCTFail("Rich TIFF flattened or changed layer kinds") }
    XCTAssertEqual(levels.rgb, .init(inputBlack: 17, inputWhite: 231, gamma: 1.25, outputBlack: 9, outputWhite: 244))
    XCTAssertEqual(curves.rgb.points, [.init(0, 9), .init(127, 115), .init(255, 244)])
    XCTAssertTrue(hue.colorize); XCTAssertEqual(hue.colorization, .init(hue: 37, saturation: 23, lightness: -7))
    XCTAssertEqual(hue.master, .init(hue: -15, saturation: 18, lightness: 4))
    XCTAssertEqual(balance.shadows, .init(cyanRed: -31, magentaGreen: 17, yellowBlue: 4))
    XCTAssertTrue(balance.preserveLuminosity)
    XCTAssertEqual(threshold, .init(kind: .threshold, level: 117))
    XCTAssertEqual(posterize, .init(kind: .posterize, level: 7))
    if d.depth != .f32 {
      guard case .adjustment(.gradientMap(let gradient)) = d.layers[7].content else { return XCTFail("Missing Gradient Map") }
      XCTAssertEqual(gradient.gradient.name, "Crème 🥔"); XCTAssertTrue(gradient.reverse)
      XCTAssertEqual(gradient.gradient.colors.count, 2)
      XCTAssertEqual(gradient.gradient.colors[0].midpoint, 0.37)
    }
    let vector = try XCTUnwrap(d.layers[0].vectorMask)
    XCTAssertEqual(vector.path.knotCount, 3)
    XCTAssertEqual(vector.path.components[0].knots[0].anchor, .init(0.625, 1))
  }
  func testIndependentTIFFRichLayersAndGlobalMaskSurviveNativePSDPSBAndBothTIFFOrders() throws {
    for depth in [8, 16, 32] { for order in ["big", "little"] {
      let d = try RasterIO.read(fixture("\(depth)-\(order).tiff"))
      try check(d)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)), d)
      var outputs: [(String, Data)] = []
      for format in [PSDFileFormat.psd, .psb] {
        let bytes = try PSDCodec.writeRasterLayers(d, format: format)
        let reopened = try PSDCodec.read(bytes)
        try check(reopened)
        XCTAssertEqual(reopened.layers.map(\.content), d.layers.map(\.content))
        outputs.append((format == .psd ? "psd" : "psb", bytes))
      }
      for target in RasterEncodingOptions.TIFFByteOrder.allCases {
        let bytes = try RasterIO.encoded(d, type: .tiff,
          options: .init(tiffByteOrder: target, tiffLayers: true, tiffLayerCompression: .zip))
        let reopened = try RasterIO.read(bytes)
        try check(reopened)
        XCTAssertEqual(reopened.layers.map(\.content), d.layers.map(\.content))
        XCTAssertEqual(reopened.layers.map(\.vectorMask), d.layers.map(\.vectorMask))
        outputs.append(("\(target.rawValue).tiff", bytes))
      }
      if let folder = ProcessInfo.processInfo.environment["PHOTATO_TIFF_RICH_OUTPUT_DIR"] {
        for (suffix, bytes) in outputs {
          try bytes.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(depth)-\(order).\(suffix)"))
        }
      }
    } }
  }
  func testTruncatedInvalidAndUnqualifiedRichRecordsReject() throws {
    for name in tags {
      let bytes = try fixture("\(name)-little.bin"), tag = String(name.prefix(4))
      for size in [0, 1, bytes.count / 2] {
        XCTAssertThrowsError(try TIFFLayerEndian.payload(Data(bytes.prefix(size)), tag: tag, global: false), name)
      }
    }
    var vector = try fixture("vmsk-little.bin")
    vector[8] = 255
    XCTAssertThrowsError(try TIFFLayerEndian.payload(vector, tag: "vmsk", global: false))
    var curves = try fixture("curv-little.bin")
    curves[7] = 255; curves[8] = 255
    XCTAssertThrowsError(try TIFFLayerEndian.payload(curves, tag: "curv", global: false))
    var gradient = try fixture("grdm-little.bin")
    gradient.replaceSubrange(8..<12, with: Data(repeating: 255, count: 4))
    XCTAssertThrowsError(try TIFFLayerEndian.payload(gradient, tag: "grdm", global: false))
    for tag in ["SoCo", "GdFl", "PtFl", "pths", "shmd", "Patt"] {
      XCTAssertThrowsError(try TIFFLayerEndian.payload(Data(repeating: 0, count: 16), tag: tag, global: false))
    }
    var unsupported = try RasterIO.read(fixture("32-little.tiff"))
    unsupported.layers.append(try RasterIO.read(fixture("16-little.tiff")).layers[7])
    XCTAssertThrowsError(try RasterIO.encoded(unsupported, type: .tiff, options: .init(tiffLayers: true)))
    var model = try CraftDocument(width: 2, height: 2)
    for bytes in [Data(), Data(repeating: 0, count: 14), Data(repeating: 128, count: 17)] {
      model.sourceMetadata = ["psdGlobal_LMsk": bytes]
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(model))
    }
  }
  func testCancelledVectorConversionDoesNotPublishBytes() async throws {
    let bytes = try fixture("vmsk-little.bin")
    let task = Task {
      while !Task.isCancelled { await Task.yield() }
      return try TIFFLayerEndian.payload(bytes, tag: "vmsk", global: false)
    }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled conversion returned bytes") }
    catch { XCTAssertTrue(error is CancellationError) }
  }
}
