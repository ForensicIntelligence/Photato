import CoreGraphics
import Foundation
import XCTest
@testable import PhotoCraftCore

final class DocumentModeTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var document = try CraftDocument(width: 4, height: 3, depth: .u16)
    var pixels = try Surface(width: 4, height: 3, depth: .u16)
    for y in 0..<3 { for x in 0..<4 { pixels.setPixel(x: x, y: y, Pixel(Float(x + 1) / 5, Float(y + 1) / 4, 0.65, Float(x) / 3)) } }
    document.layers[0].content = .raster(pixels)
    return document
  }
  func testModeConversionNativeArchiveVersionsAndUndoRestoreEveryPlane() throws {
    let original = try fixture()
    for mode in DocumentColorMode.componentModes {
      var session = EditorSession(document: original)
      try session.execute(.documentMode(.init(mode: mode, depth: .u16)))
      let converted = session.document
      XCTAssertEqual(converted.colorMode, mode); XCTAssertEqual(converted.minimumArchiveVersion, 46)
      XCTAssertEqual(converted.layers[0].nativeMode?.planes.count, mode.componentCount + 1)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(converted)), converted)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(converted)), converted)
      try session.undo(); XCTAssertEqual(session.document, original)
      try session.redo(); XCTAssertEqual(session.document, converted)
    }
    XCTAssertNil(try NativeArchive.decode(NativeArchive.encode(original)).modeDescriptor)
  }
  func testOrdinaryEditingPreservesUntouchedInkAndNativeChannelUndo() throws {
    var session = EditorSession(document: try fixture())
    try session.execute(.documentMode(.init(mode: .cmyk, depth: .u16)))
    let id = try XCTUnwrap(session.document.activeLayerID)
    var black = try session.document.modeChannel(layerID: id, component: 3)
    black.setPixel(x: 0, y: 0, Pixel(0.7, 0.7, 0.7))
    try session.execute(.modeChannel(.init(layerID: id, component: 3, pixels: black)))
    let before = try XCTUnwrap(session.document.layers[0].nativeMode)
    try session.execute(.selection(IntRect(x: 1, y: 1, width: 1, height: 1)))
    try session.execute(.fill(id, Pixel(0.3, 0.8, 0.9)))
    let after = try XCTUnwrap(session.document.layers[0].nativeMode)
    for i in 0..<12 where i != 5 { XCTAssertEqual(after.components(index: i), before.components(index: i)) }
    XCTAssertNotEqual(after.components(index: 5), before.components(index: 5))
    try session.undo(); XCTAssertEqual(session.document.layers[0].nativeMode, before)
    try session.execute(.opacity(id, 0.5))
    XCTAssertEqual(session.document.layers[0].nativeMode, before)
  }
  func testGeometryUsesNativeComponentsWithoutReseparatingBlack() throws {
    var document = try fixture().convertingMode(.init(mode: .cmyk, depth: .u16))
    let id = try XCTUnwrap(document.activeLayerID)
    var black = try document.modeChannel(layerID: id, component: 3)
    black.setPixel(x: 3, y: 2, Pixel(0.8, 0.8, 0.8))
    try Command.modeChannel(.init(layerID: id, component: 3, pixels: black)).apply(to: &document)
    let source = try XCTUnwrap(document.layers[0].nativeMode)
    var session = EditorSession(document: document)
    try session.execute(.flip(id, true))
    let flipped = try XCTUnwrap(session.document.layers[0].nativeMode)
    for y in 0..<3 { for x in 0..<4 { XCTAssertEqual(flipped.components(index: y * 4 + x), source.components(index: y * 4 + 3 - x)) } }
    try session.undo()
    var request = CropRequest(x: 1, y: 1, width: 2, height: 2)
    request.deleteCroppedPixels = true
    let cropped = try CropGeometry.applying(request, to: document)
    XCTAssertEqual(cropped.layers[0].nativeMode, try source.cropped(to: IntRect(x: 1, y: 1, width: 2, height: 2)))
    try session.execute(.imageSize(8, 6, 72, .nearest))
    let enlarged = try XCTUnwrap(session.document.layers[0].nativeMode)
    XCTAssertEqual(enlarged.components(index: 5 * 8 + 7), source.components(index: 11))
    try session.execute(.canvasSize(10, 8, .center, .white))
    XCTAssertTrue(session.document.layers.filter { if case .raster = $0.content { return true }; return false }.allSatisfy { $0.nativeMode != nil })
  }
  func testDirectCMYKToLabConversionUsesRetainedInkRatherThanDisplayRGB() throws {
    var document = try fixture().convertingMode(.init(mode: .cmyk, depth: .u16))
    var native = try XCTUnwrap(document.layers[0].nativeMode)
    for c in 0..<5 { try native.set(c == 0 || c == 2 || c == 4 ? 1 : 0, component: c, index: 0) }
    document.layers[0].nativeMode = native; document.layers[0].content = .raster(try native.surface())
    let lab = try document.convertingMode(.init(mode: .lab, depth: .u16))
    let result = try XCTUnwrap(lab.layers[0].nativeMode)
    let sourceSpace = try XCTUnwrap(CGColorSpace(iccData: native.profile as CFData))
    let targetSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.genericLab))
    let input = try XCTUnwrap(CGColor(colorSpace: sourceSpace, components: native.components(index: 0).map { CGFloat($0) }))
    let expected = try XCTUnwrap(input.converted(to: targetSpace, intent: .relativeColorimetric, options: nil)?.components)
    XCTAssertEqual(result.value(component: 0, index: 0), PixelDepth.u16.quantize(Float(expected[0]) / 100))
    XCTAssertEqual(result.value(component: 1, index: 0), PixelDepth.u16.quantize((Float(expected[1]) + 128) / 255))
    XCTAssertEqual(result.value(component: 2, index: 0), PixelDepth.u16.quantize((Float(expected[2]) + 128) / 255))
  }
  func testSourceWorkingProfileAndDepthConversionPreserveCorrectColorCoordinates() throws {
    var document = try fixture()
    let sourceSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
    document.workingICC = try XCTUnwrap(sourceSpace.copyICCData() as Data?)
    let converted = try document.convertingMode(.init(mode: .lab, depth: .u16))
    let native = try XCTUnwrap(converted.layers[0].nativeMode)
    let targetSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.genericLab))
    guard case .raster(let pixels) = document.layers[0].content else { return XCTFail() }
    let p = pixels.pixel(x: 1, y: 1)
    let input = try XCTUnwrap(CGColor(colorSpace: sourceSpace, components: [CGFloat(p.r), CGFloat(p.g), CGFloat(p.b), CGFloat(p.a)]))
    let expected = try XCTUnwrap(input.converted(to: targetSpace, intent: .relativeColorimetric, options: nil)?.components)
    XCTAssertEqual(native.value(component: 0, index: 5), PixelDepth.u16.quantize(Float(expected[0]) / 100))
    for c in 1...2 { XCTAssertEqual(native.value(component: c, index: 5), PixelDepth.u16.quantize((Float(expected[c]) + 128) / 255)) }
    XCTAssertNil(converted.workingICC)
    let hdr = try fixture().convertingMode(.init(mode: .rgb, depth: .f32))
    XCTAssertEqual(hdr.depth, .f32)
    let lowered = try hdr.convertingMode(.init(mode: .grayscale, depth: .u8))
    XCTAssertEqual(lowered.layers[0].nativeMode?.planes.count, 2)
    XCTAssertEqual(lowered.depth, .u8)
  }
  func testInvalidModeOrChannelRequestIsAtomicAndProtectedLayersStayUnchanged() throws {
    var session = EditorSession(document: try fixture())
    let original = session.document
    XCTAssertThrowsError(try session.execute(.documentMode(.init(mode: .cmyk, depth: .f32))))
    XCTAssertEqual(session.document, original); XCTAssertTrue(session.undoStack.isEmpty)
    try session.execute(.documentMode(.init(mode: .cmyk, depth: .u16)))
    let id = try XCTUnwrap(session.document.activeLayerID)
    let channel = try session.document.modeChannel(layerID: id, component: 0)
    try session.execute(.lock(id, true))
    let locked = session.document
    XCTAssertThrowsError(try session.execute(.modeChannel(.init(layerID: id, component: 0, pixels: channel))))
    XCTAssertEqual(session.document, locked)
  }
  func testNativeArchiveRestoresAuthoritativeComponentsAndRejectsMissingPlanes() throws {
    let correct = try fixture().convertingMode(.init(mode: .lab, depth: .u16))
    var stale = correct
    stale.layers[0].content = .raster(try Surface(width: 4, height: 3, depth: .u16, fill: .black))
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(stale)), correct)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(stale)), correct)
    stale.layers[0].nativeMode = nil
    XCTAssertThrowsError(try stale.validate())
    XCTAssertThrowsError(try NativeArchive.encode(stale))
    XCTAssertThrowsError(try NativeArchive.decode(NativeArchive.encode(correct), rasterByteLimit: 0))
  }
  func testHistorySpillingRestoresNativeComponentsAndProfile() throws {
    var session = EditorSession(document: try fixture(), historyByteLimit: 0)
    let original = session.document
    try session.execute(.documentMode(.init(mode: .cmyk, depth: .u16)))
    let converted = session.document, id = try XCTUnwrap(converted.activeLayerID)
    try session.execute(.opacity(id, 0.5))
    XCTAssertGreaterThan(session.historySpilledStates, 0)
    try session.undo(); XCTAssertEqual(session.document, converted)
    try session.undo(); XCTAssertEqual(session.document, original)
    try session.redo(); XCTAssertEqual(session.document, converted)
  }
  func testLayerViaCopyRetainsInkAndMergedResultRemainsAValidModeDocument() throws {
    var document = try fixture().convertingMode(.init(mode: .cmyk, depth: .u16))
    let id = try XCTUnwrap(document.activeLayerID)
    var black = try document.modeChannel(layerID: id, component: 3)
    black.setPixel(x: 2, y: 1, Pixel(0.9, 0.9, 0.9))
    try Command.modeChannel(.init(layerID: id, component: 3, pixels: black)).apply(to: &document)
    let native = try XCTUnwrap(document.layers[0].nativeMode)
    document.selection = IntRect(x: 1, y: 1, width: 2, height: 2)
    var session = EditorSession(document: document)
    try session.execute(.layerVia(id, .copy))
    let copied = try XCTUnwrap(session.document.layers.last?.nativeMode)
    for c in 0..<4 { XCTAssertEqual(copied.value(component: c, index: 1), native.value(component: c, index: 6)) }
    try session.execute(.mergeLayers(Set(session.document.layers.map(\.id)), .selected))
    XCTAssertEqual(session.document.layers.count, 1)
    XCTAssertNoThrow(try session.document.validate())
    XCTAssertNotNil(session.document.layers[0].nativeMode)
  }
}
