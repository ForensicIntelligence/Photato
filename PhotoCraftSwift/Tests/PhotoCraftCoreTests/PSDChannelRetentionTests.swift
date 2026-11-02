import Foundation
import XCTest
@testable import PhotoCraftCore

final class PSDChannelRetentionTests:XCTestCase {
  func document()throws->CraftDocument {
    var d=try CraftDocument(width:8,height:8,depth:.f32)
    var gray=try Surface(width:8,height:8,depth:.f32,fill:Pixel(0.1234567,0.1234567,0.1234567))
    gray.setPixel(x:2,y:3,Pixel(-0.0,-0.0,-0.0))
    let density=try gray.mappedStoredSamples{p in let v=1-p.r;return Pixel(v,v,v)}
    var channel=AlphaChannel(name:"Ink",pixels:density,spot:SpotInk());channel.psdSpotGray=gray;channel.psdIdentifier=73
    channel.psdDisplay=Data(repeating:0,count:13);channel.psdDisplay?[12]=2
    d.alphaChannels=[channel];return d
  }
  func testFloatGrayBitsMetadataAndNative77SurviveHistoryAndBothContainers()throws {
    let original=try document();XCTAssertEqual(original.minimumArchiveVersion,77)
    for archive in [try NativeArchive.encode(original),try NativeArchive.encodeChunked(original)] {
      let restored=try NativeArchive.decode(archive);XCTAssertEqual(restored,original)
      XCTAssertEqual(restored.alphaChannels?[0].psdSpotGray?.pixel(x:2,y:3).r.bitPattern,Float(-0.0).bitPattern)
    }
    var session=EditorSession(document:original);let channel=try XCTUnwrap(original.alphaChannels?.first)
    try session.execute(.channel(.configure(channel.id,"Ink",channel.options,SpotInk(color:Pixel(0,1,1),solidity:1))))
    XCTAssertEqual(session.document.alphaChannels?.first?.psdSpotGray,channel.psdSpotGray)
    try session.undo();XCTAssertEqual(session.document,original)
  }
  func testDuplicateAndGeometryKeepDataWithoutDuplicateExternalIDs()throws {
    var session=EditorSession(document:try document());let channel=try XCTUnwrap(session.document.alphaChannels?.first)
    try session.execute(.channel(.duplicate(channel.id,nil)));XCTAssertNil(session.document.alphaChannels?.last?.psdIdentifier)
    XCTAssertEqual(session.document.alphaChannels?.last?.psdSpotGray,channel.psdSpotGray)
    try session.execute(.crop(.init(x:1,y:1,width:4,height:4)))
    for channel in session.document.alphaChannels ?? [] {XCTAssertEqual(channel.psdSpotGray?.width,4);XCTAssertEqual(channel.psdSpotGray?.height,4)}
    try session.document.validate()
  }
  func testInvalidRetentionAndDuplicateIdentifiersRejectAtomically()throws {
    let original=try document();var invalid=original
    invalid.alphaChannels?[0].psdDisplay=Data([1]);XCTAssertThrowsError(try invalid.validate())
    invalid=original;var copy=try XCTUnwrap(original.alphaChannels?.first);copy.id=UUID();invalid.alphaChannels?.append(copy)
    XCTAssertThrowsError(try invalid.validate())
    invalid=original;invalid.alphaChannels?[0].spot=nil;XCTAssertThrowsError(try invalid.validate())
    invalid=original;invalid.alphaChannels?[0].psdSpotGray=try Surface(width:1,height:1,depth:.f32);XCTAssertThrowsError(try invalid.validate())
    XCTAssertEqual(original,try NativeArchive.decode(NativeArchive.encode(original)))
  }
  func testDepthConversionsInvalidateOnlyTheOldGrayDomain()throws {
    let original=try document(),source=try XCTUnwrap(original.alphaChannels?.first)
    for depth in PixelDepth.allCases {
      let channel=try source.convertedCoverage(to:depth)
      XCTAssertEqual(channel.pixels.depth,depth);XCTAssertEqual(channel.psdIdentifier,source.psdIdentifier);XCTAssertEqual(channel.psdDisplay,source.psdDisplay)
      if depth == .f32 {XCTAssertEqual(channel.psdSpotGray,source.psdSpotGray)}else{XCTAssertNil(channel.psdSpotGray)}
      try channel.validate(width:8,height:8,depth:depth)
      var ink=original;try ink.convertAuxiliaryChannelDepth(to:depth)
      XCTAssertEqual(ink.alphaChannels?.first,channel)
    }
  }
  func testSpotToAlphaDropsOnlyInapplicableSourceGray()throws {
    var d=try document();let channel=try XCTUnwrap(d.alphaChannels?.first)
    try Command.channel(.configure(channel.id,"Mask",channel.options,nil)).apply(to:&d)
    XCTAssertNil(d.alphaChannels?.first?.psdSpotGray);XCTAssertEqual(d.alphaChannels?.first?.psdIdentifier,73)
    XCTAssertEqual(d.alphaChannels?.first?.psdDisplay,channel.psdDisplay);XCTAssertEqual(d.minimumArchiveVersion,77)
  }
}
