import Darwin
import CryptoKit
import Foundation
import XCTest
@testable import PhotoCraftCore

final class NativeIndexedArchiveTests:XCTestCase {
  func fixture(_ depth:PixelDepth)throws->CraftDocument {
    var d=try CraftDocument(width:128,height:128,depth:depth)
    var s=try Surface(width:128,height:128,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    if depth == .f32 {s.setLinearPixel(x:0,y:0,Pixel(-0.0,4,-0.25,0.5));s.setLinearPixel(x:64,y:64,Pixel(2,0.25,0,1))}
    else {s.setPixel(x:0,y:0,Pixel(0.2,0.4,0.6,0.5));s.setPixel(x:64,y:64,.white)}
    d.layers[0].content = .raster(s);return d
  }
  func temporary()throws->URL {
    let u=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:u,withIntermediateDirectories:true);addTeardownBlock{try? FileManager.default.removeItem(at:u)};return u
  }
  func read(_ data:Data,_ offset:Int,_ count:Int)throws->Data {data.subdata(in:offset..<offset+count)}
  func testAllDepthsPreserveBitsHistoryDimensionsAndRecoveryThroughDataAndFile()throws {
    for depth in PixelDepth.allCases {
      let model=try fixture(depth),bytes=try NativeArchive.encodeChunked(model,minimumVersion:63)
      if let directory=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let folder=URL(fileURLWithPath:directory);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try bytes.write(to:folder.appendingPathComponent("native63-\(depth.rawValue).photato"))
      }
      XCTAssertTrue(bytes.starts(with:NativeIndexedArchive.header));XCTAssertEqual(try NativeArchive.dimensions(bytes).width,128)
      XCTAssertEqual(try NativeArchive.decode(bytes),model)
      let mapped=try NativeArchive.decodePaged(bytes);XCTAssertEqual(mapped,model);XCTAssertEqual(mapped.mappedRasterBytes,131072)
      guard case .raster(let s)=mapped.layers[0].content,case .raster(let original)=model.layers[0].content else {return XCTFail("Raster")}
      let p=depth == .f32 ? s.linearPixel(x:0,y:0):s.pixel(x:0,y:0),q=depth == .f32 ? original.linearPixel(x:0,y:0):original.pixel(x:0,y:0);XCTAssertTrue(p.hasSameBits(as:q))
      var session=EditorSession(document:mapped);var brush=Brush();brush.size=8;brush.color = .white
      try session.execute(.stroke(model.layers[0].id,[.init(x:80.5,y:80.5)],brush));XCTAssertNotEqual(session.document,model);try session.undo();XCTAssertEqual(session.document,model);try session.redo()
      let url=try temporary().appendingPathComponent("owned.photato"),file=try AtomicFileWriter(to:url)
      try NativeIndexedArchive.write(model,output:.init(file:file,maximumBytes:NativeArchive.maximumBytes),recoveryContext:Data("owned context".utf8));try file.commit()
      XCTAssertEqual(try NativeArchive.readPaged(url),model);XCTAssertEqual(try NativeArchive.read(url),model)
      let context=try NativeArchive.readRecoveryPaged(url);XCTAssertEqual(context.context,Data("owned context".utf8));XCTAssertFalse(context.invalidContext)
      XCTAssertEqual(try NativeArchive.readRecoveryContext(url),context.context);XCTAssertEqual(try NativeArchive.readRecoveryMetadata(url)?.width,128)
      try FileManager.default.removeItem(at:url);XCTAssertEqual(mapped,model)
    }
  }
  func testCompactPagesRepresentMoreThan65536TilesWithBoundedManifest()throws {
    // Independently assemble native63 pages from one valid encoded tile. Logical
    // references exceed4GiB; the one identical sample block stays shared on disk.
    let model=try fixture(.f32),small=try NativeArchive.encodeChunked(model,minimumVersion:63)
    let (metadata,_)=try NativeChunkedArchive.manifest(count:small.count){try self.read(small,$0,$1)}
    var envelope=try XCTUnwrap(PropertyListSerialization.propertyList(from:metadata,format:nil)as?[String:Any])
    var d=try XCTUnwrap(envelope["document"]as?[String:Any]),layers=try XCTUnwrap(d["layers"]as?[[String:Any]]),content=try XCTUnwrap(layers[0]["content"]as?[String:Any]),raster=try XCTUnwrap(content["raster"]as?[String:Any]),s=try XCTUnwrap(raster["_0"]as?[String:Any])
    let sink=NativeChunkedArchive.Output(maximumBytes:NativeArchive.maximumBytes);try sink.append(NativeIndexedArchive.header)
    let output=try NativeIndexedArchive.Output(sink:sink)
    var samples=[Pixel](repeating:.clear,count:4096);samples[0]=Pixel(-0.0,4,-0.25,0.5)
    let tile=try output.storeOrdinal(TileArchive.encode(samples)),count=65792,width=16384,height=16448
    var pages:[String]=[]
    for first in stride(from:0,to:count,by:1024) {pages.append(try output.storeBytes(NativeTilePage.encode((first..<min(first+1024,count)).map{($0,tile)})))}
    s["width"]=width;s["height"]=height;s["tileCount"]=count;s["tilePages"]=pages
    raster["_0"]=s;content["raster"]=raster;layers[0]["content"]=content;d["layers"]=layers;d["width"]=width;d["height"]=height;envelope["document"]=d
    let catalog=try output.finishIndex();envelope["index"]=try PropertyListSerialization.propertyList(from:PropertyListEncoder().encode(catalog),format:nil)
    let meta=try PropertyListSerialization.data(fromPropertyList:envelope,format:.binary,options:0),offset=sink.count
    try sink.append(meta);try sink.append(NativeIndexedArchive.footer+NativeChunkedArchive.integer(UInt64(offset),width:8)+NativeChunkedArchive.integer(UInt64(meta.count),width:8)+Data(SHA256.hash(data:meta)))
    if let directory=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let folder=URL(fileURLWithPath:directory);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
      try sink.data.write(to:folder.appendingPathComponent("native63-65792-tiles.photato"))
      try JSONSerialization.data(withJSONObject:["tileReferences":count,"referencedSampleBytes":count*65536,"manifestBytes":meta.count,"archiveBytes":sink.count,"blobRecords":catalog.records],options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("native63-paged-measurement.json"))
    }
    XCTAssertLessThan(meta.count,10000);XCTAssertThrowsError(try NativeArchive.decode(sink.data)){$0 is NativeArchiveMemoryLimit ? ():XCTFail("Wrong capacity error")}
    let large=try NativeArchive.decodePaged(sink.data,heapByteLimit:16*1024*1024,scratchByteLimit:65536)
    guard case .raster(let grid)=large.layers[0].content else {return XCTFail("Raster")}
    XCTAssertEqual(grid.tileCount,count);XCTAssertEqual(grid.mappedBytes,4_311_744_512)
    XCTAssertTrue(grid.linearPixel(x:16320,y:16384).hasSameBits(as:samples[0]));XCTAssertLessThan(large.estimatedBytes,16*1024*1024)
  }
  func testIndexOutputBeyond65536RecordsAndBoundedCache()throws {
    let sink=NativeChunkedArchive.Output(maximumBytes:16*1024*1024);try sink.append(NativeIndexedArchive.header)
    let output=try NativeIndexedArchive.Output(sink:sink)
    for i in 0..<65537 {var n=UInt64(i).littleEndian;XCTAssertEqual(try output.storeOrdinal(withUnsafeBytes(of:&n){Data($0)}),UInt64(i))}
    let c=try output.finishIndex();XCTAssertEqual(c.records,65537)
    let reader=try NativeBlobIndex.Reader(catalog:c){o,n in try self.read(sink.data,Int(c.payloadEnd+o),n)};try reader.validate()
    XCTAssertEqual(try reader.record(at:65536).offset,16+65536*8)
  }
  func testLegacyTableCapRetriesFreshAtomicIndexedTransactionAndRetainsDestinationOnFailure()throws {
    let model=try fixture(.f32),url=try temporary().appendingPathComponent("owned.photato")
    var calls=0
    try NativeArchive.write(model,to:url,recoveryContext:Data("context".utf8),legacyRecordLimit:1) {u,n in calls+=1;return try AtomicFileWriter(to:u,maximumBytes:n)}
    XCTAssertEqual(calls,2);let saved=try Data(contentsOf:url);XCTAssertTrue(saved.starts(with:NativeIndexedArchive.header));XCTAssertEqual(try NativeArchive.readPaged(url),model)
    XCTAssertEqual(try NativeArchive.readRecoveryContext(url),Data("context".utf8))
    calls=0
    XCTAssertThrowsError(try NativeArchive.write(model,to:url,legacyRecordLimit:1) {u,n in
      calls+=1;var operations=AtomicFileWriter.Operations()
      if calls==2 {operations.write={_,_,_,_ in errno=EIO;return -1}}
      return try AtomicFileWriter(to:u,maximumBytes:n,operations:operations)
    })
    XCTAssertEqual(calls,2);XCTAssertEqual(try Data(contentsOf:url),saved)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(at:url.deletingLastPathComponent(),includingPropertiesForKeys:nil).map(\.lastPathComponent),[url.lastPathComponent])
  }
  func testRehashedManifestCannotHideUnusedRecordsOrInvalidPageCounts()throws {
    let valid=try NativeArchive.encodeChunked(fixture(.f32),minimumVersion:63)
    let (metadata,offset)=try NativeChunkedArchive.manifest(count:valid.count){try self.read(valid,$0,$1)}
    let original=try XCTUnwrap(PropertyListSerialization.propertyList(from:metadata,format:nil)as?[String:Any])
    for mutation in 0..<5 {
      var envelope=original,d=try XCTUnwrap(envelope["document"]as?[String:Any]),layers=try XCTUnwrap(d["layers"]as?[[String:Any]]),content=try XCTUnwrap(layers[0]["content"]as?[String:Any]),raster=try XCTUnwrap(content["raster"]as?[String:Any]),s=try XCTUnwrap(raster["_0"]as?[String:Any])
      switch mutation {
      case 0:s["tileCount"]=0;s["tilePages"]=[] // Valid empty raster; payload ownership must still reject.
      case 1:s["tileCount"]=5
      case 2:s["tilePages"]=["b00"]
      case 3:s["tileData"]=[:]
      default:s["tilePages"]=["b999999"]
      }
      raster["_0"]=s;content["raster"]=raster;layers[0]["content"]=content;d["layers"]=layers;envelope["document"]=d
      let meta=try PropertyListSerialization.data(fromPropertyList:envelope,format:.binary,options:0)
      var forged=Data(valid.prefix(Int(offset)));forged.append(meta);forged.append(NativeIndexedArchive.footer+NativeChunkedArchive.integer(offset,width:8)+NativeChunkedArchive.integer(UInt64(meta.count),width:8)+Data(SHA256.hash(data:meta)))
      XCTAssertThrowsError(try NativeArchive.decodePaged(forged),"Mutation \(mutation)")
    }
  }
  func testBudgetsCorruptionInvalidVersionsAndPageShapesReject()throws {
    let bytes=try NativeArchive.encodeChunked(fixture(.u8),minimumVersion:63)
    XCTAssertThrowsError(try NativeArchive.decodePaged(bytes,heapByteLimit:0));XCTAssertThrowsError(try NativeArchive.decodePaged(bytes,scratchByteLimit:0));XCTAssertThrowsError(try NativeArchive.decodePaged(bytes,maximumMetadataBytes:0))
    XCTAssertThrowsError(try NativeArchive.encodeChunked(fixture(.u8),maximumBytes:16,minimumVersion:63));XCTAssertThrowsError(try NativeArchive.encodeChunked(fixture(.u8),minimumVersion:66))
    let model64=try fixture(.u8),version64=try NativeArchive.encodeChunked(model64,minimumVersion:64)
    XCTAssertEqual(try NativeArchive.decodePaged(version64),model64)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(model64,minimumVersion:65)),model64)
    for at in [16,bytes.count-1,bytes.count-56] {var bad=bytes;bad[at]^=1;XCTAssertThrowsError(try NativeArchive.decodePaged(bad))}
    XCTAssertThrowsError(try NativeTilePage.encode([]));XCTAssertThrowsError(try NativeTilePage.encode([(-1,0)]));XCTAssertThrowsError(try NativeTilePage.decode(Data()))
    let page=try NativeTilePage.encode([(0,7),(1,8)]);XCTAssertEqual(try NativeTilePage.decode(page).map{$0.1},[7,8]);XCTAssertThrowsError(try NativeTilePage.decode(page+Data([0])))
  }
}
