import XCTest
@testable import PhotoCraftCore

final class ChannelOnlyDocumentTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:8,height:4,depth:depth)
    d.setCoverageSelection(try SelectionMask(width:8,height:4,bytes:Array(repeating:[0,32,64,96,128,160,224,255],count:4).flatMap{$0}))
    return d
  }
  func testStandaloneAllDepthsPreserveSourceAndNative85()throws {
    for depth in PixelDepth.allCases {
      let source=try fixture(depth),result=try source.selectionDocument(channelName:"Subject 日本語")
      XCTAssertTrue(result.isChannelOnly);XCTAssertEqual(result.colorMode,.multichannel);XCTAssertTrue(result.layers.isEmpty);XCTAssertNil(result.activeLayerID)
      XCTAssertEqual(result.minimumArchiveVersion,85);XCTAssertEqual(result.alphaChannels?.first?.name,"Subject 日本語")
      XCTAssertEqual(try result.alphaChannels?.first?.selection().denseBytes(),try source.coverageSelection()?.denseBytes())
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(result)),result)
      XCTAssertNil(source.channelOnly);XCTAssertEqual(source.layers.count,1)
    }
  }
  func testMaximumCanvasSelectionDocumentRetainsSparseStorageAndNative85()throws {
    var source=try CraftDocument(width:300000,height:300000)
    source.selection = .init(x:0,y:0,width:300000,height:300000)
    let result=try source.selectionDocument(),channel=try XCTUnwrap(result.alphaChannels?.first)
    XCTAssertEqual(channel.pixels.pixel(x:299999,y:299999).r,1);XCTAssertLessThan(channel.pixels.allocatedBytes,100000)
    let data=try NativeArchive.encodeChunked(result);XCTAssertLessThan(data.count,100000)
    XCTAssertEqual(try NativeArchive.decode(data),result)
  }
  func testInvalidStandaloneStateAndUnsupportedConversionRemainAtomic()throws {
    let result=try fixture().selectionDocument();var session=EditorSession(document:result)
    XCTAssertThrowsError(try session.execute(.newPixelLayer(.init(name:"Invalid image layer"))))
    XCTAssertThrowsError(try session.execute(.channel(.delete(try XCTUnwrap(result.alphaChannels?.first?.id)))))
    XCTAssertEqual(session.document,result);XCTAssertTrue(session.undoStack.isEmpty)
    var invalid=result;invalid.channelOnly=nil;XCTAssertFalse(invalid.isChannelOnly)
    XCTAssertThrowsError(try result.convertingMode(.init(mode:.rgb,depth:.u8)))
    var noSelection=try fixture();noSelection.setCoverageSelection(nil);XCTAssertThrowsError(try noSelection.selectionDocument())
    try Command.channel(.quickMask(true,.init())).apply(to:&noSelection);XCTAssertThrowsError(try noSelection.selectionDocument())
  }
  func testChannelOnlyPaintingFillQuickMaskAndUndoRetainNoImageLayers()throws {
    let original=try fixture().selectionDocument();var session=EditorSession(document:original);let id=try XCTUnwrap(original.alphaChannels?.first?.id)
    try session.execute(.channel(.fill(.alpha(id),0.25,1)))
    XCTAssertTrue(session.document.layers.isEmpty);XCTAssertEqual(session.document.alphaChannels?.first?.pixels.pixel(x:0,y:0).r,64/255)
    try session.undo();XCTAssertEqual(session.document,original)
    try session.execute(.channel(.load(.alpha(id),.replace,false)))
    try session.execute(.channel(.quickMask(true,.init())))
    try session.execute(.channel(.quickMask(false,.init())))
    XCTAssertTrue(session.document.isChannelOnly);XCTAssertTrue(session.document.layers.isEmpty)
  }
  func testPreparedChannelSelectionClassificationCannotAuthorizeRGBChanges()throws {
    let source=try fixture(),loaded=try PreparedEdit(command:.channel(.loadCoverage(try XCTUnwrap(source.coverageSelection()),.replace)),document:source)
    XCTAssertTrue(loaded.isSelectionOnly);XCTAssertTrue(loaded.isChannelOnlyEdit)
    let saved=try PreparedEdit(command:.channel(.saveSelection(nil,"Saved",.replace)),document:source)
    XCTAssertFalse(saved.isSelectionOnly);XCTAssertTrue(saved.isChannelOnlyEdit)
    let image=try PreparedEdit(command:.fill(try XCTUnwrap(source.activeLayerID),.black),document:source)
    XCTAssertFalse(image.isSelectionOnly);XCTAssertFalse(image.isChannelOnlyEdit)
  }
}
