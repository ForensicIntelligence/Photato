import Foundation
import XCTest
@testable import PhotoCraftCore

final class QuickMaskSemanticsTests: XCTestCase {
  func options(_ indication: ChannelDisplayOptions.Indicates) -> ChannelDisplayOptions {
    var value = ChannelDisplayOptions(); value.indicates = indication; return value
  }
  func testExplicitFullSelectionSurvivesEntryAndExitAtEveryDepth() throws {
    for depth in PixelDepth.allCases { for indication in ChannelDisplayOptions.Indicates.allCases {
      var d = try CraftDocument(width: 8, height: 8, depth: depth)
      d.selection = .init(x: 0, y: 0, width: 8, height: 8)
      let before = d
      try Command.channel(.quickMask(true, options(indication))).apply(to: &d)
      XCTAssertEqual(d.quickMask?.psdQuickMaskInitiallyEmpty, false)
      XCTAssertTrue(try XCTUnwrap(d.quickMask).selection().isFullCoverage)
      try Command.channel(.quickMask(false, options(indication))).apply(to: &d)
      XCTAssertEqual(d.selection, before.selection)
      XCTAssertTrue(try XCTUnwrap(d.coverageSelection()).isFullCoverage)
      XCTAssertEqual(d.layers, before.layers)
    } }
  }
  func testNoSelectionStartsWithoutOverlayForEitherIndication() throws {
    for depth in PixelDepth.allCases { for indication in ChannelDisplayOptions.Indicates.allCases {
      var d = try CraftDocument(width: 8, height: 8, depth: depth)
      let before = d
      try Command.channel(.quickMask(true, options(indication))).apply(to: &d)
      let mask = try XCTUnwrap(d.quickMask)
      XCTAssertEqual(mask.psdQuickMaskInitiallyEmpty, true)
      let expected: Float = indication == .maskedAreas ? 1 : 0
      for y in 0..<8 { for x in 0..<8 {
        let value = mask.pixels.pixel(x: x, y: y).r
        XCTAssertEqual(value, expected)
        XCTAssertEqual(mask.options.overlay(value), 0)
        XCTAssertEqual(mask.display(value), 1)
      } }
      try Command.channel(.quickMask(false, options(indication))).apply(to: &d)
      XCTAssertNil(try d.coverageSelection()); XCTAssertEqual(d.layers, before.layers)
    } }
  }
  func testChangingIndicationPreservesCoverageAndCanProduceExplicitFullSelection() throws {
    var d = try CraftDocument(width: 8, height: 8)
    try Command.channel(.quickMask(true, options(.maskedAreas))).apply(to: &d)
    let plane = try XCTUnwrap(d.quickMask).pixels
    try Command.channel(.options(.quickMask, options(.selectedAreas))).apply(to: &d)
    XCTAssertEqual(d.quickMask?.pixels, plane)
    XCTAssertEqual(d.quickMask?.psdQuickMaskInitiallyEmpty, true)
    try Command.channel(.quickMask(false, options(.selectedAreas))).apply(to: &d)
    XCTAssertTrue(try XCTUnwrap(d.coverageSelection()).isFullCoverage)
  }
  func testSelectedAreaBlackFillProducesFullSelectionFromInitiallyEmptyAndPartial() throws {
    for partial in [false, true] {
      var d = try CraftDocument(width: 8, height: 8)
      if partial { d.selection = .init(x: 0, y: 0, width: 5, height: 8) }
      let before = d.layers
      try Command.channel(.quickMask(true, options(.selectedAreas))).apply(to: &d)
      try Command.channel(.fill(.quickMask, 0, 1)).apply(to: &d)
      XCTAssertTrue(try XCTUnwrap(d.quickMask).selection().isFullCoverage)
      try Command.channel(.quickMask(false, options(.selectedAreas))).apply(to: &d)
      XCTAssertTrue(try XCTUnwrap(d.coverageSelection()).isFullCoverage)
      XCTAssertEqual(d.layers, before)
    }
  }
  func testLegacyMissingOriginKeepsItsExistingFullExitPolicy() throws {
    for indication in ChannelDisplayOptions.Indicates.allCases {
      var d = try CraftDocument(width: 8, height: 8)
      d.quickMask = AlphaChannel(name: "Legacy Quick Mask", pixels: try Surface(width: 8, height: 8, fill: .white), options: options(indication))
      XCTAssertNil(d.quickMask?.psdQuickMaskInitiallyEmpty)
      try Command.channel(.quickMask(false, options(indication))).apply(to: &d)
      XCTAssertNil(try d.coverageSelection())
    }
  }
  func testHistoryAndNativeContainersPreserveEntryOriginAndFullExit() throws {
    var d = try CraftDocument(width: 8, height: 8)
    d.selection = .init(x: 0, y: 0, width: 8, height: 8)
    var session = EditorSession(document: d)
    try session.execute(.channel(.quickMask(true, options(.selectedAreas))))
    let active = session.document
    XCTAssertEqual(active.quickMask?.psdQuickMaskInitiallyEmpty, false)
    for bytes in [try NativeArchive.encode(active), try NativeArchive.encodeChunked(active)] {
      XCTAssertEqual(try NativeArchive.decode(bytes), active)
    }
    try session.execute(.channel(.quickMask(false, options(.selectedAreas))))
    let exited = session.document
    XCTAssertEqual(exited.selection, d.selection)
    try session.undo(); XCTAssertEqual(session.document, active)
    try session.undo(); XCTAssertEqual(session.document, d)
    try session.redo(); XCTAssertEqual(session.document, active)
    try session.redo(); XCTAssertEqual(session.document, exited)
  }
  func retainedModel() throws -> CraftDocument {
    var d = try CraftDocument(width: 8, height: 8, depth: .f32)
    var gray = try Surface(width: 8, height: 8, depth: .f32, fill: Pixel(0.1234567, 0.1234567, 0.1234567))
    gray.setPixel(x: 2, y: 3, Pixel(-0.0, -0.0, -0.0))
    let coverage = try gray.mappedStoredSamples { p in let v: Float = 1 - p.r; return Pixel(v, v, v) }
    var channel = AlphaChannel(name: "Selected area", pixels: coverage, options: options(.selectedAreas))
    channel.psdSelectedGray = gray; d.alphaChannels = [channel]; return d
  }
  func testRetainedSelectedGrayUsesNative91AndCountsItsMemory() throws {
    let d = try retainedModel(), channel = try XCTUnwrap(d.alphaChannels?.first)
    var plain = d; plain.alphaChannels?[0].psdSelectedGray = nil
    XCTAssertEqual(d.minimumArchiveVersion, 91)
    XCTAssertEqual(d.estimatedBytes - plain.estimatedBytes, channel.psdSelectedGray?.allocatedBytes)
    for bytes in [try NativeArchive.encode(d), try NativeArchive.encodeChunked(d)] {
      let restored = try NativeArchive.decode(bytes)
      XCTAssertEqual(restored, d)
      XCTAssertEqual(restored.alphaChannels?[0].psdSelectedGray?.pixel(x: 2, y: 3).r.bitPattern, Float(-0.0).bitPattern)
      var lower = bytes; lower[8] = 90
      XCTAssertThrowsError(try NativeArchive.decode(lower))
    }
  }
  func testRetainedGrayGeometryDepthConversionAndInvalidStateAreAtomic() throws {
    let original = try retainedModel(), channel = try XCTUnwrap(original.alphaChannels?.first)
    for depth in PixelDepth.allCases {
      let changed = try channel.convertedCoverage(to: depth)
      if depth == .f32 { XCTAssertEqual(changed.psdSelectedGray, channel.psdSelectedGray) }
      else { XCTAssertNil(changed.psdSelectedGray) }
    }
    var d = original
    try Command.crop(.init(x: 1, y: 1, width: 4, height: 4)).apply(to: &d)
    XCTAssertEqual(d.alphaChannels?.first?.psdSelectedGray?.width, 4)
    XCTAssertEqual(d.alphaChannels?.first?.psdSelectedGray?.pixel(x: 1, y: 2).r.bitPattern, Float(-0.0).bitPattern)
    try d.validate()
    var invalid = original; invalid.alphaChannels?[0].spot = SpotInk()
    XCTAssertThrowsError(try invalid.validate())
    invalid = original; invalid.alphaChannels?[0].psdSelectedGray = try Surface(width: 1, height: 1, depth: .f32)
    XCTAssertThrowsError(try invalid.validate())
    XCTAssertEqual(original, try NativeArchive.decode(NativeArchive.encode(original)))
  }
  func testSparseMaximumGeometryRetainsNoSelectionAndExplicitFullSemantics() throws {
    for depth in PixelDepth.allCases { for indication in ChannelDisplayOptions.Indicates.allCases { for full in [false, true] {
      var d = try CraftDocument(width: 300_000, height: 300_000, depth: depth)
      if full { d.selection = .init(x: 0, y: 0, width: d.width, height: d.height) }
      try Command.channel(.quickMask(true, options(indication))).apply(to: &d)
      XCTAssertEqual(d.quickMask?.psdQuickMaskInitiallyEmpty, !full)
      XCTAssertEqual(d.quickMask?.pixels.tileCount, 0)
      XCTAssertLessThanOrEqual(try XCTUnwrap(d.quickMask).pixels.allocatedBytes, 1024)
      try Command.channel(.quickMask(false, options(indication))).apply(to: &d)
      if full { XCTAssertEqual(d.selection, .init(x: 0, y: 0, width: 300_000, height: 300_000)) }
      else { XCTAssertNil(try d.coverageSelection()) }
    } } }
  }
}
