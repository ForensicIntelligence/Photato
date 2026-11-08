import XCTest
@testable import PhotoCraftCore

final class AlphaChannelTests: XCTestCase {
  func fixture(_ depth: PixelDepth) throws -> CraftDocument {
    var d = try CraftDocument(width:12,height:8,depth:depth)
    d.selection = .init(x:2,y:2,width:6,height:4); return d
  }
  func testSaveLoadCombineNative20AndHistoryAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      let original = try fixture(depth); var session = EditorSession(document:original)
      try session.execute(.channel(.saveSelection(nil,"Subject",.replace)))
      let channel = try XCTUnwrap(session.document.alphaChannels?.first); XCTAssertEqual(channel.name,"Subject"); XCTAssertEqual(channel.pixels.depth,depth)
      XCTAssertEqual(channel.pixels.pixel(x:3,y:3).r,1); XCTAssertEqual(channel.pixels.pixel(x:0,y:0).r,0)
      let saved = session.document; XCTAssertEqual(saved.minimumArchiveVersion,20)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(saved)),saved)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(saved)),saved)
      try session.undo(); XCTAssertEqual(session.document,original); try session.redo(); XCTAssertEqual(session.document,saved)
      try session.execute(.selection(nil)); try session.execute(.channel(.load(.alpha(channel.id),.replace,false)))
      XCTAssertEqual(session.document.selection,original.selection)
      try session.execute(.channel(.load(.alpha(channel.id),.subtract,false))); XCTAssertNil(session.document.selection)
      try session.execute(.channel(.duplicate(channel.id,nil))); XCTAssertEqual(session.document.alphaChannels?.count,2)
      let copy = try XCTUnwrap(session.document.alphaChannels?.last); XCTAssertNotEqual(copy.id,channel.id)
      try session.execute(.channel(.move(copy.id,0))); XCTAssertEqual(session.document.alphaChannels?.first?.id,copy.id)
      try session.execute(.channel(.rename(copy.id,"Copy"))); XCTAssertEqual(session.document.alphaChannels?.first?.name,"Copy")
      try session.execute(.channel(.delete(copy.id))); XCTAssertEqual(session.document.alphaChannels?.count,1)
    }
  }
  func testQuickMaskBrushEraseOptionsExitAndUndo() throws {
    var session = EditorSession(document:try fixture(.u8)); let original = session.document
    try session.execute(.channel(.quickMask(true,.init()))); XCTAssertNil(session.document.selection)
    XCTAssertEqual(session.document.quickMask?.pixels.pixel(x:3,y:3).r,1)
    var brush = Brush(); brush.size = 3; brush.hardness = 1; brush.color = .black
    try session.execute(.channel(.stroke(.quickMask,[.init(x:4,y:4)],brush)))
    XCTAssertEqual(session.document.quickMask?.pixels.pixel(x:4,y:4).r,0)
    brush.erase = true; brush.backgroundColor = .white
    try session.execute(.channel(.stroke(.quickMask,[.init(x:4,y:4)],brush)))
    XCTAssertEqual(session.document.quickMask?.pixels.pixel(x:4,y:4).r,1)
    var options = ChannelDisplayOptions(); options.indicates = .selectedAreas; options.opacity = 0.3
    let old = session.document.quickMask?.pixels
    try session.execute(.channel(.options(.quickMask,options))); XCTAssertEqual(session.document.quickMask?.pixels,old)
    try session.execute(.channel(.fill(.quickMask,0,1))); XCTAssertEqual(session.document.quickMask?.pixels.pixel(x:0,y:0).r,1)
    let beforeExit = session.document
    // Photoshop selected-area black Fill preserves an explicit full selection; see the independent Quick Mask fixtures.
    try session.execute(.channel(.quickMask(false,options))); XCTAssertEqual(session.document.selection,IntRect(x:0,y:0,width:12,height:8)); XCTAssertTrue(try XCTUnwrap(session.document.coverageSelection()).isFullCoverage); XCTAssertNil(session.document.quickMask)
    try session.undo(); XCTAssertEqual(session.document,beforeExit)
    XCTAssertEqual(session.document.layers,original.layers)
  }
  func testGrayscalePrecisionFiltersSelectionAndCanvasGeometry() throws {
    var d = try fixture(.f32); d.selection = nil
    var pixels = try Surface(width:12,height:8,depth:.f32,fill:.black); pixels.setPixel(x:4,y:3,Pixel(0.1234567,0.1234567,0.1234567))
    let channel = AlphaChannel(name:"Precision",pixels:pixels)
    try Command.channel(.create(channel)).apply(to:&d)
    XCTAssertEqual(d.alphaChannels?.first?.pixels.pixel(x:4,y:3).r,0.1234567)
    try Command.crop(.init(x:2,y:1,width:8,height:6)).apply(to:&d)
    XCTAssertEqual(d.alphaChannels?.first?.pixels.pixel(x:2,y:2).r,0.1234567)
    try Command.rotateCanvas(.clockwise).apply(to:&d)
    XCTAssertEqual(d.alphaChannels?.first?.pixels.width,6); XCTAssertEqual(d.alphaChannels?.first?.pixels.height,8)
    let before = d.layers
    var filter = RasterFilter(.gaussianBlur); filter.radius = 1
    try Command.channel(.filter(.alpha(channel.id),filter)).apply(to:&d)
    XCTAssertEqual(d.layers,before); XCTAssertGreaterThan(d.alphaChannels!.first!.pixels.pixel(x:3,y:2).r,0)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
  }
  func testInvalidChannelAndFailedCommandAreAtomic() throws {
    let d = try fixture(.u16); var session = EditorSession(document:d)
    XCTAssertThrowsError(try session.execute(.channel(.create(AlphaChannel(name:"Bad",pixels:Surface(width:1,height:1))))))
    XCTAssertThrowsError(try session.execute(.channel(.load(.alpha(UUID()),.replace,false))))
    XCTAssertEqual(session.document,d); XCTAssertTrue(session.undoStack.isEmpty)
    var options = ChannelDisplayOptions(); options.opacity = .nan; XCTAssertThrowsError(try options.validate())
    try session.execute(.selection(nil)); try session.execute(.channel(.quickMask(true,.init())))
    XCTAssertEqual(session.document.quickMask?.pixels.defaultPixel,.white)
    try session.execute(.channel(.quickMask(false,.init()))); XCTAssertNil(session.document.selection)
  }
}
