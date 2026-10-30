import Foundation
import XCTest
import UniformTypeIdentifiers
import PhotoCraftCore
@testable import PhotoCraftImaging

final class RestrictedModeInputTests: XCTestCase {
  func testIndexedFlatteningIsExplicitAndUndoRestoresHiddenLayers() throws {
    var document = try CraftDocument(width: 4, height: 2)
    var hidden = Layer(name: "Hidden source", content: .raster(try Surface(width: 4, height: 2, fill: .black))); hidden.visible = false
    document.layers.append(hidden)
    var settings = IndexedColorSettings(); settings.palette = .exact; settings.forced = .none
    XCTAssertTrue(RestrictedModeInput.needsMerge(document))
    XCTAssertThrowsError(try RestrictedModeInput.indexed(settings, in: document))
    var session = EditorSession(document: document)
    let command = try RestrictedModeInput.indexed(settings, in: document, mergeVisible: true)
    try session.execute(command)
    XCTAssertEqual(session.document.colorMode, .indexed); XCTAssertEqual(session.document.layers.count, 1)
    XCTAssertEqual(try Renderer.composite(session.document).pixel(x: 0, y: 0), .white)
    try session.undo(); XCTAssertEqual(session.document, document)
    try session.redo(); XCTAssertThrowsError(try session.execute(command))
  }
  func testBitmapResolutionAndThresholdUseGrayPlaneAndOneHistoryStep() throws {
    var document = try CraftDocument(width: 2, height: 1).convertingMode(.init(mode: .grayscale, depth: .u8))
    let id = try XCTUnwrap(document.activeLayerID)
    var channel = try document.modeChannel(layerID: id, component: 0)
    channel.setPixel(x: 0, y: 0, Pixel(0.49, 0.49, 0.49)); channel.setPixel(x: 1, y: 0, Pixel(0.51, 0.51, 0.51))
    try Command.modeChannel(.init(layerID: id, component: 0, pixels: channel)).apply(to: &document)
    document.resolution = 100
    var settings = BitmapConversionSettings(); settings.method = .threshold; settings.outputResolution = 100
    var session = EditorSession(document: document)
    try session.execute(RestrictedModeInput.bitmap(settings, in: document))
    guard case .bitmap(let raster) = session.document.restrictedMode else { return XCTFail() }
    XCTAssertEqual(raster.bits, Data([0x80])); XCTAssertEqual(session.undoStack.count, 1)
    try session.undo(); XCTAssertEqual(session.document, document)
    settings.outputResolution = 200
    try session.execute(RestrictedModeInput.bitmap(settings, in: document))
    XCTAssertEqual(session.document.width, 4); XCTAssertEqual(session.document.height, 2)
    XCTAssertEqual(session.document.pixelsPerInch, 200); XCTAssertEqual(session.document.bitsPerChannel, 1)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(session.document)), session.document)
    try session.undo(); XCTAssertEqual(session.document, document)
  }
  func testPrerequisitesOutputBoundsAndUnsupportedInterchangeReject() throws {
    let rgb = try CraftDocument(width: 9, height: 1)
    var bitmap = BitmapConversionSettings(); bitmap.outputResolution = 72
    XCTAssertThrowsError(try RestrictedModeInput.bitmap(bitmap, in: rgb))
    XCTAssertThrowsError(try RestrictedModeInput.indexed(.init(), in: rgb.convertingMode(.init(mode: .rgb, depth: .u16))))
    let gray = try rgb.convertingMode(.init(mode: .grayscale, depth: .u8))
    bitmap.outputResolution = 9600
    let big = try CraftDocument(width: 3000, height: 1).convertingMode(.init(mode: .grayscale, depth: .u8))
    XCTAssertThrowsError(try RestrictedModeInput.bitmap(bitmap, in: big))
    bitmap.outputResolution = 72
    var converted = gray; try RestrictedModeInput.bitmap(bitmap, in: gray).apply(to: &converted)
    XCTAssertEqual(try RasterIO.read(RasterIO.encoded(converted, type: .png)).restrictedMode, converted.restrictedMode)
    XCTAssertEqual(try RasterIO.read(RasterIO.encoded(converted, type: .tiff)).restrictedMode, converted.restrictedMode)
    XCTAssertEqual(try PSDCodec.read(PSDCodec.writeRasterLayers(converted)).restrictedMode, converted.restrictedMode)
  }
  func testSharedColorTableCommandRetainsIndicesAndHistory() throws {
    let r = try IndexedRaster(width: 2, height: 1, palette: [.init(255, 0, 0), .init(255, 0, 0)], indices: Data([1, 0]))
    let document = try CraftDocument(width: 2, height: 1).replacingRestrictedMode(.indexed(r))
    var session = EditorSession(document: document)
    try session.execute(RestrictedModeInput.colorTable([.init(255, 0, 0), .init(0, 0, 255)], transparentIndex: nil, in: document))
    let rendered = try Renderer.composite(session.document)
    XCTAssertEqual(rendered.pixel(x: 0, y: 0), Pixel(0, 0, 1)); XCTAssertEqual(rendered.pixel(x: 1, y: 0), Pixel(1, 0, 0))
    try session.undo(); XCTAssertEqual(session.document, document)
  }
}
