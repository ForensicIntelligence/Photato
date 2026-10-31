import Darwin
import Foundation
import XCTest
@testable import PhotoCraftCore

final class NativeMappedTileCacheTests: XCTestCase {
  private func temporary() throws -> URL {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
    addTeardownBlock {try? FileManager.default.removeItem(at:url)};return url
  }
  func testSparseDistantSlotsRetainSamplesAfterCacheAndStoreCloseWithCOW() throws {
    let directory=try temporary(),count=UInt64(RuntimeTileIndex.maximumEntries)*4
    var retained:RasterTile?
    do {
      let store=try RasterTileStore(directory:directory),pixel=Pixel(4,-0.0,-0.25,0.5)
      let tile=try store.append(RasterTile(repeating:pixel,count:4096))
      var reserved=0
      let cache=try NativeMappedTileCache(records:count,directory:directory,reserveSegment:{reserved += $0})
      XCTAssertEqual(cache.mappedBytes,703_275_008);XCTAssertNil(try cache.tile(at:count-1))
      for ordinal in [UInt64(0),1024,count/2,count-1] {try cache.store(tile,at:ordinal)}
      for ordinal in [UInt64(0),1024,count/2,count-1] {
        let value=try XCTUnwrap(cache.tile(at:ordinal));XCTAssertEqual(value.identity,tile.identity)
        XCTAssertTrue(value[4095].hasSameBits(as:pixel))
      }
      XCTAssertEqual(reserved,128);XCTAssertEqual(cache.residentEstimate,640)
      XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
      retained=try cache.tile(at:count-1)
    }
    var copy=try XCTUnwrap(retained);copy[0] = .white
    XCTAssertTrue(retained![0].hasSameBits(as:Pixel(4,-0.0,-0.25,0.5)))
    XCTAssertEqual(copy[0],.white);XCTAssertTrue(copy[4095].hasSameBits(as:retained![4095]))
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
  }
  func testEmptyOverflowInvalidDirectoriesAndOrdinalBounds() throws {
    let empty=try NativeMappedTileCache(records:0);XCTAssertEqual(empty.mappedBytes,0)
    XCTAssertThrowsError(try empty.tile(at:0))
    XCTAssertThrowsError(try NativeMappedTileCache(records:UInt64(Int.max)/8+1))
    XCTAssertThrowsError(try NativeMappedTileCache(records:UInt64.max))
    XCTAssertThrowsError(try NativeMappedTileCache(records:1,directory:URL(string:"https://invalid.example/")!))
    XCTAssertThrowsError(try NativeMappedTileCache(records:1,directory:try temporary().appendingPathComponent("missing")))
    let cache=try NativeMappedTileCache(records:1)
    XCTAssertThrowsError(try cache.tile(at:1));XCTAssertThrowsError(try cache.tile(at:UInt64.max))
    XCTAssertNil(try cache.tile(at:0))
  }
  func testShortInterruptedWritesAndFailClosedIO() throws {
    let store=try RasterTileStore(),tile=try store.append(RasterTile(repeating:.white,count:4096))
    var calls=0
    let cache=try NativeMappedTileCache(records:2,write:{fd,bytes,count,offset in
      calls += 1;if calls == 1 {errno=EINTR;return -1}
      return pwrite(fd,bytes,min(3,count),offset)
    })
    try cache.store(tile,at:1);XCTAssertEqual(calls,4);XCTAssertEqual(try cache.tile(at:1)?.identity,tile.identity)
    for failure in [ENOSPC,EIO] {
      var writes=0
      let failed=try NativeMappedTileCache(records:1,write:{fd,bytes,count,offset in
        writes += 1;if writes == 1 {return pwrite(fd,bytes,3,offset)}
        errno=failure;return -1
      })
      XCTAssertThrowsError(try failed.store(tile,at:0)) { error in
        XCTAssertEqual(error as? RasterScratchFailure,.io(operation:"ordinal cache write",code:failure))
      }
      XCTAssertThrowsError(try failed.tile(at:0));XCTAssertThrowsError(try failed.store(tile,at:0))
    }
    let zero=try NativeMappedTileCache(records:1,write:{_,_,_,_ in 0})
    XCTAssertThrowsError(try zero.store(tile,at:0)) {XCTAssertEqual($0 as? RasterScratchFailure,.io(operation:"ordinal cache write",code:EIO))}
  }
  func testInvalidSamplesDuplicateSlotsAndSegmentBudgetPoisonWriter() throws {
    let store=try RasterTileStore(),tile=try store.append(RasterTile(repeating:.white,count:4096))
    let cache=try NativeMappedTileCache(records:2);try cache.store(tile,at:0)
    XCTAssertThrowsError(try cache.store(tile,at:0));XCTAssertThrowsError(try cache.tile(at:0))
    for invalid in [RasterTile(repeating:.white,count:4096),RasterTile(segment:tile.segment!,offset:1),RasterTile(segment:tile.segment!,offset:tile.segment!.length)] {
      let c=try NativeMappedTileCache(records:1);XCTAssertThrowsError(try c.store(invalid,at:0))
      XCTAssertThrowsError(try c.tile(at:0))
    }
    let limited=try NativeMappedTileCache(records:1,reserveSegment:{_ in throw NativeArchiveMemoryLimit.raster(requiredBytes:128,limitBytes:0)})
    XCTAssertThrowsError(try limited.store(tile,at:0));XCTAssertThrowsError(try limited.tile(at:0))
  }
  func testCancellationIsCheckedOnCachedReadsAndCreation() async throws {
    let result=try await Task.detached { () throws -> Bool in
      let store=try RasterTileStore(),tile=try store.append(RasterTile(repeating:.white,count:4096))
      let cache=try NativeMappedTileCache(records:1);try cache.store(tile,at:0)
      withUnsafeCurrentTask {$0?.cancel()}
      do {_ = try cache.tile(at:0);return false} catch is CancellationError {} catch {return false}
      do {_ = try NativeMappedTileCache(records:1);return false} catch is CancellationError {} catch {return false}
      do {try cache.store(tile,at:0);return false} catch is CancellationError {return true} catch {return false}
    }.value
    XCTAssertTrue(result)
  }
  func testInputDecodesDistantAliasesOnlyOnceWithinExactUniqueScratchBudget() throws {
    let sink=NativeChunkedArchive.Output(maximumBytes:16*1024*1024);try sink.append(NativeIndexedArchive.header)
    let output=try NativeIndexedArchive.Output(sink:sink)
    let unique=269
    var ordinals=[UInt64]()
    for i in 0..<unique {ordinals.append(try output.storeOrdinal(TileArchive.encode([Pixel](repeating:Pixel(Float(i+1),-0.0,-0.25,0.5),count:4096))))}
    let catalog=try output.finishIndex()
    let index=try NativeBlobIndex.Reader(catalog:catalog) {offset,count in sink.data.subdata(in:Int(catalog.payloadEnd+offset)..<Int(catalog.payloadEnd+offset)+count)}
    try index.validate()
    let store=try RasterTileStore(maximumBytes:unique*65536);var reads=0
    let input=try NativeIndexedArchive.Input(index:index,backing:store,budget:RasterDecodeBudget(bytes:65536)) {offset,count in
      reads += 1;return sink.data.subdata(in:offset..<offset+count)
    }
    for _ in 0..<3 {for i in 0..<unique {
      let tile=try input.storedTile(NativeIndexedArchive.identifier(ordinals[i]))
      XCTAssertTrue(tile[4095].hasSameBits(as:Pixel(Float(i+1),-0.0,-0.25,0.5)))
    }}
    XCTAssertEqual(reads,unique);XCTAssertEqual(store.storedBytes,17_629_184);XCTAssertTrue(input.allReferenced)
    for id in ["b269","b-1","b00","b18446744073709551615","bad"] {XCTAssertThrowsError(try input.storedTile(id))}
    // Owned decoding keeps its bounded cache; it does not retain269 heap tiles.
    var ownedReads=0
    let owned=try NativeIndexedArchive.Input(index:index,backing:nil,budget:RasterDecodeBudget(bytes:65536)) {offset,count in ownedReads += 1;return sink.data.subdata(in:offset..<offset+count)}
    for _ in 0..<2 {for id in ordinals {_ = try owned.storedTile(NativeIndexedArchive.identifier(id))}}
    XCTAssertEqual(ownedReads,unique*2)
  }
  func testNative63AliasRoundTripAllDepthsFileAndDataAtUniqueScratchLimit() throws {
    let unique=269,count=unique*3
    for depth in PixelDepth.allCases {
      var model=try CraftDocument(width:count*64,height:64,depth:depth)
      var surface=try Surface(width:count*64,height:64,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      for key in 0..<count {
        // Two quantized channels keep all269 patterns distinct even in RGB/8.
        let p=Pixel(Float(key%unique%256)/255,Float((key%unique)/256)/255,depth == .f32 ? -0.0:0,1)
        if depth == .f32 {surface.setLinearPixel(x:key*64,y:0,p)} else {surface.setPixel(x:key*64,y:0,p)}
      }
      model.layers[0].content = .raster(surface)
      let bytes=try NativeArchive.encodeChunked(model,minimumVersion:63)
      let decoded=try NativeArchive.decodePaged(bytes,scratchByteLimit:unique*65536)
      XCTAssertEqual(decoded,model)
      let file=try temporary().appendingPathComponent("aliases-\(depth.rawValue).photato");try bytes.write(to:file)
      let fromFile=try NativeArchive.readPaged(file,scratchByteLimit:unique*65536)
      XCTAssertEqual(fromFile,model)
      guard case .raster(let restored)=decoded.layers[0].content else {return XCTFail("Missing raster")}
      for key in 0..<count {
        let a=restored.linearPixel(x:key*64,y:0),b=surface.linearPixel(x:key*64,y:0)
        XCTAssertTrue(a.hasSameBits(as:b))
      }
      XCTAssertThrowsError(try NativeArchive.decodePaged(bytes,scratchByteLimit:unique*65536-1))
      if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let directory=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try bytes.write(to:directory.appendingPathComponent("native63-807-aliases-\(depth.rawValue).photato"))
      }
    }
  }
}
