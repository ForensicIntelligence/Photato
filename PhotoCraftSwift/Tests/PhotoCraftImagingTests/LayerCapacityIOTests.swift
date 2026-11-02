import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class LayerCapacityIOTests: XCTestCase {
  func fixture(_ count: Int = 8000, depth: PixelDepth = .u8, groups: Bool = false) throws -> CraftDocument {
    var d = try CraftDocument(width: 2, height: 1, depth: depth)
    let s = try Surface(width: 2, height: 1, depth: depth, fill: Pixel(1, 0, 0))
    d.layers = (0..<count).map { Layer(name: "Layer \($0)", content: groups ? .group(GroupContent()) : .raster(s)) }
    d.activeLayerID = d.layers.last?.id; return d
  }
  func capture(_ data: Data, _ name: String) throws {
    if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let dir = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try data.write(to: dir.appendingPathComponent(name))
    }
  }
  func testNativeArchive8000LayersEveryDepthPreservesModel() throws {
    for depth in PixelDepth.allCases {
      let d = try fixture(depth: depth), bytes = try NativeArchive.encodeChunked(d)
      XCTAssertEqual(try NativeArchive.decode(bytes), d)
    }
  }
  func testPSDAndPSB8000RasterLayersPreserveOrderNamesAndPixels() throws {
    let d = try fixture()
    for format: PSDFileFormat in [.psd, .psb] {
      let bytes = try PSDCodec.writeRasterLayers(d, compression: .raw, format: format)
      let read = try PSDCodec.read(bytes)
      XCTAssertEqual(read.layers.count, 8000); XCTAssertEqual(read.layers.map(\.name), d.layers.map(\.name))
      for layer in read.layers { guard case .raster(let s) = layer.content else { return XCTFail("Raster") }; XCTAssertEqual(s.pixel(x: 0, y: 0), Pixel(1, 0, 0)); XCTAssertEqual(s.pixel(x: 1, y: 0), Pixel(1, 0, 0)) }
      try capture(bytes, "capacity-8000-raster.\(format == .psd ? "psd" : "psb")")
    }
  }
  func testPSDPSB8000GroupsUse16000PhysicalRecordsWithoutDroppingGroups() throws {
    let d = try fixture(groups: true)
    for format: PSDFileFormat in [.psd, .psb] {
      let bytes = try PSDCodec.writeRasterLayers(d, compression: .raw, format: format)
      let read = try PSDCodec.read(bytes)
      XCTAssertEqual(read.layers.count, 8000); XCTAssertTrue(read.layers.allSatisfy(\.isGroup))
      XCTAssertEqual(read.layers.map(\.name), d.layers.map(\.name))
      try capture(bytes, "capacity-8000-groups.\(format == .psd ? "psd" : "psb")")
    }
  }
  func testProjectLimitsRetainIndependentManifestSurfaceAndByteBudgets() throws {
    var limits = PcraftProject.Limits(); limits.layers = 8000; limits.surfaces = 16001
    XCTAssertNoThrow(try limits.validate()); limits.layers = 8001; XCTAssertThrowsError(try limits.validate())
    limits.layers = 8000; limits.manifestBytes = 16 * 1024 * 1024 + 1; XCTAssertThrowsError(try limits.validate())
  }
}
