import XCTest
@testable import PhotoCraftCore

final class LayerContentClassificationTests: XCTestCase {
  func testSurfaceRawAlphaSparseMaximumAndExplicitTransparentTilePaddingAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var huge = try Surface(width: 300000, height: 300000, depth: depth)
      XCTAssertFalse(try huge.hasPixelContent())
      let alpha: Float = depth == .f32 ? Float(bitPattern: 1) : depth == .u16 ? 1 / 65535 : 1 / 255
      huge.setPixel(x: 299999, y: 299999, Pixel(1, 0, 0, alpha))
      XCTAssertTrue(try huge.hasPixelContent()); XCTAssertLessThan(huge.allocatedBytes + huge.residentTileIndexEstimate, 200000)
      huge.setPixel(x: 299999, y: 299999, .clear); XCTAssertFalse(try huge.hasPixelContent())
      var filled = try Surface(width: 65, height: 3, depth: depth, fill: .white)
      XCTAssertTrue(try filled.hasPixelContent())
      for y in 0..<3 { for x in 0..<65 { filled.setPixel(x: x, y: y, .clear) } }
      XCTAssertFalse(try filled.hasPixelContent(), "Padding outside the raster is not content.")
      let store = try RasterTileStore(maximumBytes: 1_000_000)
      let mapped = try filled.spillingTiles(to: store)
      XCTAssertFalse(try mapped.hasPixelContent()); XCTAssertEqual(mapped, filled)
    }
  }
  func testNativeRawAlphaAcrossAllModesDepthsPreservesEveryPlaneByte() throws {
    for mode in [DocumentColorMode.rgb, .grayscale, .cmyk, .lab] {
      for depth in mode.depths {
        var native = try NativeModeRaster(width: 2, height: 3, mode: mode, depth: depth)
        XCTAssertFalse(try native.hasAlphaContent())
        let tiny: Float = depth == .f32 ? Float(bitPattern: 1) : depth == .u16 ? 1 / 65535 : 1 / 255
        try native.set(tiny, component: mode.componentCount, index: 5)
        let bytes = try native.planes
        XCTAssertTrue(try native.hasAlphaContent()); XCTAssertEqual(try native.planes, bytes)
        try native.set(-Float.zero, component: mode.componentCount, index: 5)
        XCTAssertFalse(try native.hasAlphaContent())
      }
    }
  }
  func testComponentSignedZeroSubnormalMappedBlocksAndImplicitPositiveDefault() throws {
    var p = try ComponentPlane(width: 300000, height: 300000, depth: .f32, defaultWord: 0x80000000)
    XCTAssertFalse(try p.containsPositiveSample())
    try p.setWord(1, at: p.count - 1)
    let mapped = try p.spilling(maximumBytes: 3_000_000)
    XCTAssertTrue(try mapped.containsPositiveSample()); XCTAssertEqual(mapped.word(at: p.count - 1), 1)
    let positive = try ComponentPlane(width: 300000, height: 300000, depth: .u16, defaultWord: 1)
    XCTAssertTrue(try positive.containsPositiveSample()); XCTAssertEqual(positive.residentEditBytes, 0)
    var filled = try ComponentPlane(width: 3, height: 1, depth: .u8, defaultWord: 255)
    for i in 0..<3 { try filled.setWord(0, at: i) }
    XCTAssertFalse(try filled.containsPositiveSample())
  }
  func testOwnedPhotoshopTypeObservationsIgnoreVisibilityOpacityMasksAndLayerEffects() throws {
    var d = try CraftDocument(width: 2, height: 3)
    let transparent = try Surface(width: 2, height: 3)
    let ordinary = Layer(name: "Empty", content: .raster(transparent))
    let group = Layer(name: "Childless group", content: .group(.init()))
    var smartLayer = Layer(name: "Owned transparent cache", content: .raster(transparent))
    // The classifier inspects cached alpha, never parses/reads the inert source bytes.
    smartLayer.smartObject = try SmartObject(fileName: "owned.psd", mediaType: "image/vnd.adobe.photoshop",
      data: Data([1, 2, 3]), width: 2, height: 3)
    var filled = Layer(name: "Pixels", content: .raster(try Surface(width: 2, height: 3, fill: .white)))
    filled.visible = false; filled.opacity = 0; filled.mask = transparent
    filled.style = LayerStyle(effects: [LayerEffect(.dropShadow)])
    d.layers = [ordinary, group, smartLayer, filled]; d.activeLayerID = filled.id
    let snapshot = d
    XCTAssertEqual(try LayerContentSource(d).emptyLayerIDs(), [ordinary.id, smartLayer.id])
    XCTAssertEqual(d, snapshot)
  }
  func testCancellationStopsTheReadOnlyQueryBeforeScanning() async throws {
    let p = try ComponentPlane(width: 300000, height: 300000, depth: .u8)
    let worker = Task { withUnsafeCurrentTask { $0?.cancel() }; return try p.containsPositiveSample() }
    worker.cancel()
    do { _ = try await worker.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("\(error)") }
    XCTAssertEqual(p.residentEditBytes, 0)
  }
}
