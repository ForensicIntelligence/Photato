import XCTest
@testable import PhotoCraftCore

final class SpotChannelTests:XCTestCase {
  func testSelectionCreationPaintingPrecisionAndNative76History()throws {
    for depth in PixelDepth.allCases {
      var original=try CraftDocument(width:16,height:12,depth:depth);original.selection = .init(x:3,y:3,width:8,height:6)
      var session=EditorSession(document:original)
      let ink=SpotInk(color:Pixel(0.125,0.625,0.875),solidity:0.375)
      let channel=try original.newSpotChannel(name:"Varnish Ω",ink:ink)
      try session.execute(.channel(.create(channel)));XCTAssertEqual(session.document.minimumArchiveVersion,76)
      XCTAssertEqual(channel.pixels.pixel(x:4,y:4).r,1);XCTAssertEqual(channel.pixels.pixel(x:0,y:0).r,0)
      try session.execute(.channel(.fill(.alpha(channel.id),1,1)))
      XCTAssertEqual(session.document.alphaChannels?.first?.pixels.pixel(x:4,y:4).r,0)
      var brush=Brush();brush.size=3;brush.hardness=1;brush.color = .black
      try session.execute(.channel(.stroke(.alpha(channel.id),[.init(x:6,y:6)],brush)))
      XCTAssertEqual(session.document.alphaChannels?.first?.pixels.pixel(x:6,y:6).r,1)
      XCTAssertEqual(session.document.layers,original.layers)
      let saved=session.document;XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(saved)),saved)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(saved)),saved)
      try session.undo();try session.redo();XCTAssertEqual(session.document,saved)
    }
  }
  func testConversionsPreserveEditingGrayAndSolidityNeverChangesSeparation()throws {
    for depth in PixelDepth.allCases {
      var d=try CraftDocument(width:8,height:6,depth:depth)
      let alpha=AlphaChannel(name:"Mask",pixels:try Surface(width:8,height:6,depth:depth,fill:Pixel(0.25,0.25,0.25)))
      try Command.channel(.create(alpha)).apply(to:&d);let gray=alpha.display(alpha.pixels.pixel(x:0,y:0).r)
      try Command.channel(.configure(alpha.id,"Ink",alpha.options,SpotInk(color:Pixel(0,1,1),solidity:0))).apply(to:&d)
      let spot=try d.channel(.alpha(alpha.id));XCTAssertEqual(spot.pixels.depth,depth)
      XCTAssertEqual(spot.display(spot.pixels.pixel(x:0,y:0).r),gray,accuracy:1/65535)
      let pixels=spot.pixels
      try Command.channel(.configure(alpha.id,"Ink",alpha.options,SpotInk(color:Pixel(0,1,1),solidity:1))).apply(to:&d)
      XCTAssertEqual(try d.channel(.alpha(alpha.id)).pixels,pixels)
      try Command.channel(.configure(alpha.id,"Mask",alpha.options,nil)).apply(to:&d)
      XCTAssertEqual(try d.channel(.alpha(alpha.id)).pixels,alpha.pixels);XCTAssertEqual(d.minimumArchiveVersion,20)
    }
  }
  func testModernBrushAndEraserUseSpotEditingGray()throws {
    var d=try CraftDocument(width:32,height:24)
    let channel=try d.newSpotChannel(name:"Ink",ink:SpotInk());try Command.channel(.create(channel)).apply(to:&d)
    var brush=Brush();brush.size=5;brush.hardness=1;brush.color = .black
    let request=PaintToolRequest(tool:.brush,target:.channel(.alpha(channel.id)),points:[.init(x:10,y:10)],brush:brush)
    d=try PaintingEdit.prepare(request,in:d).result
    XCTAssertEqual(try d.channel(.alpha(channel.id)).pixels.pixel(x:10,y:10).r,1)
    brush.color = .white
    let erase=PaintToolRequest(tool:.brush,target:.channel(.alpha(channel.id)),points:[.init(x:10,y:10)],brush:brush)
    d=try PaintingEdit.prepare(erase,in:d).result
    XCTAssertEqual(try d.channel(.alpha(channel.id)).pixels.pixel(x:10,y:10).r,0)
  }
  func testInvalidOptionsQuickMaskAndLegacyDecodingAreAtomic()throws {
    var session=EditorSession(document:try CraftDocument(width:8,height:8));let channel=try session.document.newSpotChannel(name:"Ink",ink:SpotInk())
    try session.execute(.channel(.create(channel)));let before=session.document
    XCTAssertThrowsError(try session.execute(.channel(.configure(channel.id,"",channel.options,SpotInk(solidity:2)))))
    XCTAssertEqual(session.document,before)
    var invalid=before;invalid.quickMask=channel;invalid.alphaChannels=nil;XCTAssertThrowsError(try invalid.validate())
    let old=AlphaChannel(name:"Old",pixels:try Surface(width:8,height:8))
    let bytes=try JSONEncoder().encode(old);var object=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes)as?[String:Any]);object.removeValue(forKey:"spot")
    XCTAssertNil(try JSONDecoder().decode(AlphaChannel.self,from:JSONSerialization.data(withJSONObject:object)).spot)
    XCTAssertThrowsError(try SpotInk(color:Pixel(.nan,0,0)).validate())
  }
}
