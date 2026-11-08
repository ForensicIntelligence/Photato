import Foundation
import XCTest
@testable import PhotoCraftCore

final class MagicWandSamplingTests: XCTestCase {
  func testAllSevenSizesSelectKnownAverageTargetsExactly() throws {
    let width = 103, height = 103
    var pixels = [SIMD4<UInt8>](repeating:SIMD4(96,96,96,255),count:width*height)
    pixels[51*width+51] = SIMD4(160,160,160,255)
    for (y,value) in [103,99,97].enumerated() { pixels[y*width] = SIMD4(UInt8(value),UInt8(value),UInt8(value),255) }
    let targets = [1:160,3:103,5:99,11:97,31:96,51:96,101:96]
    var captured = Data()
    for size in ColorSampleSettings.sizes {
      var options = ColorMatchOptions(); options.sampleSize = size
      options.tolerance = 0; options.antiAlias = false; options.contiguous = false
      let result = try ColorRegion.selection(pixels:pixels,width:width,height:height,seedX:51,seedY:51,options:options)
      let expected = pixels.map { Int($0.x) == targets[size]! ? UInt8(255):0 }
      XCTAssertEqual(try result.bytes,expected,"Sample size \(size)")
      captured.append(contentsOf: try result.bytes)
    }
    if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try captured.write(to:URL(fileURLWithPath:path).appendingPathComponent("wand-seven-sizes.mask"))
    }
  }
  func testClippedAverageCanDifferFromTheClickedPixel() throws {
    let pixels: [SIMD4<UInt8>] = [SIMD4(0,0,0,255),SIMD4(128,128,128,255),SIMD4(64,64,64,255),SIMD4(64,64,64,255)]
    var options = ColorMatchOptions(); options.sampleSize = 3
    options.tolerance = 0; options.antiAlias = false; options.contiguous = false
    let mask = try ColorRegion.selection(pixels:pixels,width:4,height:1,seedX:0,seedY:0,options:options)
    XCTAssertEqual(try mask.bytes,[0,0,255,255])
    options.contiguous = true
    XCTAssertNil(try ColorRegion.selection(pixels:pixels,width:4,height:1,seedX:0,seedY:0,options:options).bounds)
  }
  func testAverageRetainsExistingHiddenRGBAndAlphaComparisonPolicy() throws {
    let pixels: [SIMD4<UInt8>] = [SIMD4(255,0,0,0),SIMD4(0,0,255,255),SIMD4(128,0,128,128)]
    var options = ColorMatchOptions(); options.sampleSize = 3
    options.tolerance = 0; options.antiAlias = false; options.contiguous = false
    XCTAssertEqual(try ColorRegion.selection(pixels:pixels,width:3,height:1,seedX:0,seedY:0,options:options).bytes,[0,0,255])
  }
  func testContiguousAverageDoesNotCrossAnUnmatchedBarrier() throws {
    let values: [UInt8] = [0,128,128,128,255,255,128]
    let pixels = values.map { SIMD4($0,$0,$0,UInt8(255)) }
    var options = ColorMatchOptions(); options.sampleSize = 3
    options.tolerance = 43; options.antiAlias = false
    XCTAssertEqual(try ColorRegion.selection(pixels:pixels,width:7,height:1,seedX:1,seedY:0,options:options).bytes,[0,255,255,255,0,0,0])
    options.contiguous = false
    XCTAssertEqual(try ColorRegion.selection(pixels:pixels,width:7,height:1,seedX:1,seedY:0,options:options).bytes,[0,255,255,255,0,0,255])
  }
  func testAverageUsesDocumentCoordinatesAtEveryDepthAndPreservesHistory() throws {
    for depth in PixelDepth.allCases {
      var pixels = try Surface(width:4,height:1,depth:depth,fill:Pixel(64.0/255,64.0/255,64.0/255))
      pixels.setPixel(x:0,y:0,.black); pixels.setPixel(x:1,y:0,Pixel(128.0/255,128.0/255,128.0/255))
      let source = CloneSample(surface:pixels,transform:.translation(1,0))
      var options = ColorMatchOptions(); options.sampleSize = 3
      options.tolerance = 0; options.antiAlias = false; options.contiguous = false
      var document = try CraftDocument(width:6,height:1,depth:depth)
      document.layers[0].content = .raster(try Surface(width:6,height:1,depth:depth,fill:.white))
      var session = EditorSession(document:document)
      try session.execute(.magicWand(source,.init(2,0),options,.replace,false))
      XCTAssertEqual(try session.document.selectionMask?.bytes,[0,0,0,255,255,0])
      XCTAssertEqual(session.document.layers,document.layers)
      let after = session.document; try session.undo(); XCTAssertEqual(session.document,document)
      try session.redo(); XCTAssertEqual(session.document,after)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(after)),after)
    }
  }
  func testInvalidSizesAndCancellationDoNotPublishSelections() async throws {
    for size in [0,2,7,100,102,Int.max] {
      var options = ColorMatchOptions(); options.sampleSize = size
      XCTAssertThrowsError(try options.validate())
    }
    let source = CloneSample(surface:try Surface(width:4,height:1,fill:.white))
    let original = try CraftDocument(width:4,height:1)
    await Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      var document = original, options = ColorMatchOptions(); options.sampleSize = 101
      do { try Command.magicWand(source,.init(0,0),options,.replace,false).apply(to:&document); XCTFail("Cancelled selection committed") }
      catch is CancellationError {} catch { XCTFail("\(error)") }
      XCTAssertEqual(document,original)
    }.value
  }
}
