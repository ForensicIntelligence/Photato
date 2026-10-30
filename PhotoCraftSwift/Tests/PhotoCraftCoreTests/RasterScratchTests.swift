import Foundation
import XCTest
@testable import PhotoCraftCore

final class RasterScratchTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .f32) throws -> Surface {
    var s = try Surface(width:130,height:66,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<66 { for x in 0..<130 {
      let p=Pixel(Float(x%11)/10,Float(y%7)/6,Float((x+y)%13)/12,Float((x+y)%5)/4)
      if depth == .f32 { s.setLinearPixel(x:x,y:y,p) } else { s.setPixel(x:x,y:y,p) }
    } }
    if depth == .f32 { s.setLinearPixel(x:0,y:0,Pixel(-0.0,4,-0.25,0.5)) }
    return s
  }
  func testMappedSamplesCopyOnWriteAndPortableBitsAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      let source=try fixture(depth)
      var mapped=try source.spillingTiles(to:RasterTileStore())
      XCTAssertEqual(mapped,source);XCTAssertEqual(mapped.mappedTileCount,source.tileCount)
      XCTAssertEqual(mapped.mappedBytes,source.tileCount*65536)
      XCTAssertLessThan(mapped.allocatedBytes,source.allocatedBytes)
      let frozen=mapped
      let before=depth == .f32 ? frozen.linearPixel(x:0,y:0):frozen.pixel(x:0,y:0)
      if depth == .f32 {mapped.setLinearPixel(x:0,y:0,.white)} else {mapped.setPixel(x:0,y:0,.white)}
      XCTAssertTrue((depth == .f32 ? frozen.linearPixel(x:0,y:0):frozen.pixel(x:0,y:0)).hasSameBits(as:before))
      XCTAssertEqual(mapped.mappedTileCount,frozen.mappedTileCount-1)
      XCTAssertEqual(mapped.allocatedBytes,65536+mapped.mappedTileCount*128)
      var d=try CraftDocument(width:130,height:66,depth:depth)
      d.layers[0].content = .raster(frozen)
      let data=try NativeArchive.encodeChunked(d), restored=try NativeArchive.decode(data)
      guard case .raster(let p)=restored.layers[0].content else{return XCTFail("Missing raster")}
      for (x,y) in [(0,0),(64,63),(129,65)] {
        let a=depth == .f32 ? p.linearPixel(x:x,y:y):p.pixel(x:x,y:y)
        let b=depth == .f32 ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y)
        XCTAssertTrue(a.hasSameBits(as:b))
      }
      let view=try frozen.floatingStorageView()
      XCTAssertEqual(view.mappedBytes,frozen.mappedBytes);XCTAssertEqual(view.depth,.f32)
    }
  }
  func testOwnedAnonymousFilesLifetimeAndCapacityFailureLeaveInputUnchanged() throws {
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:folder)}
    let source=try fixture()
    let store=try RasterTileStore(maximumBytes:65536,directory:folder)
    XCTAssertThrowsError(try source.spillingTiles(to:store))
    XCTAssertEqual(source.mappedBytes,0)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:folder.path).isEmpty)
    var retained:Surface?
    do {let writer=try RasterTileStore(directory:folder);retained=try source.spillingTiles(to:writer)}
    XCTAssertEqual(retained,source,"Mappings outlive their writer")
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:folder.path).isEmpty)
    retained=nil
    XCTAssertThrowsError(try RasterTileStore(maximumBytes:-1))
    XCTAssertThrowsError(try RasterTileStore(directory:URL(string:"https://example.invalid/scratch")!))
    XCTAssertThrowsError(try RasterTileStore().append(RasterTile(Array(repeating:Pixel(.nan,0,0),count:4096))))
  }
  func testPatchDefaultsBoundaryTilesAndAtomicFailure() throws {
    var result=try Surface(width:131,height:66)
    let store=try RasterTileStore()
    let first=try Surface(width:128,height:64,fill:Pixel(0.2,0.4,0.6))
    try result.importPatch(first,atX:0,atY:0,backing:store)
    let edge=try Surface(width:3,height:64,fill:.black)
    try result.importPatch(edge,atX:128,atY:0,backing:store)
    let last=try Surface(width:131,height:2,fill:.white)
    try result.importPatch(last,atX:0,atY:64,backing:store)
    XCTAssertEqual(result.pixel(x:127,y:63),first.defaultPixel)
    XCTAssertEqual(result.pixel(x:130,y:63),.black)
    XCTAssertEqual(result.pixel(x:130,y:65),.white)
    let original=result
    XCTAssertThrowsError(try result.importPatch(first,atX:1,atY:0,backing:store));XCTAssertEqual(result,original)
    XCTAssertThrowsError(try result.importPatch(first,atX:0,atY:0,backing:RasterTileStore(maximumBytes:0)));XCTAssertEqual(result,original)
  }
  func testCancellationAndConcurrentSnapshotsDoNotChangeBacking() async throws {
    let source=try fixture(),mapped=try source.spillingTiles(to:RasterTileStore())
    let cancelled=Task.detached {while !Task.isCancelled {await Task.yield()};return try source.spillingTiles(to:RasterTileStore())}
    cancelled.cancel()
    do {_ = try await cancelled.value;XCTFail("Expected cancellation")}catch{XCTAssertTrue(error is CancellationError)}
    let a=Task.detached {var p=mapped;p.setLinearPixel(x:0,y:0,.white);return p}
    let b=Task.detached {var p=mapped;p.setLinearPixel(x:64,y:64,.black);return p}
    let left=await a.value,right=await b.value
    XCTAssertEqual(mapped,source)
    XCTAssertTrue(left.linearPixel(x:64,y:64).hasSameBits(as:source.linearPixel(x:64,y:64)))
    XCTAssertTrue(right.linearPixel(x:0,y:0).hasSameBits(as:source.linearPixel(x:0,y:0)))
  }
}
