import Foundation
import CryptoKit
import XCTest
@testable import PhotoCraftCore

final class ChannelFilterCapacityTests:XCTestCase {
  var folder:URL {URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/large-channel-filters")}
  func fixture(_ depth:PixelDepth,target:LegacyChannelFilterCaptureTests.Target,width:Int=300_000,height:Int=300_000)throws->(CraftDocument,ChannelPlaneTarget) {
    var d=try CraftDocument(width:width,height:height,depth:depth)
    var options=ChannelDisplayOptions();options.indicates = .selectedAreas;options.opacity=0.37
    var value=AlphaChannel(name:"Owned large \(target.rawValue)",pixels:try Surface(width:width,height:height,depth:depth,fill:.black),options:options,spot:target == .spot ? SpotInk(color:Pixel(0.8,0.2,0.6),solidity:0.43):nil)
    value.psdIdentifier=42
    if target == .spot && depth == .f32 {value.psdSpotGray=try Surface(width:width,height:height,depth:depth,fill:.white)}
    if target == .quickMask {d.quickMask=value;return(d,.quickMask)}
    d.alphaChannels=[value];return(d,.alpha(value.id))
  }
  func testAll288SmallProgramsRetainEveryFrozenSampleBit() throws {
    let expected=try Data(contentsOf:folder.appendingPathComponent("legacy-small.f32")),cases=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("legacy-cases.json")))as?[[String:Any]])
    let provenance=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("provenance.json")))as?[String:Any]),hashes=try XCTUnwrap(provenance["sha256"]as?[String:String])
    XCTAssertEqual(SHA256.hash(data:expected).map{String(format:"%02x",$0)}.joined(),hashes["legacy-small.f32"])
    XCTAssertEqual(cases.count,288)
    let helper=LegacyChannelFilterCaptureTests();var actual=Data()
    for depth in PixelDepth.allCases {for target in LegacyChannelFilterCaptureTests.Target.allCases {for kind in LegacyChannelFilterCaptureTests.kinds {for selected in [false,true] {for indicates in ChannelDisplayOptions.Indicates.allCases {
      var(d,plane)=try helper.fixture(depth,target:target,selected:selected,indicates:indicates)
      try Command.channel(.filter(plane,helper.filter(kind))).apply(to:&d)
      let pixels=try d.channel(plane).pixels
      for y in 0..<8 {for x in 0..<12 {helper.append(pixels.pixel(x:x,y:y),to:&actual)}}
    }}}}}
    let different=actual.indices.filter{actual[$0] != expected[$0]}
    XCTAssertEqual(actual.count,expected.count);XCTAssertTrue(different.isEmpty,"Different bytes: \(different.count), first offsets: \(Array(different.prefix(24)))")
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {try actual.write(to:URL(fileURLWithPath:path).appendingPathComponent("channel-filter-current-small.f32"))}
  }
  func testMaximumGeometrySevenConstantFiltersRetainDepthMetadataHistoryAndSource() throws {
    let helper=LegacyChannelFilterCaptureTests()
    for depth in PixelDepth.allCases {for target in LegacyChannelFilterCaptureTests.Target.allCases {for kind in AuxiliaryChannelFiltering.kinds where kind != .addNoise {
      let(original,plane)=try fixture(depth,target:target),before=try original.channel(plane)
      XCTAssertTrue(AuxiliaryChannelFiltering.available(original,target:plane,kind:kind))
      var session=EditorSession(document:original)
      try session.execute(.channel(.filter(plane,helper.filter(kind))))
      let result=session.document,after=try result.channel(plane),expected=kind == .highPass ? Pixel(0.5,0.5,0.5).quantized(depth):.black
      XCTAssertEqual(after.pixels.pixel(x:299_999,y:299_999),expected);XCTAssertEqual(after.pixels.tileCount,0);XCTAssertEqual(after.pixels.depth,depth);XCTAssertEqual(after.pixels.colorEncoding,.sRGB)
      var owner=before;owner.pixels=after.pixels;XCTAssertEqual(after,owner);XCTAssertEqual(result.layers,original.layers)
      let changed=result != original;XCTAssertEqual(session.undoStack.count,changed ? 1:0)
      if changed {try session.undo();XCTAssertEqual(session.document,original);try session.redo();XCTAssertEqual(session.document,result)}
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(result)),result)
    }}}
  }
  func testActualAboveEightMegapixelNoiseMatchesFrozenRowAndLeavesUnselectedCoverage() throws {
    let helper=LegacyChannelFilterCaptureTests();var(d,plane)=try fixture(.u8,target:.alpha,width:4096,height:2049)
    let(small,smallPlane)=try helper.fixture(.u8,target:.alpha)
    var samples=try d.channel(plane).pixels
    for x in 0..<12 {samples.setPixel(x:x,y:0,try small.channel(smallPlane).pixels.pixel(x:x,y:0))}
    d.alphaChannels?[0].pixels=samples;d.selection = .init(x:0,y:0,width:12,height:1)
    let original=d
    try Command.channel(.filter(plane,helper.filter(.addNoise))).apply(to:&d)
    let output=try d.channel(plane).pixels
    let cases=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("legacy-cases.json")))as?[[String:Any]])
    let row=try XCTUnwrap(cases.first{($0["depth"]as?String)=="u8" && ($0["target"]as?String)=="alpha" && ($0["kind"]as?String)=="addNoise" && ($0["selected"]as?Bool)==false && ($0["indicates"]as?String)=="maskedAreas"})
    let offset=try XCTUnwrap(row["offset"]as?Int),reference=try Data(contentsOf:folder.appendingPathComponent("legacy-small.f32"));var captured=Data()
    for x in 0..<12 {helper.append(output.pixel(x:x,y:0),to:&captured)}
    XCTAssertEqual(captured,reference.subdata(in:offset..<(offset+192)))
    for point in [(12,0),(4095,0),(0,1),(2048,1024),(4095,2048)] {XCTAssertEqual(output.pixel(x:point.0,y:point.1),.black)}
    XCTAssertGreaterThan(d.width*d.height,RasterFilterEngine.maximumPixels)
    XCTAssertGreaterThan(output.mappedBytes,0);XCTAssertLessThanOrEqual(output.tileCount,1);XCTAssertLessThan(output.allocatedBytes,8*1024*1024)
    XCTAssertEqual(d.layers,original.layers);XCTAssertEqual(d.selection,original.selection)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {try captured.write(to:URL(fileURLWithPath:path).appendingPathComponent("channel-filter-large-noise-row.f32"))}
  }
  func testMaximumStandaloneSelectionFiltersWithoutInventingImageLayers() throws {
    var d=try CraftDocument(width:300_000,height:300_000,depth:.u16)
    d.layers=[];d.activeLayerID=nil;d.channelOnly=true
    let value=AlphaChannel(name:"Owned standalone",pixels:try Surface(width:d.width,height:d.height,depth:.u16,fill:.black));d.alphaChannels=[value]
    let before=d;var session=EditorSession(document:d)
    try session.execute(.channel(.filter(.alpha(value.id),RasterFilter(.highPass))))
    XCTAssertTrue(session.document.layers.isEmpty);XCTAssertNil(session.document.activeLayerID);XCTAssertTrue(session.document.isChannelOnly)
    XCTAssertEqual(session.document.alphaChannels?.first?.pixels.pixel(x:299_999,y:299_999).r,32768/65535)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(session.document)),session.document)
    try session.undo();XCTAssertEqual(session.document,before)
  }
  func testLegacyBoundedLiquifyStillMatchesThePriorDensePreparation() throws {
    let helper=LegacyChannelFilterCaptureTests()
    for depth in PixelDepth.allCases {for target in LegacyChannelFilterCaptureTests.Target.allCases {
      let(original,plane)=try helper.fixture(depth,target:target)
      var f=RasterFilter(.liquify);f.liquify?.strokes=[.init(size:6,points:[[4,4],[6,4]])]
      var result=original;try Command.channel(.filter(plane,f)).apply(to:&result)
      let value=try original.channel(plane)
      var proxy=try CraftDocument(width:original.width,height:original.height,depth:depth)
      var numeric=try Surface(width:original.width,height:original.height,depth:depth,fill:.black,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      for y in 0..<original.height {for x in 0..<original.width {let v=unit(value.pixels.pixel(x:x,y:y).r),p=Pixel(v,v,v);if depth == .f32{numeric.setLinearPixel(x:x,y:y,p)}else{numeric.setPixel(x:x,y:y,p)}}}
      proxy.layers[0].content = .raster(numeric);try RasterFilterEngine.apply(f,to:proxy.layers[0].id,in:&proxy)
      guard case .raster(let rendered)=proxy.layers[0].content else{return XCTFail("Missing reference")}
      var expected=value.pixels
      for y in 0..<original.height {for x in 0..<original.width {let v=unit(depth == .f32 ? rendered.linearPixel(x:x,y:y).r:rendered.pixel(x:x,y:y).r);expected.setPixel(x:x,y:y,Pixel(v,v,v))}}
      XCTAssertEqual(try result.channel(plane).pixels,expected)
      XCTAssertFalse(AuxiliaryChannelFiltering.available(original,target:plane,kind:.liquify))
    }}
    var(large,plane)=try fixture(.u8,target:.alpha);let before=large
    XCTAssertThrowsError(try Command.channel(.filter(plane,RasterFilter(.liquify))).apply(to:&large));XCTAssertEqual(large,before)
  }
  func testMissingInvalidAndCancelledFiltersCannotPublish() async throws {
    let(d,plane)=try fixture(.f32,target:.alpha);var copy=d
    XCTAssertThrowsError(try Command.channel(.filter(.alpha(UUID()),RasterFilter(.average))).apply(to:&copy));XCTAssertEqual(copy,d)
    XCTAssertThrowsError(try Command.channel(.filter(plane,RasterFilter(.cameraRaw))).apply(to:&copy));XCTAssertEqual(copy,d)
    let work=Task.detached{var candidate=d;withUnsafeCurrentTask{$0?.cancel()};try Command.channel(.filter(plane,RasterFilter(.gaussianBlur))).apply(to:&candidate)}
    do{try await work.value;XCTFail("Cancelled channel filter published")}catch is CancellationError{}
  }
}
