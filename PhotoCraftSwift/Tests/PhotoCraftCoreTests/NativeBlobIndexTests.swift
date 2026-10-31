import CryptoKit
import Foundation
import XCTest
@testable import PhotoCraftCore

final class NativeBlobIndexTests:XCTestCase {
  func testBoundedHierarchyAcrossOldLimitAndMultipleBranchLevels()throws {
    for count in [0,1,1024,1025,65536,65537,262144,300000] {
      let scratch=try NativeIndexScratch(),start:UInt64=4_294_967_400
      let writer=NativeBlobIndex.Writer(payloadStart:start,appendNode:scratch.append)
      for i in 0..<count {var n=UInt64(i).littleEndian;let data=withUnsafeBytes(of:&n){Data($0)};XCTAssertEqual(try writer.append(.init(offset:start+UInt64(i)*8,length:8,digest:Data(SHA256.hash(data:data)))),UInt64(i))}
      let catalog=try writer.finish(),reader=try NativeBlobIndex.Reader(catalog:catalog,read:scratch.read)
      XCTAssertThrowsError(try reader.record(at:0));try reader.validate(payloadStart:start)
      if count>0 {for i in Set([0,count-1,count/2]+(0..<200).map{($0*7919)%count}) {let r=try reader.record(at:UInt64(i));var n=UInt64(i).littleEndian;XCTAssertEqual(r.offset,start+UInt64(i)*8);XCTAssertEqual(r.length,8);XCTAssertEqual(r.digest,withUnsafeBytes(of:&n){Data(SHA256.hash(data:Data($0)))})}}
      XCTAssertThrowsError(try reader.record(at:UInt64(count)))
      XCTAssertLessThanOrEqual(writer.maximumBufferedRecords,1024);XCTAssertLessThanOrEqual(writer.maximumBufferedReferences,256*17);XCTAssertLessThanOrEqual(reader.maximumCachedNodes,8);XCTAssertLessThanOrEqual(scratch.maximumPhysicalIO,65536)
      XCTAssertThrowsError(try writer.finish())
    }
  }
  func testErrorsPoisonWriterAndScratchRejectsInvalidAdmission()throws {
    let writer=NativeBlobIndex.Writer{_ in throw NativeIndexFailure.io("injected",5)}
    for i in 0..<1023 {try writer.append(.init(offset:UInt64(16+i),length:1,digest:Data(repeating:0,count:32)))}
    XCTAssertThrowsError(try writer.append(.init(offset:1039,length:1,digest:Data(repeating:0,count:32))))
    XCTAssertThrowsError(try writer.finish());XCTAssertThrowsError(try writer.append(.init(offset:1040,length:1,digest:Data(repeating:0,count:32))))
    let tiny=try NativeIndexScratch(maximumBytes:0);XCTAssertThrowsError(try tiny.append(Data([1])))
    XCTAssertThrowsError(try tiny.read(1,0));XCTAssertThrowsError(try NativeIndexScratch(maximumBytes:-1));XCTAssertThrowsError(try NativeIndexScratch(directory:URL(string:"https://example.invalid")!))
  }
  func testCorruptionTruncationAndSemanticCoverageReject()throws {
    let scratch=try NativeIndexScratch(),writer=NativeBlobIndex.Writer(appendNode:scratch.append)
    for i in 0..<1025 {try writer.append(.init(offset:UInt64(16+i),length:1,digest:Data(repeating:0,count:32)))}
    let c=try writer.finish()
    let corrupt=try NativeBlobIndex.Reader(catalog:c){o,n in var d=try scratch.read(o,n);d[0]^=1;return d}
    XCTAssertThrowsError(try corrupt.validate())
    let short=try NativeBlobIndex.Reader(catalog:c){o,n in Data(try scratch.read(o,n).dropLast())};XCTAssertThrowsError(try short.validate())
    let root=try XCTUnwrap(c.root);var changed=try scratch.read(root.offset,root.length)
    changed.withUnsafeMutableBytes{$0.storeBytes(of:UInt64(1).littleEndian,toByteOffset:64,as:UInt64.self)}
    let ref=NativeBlobIndex.Reference(offset:root.offset,length:root.length,level:root.level,first:root.first,count:root.count,spanStart:root.spanStart,spanEnd:root.spanEnd,digest:Data(SHA256.hash(data:changed)))
    let forged=NativeBlobIndex.Catalog(root:ref,records:c.records,indexBytes:c.indexBytes,payloadEnd:c.payloadEnd)
    let reader=try NativeBlobIndex.Reader(catalog:forged){o,n in o==root.offset ? changed:try scratch.read(o,n)}
    XCTAssertThrowsError(try reader.validate());XCTAssertThrowsError(try reader.record(at:0))
    let noCache=try NativeBlobIndex.Reader(catalog:c,cacheNodes:0,read:scratch.read);try noCache.validate();XCTAssertEqual(try noCache.record(at:1024).offset,1040);XCTAssertEqual(noCache.maximumCachedNodes,0)
  }
  func testCancellationDoesNotFinishOrPublishAnIndex()async throws {
    let worker=Task { ()throws->Void in
      withUnsafeCurrentTask{$0?.cancel()}
      let scratch=try NativeIndexScratch(),writer=NativeBlobIndex.Writer(appendNode:scratch.append)
      XCTAssertThrowsError(try writer.append(.init(offset:16,length:1,digest:Data(repeating:0,count:32)))){$0 is CancellationError ? ():XCTFail("Wrong error")}
      XCTAssertThrowsError(try writer.finish());XCTAssertEqual(scratch.count,0)
    }
    try await worker.value
  }
}
